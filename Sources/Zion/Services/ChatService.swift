import Foundation

// MARK: - ChatService

@MainActor
@Observable
final class ChatService {

    // MARK: - Observable State

    /// All threads for this repo, ordered most-recent-first.
    var threads: [ChatThread] = []

    /// The ID of the currently active thread.
    var activeThreadID: UUID = UUID()

    /// Forwarding computed property — back-compat for callers that use `service.thread`.
    var thread: ChatThread {
        get {
            threads.first { $0.id == activeThreadID } ?? ChatThread()
        }
        set {
            if let idx = threads.firstIndex(where: { $0.id == activeThreadID }) {
                threads[idx] = newValue
            }
        }
    }

    var isStreaming: Bool = false

    /// Set when a persistence operation fails; consumed by UI to surface a one-time error.
    var lastPersistenceError: String?

    // MARK: - Private (non-observable)

    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private let ai: AIClient
    @ObservationIgnored private let worker: RepositoryWorker
    @ObservationIgnored private let contextBuilder: ChatContextBuilder
    @ObservationIgnored private let harness: ZionHarness
    @ObservationIgnored private let streamProvider: ((LocalLLMConfig, AIPromptPayload, Int, String) -> AsyncThrowingStream<String, Error>)?

    /// Injected storage (nil = volatile/test)
    @ObservationIgnored private let storage: ChatStorage?
    @ObservationIgnored private let repoID: String

    /// Pending debounce tasks keyed by message UUID
    @ObservationIgnored private var persistDebounce: [UUID: Task<Void, Never>] = [:]

    // MARK: - Init (production)

    init(ai: AIClient, worker: RepositoryWorker, contextBuilder: ChatContextBuilder, harness: ZionHarness, storage: ChatStorage? = nil, repoID: String = "") {
        self.ai = ai
        self.worker = worker
        self.contextBuilder = contextBuilder
        self.harness = harness
        self.streamProvider = nil
        self.storage = storage
        self.repoID = repoID

        if storage != nil {
            Task { await self.reloadFromStorage() }
        }
    }

    // MARK: - Init (test injection)

    init(
        ai: AIClient,
        worker: RepositoryWorker,
        contextBuilder: ChatContextBuilder,
        harness: ZionHarness,
        streamProvider: @escaping (LocalLLMConfig, AIPromptPayload, Int, String) -> AsyncThrowingStream<String, Error>,
        storage: ChatStorage? = nil,
        repoID: String = ""
    ) {
        self.ai = ai
        self.worker = worker
        self.contextBuilder = contextBuilder
        self.harness = harness
        self.streamProvider = streamProvider
        self.storage = storage
        self.repoID = repoID

        if storage != nil {
            Task { await self.reloadFromStorage() }
        }
    }

    // MARK: - Thread Management

    /// Loads persisted threads. On error: logs + sets lastPersistenceError, continues volatile.
    private func reloadFromStorage() async {
        guard let storage else { return }
        do {
            var loaded = try await storage.loadThreads(repoID: repoID)
            if loaded.isEmpty {
                let fresh = ChatThread(repoID: repoID)
                try await storage.saveThread(fresh, repoID: repoID)
                loaded = [fresh]
            } else {
                // Eagerly load messages for each thread
                for i in loaded.indices {
                    let msgs = (try? await storage.loadMessages(threadID: loaded[i].id, repoID: repoID)) ?? []
                    loaded[i].messages = msgs
                }
            }
            threads = loaded
            activeThreadID = loaded[0].id
        } catch {
            DiagnosticLogger.shared.log(.error, "ChatService: failed to load threads", context: error.localizedDescription, source: "ChatService")
            lastPersistenceError = L10n("chat.persistence.error")
            let fallback = ChatThread(repoID: repoID)
            threads = [fallback]
            activeThreadID = fallback.id
        }
    }

    /// Creates a new thread, appends it as the first element, and activates it.
    func createThread() {
        let t = ChatThread(repoID: repoID)
        threads.insert(t, at: 0)
        activeThreadID = t.id
        Task { await persistThread(t) }
    }

    /// Deletes a thread by id. If it was active, selects the next most-recent or creates a new one.
    func deleteThread(_ id: UUID) {
        let wasActive = id == activeThreadID
        threads.removeAll { $0.id == id }
        Task {
            try? await storage?.deleteThread(id, repoID: repoID)
        }
        if wasActive {
            if let first = threads.first {
                activeThreadID = first.id
            } else {
                let fresh = ChatThread(repoID: repoID)
                threads = [fresh]
                activeThreadID = fresh.id
                Task { await persistThread(fresh) }
            }
        }
    }

    /// Renames a thread.
    func renameThread(_ id: UUID, title: String) {
        guard let idx = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[idx].title = title
        Task {
            do {
                try await storage?.renameThread(id, title: title, repoID: repoID)
            } catch {
                lastPersistenceError = L10n("chat.persistence.error")
            }
        }
    }

    /// Switches the active thread to `id`.
    func selectThread(_ id: UUID) {
        guard threads.contains(where: { $0.id == id }) else { return }
        activeThreadID = id
    }

    // MARK: - Public API

    /// Sends a user message and receives a response.
    func send(
        text: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode,
        repoURL: URL,
        branch: String
    ) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Ensure we have at least one thread (Phase 2 multi-thread)
        if threads.isEmpty { createThread() }
        let threadID = activeThreadID

        // Build display content (what user sees in bubble) — keep clean, just typed text + explicit slash expansions
        let displayContent = await contextBuilder.expandSlashCommands(text, repoURL: repoURL)

        // Build hidden context that goes to the model but NOT to the bubble
        let isFirstMessage = thread.messages.filter { $0.role == .user }.isEmpty
        var hiddenContext = ""
        if isFirstMessage {
            hiddenContext = await contextBuilder.gitContextHeader(repoURL: repoURL, branch: branch)
        }

        // MARK: Pre-flight intent injection — runs for ALL providers (tool loop NYI Phase 3)
        let autoInject = UserDefaults.standard.object(forKey: "chat.autoInject") as? Bool ?? true
        var injectedLabel: String? = nil

        var freshInjection: String? = nil

        if autoInject, let intent = IntentClassifier.classify(text) {
            let (args, label): ([String], String)
            switch intent {
            case .lastCommit:
                args = ["show", "HEAD", "--patch"]
                label = L10n("chat.harness.intent.lastCommit")
            case .currentChanges:
                args = ["diff", "HEAD"]
                label = L10n("chat.harness.intent.currentChanges")
            case .recentHistory:
                args = ["log", "--oneline", "-20"]
                label = L10n("chat.harness.intent.recentHistory")
            case .status:
                args = ["status", "--porcelain"]
                label = L10n("chat.harness.intent.status")
            case .fileContent(let path):
                args = ["show", "HEAD:\(path)"]
                label = String(format: L10n("chat.harness.intent.fileContent"), path)
            case .commitDetails(let sha):
                args = ["show", sha, "--patch"]
                label = String(format: L10n("chat.harness.intent.commitDetails"), sha)
            }
            if let output = try? await worker.runAction(args: args, in: repoURL) {
                let truncated = String(output.prefix(AILimits.maxDiffContentLength))
                let block = "```\n\(truncated)\n```"
                hiddenContext += (hiddenContext.isEmpty ? "" : "\n\n") + block
                injectedLabel = label
                freshInjection = block
            }
        }

        // Sticky context: if NO fresh intent this turn, carry forward most recent prior user message's internalContext
        let stickyContext: String?
        if freshInjection != nil {
            stickyContext = freshInjection
        } else {
            stickyContext = thread.messages.reversed().first(where: { $0.role == .user && $0.internalContext != nil })?.internalContext
        }

        // Build conversation history block (last 10 messages BEFORE appending current) for multi-turn context
        let historyMessages = thread.messages.suffix(10)
        var historyBlock = ""
        if !historyMessages.isEmpty {
            historyBlock = "## Conversation so far\n\n"
            for msg in historyMessages {
                let speaker = msg.role == .user ? "User" : "Assistant"
                historyBlock += "**\(speaker):** \(msg.content)\n\n"
            }
        }

        // User bubble shows ONLY clean displayContent + chip (if injected). Persist internalContext when fresh (sticky).
        let userMessage = ChatMessage(role: .user, content: displayContent, autoInjectedIntent: injectedLabel, internalContext: freshInjection)
        thread.messages.append(userMessage)

        // Payload = history + hidden context (header + fresh injection) + sticky context (if no fresh) + user text
        var parts: [String] = []
        if !historyBlock.isEmpty { parts.append(historyBlock) }
        if !hiddenContext.isEmpty {
            parts.append(hiddenContext)
        } else if let sticky = stickyContext {
            parts.append("## Carried context from previous turn\n\n" + sticky)
        }
        parts.append("## Current user message\n\n" + displayContent)
        let expandedText: String = parts.joined(separator: "\n\n")

        // Persist user message
        Task {
            do {
                try await storage?.appendMessage(userMessage, threadID: threadID, repoID: repoID)
            } catch {
                lastPersistenceError = L10n("chat.persistence.error")
            }
        }

        // Auto-title: if thread title is the default pattern, use first 60 chars of user text
        if isDefaultTitle(thread.title) {
            let titleText = String(text.prefix(60))
            renameThread(activeThreadID, title: titleText)
        }

        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        thread.messages.append(assistantMessage)
        let assistantID = assistantMessage.id

        // Persist initial (empty, streaming) assistant message
        Task {
            do {
                try await storage?.appendMessage(assistantMessage, threadID: threadID, repoID: repoID)
            } catch {
                lastPersistenceError = L10n("chat.persistence.error")
            }
        }

        isStreaming = true

        let task = Task<Void, Never> {
            defer {
                Task { @MainActor in
                    self.isStreaming = false
                    self.updateAssistantIsStreaming(id: assistantID, isStreaming: false)
                    // Final flush to persistence
                    self.cancelDebounce(for: assistantID)
                    Task { await self.flushMessageToPersistence(id: assistantID, threadID: threadID) }
                }
            }

            let payload = Self.makePayload(for: expandedText)

            switch provider {
            case .local:
                await self.runLocalStream(payload: payload, assistantID: assistantID)

            case .anthropic:
                let modelID = AIModelCatalogService.selection(for: .anthropic, mode: mode, lane: .general).primaryModelID
                let stream = await self.ai.streamAnthropic(payload: payload, apiKey: apiKey, maxTokens: 2048, modelID: modelID)
                await self.consumeStream(stream, assistantID: assistantID, threadID: threadID)

            case .openai:
                let modelID = AIModelCatalogService.selection(for: .openai, mode: mode, lane: .general).primaryModelID
                let stream = await self.ai.streamOpenAI(payload: payload, apiKey: apiKey, maxTokens: 2048, modelID: modelID)
                await self.consumeStream(stream, assistantID: assistantID, threadID: threadID)

            case .gemini, .none:
                do {
                    let response = try await self.ai.call(
                        payload: payload,
                        provider: provider,
                        apiKey: apiKey,
                        maxTokens: 2048,
                        lane: .general,
                        mode: mode
                    )
                    await MainActor.run {
                        self.setAssistantContent(id: assistantID, content: response)
                    }
                } catch {
                    await MainActor.run {
                        self.setAssistantContent(id: assistantID, content: L10n("chat.error.generic"))
                    }
                }
            }
        }

        activeTask = task
        await task.value
    }

    /// Creates a fresh thread (Phase 2 multi-thread) and clears harness session state (Phase 3).
    func newThread() {
        activeTask?.cancel()
        activeTask = nil
        isStreaming = false
        createThread()
        Task { await harness.resetSession() }
    }

    /// Cancels the active streaming task.
    func stop() {
        activeTask?.cancel()
        activeTask = nil
        isStreaming = false
    }

    // MARK: - Private Stream Helpers

    private func runLocalStream(payload: AIPromptPayload, assistantID: UUID) async {
        let config = AIClient.loadLocalConfig() ?? LocalLLMConfig()
        let modelID = config.modelName.isEmpty ? LocalLLMConfig().modelName : config.modelName
        let maxTokens = 2048
        let threadID = activeThreadID

        let stream: AsyncThrowingStream<String, Error>
        if let injected = streamProvider {
            stream = injected(config, payload, maxTokens, modelID)
        } else {
            stream = await ai.streamLocalLLM(
                payload: payload,
                config: config,
                maxTokens: maxTokens,
                modelID: modelID
            )
        }

        await consumeStream(stream, assistantID: assistantID, threadID: threadID)
    }

    private func consumeStream(_ stream: AsyncThrowingStream<String, Error>, assistantID: UUID, threadID: UUID) async {
        do {
            for try await delta in stream {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.appendAssistantDelta(id: assistantID, delta: delta)
                    self.scheduleDebounce(for: assistantID, threadID: threadID)
                }
            }
        } catch {
            // Leave whatever was accumulated
        }
    }

    // MARK: - Private State Mutation Helpers (must be called on MainActor)

    private func appendAssistantDelta(id: UUID, delta: String) {
        guard let tIdx = threads.firstIndex(where: { $0.id == activeThreadID }),
              let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == id }) else { return }
        threads[tIdx].messages[mIdx].content += delta
    }

    private func setAssistantContent(id: UUID, content: String) {
        guard let tIdx = threads.firstIndex(where: { $0.id == activeThreadID }),
              let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == id }) else { return }
        threads[tIdx].messages[mIdx].content = content
    }

    private func updateAssistantIsStreaming(id: UUID, isStreaming: Bool) {
        for tIdx in threads.indices {
            if let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == id }) {
                threads[tIdx].messages[mIdx].isStreaming = isStreaming
                return
            }
        }
    }

    // MARK: - Persistence Helpers

    private func persistThread(_ t: ChatThread) async {
        do {
            try await storage?.saveThread(t, repoID: repoID)
        } catch {
            await MainActor.run { self.lastPersistenceError = L10n("chat.persistence.error") }
        }
    }

    private func scheduleDebounce(for messageID: UUID, threadID: UUID) {
        persistDebounce[messageID]?.cancel()
        persistDebounce[messageID] = Task {
            try? await Task.sleep(for: .seconds(Constants.Timing.chatPersistenceDebounce))
            guard !Task.isCancelled else { return }
            await self.flushMessageToPersistence(id: messageID, threadID: threadID)
        }
    }

    private func cancelDebounce(for messageID: UUID) {
        persistDebounce[messageID]?.cancel()
        persistDebounce.removeValue(forKey: messageID)
    }

    private func flushMessageToPersistence(id: UUID, threadID: UUID) async {
        guard let storage else { return }
        // Find the message across all threads
        var msg: ChatMessage?
        for t in threads where msg == nil {
            msg = t.messages.first { $0.id == id }
        }
        guard let message = msg else { return }
        do {
            try await storage.updateMessage(message, repoID: repoID)
        } catch {
            await MainActor.run { self.lastPersistenceError = L10n("chat.persistence.error") }
        }
    }

    // MARK: - Private Helpers

    private func isDefaultTitle(_ title: String) -> Bool {
        // Default title format: "Untitled yyyy-MM-dd HH:mm" (locale-specific)
        // We match by checking if the title starts with L10n("chat.thread.untitled") base,
        // which is a %@ format string, so we test against a prefix approach.
        let untitledBase = L10n("chat.thread.untitled", "").trimmingCharacters(in: .whitespaces)
        // If format string is "Untitled %@", base becomes "Untitled "
        // If L10n("chat.thread.untitled") strips the %@, match the prefix
        if untitledBase.isEmpty {
            // Fallback: check if title matches "Untitled XXXX" pattern
            return title.hasPrefix("Untitled ")
        }
        return title.hasPrefix(untitledBase)
    }

    private static func makePayload(for text: String) -> AIPromptPayload {
        AIClient.makePromptPayload(
            task: "Chat",
            taskInstructions: """
            You are Zion's coding assistant, embedded in a native macOS git client.

            What you do well:
            - Code review on diffs the user shares via /diff
            - Explain repository structure and file contents via /file <path>
            - Reason about git history (/log) and individual commits (/commit <sha>)
            - Suggest branch names and merge strategies
            - Draft commit messages and PR descriptions (the user copies them)
            - Guide the user through conflict resolution step-by-step

            You are READ-ONLY. You cannot:
            - Execute git commands, stage files, or create commits
            - Edit, create, or delete files in the user's repo
            - Read files outside of /file <path> the user requests

            Context: repository state (repo · branch · HEAD · uncommitted count) is
            prepended to every user message. Treat it as ground truth.

            Slash commands available to the user: /diff /log /status /file /commit.
            Their output appears as fenced blocks in the message. When context is NOT
            already provided, ASK the user to send the right slash command. Map intent:
            - "last commit", "ultimo commit", "current changes" → /diff or /log
            - "show file X" → /file <path>
            - "what changed in <sha>" → /commit <sha>
            - "working tree state" → /status
            Be specific. Example: "Send `/log` and I'll summarize the last commits"
            or "Send `/file Sources/Foo.swift` and I'll review it."
            Do NOT refuse with "I can't show code"; guide the user.

            Output style: concise. Code blocks for commands, file paths, hashes.
            Never invent file paths or commit SHAs you haven't seen in context.
            """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "user_message",
                    label: "User message",
                    content: text,
                    maxLength: AILimits.maxDiffContentLength
                )
            ]
        )
    }
}
