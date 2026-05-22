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

    /// Live tool events from the active CLI stream. Cleared automatically after each event completes.
    var pendingToolEvents: [ChatToolEvent] = []

    // MARK: - Private (non-observable)

    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private let ai: AIClient
    @ObservationIgnored private let worker: RepositoryWorker
    @ObservationIgnored private let contextBuilder: ChatContextBuilder
    @ObservationIgnored private let harness: ZionHarness
    @ObservationIgnored private let streamProvider: ((LocalLLMConfig, AIPromptPayload, Int, String) -> AsyncThrowingStream<String, Error>)?
    @ObservationIgnored private let cliStreamProvider: ((AIPromptPayload, URL) -> AsyncThrowingStream<CLIStreamEvent, Error>)?

    /// Injected storage (nil = volatile/test)
    @ObservationIgnored private let storage: ChatStorage?
    @ObservationIgnored private let repoID: String

    /// Pending debounce tasks keyed by message UUID
    @ObservationIgnored private var persistDebounce: [UUID: Task<Void, Never>] = [:]

    /// Plan detector — lazy, reset at the start of each stream
    @ObservationIgnored private var planDetector: PlanDetector?

    /// The URL of the currently active repo (set during send, used by applyPlan)
    @ObservationIgnored private var activeRepoURL: URL?

    /// The active provider (set during send, used by applyPlan)
    @ObservationIgnored private var activeProvider: AIProvider = .none
    @ObservationIgnored private var activeAPIKey: String = ""
    @ObservationIgnored private var activeMode: AIMode = .efficient
    @ObservationIgnored private var activeBranch: String = ""

    // MARK: - Init (production)

    init(ai: AIClient, worker: RepositoryWorker, contextBuilder: ChatContextBuilder, harness: ZionHarness, storage: ChatStorage? = nil, repoID: String = "") {
        self.ai = ai
        self.worker = worker
        self.contextBuilder = contextBuilder
        self.harness = harness
        self.streamProvider = nil
        self.cliStreamProvider = nil
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
        self.cliStreamProvider = nil
        self.storage = storage
        self.repoID = repoID

        if storage != nil {
            Task { await self.reloadFromStorage() }
        }
    }

    // MARK: - Init (CLI test injection)

    init(
        ai: AIClient,
        worker: RepositoryWorker,
        contextBuilder: ChatContextBuilder,
        harness: ZionHarness,
        cliStreamProvider: @escaping (AIPromptPayload, URL) -> AsyncThrowingStream<CLIStreamEvent, Error>,
        storage: ChatStorage? = nil,
        repoID: String = ""
    ) {
        self.ai = ai
        self.worker = worker
        self.contextBuilder = contextBuilder
        self.harness = harness
        self.streamProvider = nil
        self.cliStreamProvider = cliStreamProvider
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

        // Capture active context for applyPlan
        activeRepoURL = repoURL
        activeProvider = provider
        activeAPIKey = apiKey
        activeMode = mode
        activeBranch = branch

        // Reset plan detector for this stream
        if PlanModeState.current() == .planFirst {
            planDetector = PlanDetector()
        } else {
            planDetector = nil
        }

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

            var payload = Self.makePayload(for: expandedText, provider: provider)
            payload.cwd = repoURL

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

            case .claudeCLI:
                let stream: AsyncThrowingStream<CLIStreamEvent, Error>
                await MainActor.run { self.stampSessionProvider("claude", threadID: threadID) }
                if let injected = self.cliStreamProvider {
                    stream = injected(payload, repoURL)
                } else {
                    let resumeID = await MainActor.run { self.resumeSessionID(for: "claude", threadID: threadID) }
                    stream = await self.ai.streamClaudeCLI(
                        payload: payload,
                        cwd: repoURL,
                        maxTokens: 2048,
                        allowEdits: UserDefaults.standard.bool(forKey: "chat.cliAllowEdits"),
                        resumeSessionID: resumeID
                    )
                }
                await self.consumeCLIStream(stream, assistantID: assistantID, threadID: threadID)

            case .codexCLI:
                let stream: AsyncThrowingStream<CLIStreamEvent, Error>
                await MainActor.run { self.stampSessionProvider("codex", threadID: threadID) }
                if let injected = self.cliStreamProvider {
                    stream = injected(payload, repoURL)
                } else {
                    let resumeID = await MainActor.run { self.resumeSessionID(for: "codex", threadID: threadID) }
                    stream = await self.ai.streamCodexCLI(
                        payload: payload,
                        cwd: repoURL,
                        allowEdits: UserDefaults.standard.bool(forKey: "chat.cliAllowEdits"),
                        resumeSessionID: resumeID
                    )
                }
                await self.consumeCLIStream(stream, assistantID: assistantID, threadID: threadID)

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

        if config.autoStartEnabled, streamProvider == nil {
            await ensureLocalServerRunning(config: config, assistantID: assistantID)
        }

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

    private func ensureLocalServerRunning(config: LocalLLMConfig, assistantID: UUID) async {
        let launcher = LocalServerLauncher()
        let outcome = await launcher.ensureRunning(config: config, engine: config.engineKind)
        switch outcome {
        case .alreadyRunning, .started:
            break // proceed with stream
        case .binaryNotFound(let engine):
            await MainActor.run {
                self.setAssistantContent(
                    id: assistantID,
                    content: L10n("chat.local.autostart.binaryMissing", engine.rawValue)
                )
            }
        case .timedOut:
            await MainActor.run {
                self.setAssistantContent(id: assistantID, content: L10n("chat.local.autostart.timedOut"))
            }
        case .spawnFailed(let message):
            await MainActor.run {
                self.setAssistantContent(
                    id: assistantID,
                    content: L10n("chat.local.autostart.spawnFailed", message)
                )
            }
        case .unsupported:
            break // custom engine — assume user manages it manually
        }
    }

    private func consumeStream(_ stream: AsyncThrowingStream<String, Error>, assistantID: UUID, threadID: UUID) async {
        do {
            for try await delta in stream {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.appendAssistantDelta(id: assistantID, delta: delta)
                    self.scheduleDebounce(for: assistantID, threadID: threadID)
                    if self.planDetector != nil {
                        if let plan = self.planDetector!.feed(delta) {
                            self.planDetector = nil
                            self.attachPlanToAssistant(plan, assistantID: assistantID, threadID: threadID)
                        }
                    }
                }
            }
        } catch {
            // Leave whatever was accumulated
        }
    }

    private func consumeCLIStream(_ stream: AsyncThrowingStream<CLIStreamEvent, Error>, assistantID: UUID, threadID: UUID) async {
        var streamCompleted = false
        do {
            for try await event in stream {
                if Task.isCancelled { break }
                // Discard late events after .done / .error
                if streamCompleted { break }

                switch event {
                case .textDelta(let text):
                    await MainActor.run {
                        self.appendAssistantDelta(id: assistantID, delta: text)
                        self.scheduleDebounce(for: assistantID, threadID: threadID)
                        if self.planDetector != nil {
                            if let plan = self.planDetector!.feed(text) {
                                self.planDetector = nil
                                self.attachPlanToAssistant(plan, assistantID: assistantID, threadID: threadID)
                            }
                        }
                    }

                case .toolStart(let id, let name, let description):
                    await MainActor.run {
                        let event = ChatToolEvent(id: id, name: name, status: .running, argsPreview: String(description.prefix(60)))
                        if let idx = self.pendingToolEvents.firstIndex(where: { $0.id == id }) {
                            self.pendingToolEvents[idx] = event
                        } else {
                            self.pendingToolEvents.append(event)
                        }
                    }

                case .toolEnd(let id, let success, let output):
                    await MainActor.run {
                        if let idx = self.pendingToolEvents.firstIndex(where: { $0.id == id }) {
                            self.pendingToolEvents[idx].status = success ? .completed : .failed
                            self.pendingToolEvents[idx].output = output
                        }
                        // Also persist the final tool event into the assistant message so
                        // it survives a thread reload (pendingToolEvents is transient).
                        self.attachToolEventToAssistant(assistantID: assistantID, id: id, status: success ? .completed : .failed, output: output)
                    }
                    // Schedule cleanup after delay
                    let capturedID = id
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(Constants.Timing.toolEventCleanupDelay * 1_000_000_000))
                        self.pendingToolEvents.removeAll { $0.id == capturedID }
                    }

                case .sessionStarted(let sessionID):
                    await MainActor.run {
                        self.recordCLISessionID(sessionID, threadID: threadID)
                    }

                case .turnCost(let usd):
                    await MainActor.run {
                        self.addTurnCost(usd, threadID: threadID)
                    }

                case .turnUsage(let input, let output):
                    await MainActor.run {
                        self.addTurnUsage(input: input, output: output, threadID: threadID)
                    }

                case .done:
                    streamCompleted = true
                    // Flush any remaining .running events to .completed
                    await MainActor.run {
                        for idx in self.pendingToolEvents.indices where self.pendingToolEvents[idx].status == .running {
                            self.pendingToolEvents[idx].status = .completed
                        }
                    }

                case .error(let msg):
                    streamCompleted = true
                    await MainActor.run {
                        // Flush remaining .running events to .failed
                        for idx in self.pendingToolEvents.indices where self.pendingToolEvents[idx].status == .running {
                            self.pendingToolEvents[idx].status = .failed
                        }
                        self.appendAssistantDelta(id: assistantID, delta: "\n\n" + msg)
                    }
                }
            }
        } catch {
            // Leave whatever was accumulated
            await MainActor.run {
                for idx in self.pendingToolEvents.indices where self.pendingToolEvents[idx].status == .running {
                    self.pendingToolEvents[idx].status = .failed
                }
            }
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

    // MARK: - CLI session resume + cost tracking (MainActor)

    /// Returns the CLI session id stored on the thread when it was opened with
    /// the same provider. Switching providers clears the resume so we don't
    /// hand a claude session id to codex (or vice versa).
    func resumeSessionID(for provider: String, threadID: UUID) -> String? {
        guard let tIdx = threads.firstIndex(where: { $0.id == threadID }) else { return nil }
        let thread = threads[tIdx]
        if thread.cliSessionProvider == provider {
            return thread.cliSessionID
        }
        return nil
    }

    fileprivate func stampSessionProvider(_ provider: String, threadID: UUID) {
        guard let tIdx = threads.firstIndex(where: { $0.id == threadID }) else { return }
        // Switching providers within the same thread invalidates the prior
        // session id (claude id != codex id).
        if threads[tIdx].cliSessionProvider != provider {
            threads[tIdx].cliSessionProvider = provider
            threads[tIdx].cliSessionID = nil
        }
    }

    fileprivate func recordCLISessionID(_ sessionID: String, threadID: UUID) {
        guard let tIdx = threads.firstIndex(where: { $0.id == threadID }) else { return }
        // Only record if empty — re-emitted session lines on subsequent turns are
        // the same id; defensive against future schema additions.
        if threads[tIdx].cliSessionID == nil {
            threads[tIdx].cliSessionID = sessionID
            // Provider tag is recovered from the active provider at send time; we
            // do the actual binding in attachToolEventToAssistant below since both
            // happen in the same MainActor consumer arm.
        } else {
            threads[tIdx].cliSessionID = sessionID
        }
    }

    fileprivate func addTurnCost(_ usd: Double, threadID: UUID) {
        guard let tIdx = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[tIdx].totalCostUSD += usd
    }

    fileprivate func addTurnUsage(input: Int, output: Int, threadID: UUID) {
        guard let tIdx = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[tIdx].totalInputTokens += input
        threads[tIdx].totalOutputTokens += output
    }

    fileprivate func attachToolEventToAssistant(assistantID: UUID, id: String, status: ToolEventStatus, output: String?) {
        for tIdx in threads.indices {
            if let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == assistantID }) {
                var events = threads[tIdx].messages[mIdx].toolEvents ?? []
                if let existing = events.firstIndex(where: { $0.id == id }) {
                    events[existing].status = status
                    events[existing].output = output
                } else {
                    let pending = pendingToolEvents.first(where: { $0.id == id })
                    events.append(ChatToolEvent(
                        id: id,
                        name: pending?.name ?? "tool",
                        status: status,
                        argsPreview: pending?.argsPreview ?? "",
                        output: output
                    ))
                }
                threads[tIdx].messages[mIdx].toolEvents = events
                return
            }
        }
    }

    // MARK: - Plan Attachment (MainActor)

    private func attachPlanToAssistant(_ plan: ChatPlan, assistantID: UUID, threadID: UUID) {
        for tIdx in threads.indices {
            if let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == assistantID }) {
                threads[tIdx].messages[mIdx].plan = plan
                // Schedule persistence with a short debounce so the plan lands in storage
                scheduleDebounce(for: assistantID, threadID: threadID)
                return
            }
        }
    }

    // MARK: - Plan Actions (public API)

    /// Applies the plan attached to a message: takes a recovery snapshot, then re-runs.
    func applyPlan(messageID: UUID) {
        guard let repoURL = activeRepoURL else { return }
        let provider = activeProvider
        let apiKey = activeAPIKey
        let mode = activeMode
        let branch = activeBranch

        Task {
            // Recovery-vault snapshot before potentially destructive apply
            let shortUUID = String(UUID().uuidString.prefix(7))
            let snapshotTag = "zion-pre-plan-apply-\(shortUUID)"
            do {
                let hash = try await worker.runAction(args: ["stash", "create"], in: repoURL)
                let trimmedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedHash.isEmpty {
                    _ = try? await worker.runAction(
                        args: ["stash", "store", "-m", snapshotTag, trimmedHash],
                        in: repoURL
                    )
                }
            } catch {
                // Non-fatal — proceed even if stash fails (clean tree)
            }

            // Find the plan message and the user message that preceded it
            let (planMessage, precedingUserText) = await MainActor.run { () -> (ChatMessage?, String?) in
                guard let tIdx = self.threads.firstIndex(where: { $0.id == self.activeThreadID }) else {
                    return (nil, nil)
                }
                let messages = self.threads[tIdx].messages
                guard let mIdx = messages.firstIndex(where: { $0.id == messageID }) else {
                    return (nil, nil)
                }
                let planMsg = messages[mIdx]
                // Walk backwards for the preceding user message
                let precedingUser = messages[..<mIdx].reversed().first(where: { $0.role == .user })?.content
                return (planMsg, precedingUser)
            }
            guard planMessage != nil else { return }

            // Build re-run text
            let isCLI = (provider == .claudeCLI || provider == .codexCLI)
            let rerunText: String
            if isCLI, let userText = precedingUserText {
                rerunText = userText
            } else {
                let steps = planMessage?.plan?.steps.enumerated().map { i, s in
                    "\(i+1). \(s.summary)"
                }.joined(separator: "\n") ?? ""
                rerunText = "Execute the plan now:\n\(steps)"
            }

            await self.send(
                text: rerunText,
                provider: provider,
                apiKey: apiKey,
                mode: mode,
                repoURL: repoURL,
                branch: branch
            )
        }
    }

    /// Rejects the plan: clears it from the message.
    func rejectPlan(messageID: UUID) {
        for tIdx in threads.indices {
            if let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == messageID }) {
                threads[tIdx].messages[mIdx].plan = nil
                return
            }
        }
    }

    /// Replaces the plan XML in a message (from PlanCard edit).
    func editPlan(messageID: UUID, xml: String) {
        for tIdx in threads.indices {
            if let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == messageID }) {
                guard var plan = threads[tIdx].messages[mIdx].plan else { return }
                var detector = PlanDetector()
                let updatedPlan = detector.feed(xml) ?? PlanDetector().parsePlanXML(xml)
                plan.rawXML = xml
                plan.steps = updatedPlan.steps
                threads[tIdx].messages[mIdx].plan = plan
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

    private static func makePayload(for text: String, provider: AIProvider) -> AIPromptPayload {
        AIClient.makePromptPayload(
            task: "Chat",
            taskInstructions: taskInstructions(for: provider),
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

    private static func taskInstructions(for provider: AIProvider) -> String {
        var base: String
        switch provider {
        case .claudeCLI, .codexCLI:
            // CLI providers bring their own tool harness (Read/Edit/Bash/Grep/etc.) and
            // session memory. We only tell them where they are and let them work.
            base = """
            You are running inside Zion, a native macOS git client. The working
            directory is the user's git repository — use your built-in tools
            (Read, Bash, Edit, etc.) to inspect and act on it.

            File edits are gated by Zion's `chat.cliAllowEdits` setting; if the
            user asked you to modify files and you find you cannot, tell them to
            enable "Allow file edits" in Settings → AI → Subscription CLIs.

            Output style: concise. Code blocks for commands, paths, hashes.
            """
        default:
            base = """
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
            """
        }

        // Plan-first mode: append plan-tag directive so model wraps multi-step proposals in XML
        if PlanModeState.current() == .planFirst {
            base += """


            ## Plan-first mode
            When the user's request requires multiple coordinated changes (edits to
            several files, a multi-step refactor, a new feature spanning many modules),
            wrap your proposed steps in a structured XML block BEFORE writing any prose.
            Use exactly this format:

            <plan>
              <step>
                <commit>feat(scope): short commit message</commit>
                <files>Sources/Foo.swift, Sources/Bar.swift</files>
                <summary>Describe what this step does in one sentence.</summary>
              </step>
              <step>
                <commit>test(scope): add unit tests for Foo</commit>
                <files>Tests/FooTests.swift</files>
                <summary>Add happy-path and error-path unit tests.</summary>
              </step>
            </plan>

            Each <step> is one atomic commit. Keep summaries to one sentence.
            After the plan block, continue with your usual explanation if needed.
            For simple single-file questions, skip the plan block.
            """
        }

        return base
    }
}
