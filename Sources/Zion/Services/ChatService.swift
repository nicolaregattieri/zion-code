import Foundation

// MARK: - ChatService

@MainActor
@Observable
final class ChatService {

    // MARK: - Observable State

    var thread: ChatThread = ChatThread()
    var isStreaming: Bool = false

    // MARK: - Private (non-observable)

    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private let ai: AIClient
    @ObservationIgnored private let worker: RepositoryWorker
    @ObservationIgnored private let contextBuilder: ChatContextBuilder
    @ObservationIgnored private let harness: ZionHarness
    @ObservationIgnored private let streamProvider: ((LocalLLMConfig, AIPromptPayload, Int, String) -> AsyncThrowingStream<String, Error>)?

    // MARK: - Init (production)

    init(ai: AIClient, worker: RepositoryWorker, contextBuilder: ChatContextBuilder, harness: ZionHarness) {
        self.ai = ai
        self.worker = worker
        self.contextBuilder = contextBuilder
        self.harness = harness
        self.streamProvider = nil
    }

    // MARK: - Init (test injection)

    init(
        ai: AIClient,
        worker: RepositoryWorker,
        contextBuilder: ChatContextBuilder,
        harness: ZionHarness,
        streamProvider: @escaping (LocalLLMConfig, AIPromptPayload, Int, String) -> AsyncThrowingStream<String, Error>
    ) {
        self.ai = ai
        self.worker = worker
        self.contextBuilder = contextBuilder
        self.harness = harness
        self.streamProvider = streamProvider
    }

    // MARK: - Public API

    /// Sends a user message and receives a response.
    ///
    /// - For `.local` provider: streams via `AIClient.streamLocalLLM` (or injected provider).
    /// - For other providers: falls back to non-streaming `AIClient.call`.
    func send(
        text: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode,
        repoURL: URL,
        branch: String
    ) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Inject git context header into the first user message only
        let isFirstMessage = thread.messages.filter { $0.role == .user }.isEmpty
        var expandedText: String
        if isFirstMessage {
            let header = await contextBuilder.gitContextHeader(repoURL: repoURL, branch: branch)
            let rawExpanded = await contextBuilder.expandSlashCommands(text, repoURL: repoURL)
            expandedText = header + "\n\n" + rawExpanded
        } else {
            expandedText = await contextBuilder.expandSlashCommands(text, repoURL: repoURL)
        }

        // MARK: Intent fallback — auto-inject git context for tool-incapable providers
        let toolsEnabled = UserDefaults.standard.object(forKey: "chat.toolsEnabled") as? Bool ?? true
        let autoInject = UserDefaults.standard.object(forKey: "chat.autoInject") as? Bool ?? true
        let useTools = toolsEnabled && provider.supportsToolCalling

        if !useTools && autoInject, let intent = IntentClassifier.classify(text) {
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
                expandedText = "```\n\(truncated)\n```\n\n" + expandedText
            }
            // Append the user message now with intent label
            let userMsg = ChatMessage(role: .user, content: expandedText, autoInjectedIntent: label)
            thread.messages.append(userMsg)
        } else {
            thread.messages.append(ChatMessage(role: .user, content: expandedText))
        }

        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        thread.messages.append(assistantMessage)
        let assistantIndex = thread.messages.count - 1

        isStreaming = true

        let task = Task<Void, Never> {
            defer {
                Task { @MainActor in
                    self.isStreaming = false
                    if assistantIndex < self.thread.messages.count {
                        self.thread.messages[assistantIndex].isStreaming = false
                    }
                }
            }

            let payload = Self.makePayload(for: expandedText)

            if provider == .local {
                let config = AIClient.loadLocalConfig() ?? LocalLLMConfig()
                let modelID = config.modelName.isEmpty ? LocalLLMConfig().modelName : config.modelName
                let maxTokens = 2048

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

                do {
                    for try await delta in stream {
                        if Task.isCancelled { break }
                        await MainActor.run {
                            if assistantIndex < self.thread.messages.count {
                                self.thread.messages[assistantIndex].content += delta
                            }
                        }
                    }
                } catch {
                    // Stream error: leave whatever was accumulated
                }
            } else {
                do {
                    let response = try await ai.call(
                        payload: payload,
                        provider: provider,
                        apiKey: apiKey,
                        maxTokens: 2048,
                        lane: .general,
                        mode: mode
                    )
                    await MainActor.run {
                        if assistantIndex < self.thread.messages.count {
                            self.thread.messages[assistantIndex].content = response
                        }
                    }
                } catch {
                    await MainActor.run {
                        if assistantIndex < self.thread.messages.count {
                            self.thread.messages[assistantIndex].content = L10n("chat.error.generic")
                        }
                    }
                }
            }
        }

        activeTask = task
        await task.value
    }

    /// Resets the thread to an empty state and clears harness session state.
    func newThread() {
        activeTask?.cancel()
        activeTask = nil
        isStreaming = false
        thread = ChatThread()
        Task { await harness.resetSession() }
    }

    /// Cancels the active streaming task.
    func stop() {
        activeTask?.cancel()
        activeTask = nil
        isStreaming = false
    }

    // MARK: - Private Helpers

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
            Their output appears as fenced blocks in the message.

            Output style: concise. Code blocks for commands, file paths, hashes.
            Never invent file paths or commit SHAs you haven't seen in context.
            If you'd need to run a command to answer, instruct the user to type that
            slash command first.
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
