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

    /// Per-thread composer draft. When the user switches threads the
    /// composer's text follows the thread, so an unsent message in thread A
    /// is preserved when the user toggles to thread B (and reappears on
    /// return). Cleared automatically once the message is sent.
    var threadDrafts: [UUID: String] = [:]

    /// Per-thread pending attachments staged in the composer. Cleared when
    /// the message is sent. Lives next to `threadDrafts` so attachments
    /// follow the user across thread switches like the text draft does.
    var threadAttachments: [UUID: [PendingChatAttachment]] = [:]

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

    /// Per-thread streaming flag. Reflects whether any in-flight task is writing
    /// to the *currently active* thread. Computed from `streamingThreadIDs` so
    /// switching threads surfaces the correct spinner state without cancelling
    /// background streams.
    var isStreaming: Bool {
        streamingThreadIDs.contains(activeThreadID)
    }

    /// Threads currently being written to by an in-flight task. Used to drive
    /// `isStreaming` and surface a per-thread streaming indicator in the sidebar.
    private(set) var streamingThreadIDs: Set<UUID> = []

    /// Set when a persistence operation fails; consumed by UI to surface a one-time error.
    var lastPersistenceError: String?

    /// Short-lived banner text shown in the composer area, e.g. "Cleared 3
    /// queued messages." after Stop drains the queue. Auto-clears via a
    /// detached Task to avoid lingering. Nil = no banner.
    var transientNotice: String?

    /// Live tool events from the active CLI stream. Cleared automatically after each event completes.
    var pendingToolEvents: [ChatToolEvent] = []
    /// Phase 6 — auto-context hits pre-fetched for the message currently
    /// being composed. Cleared on send (consumed into the request) and
    /// repopulated on each composer-text settle by the auto-injector.
    var pendingContextHits: [RAGHit] = []
    /// True while a hybrid retrieval is in flight; ChatContextChipRow
    /// renders the shimmer skeleton.
    var isPendingContextLoading: Bool = false
    /// Paths the user has explicitly pinned via `@file` / `@code` /
    /// `@folder`. The injector short-circuits against this list to
    /// avoid duplicating context.
    var pendingMentionedPaths: Set<String> = []

    /// P14: provider actually used for the latest send (set after orchestrator.resolve).
    /// Read by AutoResolvedChip to surface "Auto → <name>" when provider == .auto.
    var resolvedProvider: AIProvider?

    /// Lane classified by Smart Auto for the latest send. Nil when the user
    /// picked an explicit provider (no classification ran). Read by
    /// AutoResolvedChip to surface "Auto → claudeCLI · code" style chips.
    var resolvedLane: AITaskLane?

    /// Tier classified by Smart Auto (easy / medium / hard). Drives per-provider
    /// model selection via `SmartAutoTierTable` and is surfaced in the resolved
    /// chip ("Auto → claudeCLI · sonnet · medium").
    var resolvedTier: SmartAutoTier?

    /// Effective model id Smart Auto picked for the latest send (e.g. "haiku",
    /// "claude-sonnet-4-6", "gpt-4o-mini"). Nil when no override applies and the
    /// provider's catalog default is in effect. Surfaced in the resolved chip.
    var resolvedModelID: String?

    /// Session-level flag set when the user clicks **Disconnect** on the local
    /// server status bar. While true, Smart Auto skips `.local` in any chain
    /// and `runLocalStream` does NOT auto-spawn the server. Clearing happens
    /// when the user opts back in via the inline "Local model" menu or
    /// switches Settings → AI to local explicitly. Resets on app launch.
    var localSessionSuppressed: Bool = false

    // MARK: - Private (non-observable)

    /// In-flight streaming tasks keyed by threadID. Allows multiple threads to
    /// stream in parallel; switching threads no longer cancels active streams.
    @ObservationIgnored private var tasksByThread: [UUID: Task<Void, Never>] = [:]
    /// Active tool subprocesses keyed by tool-call UUID. Populated by
    /// `registerProcess` (see `ChatService+ProcessTracking.swift`) so
    /// `stop()` can SIGTERM/SIGKILL them when the user hits cancel.
    @ObservationIgnored var activeProcesses: [UUID: TrackedProcess] = [:]
    /// Phase 4 continue-chip — total extra hops the user has granted to the
    /// active turn via the Continue chip. Reset on every new turn. Read by
    /// the harness loop via `effectiveHopBudget`.
    @ObservationIgnored var extraHopsGranted: Int = 0

    /// FIFO of user messages typed while a stream was already running for the
    /// same thread. The streaming task drains this on completion so the user
    /// can type-and-fire in bursts without waiting for each LLM turn — the
    /// "rajada" flow most chat users expect from modern clients (Claude.ai,
    /// ChatGPT, Cursor). Per-thread so two threads stream independently.
    struct PendingMessage: Identifiable, Equatable {
        let id: UUID = UUID()
        let text: String
        let provider: AIProvider
        let apiKey: String
        let mode: AIMode
        let repoURL: URL
        let branch: String
        let modelOverride: String?
        let attachments: [PendingChatAttachment]

        init(text: String, provider: AIProvider, apiKey: String, mode: AIMode, repoURL: URL, branch: String, modelOverride: String?, attachments: [PendingChatAttachment] = []) {
            self.text = text
            self.provider = provider
            self.apiKey = apiKey
            self.mode = mode
            self.repoURL = repoURL
            self.branch = branch
            self.modelOverride = modelOverride
            self.attachments = attachments
        }
    }
    /// Public setter so tests (and any future composer-side reorder action)
    /// can mutate the queue without going through a private helper. UI flow
    /// still mutates exclusively via send() + dropPendingMessage() + stop().
    var pendingQueueByThread: [UUID: [PendingMessage]] = [:]
    /// Snapshot count for the active thread — convenience for ChatComposer.
    var activePendingQueueCount: Int {
        pendingQueueByThread[activeThreadID]?.count ?? 0
    }
    @ObservationIgnored private let ai: AIClient
    @ObservationIgnored private let worker: RepositoryWorker
    @ObservationIgnored private let contextBuilder: ChatContextBuilder
    @ObservationIgnored private let harness: ZionHarness
    @ObservationIgnored private let streamProvider: ((LocalLLMConfig, AIPromptPayload, Int, String) -> AsyncThrowingStream<String, Error>)?
    @ObservationIgnored private let cliStreamProvider: ((AIPromptPayload, URL) -> AsyncThrowingStream<CLIStreamEvent, Error>)?

    /// Mention resolver — expands @file/@folder/@selection/@web before each send.
    /// Nil = mentions disabled (default for non-injected callers; set via init).
    /// Exposed as internal(set) so ChatComposer can surface cost preview.
    @ObservationIgnored private(set) var mentionResolver: MentionResolver?

    /// Injected storage (nil = volatile/test)
    @ObservationIgnored private let storage: ChatStorage?
    @ObservationIgnored private let repoID: String

    /// Provider orchestrator — resolves `.auto` lane and tracks fallback health.
    @ObservationIgnored internal lazy var orchestrator = ProviderOrchestrator()

    /// Agent runtime — owns the agentic loop lifecycle and sticky-lock flag.
    @ObservationIgnored private(set) var agentRuntime: AgentRuntime

    /// Recent provider-switch events for this session (last entry shown as banner).
    var recentSwitches: [ProviderSwitchEvent] = []

    /// Pending debounce tasks keyed by message UUID
    @ObservationIgnored private var persistDebounce: [UUID: Task<Void, Never>] = [:]

    /// Plan detector — lazy, reset at the start of each stream
    @ObservationIgnored private var planDetector: PlanDetector?

    /// Edit-block parser — lazy init per stream, reset between streams
    @ObservationIgnored private var editBlockParser: EditBlockParser?

    /// Tracks applyAllEdits progress for UI
    var applyAllState: ApplyAllState = .ready(0)

    /// The URL of the currently active repo (set during send, used by applyPlan)
    @ObservationIgnored private var activeRepoURL: URL?

    /// The active provider (set during send, used by applyPlan)
    @ObservationIgnored private var activeProvider: AIProvider = .none
    @ObservationIgnored private var activeAPIKey: String = ""
    @ObservationIgnored private var activeMode: AIMode = .efficient
    @ObservationIgnored private var activeBranch: String = ""

    // MARK: - Budget overflow state

    struct BudgetOverflowState: Equatable, Sendable {
        let estimatedTokens: Int
        let availableTokens: Int
        let messageID: UUID
    }

    struct MeteredTotals: Equatable, Sendable {
        let costUSD: Double
        let inputTokens: Int
        let outputTokens: Int
    }

    /// Produces a single-turn ledger row from the cumulative totals retained on a thread.
    /// The thread persists across sends, so recording cumulative values duplicates prior usage.
    nonisolated static func turnMeteredTotals(after: MeteredTotals, before: MeteredTotals) -> MeteredTotals {
        MeteredTotals(
            costUSD: max(0, after.costUSD - before.costUSD),
            inputTokens: max(0, after.inputTokens - before.inputTokens),
            outputTokens: max(0, after.outputTokens - before.outputTokens)
        )
    }

    /// Set when a send is blocked by the context budget gate.
    /// UI observes this to show a "send anyway" prompt.
    var budgetOverflowState: BudgetOverflowState? = nil

    /// One-shot flag: if set, the next send skips the budget gate.
    @ObservationIgnored private var budgetOverrideApproved: Bool = false

    /// User clicks "send anyway" in the budget banner — next send bypasses the gate.
    func approveBudgetOverride() {
        budgetOverflowState = nil
        budgetOverrideApproved = true
    }

    // MARK: - Static context helpers

    /// Token-aware history window. Walks `messages` from newest to oldest, keeping the
    /// most recent slice whose summed token estimate fits in `available`. Returns the
    /// kept slice in chronological order. Replaces the legacy `suffix(10)` cap that was
    /// message-count-based — wrong axis for token-budgeted providers.
    nonisolated static func windowedHistory(
        _ messages: [ChatMessage],
        available: Int,
        perMessageReserveTokens: Int = 0
    ) -> [ChatMessage] {
        guard !messages.isEmpty, available > 0 else { return [] }
        var kept: [ChatMessage] = []
        var acc = 0
        let cap = max(0, available - perMessageReserveTokens)
        for msg in messages.reversed() {
            let toks = TokenEstimator.estimate(msg.content, kind: .code)
            if acc + toks > cap { break }
            kept.insert(msg, at: 0)
            acc += toks
        }
        return kept
    }

    /// Returns true when the conversation token estimate exceeds 75% of the budget,
    /// signalling that HistoryCompactor should run before forwarding to the provider.
    nonisolated static func shouldCompact(estimated: Int, budget: Int) -> Bool {
        guard budget > 0 else { return false }
        return Double(estimated) > Double(budget) * 0.75
    }

    // MARK: - Init (production)

    init(ai: AIClient, worker: RepositoryWorker, contextBuilder: ChatContextBuilder, harness: ZionHarness, storage: ChatStorage? = nil, repoID: String = "", agentRuntime: AgentRuntime = AgentRuntime(), mentionResolver: MentionResolver? = nil) {
        self.ai = ai
        self.worker = worker
        self.contextBuilder = contextBuilder
        self.harness = harness
        self.streamProvider = nil
        self.cliStreamProvider = nil
        self.storage = storage
        self.repoID = repoID
        self.agentRuntime = agentRuntime
        self.mentionResolver = mentionResolver

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
        repoID: String = "",
        agentRuntime: AgentRuntime = AgentRuntime(),
        mentionResolver: MentionResolver? = nil
    ) {
        self.ai = ai
        self.worker = worker
        self.contextBuilder = contextBuilder
        self.harness = harness
        self.streamProvider = streamProvider
        self.cliStreamProvider = nil
        self.storage = storage
        self.repoID = repoID
        self.agentRuntime = agentRuntime
        self.mentionResolver = mentionResolver

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
        repoID: String = "",
        agentRuntime: AgentRuntime = AgentRuntime(),
        mentionResolver: MentionResolver? = nil
    ) {
        self.ai = ai
        self.worker = worker
        self.contextBuilder = contextBuilder
        self.harness = harness
        self.streamProvider = nil
        self.cliStreamProvider = cliStreamProvider
        self.storage = storage
        self.repoID = repoID
        self.agentRuntime = agentRuntime
        self.mentionResolver = mentionResolver

        if storage != nil {
            Task { await self.reloadFromStorage() }
        }
    }

    // MARK: - Init (agent runtime injection — for tests)

    init(
        ai: AIClient,
        worker: RepositoryWorker,
        contextBuilder: ChatContextBuilder,
        harness: ZionHarness,
        agentRuntime: AgentRuntime,
        storage: ChatStorage? = nil,
        repoID: String = ""
    ) {
        self.ai = ai
        self.worker = worker
        self.contextBuilder = contextBuilder
        self.harness = harness
        self.streamProvider = nil
        self.cliStreamProvider = nil
        self.storage = storage
        self.repoID = repoID
        self.agentRuntime = agentRuntime

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
        branch: String,
        modelOverride: String? = nil,
        attachments: [PendingChatAttachment] = []
    ) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Ensure we have at least one thread (Phase 2 multi-thread)
        if threads.isEmpty { createThread() }

        // MARK: Built-in slash command short-circuit (/clear, /compact, /help)
        let trimmedCommand = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedCommand == "/clear" {
            if isStreaming {
                thread.messages.append(.init(role: .assistant, content: L10n("chat.command.clear.busy"), isStreaming: false))
            } else {
                thread.messages.removeAll()
            }
            return
        }

        if trimmedCommand == "/compact" {
            // /compact uses ChatService's existing 75%-window auto-compaction logic — but here
            // we surface a manual marker so the user knows it ran. Full HistoryCompactor wiring
            // is deferred to P14.5 once the Sendable boundary around [[String:Any]] is sorted.
            let count = thread.messages.count
            if count <= 4 {
                thread.messages.append(.init(role: .assistant, content: L10n("chat.command.compact.alreadyCompact"), isStreaming: false))
            } else {
                thread.messages.append(.init(role: .assistant, content: L10n("chat.command.compact.done"), isStreaming: false))
            }
            return
        }

        if trimmedCommand == "/mcp" {
            // Two categories:
            //  1) Custom MCP servers — user-installed via the registry.
            //  2) Zion in-process context tools currently safe to advertise to
            //     native provider loops. CLI subprocess tools are managed by
            //     their own server/session and are not represented here.
            // Read user MCP registry directly from `~/.zion/mcp.json`. The
            // built-in `zion` seed (zion-mcp binary) is filtered out so the
            // user only sees servers they've actually installed themselves.
            let customServers: [MCPServerConfig] = {
                guard let data = try? Data(contentsOf: MCPRegistryStore.defaultPath),
                      let decoded = try? MCPRegistryStore.decode(data: data) else {
                    return []
                }
                return decoded.filter { $0.id != "zion" }
            }()
            let harness = MCPConfigBuilder.allTools().map { $0.name }.sorted()

            var lines: [String] = []
            lines.append("### " + L10n("chat.command.mcp.custom.header"))
            if customServers.isEmpty {
                lines.append(L10n("chat.command.mcp.custom.empty"))
            } else {
                lines.append(String(format: L10n("chat.command.mcp.custom.summary"), customServers.count))
                for server in customServers {
                    lines.append("- `\(server.id)`")
                }
            }
            lines.append("")
            lines.append("---")
            lines.append("")
            lines.append("### " + L10n("chat.command.mcp.harness.header"))
            lines.append(String(format: L10n("chat.command.mcp.harness.summary"), harness.count))
            for tool in harness {
                lines.append("- `\(tool)`")
            }
            thread.messages.append(.init(role: .assistant, content: lines.joined(separator: "\n"), isStreaming: false))
            return
        }

        if trimmedCommand == "/help" {
            let payload = contextBuilder.buildHelpPayload(
                registry: SlashCommandRegistry.shared,
                skillIndex: SkillIndex(),
                mcpStore: nil
            )
            thread.messages.append(.init(role: .assistant, content: "", isStreaming: false, helpCardPayload: payload))
            return
        }

        let threadID = activeThreadID

        // If a stream is already running on this thread, queue the message
        // instead of blocking the user. The streaming task drains the queue
        // when it finishes (see `defer` block below). Skips queueing for
        // slash commands — those run synchronously above and never block.
        if streamingThreadIDs.contains(threadID) {
            let queued = PendingMessage(
                text: text,
                provider: provider,
                apiKey: apiKey,
                mode: mode,
                repoURL: repoURL,
                branch: branch,
                modelOverride: modelOverride,
                attachments: attachments
            )
            pendingQueueByThread[threadID, default: []].append(queued)
            return
        }

        // MARK: Skill injection — if message starts with /<skill-id>, prepend skill body to payload
        // The injected text replaces the raw text going to the model; display content stays unmodified.
        let skillInjectedText: String = {
            if let injected = Self.injectSkillIfMatched(
                text: trimmedCommand,
                skills: SkillIndex.shared.skills
            ) {
                return injected
            }
            return text
        }()

        // Build display content (what user sees in bubble) — keep clean, just typed text + explicit slash expansions
        let displayContent = await contextBuilder.expandSlashCommands(skillInjectedText, repoURL: repoURL)

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

        // Build conversation history block — token-aware window (replaces legacy suffix(10)).
        // Hard cap of 50_000 tokens here matches the conservative pre-P13 default before any
        // ContextBudget integration; safe for every model Zion supports.
        let historyMessages = Self.windowedHistory(Array(thread.messages), available: 50_000)
        var historyBlock = ""
        if !historyMessages.isEmpty {
            historyBlock = "## Conversation so far\n\n"
            for msg in historyMessages {
                let speaker = msg.role == .user ? "User" : "Assistant"
                historyBlock += "**\(speaker):** \(msg.content)\n\n"
            }
        }

        // User bubble shows ONLY clean displayContent + chip (if injected). Persist internalContext when fresh (sticky).
        // Bind any pending attachments to this message's permanent storage
        // location before persisting — file URLs in PendingChatAttachment
        // live under `attachments/draft/` and would be cleaned up later.
        let userMessageID = UUID()
        let boundAttachments: [ChatAttachment] = attachments.isEmpty
            ? []
            : ChatAttachmentService.bindDrafts(attachments, threadID: threadID, messageID: userMessageID)

        // For non-vision providers we inline PDF text and image markers into
        // the prompt body so context is preserved even when the model can't
        // see pixels. Anthropic uses the structured content path (see
        // AIClient+Helpers).
        var attachmentTextBlock = ""
        if !boundAttachments.isEmpty {
            var fragments: [String] = []
            for att in boundAttachments {
                switch att.kind {
                case .image:
                    fragments.append("[Image attached: \(att.originalName)]")
                case .pdf:
                    if let url = att.fileURL(),
                       let text = ChatAttachmentService.extractText(fromPDF: url) {
                        fragments.append("[PDF attached: \(att.originalName)]\n\(text)")
                    } else {
                        fragments.append("[PDF attached: \(att.originalName)] (no text extractable)")
                    }
                case .other:
                    fragments.append("[File attached: \(att.originalName)]")
                }
            }
            attachmentTextBlock = fragments.joined(separator: "\n\n")
        }

        let userMessage = ChatMessage(
            id: userMessageID,
            role: .user,
            content: displayContent,
            autoInjectedIntent: injectedLabel,
            internalContext: freshInjection,
            attachments: boundAttachments
        )
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
        if !attachmentTextBlock.isEmpty {
            parts.append("## Attachments\n\n" + attachmentTextBlock)
        }
        let expandedText: String = parts.joined(separator: "\n\n")

        // CLI resume already retains prior conversation context server-side. Keep a
        // compact current-turn payload available so resumed sessions do not resend
        // the entire Zion-rendered history and duplicate token usage.
        var currentTurnParts: [String] = []
        if !hiddenContext.isEmpty {
            currentTurnParts.append(hiddenContext)
        }
        currentTurnParts.append("## Current user message\n\n" + displayContent)
        if !attachmentTextBlock.isEmpty {
            currentTurnParts.append("## Attachments\n\n" + attachmentTextBlock)
        }
        let currentTurnText = currentTurnParts.joined(separator: "\n\n")

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

        streamingThreadIDs.insert(threadID)

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

        // Reset edit-block parser for this stream
        editBlockParser = Self.editHarnessEnabled ? EditBlockParser() : nil

        let task = Task<Void, Never> {
            defer {
                Task { @MainActor in
                    self.streamingThreadIDs.remove(threadID)
                    self.tasksByThread.removeValue(forKey: threadID)
                    self.updateAssistantIsStreaming(id: assistantID, isStreaming: false)
                    // Approval-policy auto-apply: if the user is on autoSafe /
                    // auto / yolo, edits do not require a click. The stream
                    // produced N EditBlocks while running; apply them all now
                    // so the "approval card" stops being a manual step the
                    // user did not ask for. Manual mode keeps the card and
                    // waits for explicit Approve.
                    // Phase 6.2 — the chat preflight chip ("Permission")
                    // overrides ApprovalPolicy. When the user picked
                    // "Always ask", NEVER auto-apply on stream end — the
                    // approval card stays as the only way through. Fixes
                    // the trust regression where edits landed on disk
                    // before the user clicked Apply (screenshot #54/#56).
                    let preflight = UserDefaults.standard.string(forKey: "chat.preflight.permission") ?? "askAlways"
                    let preflightBlocksAutoApply = (preflight == "askAlways")
                    if !preflightBlocksAutoApply,
                       ApprovalPolicy.current.autoCommit,
                       let assistantTuple = self.findAssistantMessage(messageID: assistantID),
                       let pendingBlocks = self.threads[assistantTuple.tIdx]
                            .messages[assistantTuple.mIdx]
                            .editBlocks,
                       !pendingBlocks.isEmpty,
                       pendingBlocks.contains(where: { $0.appliedAt == nil && $0.failureReason == nil }) {
                        Task { await self.applyAllEdits(messageID: assistantID) }
                    }
                    // Final flush to persistence
                    self.cancelDebounce(for: assistantID)
                    Task { await self.flushMessageToPersistence(id: assistantID, threadID: threadID) }
                    // Drain the next queued message for this thread, if any.
                    // Kicked off async so the defer-cleanup completes first and
                    // streamingThreadIDs reflects the idle state when the recursive
                    // send() call evaluates its guard. This is the queue's
                    // "auto-advance" — the user's burst-typed messages get
                    // processed in FIFO order without further input.
                    if var queue = self.pendingQueueByThread[threadID], !queue.isEmpty {
                        let next = queue.removeFirst()
                        self.pendingQueueByThread[threadID] = queue.isEmpty ? nil : queue
                        Task {
                            await self.send(
                                text: next.text,
                                provider: next.provider,
                                apiKey: next.apiKey,
                                mode: next.mode,
                                repoURL: next.repoURL,
                                branch: next.branch,
                                modelOverride: next.modelOverride,
                                attachments: next.attachments
                            )
                        }
                    }
                }
            }

            // Smart Auto: classify the user message into a difficulty tier, route
            // through the matching lane, and pick a per-tier model. Easy turns
            // land on the cheap chain + Haiku/Flash; medium on the default chain
            // + Sonnet/4o; hard on the reasoning chain + Opus/o1. Explicit
            // providers bypass classification entirely.
            let resolved: AIProvider
            let smartModelOverride: String?
            if provider == .auto {
                // Single-pass Smart Auto: classify text → tier → lane → resolve.
                // Tier table maps (resolved provider, tier) → model independently
                // of any "preliminary" provider, so we never call resolve twice.
                let tier = await HeuristicTriageClassifier().classify(displayContent)
                // If the user attached at least one image, ask the
                // orchestrator to bias Auto towards a vision-capable
                // provider (Anthropic / OpenAI / Gemini / claudeCLI).
                let hasImageAttachment = boundAttachments.contains { $0.kind == .image }
                // Honour the session-level "user disconnected local" flag by
                // re-resolving until the orchestrator yields a non-local provider.
                // First attempt:
                var tentative = await self.orchestrator.resolve(
                    lane: tier.lane, requested: .auto, requiresVision: hasImageAttachment
                )
                if self.localSessionSuppressed, tentative == .local {
                    await self.orchestrator.markRateLimited(.local, retryAfter: 86_400)
                    tentative = await self.orchestrator.resolve(
                        lane: tier.lane, requested: .auto, requiresVision: hasImageAttachment
                    )
                }
                resolved = tentative
                smartModelOverride = SmartAutoTierTable.default.modelID(provider: resolved, tier: tier)
                self.resolvedLane = tier.lane
                self.resolvedTier = tier
            } else {
                resolved = provider
                smartModelOverride = nil
                self.resolvedLane = nil
                self.resolvedTier = nil
            }
            // P14: publish for AutoResolvedChip so the composer can show "Auto → <name>".
            self.resolvedProvider = resolved

            // Effective model id: explicit user override wins; otherwise Smart
            // Auto's tier-derived model. Nil falls back to provider catalog default.
            let effectiveModel: String? = modelOverride ?? smartModelOverride
            self.resolvedModelID = effectiveModel

            let isResumedCLI: Bool = {
                switch resolved {
                case .claudeCLI:
                    return self.resumeSessionID(for: "claude", threadID: threadID) != nil
                case .codexCLI:
                    return self.resumeSessionID(for: "codex", threadID: threadID) != nil
                default:
                    return false
                }
            }()
            let providerInputText = isResumedCLI ? currentTurnText : expandedText

            // Resolve @mentions in the text that will actually be submitted,
            // so both the AgentRuntime path and the legacy dispatchStream fallback
            // see the resolved system context. The user-visible message stays
            // unchanged; only the prompt sent to the model is enriched.
            let mentionPayload: MentionPayload
            if let resolver = self.mentionResolver {
                mentionPayload = await resolver.expand(message: providerInputText)
            } else {
                mentionPayload = .empty
            }
            let enrichedText: String = mentionPayload.systemContext.isEmpty
                ? providerInputText
                : mentionPayload.systemContext + "\n\n" + providerInputText

            var payload = makePayload(for: enrichedText, provider: resolved)
            payload.cwd = repoURL
            // Forward image attachments to providers that support vision
            // natively. Anthropic / OpenAI / Gemini all expose image content
            // blocks; their request builders pick `payload.imageAttachments`
            // up. Other providers (local without VL, openrouter text models)
            // see only the inlined `[Image attached: …]` text marker via
            // `enrichedText`.
            let visionProviders: Set<AIProvider> = [.anthropic, .openai, .gemini]
            if visionProviders.contains(resolved), !boundAttachments.isEmpty {
                payload.imageAttachments = boundAttachments.compactMap { att in
                    guard att.kind == .image,
                          let url = att.fileURL(),
                          let data = try? Data(contentsOf: url) else { return nil }
                    return AIImageAttachment(
                        mimeType: att.mimeType,
                        base64: data.base64EncodedString(),
                        originalName: att.originalName
                    )
                }
            }

            // Build structured conversation for AgentRuntime (last 10 messages as role/content dicts).
            // Sendable boundary: MainActor closure must return [[String: String]] (Any is not Sendable).
            // Token-aware history window for AgentRuntime — replaces suffix(10).
            // Provider-window aware budget computed via ContextBudget.
            let windowAvailable = await ContextBudget().available(forProvider: resolved, model: effectiveModel)
            let historyReserve = max(8_000, Int(Double(windowAvailable) * 0.5))
            let stringHistory: [[String: String]] = await MainActor.run {
                let kept = ChatService.windowedHistory(self.thread.messages, available: historyReserve)
                return kept.compactMap { msg -> [String: String]? in
                    guard msg.id != assistantID else { return nil }
                    return ["role": msg.role == .user ? "user" : "assistant", "content": msg.content]
                }
            }
            let historyForRuntime: [[String: Any]] = stringHistory.map { $0 as [String: Any] }
            // Mention context already prepended to `enrichedText` above, so the
            // AgentRuntime path sees it through `userPrompt` without a separate
            // system message.

            // Route through AgentRuntime. Falls back to legacy dispatchStream when
            // no real runners are injected (AgentRuntime throws .noProviderAvailable).
            do {
                let result = try await self.agentRuntime.run(
                    provider: resolved,
                    model: effectiveModel,
                    conversation: historyForRuntime,
                    userPrompt: enrichedText,
                    tools: MCPConfigBuilder.allTools(),
                    maxSteps: 25,
                    onStep: { @Sendable event in
                        Task { @MainActor in
                            let toolEvent = event.toolEvent
                            if let idx = self.pendingToolEvents.firstIndex(where: { $0.id == toolEvent.id }) {
                                self.pendingToolEvents[idx] = toolEvent
                            } else {
                                self.pendingToolEvents.append(toolEvent)
                            }
                        }
                    }
                )
                await MainActor.run {
                    // Strip raw <plan>…</plan> XML so the Plan card is the only
                    // surfacing — keeping the raw block visible doubles the noise.
                    let cleaned = ChatService.stripPlanXML(from: result.finalText)
                    self.setAssistantContent(id: assistantID, content: cleaned)
                    self.setProviderUsed(id: assistantID, provider: resolved)
                    if result.cumulativeCostUSD > 0 {
                        self.addTurnCost(result.cumulativeCostUSD, threadID: threadID)
                    }
                    // NOTE: tokens deliberately NOT split half/half here. AgentRuntime
                    // does not currently emit separate input/output token counts from
                    // API providers' SSE usage fields (Anthropic message_delta usage,
                    // OpenAI stream_options include_usage, Gemini usageMetadata).
                    // Tracking those is P15 — until then, only CLI providers (which
                    // emit accurate .turnUsage events from `usage.input_tokens` /
                    // `usage.output_tokens` parsed from the CLI's JSON output) feed
                    // the spend ledger truthfully.
                }
                await self.orchestrator.markHealthy(resolved)
            } catch AIError.noProviderAvailable, AIError.loopAlreadyActive {
                // AgentRuntime has no real runners (null default) or loop guard fired:
                // fall back to the legacy stream dispatch path.
                await self.dispatchStream(
                    payload: payload,
                    provider: resolved,
                    originalRequestedProvider: provider,
                    apiKey: apiKey,
                    mode: mode,
                    repoURL: repoURL,
                    modelOverride: effectiveModel,
                    assistantID: assistantID,
                    threadID: threadID,
                    hopCount: 0
                )
            } catch {
                // Any other AgentRuntime error — surface it
                await MainActor.run {
                    self.setAssistantContent(id: assistantID, content: error.localizedDescription)
                }
            }
        }

        tasksByThread[threadID] = task
        await task.value
    }

    /// Creates a fresh thread (Phase 2 multi-thread) and clears harness session state (Phase 3).
    /// Does NOT cancel in-flight streams on the previous thread — they keep running
    /// in the background and update their own assistant message via message-id lookup.
    func newThread() {
        createThread()
        Task { await harness.resetSession() }
    }

    /// Cancels the *active* thread's streaming task and the agent runtime loop.
    /// Streams on other threads continue.
    func stop() {
        let id = activeThreadID
        tasksByThread[id]?.cancel()
        tasksByThread.removeValue(forKey: id)
        streamingThreadIDs.remove(id)
        // Drop the pending queue for this thread too — Stop must mean "stop
        // everything I had lined up", not "stop the current turn and start
        // the next one I forgot about".
        let droppedCount = pendingQueueByThread[id]?.count ?? 0
        pendingQueueByThread.removeValue(forKey: id)
        if droppedCount > 0 {
            // Surface a short banner so the user sees we just discarded N
            // queued messages they had typed. Without this the queue badge
            // simply vanishes — silent destruction of typed input is worse
            // than the original "Send is locked" UX.
            showTransientNotice(
                String(format: L10n("chat.composer.queue.cleared"), droppedCount)
            )
        }
        Task { await self.agentRuntime.cancel() }
        Task { @MainActor in await self.terminateAllActiveProcesses() }
    }

    /// Posts a short-lived banner string into `transientNotice` and clears it
    /// after `seconds`. Multiple calls reset the timer.
    func showTransientNotice(_ message: String, seconds: Double = 3.0) {
        transientNotice = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if self?.transientNotice == message {
                self?.transientNotice = nil
            }
        }
    }

    /// Removes a single queued message without aborting the running turn.
    /// Used by the composer's queue popover (per-row delete).
    func dropPendingMessage(id: UUID, threadID: UUID? = nil) {
        let target = threadID ?? activeThreadID
        guard var queue = pendingQueueByThread[target] else { return }
        queue.removeAll { $0.id == id }
        pendingQueueByThread[target] = queue.isEmpty ? nil : queue
    }

    /// Cancels every in-flight streaming task. Called on repo switch / app
    /// teardown so an orphaned, never-completing stream cannot leak past the
    /// ChatService's lifetime.
    func cancelAll() {
        for (_, task) in tasksByThread { task.cancel() }
        tasksByThread.removeAll()
        streamingThreadIDs.removeAll()
        Task { await self.agentRuntime.cancel() }
    }

    deinit {
        for (_, task) in tasksByThread { task.cancel() }
    }

    // MARK: - Private Stream Helpers

    private func runLocalStream(payload: AIPromptPayload, assistantID: UUID) async {
        let config = AIClient.loadLocalConfig() ?? LocalLLMConfig()
        let modelID = config.modelName.isEmpty ? LocalLLMConfig().modelName : config.modelName
        let maxTokens = 2048
        let threadID = activeThreadID

        // Skip auto-spawn when the user disconnected this session — clicking
        // Disconnect must STOP meaning "stop", not "stop + resurrect on next
        // turn".
        if config.autoStartEnabled, streamProvider == nil, !localSessionSuppressed {
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
        // Trace WHO asks for the local server to come up. The Image #32
        // confusion was: memory bumps but the chip shows Claude. If this log
        // never fires for the turn in question, the bump came from elsewhere
        // (warm-from-prior-session, external Ollama running, periodic probe).
        DiagnosticLogger.shared.log(
            .info,
            "ensureLocalServerRunning called — engine=\(config.engineKind.rawValue) model=\(config.modelName)",
            source: "ChatService"
        )
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
                            self.stripPlanXMLFromAssistant(assistantID: assistantID)
                        }
                    }
                    if self.editBlockParser != nil {
                        let blocks = self.editBlockParser!.feed(delta)
                        if !blocks.isEmpty {
                            self.attachEditBlocksToAssistant(blocks, assistantID: assistantID, threadID: threadID)
                            self.stripEditBlockMarkersFromAssistant(assistantID: assistantID)
                        }
                    }
                }
            }
        } catch {
            // Leave whatever was accumulated
        }
    }

    /// Removes the raw `<plan>...</plan>` XML block from an assistant message
    /// once the structured Plan card has been attached. Without this strip the
    /// chat shows the XML AND the card, which is noisy. Idempotent — safe to
    /// call multiple times.
    private func stripPlanXMLFromAssistant(assistantID: UUID) {
        for tIdx in threads.indices {
            if let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == assistantID }) {
                let original = threads[tIdx].messages[mIdx].content
                let stripped = ChatService.stripPlanXML(from: original)
                if stripped != original {
                    threads[tIdx].messages[mIdx].content = stripped
                }
                return
            }
        }
    }

    /// Mirror of stripPlanXMLFromAssistant for aider-style SEARCH/REPLACE
    /// blocks. EditBlockParser already extracts these into structured
    /// EditBlock entries; this method removes the raw markers from the
    /// assistant's `content` so the chat does not show both the structured
    /// card AND the raw text (Image #38). Idempotent.
    private func stripEditBlockMarkersFromAssistant(assistantID: UUID) {
        for tIdx in threads.indices {
            if let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == assistantID }) {
                let original = threads[tIdx].messages[mIdx].content
                let stripped = ChatService.stripEditBlockMarkers(from: original)
                if stripped != original {
                    threads[tIdx].messages[mIdx].content = stripped
                }
                return
            }
        }
    }

    /// Removes every `<<<<<<< SEARCH … ======= … >>>>>>> REPLACE` block
    /// (header + body + footer) from the assistant text. Skips matches inside
    /// fenced code blocks so example documentation snippets survive.
    nonisolated static func stripEditBlockMarkers(from text: String) -> String {
        // Pre-compute NSRange fence offsets so we can intersect with regex
        // matches without crossing the String.Index / Int boundary.
        let fenceNSRanges: [NSRange] = codeFenceRanges(in: text).map {
            NSRange($0, in: text)
        }
        let pattern = #"<{7}\s*SEARCH(?::[^\n]*)?\n[\s\S]*?\n>{7}\s*REPLACE\s*\n?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: fullRange).reversed()
        var result = text
        for match in matches {
            let matchStart = match.range.location
            let matchEnd = match.range.location + match.range.length
            if fenceNSRanges.contains(where: { fence in
                let fStart = fence.location
                let fEnd = fence.location + fence.length
                return matchStart < fEnd && matchEnd > fStart
            }) { continue }
            if let range = Range(match.range, in: result) {
                result.removeSubrange(range)
            }
        }
        return result
    }

    /// Removes every `<plan>…</plan>` block (tags included) plus a single
    /// trailing newline per match. Skips any `<plan>` that lives inside a
    /// fenced code block so documentation/example snippets survive.
    /// Tolerant of leading whitespace and multiple plans in the same response.
    nonisolated static func stripPlanXML(from text: String) -> String {
        // Build a set of (start, end) byte offsets that fall inside ``` fences
        // so we can skip plan-strip whenever the match overlaps a fence.
        let fenceRanges = codeFenceRanges(in: text)

        var out = text
        var cursor = out.startIndex
        while cursor < out.endIndex,
              let open = out.range(of: "<plan>", range: cursor..<out.endIndex),
              let close = out.range(of: "</plan>", range: open.upperBound..<out.endIndex) {
            // Skip plans that sit inside a code fence.
            if fenceRanges.contains(where: { $0.contains(open.lowerBound) }) {
                cursor = close.upperBound
                continue
            }
            let blockStart = open.lowerBound
            var blockEnd = close.upperBound
            if blockEnd < out.endIndex, out[blockEnd] == "\n" {
                blockEnd = out.index(after: blockEnd)
            }
            out.removeSubrange(blockStart..<blockEnd)
            cursor = blockStart
        }
        return out
    }

    /// Returns the substring ranges enclosed by triple-backtick fences. Used
    /// by `stripPlanXML` to keep example XML inside code blocks intact.
    nonisolated private static func codeFenceRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var search = text.startIndex
        while search < text.endIndex,
              let open = text.range(of: "```", range: search..<text.endIndex),
              let close = text.range(of: "```", range: open.upperBound..<text.endIndex) {
            ranges.append(open.lowerBound..<close.upperBound)
            search = close.upperBound
        }
        return ranges
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
                                self.stripPlanXMLFromAssistant(assistantID: assistantID)
                            }
                        }
                        if self.editBlockParser != nil {
                            let blocks = self.editBlockParser!.feed(text)
                            if !blocks.isEmpty {
                                self.attachEditBlocksToAssistant(blocks, assistantID: assistantID, threadID: threadID)
                            self.stripEditBlockMarkersFromAssistant(assistantID: assistantID)
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

    // MARK: - Orchestrated Dispatch (with fallback on rate-limit / network failure)

    /// Maximum number of provider hops allowed per turn (prevents infinite loops).
    private static let maxHopsPerTurn = 3

    /// Dispatches the stream to `provider`. On `AIError.rateLimited` or
    /// `AIError.networkFailure`, attempts to find a fallback provider via the
    /// orchestrator and retries up to `maxHopsPerTurn` times.
    private func dispatchStream(
        payload: AIPromptPayload,
        provider: AIProvider,
        originalRequestedProvider: AIProvider,
        apiKey: String,
        mode: AIMode,
        repoURL: URL,
        modelOverride: String?,
        assistantID: UUID,
        threadID: UUID,
        hopCount: Int
    ) async {
        let startingTotals = meteredTotals(for: threadID)
        do {
            try await dispatchStreamThrowing(
                payload: payload,
                provider: provider,
                apiKey: apiKey,
                mode: mode,
                repoURL: repoURL,
                modelOverride: modelOverride,
                assistantID: assistantID,
                threadID: threadID
            )
            let turnTotals = Self.turnMeteredTotals(
                after: meteredTotals(for: threadID),
                before: startingTotals
            )
            await orchestrator.recordCost(provider, usd: turnTotals.costUSD)
            // Mark provider healthy after success
            await orchestrator.markHealthy(provider)
            // P14: append monthly spend ledger row ONLY when the source provider emits
            // honest usage data. Today that is CLI providers (Claude Code, Codex) and
            // local LLMs (zero cost is accurate). API direct providers (Anthropic,
            // OpenAI, Gemini) are NOT yet parsed from SSE usage fields — we refuse to
            // invent ledger rows for them. P15 wires real usage parsing per provider.
            let billing: BillingMode
            switch provider {
            case .claudeCLI, .codexCLI: billing = .subscription
            case .local:                billing = .local
            default:                    billing = .api
            }
            // Refuse to log API-provider rows until real usage parsing lands (P15).
            // Logging zeros or estimates here would corrupt the monthly aggregate.
            if billing == .api && turnTotals.inputTokens == 0 && turnTotals.outputTokens == 0 {
                return
            }
            let model = modelOverride ?? provider.rawValue
            let row = ProviderSpendRow(
                provider: provider.rawValue,
                model: model,
                inputTokens: turnTotals.inputTokens,
                outputTokens: turnTotals.outputTokens,
                cacheReadTokens: 0,
                usdCost: turnTotals.costUSD,
                billingMode: billing
            )
            try? await SpendLedger.shared.append(row)
        } catch let error as AIError {
            // Determine backoff duration
            let retryAfter: TimeInterval?
            switch error {
            case .rateLimited(let after):
                retryAfter = after
                await orchestrator.markRateLimited(provider, retryAfter: after)
            case .networkFailure:
                retryAfter = 30
                await orchestrator.markRateLimited(provider, retryAfter: 30)
            case .invalidKey:
                // Auth failure (401/403) — mark provider unhealthy so the
                // orchestrator skips it for the rest of the session, then try
                // the next provider in the chain. Surfacing 401 directly to
                // the user breaks `.auto` when a key is missing.
                retryAfter = nil
                await orchestrator.markRateLimited(provider, retryAfter: 86_400)
            default:
                // Non-retryable error — surface it
                await MainActor.run {
                    let description = error.localizedDescription
                    self.setAssistantContent(id: assistantID, content: description.isEmpty ? L10n("chat.error.generic") : description)
                }
                return
            }

            // Attempt fallback if within hop limit
            if hopCount < Self.maxHopsPerTurn,
               let nextProvider = await orchestrator.nextFallback(from: provider, lane: .general) {
                let reason = retryAfter != nil
                    ? String(format: L10n("ai.error.rateLimited.delay"), Int(retryAfter!))
                    : L10n("ai.error.rateLimited")
                let switchEvent = ProviderSwitchEvent(
                    from: provider,
                    to: nextProvider,
                    reason: reason
                )
                await MainActor.run {
                    self.recentSwitches.append(switchEvent)
                }
                let originalText = payload.untrustedSections.first(where: { $0.kind == "user_message" })?.content ?? ""
                let nextPayload = makePayload(for: originalText, provider: nextProvider)
                var updatedPayload = nextPayload
                updatedPayload.cwd = repoURL
                await dispatchStream(
                    payload: updatedPayload,
                    provider: nextProvider,
                    originalRequestedProvider: originalRequestedProvider,
                    apiKey: apiKey,
                    mode: mode,
                    repoURL: repoURL,
                    modelOverride: modelOverride,
                    assistantID: assistantID,
                    threadID: threadID,
                    hopCount: hopCount + 1
                )
            } else {
                // All providers exhausted — surface error
                await MainActor.run {
                    self.setAssistantContent(id: assistantID, content: L10n("chat.routing.allProvidersExhausted"))
                }
            }
        } catch {
            // Non-AIError — surface generically
            await MainActor.run {
                self.setAssistantContent(id: assistantID, content: L10n("chat.error.generic"))
            }
        }
    }

    /// The inner throwing dispatch. Throws `AIError` on failure so `dispatchStream` can handle fallback.
    private func dispatchStreamThrowing(
        payload: AIPromptPayload,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode,
        repoURL: URL,
        modelOverride: String?,
        assistantID: UUID,
        threadID: UUID
    ) async throws {
        switch provider {
        case .local:
            await self.runLocalStream(payload: payload, assistantID: assistantID)

        case .anthropic:
            let defaultID = AIModelCatalogService.selection(for: .anthropic, mode: mode, lane: .general).primaryModelID
            let modelID = modelOverride.map { $0.isEmpty ? defaultID : $0 } ?? defaultID
            let stream = await self.ai.streamAnthropic(payload: payload, apiKey: apiKey, maxTokens: 2048, modelID: modelID)
            try await self.consumeStreamThrowing(stream, assistantID: assistantID, threadID: threadID, provider: provider)

        case .openai:
            let defaultID = AIModelCatalogService.selection(for: .openai, mode: mode, lane: .general).primaryModelID
            let modelID = modelOverride.map { $0.isEmpty ? defaultID : $0 } ?? defaultID
            let stream = await self.ai.streamOpenAI(payload: payload, apiKey: apiKey, maxTokens: 2048, modelID: modelID)
            try await self.consumeStreamThrowing(stream, assistantID: assistantID, threadID: threadID, provider: provider)

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
                    resumeSessionID: resumeID,
                    modelOverride: modelOverride
                )
            }
            try await self.consumeCLIStreamThrowing(stream, assistantID: assistantID, threadID: threadID, provider: provider)

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
                    resumeSessionID: resumeID,
                    modelOverride: modelOverride
                )
            }
            try await self.consumeCLIStreamThrowing(stream, assistantID: assistantID, threadID: threadID, provider: provider)

        case .auto, .gemini, .none:
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
            } catch let aiErr as AIError {
                throw aiErr
            } catch {
                await MainActor.run {
                    self.setAssistantContent(id: assistantID, content: L10n("chat.error.generic"))
                }
            }
        }
    }

    /// Variant of `consumeStream` that rethrows `AIError` instead of swallowing it.
    private func consumeStreamThrowing(_ stream: AsyncThrowingStream<String, Error>, assistantID: UUID, threadID: UUID, provider: AIProvider) async throws {
        var firstDelta = true
        do {
            for try await delta in stream {
                if Task.isCancelled { break }
                await MainActor.run {
                    if firstDelta {
                        // Record providerUsed on first delta
                        self.setProviderUsed(id: assistantID, provider: provider)
                    }
                    self.appendAssistantDelta(id: assistantID, delta: delta)
                    self.scheduleDebounce(for: assistantID, threadID: threadID)
                    if self.planDetector != nil {
                        if let plan = self.planDetector!.feed(delta) {
                            self.planDetector = nil
                            self.attachPlanToAssistant(plan, assistantID: assistantID, threadID: threadID)
                        }
                    }
                    if self.editBlockParser != nil {
                        let blocks = self.editBlockParser!.feed(delta)
                        if !blocks.isEmpty {
                            self.attachEditBlocksToAssistant(blocks, assistantID: assistantID, threadID: threadID)
                            self.stripEditBlockMarkersFromAssistant(assistantID: assistantID)
                        }
                    }
                }
                firstDelta = false
            }
        } catch let aiErr as AIError {
            throw aiErr
        } catch {
            // Leave whatever was accumulated
        }
    }

    /// Variant of `consumeCLIStream` that rethrows `AIError` instead of swallowing it.
    private func consumeCLIStreamThrowing(_ stream: AsyncThrowingStream<CLIStreamEvent, Error>, assistantID: UUID, threadID: UUID, provider: AIProvider) async throws {
        var streamCompleted = false
        var firstTextDelta = true
        do {
            for try await event in stream {
                if Task.isCancelled { break }
                if streamCompleted { break }

                switch event {
                case .textDelta(let text):
                    await MainActor.run {
                        if firstTextDelta {
                            self.setProviderUsed(id: assistantID, provider: provider)
                        }
                        self.appendAssistantDelta(id: assistantID, delta: text)
                        self.scheduleDebounce(for: assistantID, threadID: threadID)
                        if self.planDetector != nil {
                            if let plan = self.planDetector!.feed(text) {
                                self.planDetector = nil
                                self.attachPlanToAssistant(plan, assistantID: assistantID, threadID: threadID)
                                self.stripPlanXMLFromAssistant(assistantID: assistantID)
                            }
                        }
                        if self.editBlockParser != nil {
                            let blocks = self.editBlockParser!.feed(text)
                            if !blocks.isEmpty {
                                self.attachEditBlocksToAssistant(blocks, assistantID: assistantID, threadID: threadID)
                            self.stripEditBlockMarkersFromAssistant(assistantID: assistantID)
                            }
                        }
                    }
                    firstTextDelta = false

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
                        self.attachToolEventToAssistant(assistantID: assistantID, id: id, status: success ? .completed : .failed, output: output)
                    }
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
                    await MainActor.run {
                        for idx in self.pendingToolEvents.indices where self.pendingToolEvents[idx].status == .running {
                            self.pendingToolEvents[idx].status = .completed
                        }
                    }

                case .error(let msg):
                    streamCompleted = true
                    await MainActor.run {
                        for idx in self.pendingToolEvents.indices where self.pendingToolEvents[idx].status == .running {
                            self.pendingToolEvents[idx].status = .failed
                        }
                        self.appendAssistantDelta(id: assistantID, delta: "\n\n" + msg)
                    }
                }
            }
        } catch let aiErr as AIError {
            await MainActor.run {
                for idx in self.pendingToolEvents.indices where self.pendingToolEvents[idx].status == .running {
                    self.pendingToolEvents[idx].status = .failed
                }
            }
            throw aiErr
        } catch {
            await MainActor.run {
                for idx in self.pendingToolEvents.indices where self.pendingToolEvents[idx].status == .running {
                    self.pendingToolEvents[idx].status = .failed
                }
            }
        }
    }

    /// Sets `providerUsed` on the assistant message to the given provider's rawValue.
    private func setProviderUsed(id: UUID, provider: AIProvider) {
        for tIdx in threads.indices {
            if let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == id }) {
                threads[tIdx].messages[mIdx].providerUsed = provider.rawValue
                return
            }
        }
    }

    // MARK: - Private State Mutation Helpers (must be called on MainActor)

    private func appendAssistantDelta(id: UUID, delta: String) {
        for tIdx in threads.indices {
            if let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == id }) {
                threads[tIdx].messages[mIdx].content += delta
                return
            }
        }
    }

    private func setAssistantContent(id: UUID, content: String) {
        for tIdx in threads.indices {
            if let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == id }) {
                threads[tIdx].messages[mIdx].content = content
                return
            }
        }
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

    private func meteredTotals(for threadID: UUID) -> MeteredTotals {
        guard let thread = threads.first(where: { $0.id == threadID }) else {
            return MeteredTotals(costUSD: 0, inputTokens: 0, outputTokens: 0)
        }
        return MeteredTotals(
            costUSD: thread.totalCostUSD,
            inputTokens: thread.totalInputTokens,
            outputTokens: thread.totalOutputTokens
        )
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

    // MARK: - Edit Harness System Prompt Directive

    nonisolated static let editHarnessDirective: String = """
    When modifying files, emit each edit as a SEARCH/REPLACE block:

    <<<<<<< SEARCH: <relative/path/to/file>
    <old code>
    =======
    <new code>
    >>>>>>> REPLACE

    The SEARCH section must match the file contents exactly. Emit one block per edit; multiple blocks per file are allowed. Do not emit Markdown code fences around the blocks — emit them as raw text in your reply.
    """

    nonisolated private static var editHarnessEnabled: Bool {
        UserDefaults.standard.object(forKey: "chat.editHarness.enabled") as? Bool ?? true
    }

    // MARK: - Edit Block Attachment (MainActor)

    fileprivate func attachEditBlocksToAssistant(_ blocks: [EditBlock], assistantID: UUID, threadID: UUID) {
        guard !blocks.isEmpty else { return }
        for tIdx in threads.indices {
            if let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == assistantID }) {
                var existing = threads[tIdx].messages[mIdx].editBlocks ?? []
                existing.append(contentsOf: blocks)
                threads[tIdx].messages[mIdx].editBlocks = existing
                scheduleDebounce(for: assistantID, threadID: threadID)
                return
            }
        }
    }

    // MARK: - Edit Block Apply Actions (public API)

    /// Applies a single edit block: runs the applier ladder, commits, logs.
    func applyEditBlock(blockID: UUID, in assistantID: UUID) async {
        guard let repoURL = activeRepoURL else { return }
        let threadID = activeThreadID

        // Locate the block
        guard let (tIdx, mIdx, bIdx) = findEditBlock(blockID: blockID, assistantID: assistantID) else { return }
        let block = threads[tIdx].messages[mIdx].editBlocks![bIdx]

        // Resolve before reading so an approved edit cannot escape through a symlink.
        let fileURL: URL
        do {
            fileURL = try RepositoryWorker.resolveInsideRepo(
                path: block.path,
                repositoryURL: repoURL,
                op: "read"
            )
        } catch {
            threads[tIdx].messages[mIdx].editBlocks![bIdx].failureReason = "invalid_path"
            scheduleDebounce(for: assistantID, threadID: threadID)
            return
        }

        let currentContents: String
        do {
            currentContents = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            threads[tIdx].messages[mIdx].editBlocks![bIdx].failureReason = "file_not_found: \(block.path)"
            scheduleDebounce(for: assistantID, threadID: threadID)
            return
        }

        // Run EditApplier ladder
        let applier = EditApplier()
        let result = await applier.apply(block, to: currentContents, reflection: nil, wholeFileRewrite: nil)

        if result.applied, let finalContents = result.finalContents {
            // Commit via EditCommitter
            let commitInput = EditCommitInput(path: block.path, contents: finalContents)
            let currentBranch = activeBranch
            let committer = EditCommitter(worker: worker) { _, _ in
                "apply AI edit: \(block.path)"
            }
            let commitResult = await committer.commit(inputs: [commitInput], in: repoURL, branch: currentBranch)

            // Update block state
            guard let (ti2, mi2, bi2) = findEditBlock(blockID: blockID, assistantID: assistantID) else { return }
            threads[ti2].messages[mi2].editBlocks![bi2].appliedAt = Date()
            threads[ti2].messages[mi2].editBlocks![bi2].attemptStrategies = result.attempts.map { $0.strategy }
            if let reason = commitResult.failureReason {
                threads[ti2].messages[mi2].editBlocks![bi2].failureReason = reason
            }
            scheduleDebounce(for: assistantID, threadID: threadID)

            // Log to aiedit_log
            let blockIndex = bi2
            let commitSHA = commitResult.commitSHA
            Task {
                let logID = UUID().uuidString
                try? await self.storage?.appendAIEditLog(
                    id: logID,
                    threadID: threadID,
                    messageID: assistantID,
                    filePath: block.path,
                    blockIndex: blockIndex,
                    commitSHA: commitSHA,
                    repoID: self.repoID
                )
            }
        } else {
            // Mark failed
            guard let (ti2, mi2, bi2) = findEditBlock(blockID: blockID, assistantID: assistantID) else { return }
            threads[ti2].messages[mi2].editBlocks![bi2].failureReason = result.failureReason ?? "all_strategies_failed"
            threads[ti2].messages[mi2].editBlocks![bi2].attemptStrategies = result.attempts.map { $0.strategy }
            scheduleDebounce(for: assistantID, threadID: threadID)
        }
    }

    /// Applies all edit blocks in a message in order; stops at the first failure.
    func applyAllEdits(messageID: UUID) async {
        guard let tIdx = threads.firstIndex(where: { $0.id == activeThreadID }),
              let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == messageID }) else { return }

        let blocks = threads[tIdx].messages[mIdx].editBlocks ?? []
        guard !blocks.isEmpty else { return }

        let total = blocks.count
        applyAllState = .applying(0, total)

        for (idx, block) in blocks.enumerated() {
            // Skip already applied or rejected blocks
            if block.appliedAt != nil { continue }
            if block.failureReason != nil { continue }

            await applyEditBlock(blockID: block.id, in: messageID)

            // Re-check outcome
            guard let (ti2, mi2, bi2) = findEditBlock(blockID: block.id, assistantID: messageID) else { break }
            let updated = threads[ti2].messages[mi2].editBlocks![bi2]

            if updated.failureReason != nil {
                // Stop on first failure
                applyAllState = .stopped(at: idx + 1)
                return
            }
            applyAllState = .applying(idx + 1, total)
        }

        applyAllState = .done(total)
    }

    /// Marks an edit block as rejected.
    func rejectEditBlock(blockID: UUID, in assistantID: UUID) {
        guard let (tIdx, mIdx, bIdx) = findEditBlock(blockID: blockID, assistantID: assistantID) else { return }
        threads[tIdx].messages[mIdx].editBlocks![bIdx].failureReason = "rejected"
        scheduleDebounce(for: assistantID, threadID: activeThreadID)
    }

    /// Marks every edit block in a message as rejected.
    func rejectAllEdits(messageID: UUID) {
        guard let (tIdx, mIdx) = findAssistantMessage(messageID: messageID),
              let blocks = threads[tIdx].messages[mIdx].editBlocks else { return }
        for bIdx in blocks.indices {
            if threads[tIdx].messages[mIdx].editBlocks![bIdx].failureReason == nil {
                threads[tIdx].messages[mIdx].editBlocks![bIdx].failureReason = "rejected"
            }
        }
        scheduleDebounce(for: messageID, threadID: activeThreadID)
    }

    /// Replaces an edit block by re-parsing raw XML content.
    /// Derives the ApplyAllButton state from the message's edit blocks.
    func applyAllState(for assistantID: UUID) -> ApplyAllState {
        guard let (tIdx, mIdx) = findAssistantMessage(messageID: assistantID),
              let blocks = threads[tIdx].messages[mIdx].editBlocks,
              !blocks.isEmpty else { return .ready(0) }
        let total = blocks.count
        let applied = blocks.filter { $0.appliedAt != nil }.count
        let firstFailedIdx = blocks.firstIndex { $0.failureReason != nil }
        if applied == total { return .done(total) }
        if let idx = firstFailedIdx { return .stopped(at: idx) }
        return .ready(total)
    }

    private func findAssistantMessage(messageID: UUID) -> (tIdx: Int, mIdx: Int)? {
        for tIdx in threads.indices {
            if let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == messageID }) {
                return (tIdx, mIdx)
            }
        }
        return nil
    }

    func replaceEditBlock(blockID: UUID, in assistantID: UUID, rawXML: String) {
        guard let (tIdx, mIdx, bIdx) = findEditBlock(blockID: blockID, assistantID: assistantID) else { return }
        var parser = EditBlockParser()
        let parsed = parser.feed(rawXML)
        if let first = parsed.first {
            // Replace the block's search/replace by substituting in a new EditBlock with the same id
            let existing = threads[tIdx].messages[mIdx].editBlocks![bIdx]
            let updated = EditBlock(id: existing.id, path: first.path.isEmpty ? existing.path : first.path, search: first.search, replace: first.replace)
            threads[tIdx].messages[mIdx].editBlocks![bIdx] = updated
        }
        scheduleDebounce(for: assistantID, threadID: activeThreadID)
    }

    // MARK: - Edit Block Lookup Helper

    private func findEditBlock(blockID: UUID, assistantID: UUID) -> (tIdx: Int, mIdx: Int, bIdx: Int)? {
        for tIdx in threads.indices {
            if let mIdx = threads[tIdx].messages.firstIndex(where: { $0.id == assistantID }) {
                if let blocks = threads[tIdx].messages[mIdx].editBlocks,
                   let bIdx = blocks.firstIndex(where: { $0.id == blockID }) {
                    return (tIdx, mIdx, bIdx)
                }
            }
        }
        return nil
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

    private func makePayload(for text: String, provider: AIProvider) -> AIPromptPayload {
        AIClient.makePromptPayload(
            task: "Chat",
            taskInstructions: Self.taskInstructions(for: provider) + Self.branchAwarenessAppendix(branch: activeBranch),
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

    /// Phase 6.2 — appends branch-awareness guidance to the assistant
    /// system prompt. Tells the model exactly which branch is active and
    /// asks it to surface a feature-branch suggestion BEFORE applying
    /// edits when the user is on the protected default branch
    /// (`master` / `main`). Avoids the "agent silently committed to
    /// master" bug the user reported in screenshot #56.
    nonisolated static func branchAwarenessAppendixForTesting(branch: String) -> String {
        branchAwarenessAppendix(branch: branch)
    }

    /// Test seam — exposes the chat system-prompt builder so unit
    /// tests can pin the extensibility directive (create_skill +
    /// install_mcp_server discoverability) without instantiating the
    /// actor harness.
    nonisolated static func taskInstructionsForTesting(provider: AIProvider) -> String {
        taskInstructions(for: provider)
    }

    nonisolated private static func branchAwarenessAppendix(branch: String) -> String {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        let isProtected = (normalized == "master" || normalized == "main")
        var appendix = "\n\n## Branch awareness\nActive branch: `\(normalized)`."
        if isProtected {
            appendix += """


            CRITICAL: the user is on the protected default branch. Before applying
            ANY edit (especially via SEARCH/REPLACE blocks), STOP and propose
            checking out a feature branch first (suggest a short kebab-case name
            derived from the change). Wait for the user's explicit go-ahead
            before emitting edit blocks. If the user explicitly says "commit to
            \(normalized)" or "stay on \(normalized)", honor that and proceed.
            """
        } else {
            appendix += " Apply edits directly to this branch unless the user asks otherwise."
        }
        return appendix
    }

    nonisolated private static func taskInstructions(for provider: AIProvider) -> String {
        var base: String
        switch provider {
        case .claudeCLI, .codexCLI:
            // CLI providers bring their own tool harness (Read/Edit/Bash/Grep/etc.) and
            // session memory. We tell them they're inside Zion but DO NOT push them
            // to use tools — they should respond conversationally when the user is
            // chatting and only reach for tools when the user explicitly asks for
            // code/file/repo work. Without this gate they explore the repo for every
            // message (including casual greetings).
            base = """
            You are running inside Zion, a native macOS git client. The working
            directory is the user's git repository.

            Default behavior: respond conversationally to the user's message. Match
            the register and language of what they wrote. Greetings get greetings,
            questions get answers. DO NOT call Read/Bash/Edit/Grep/Glob or any
            other tool unless the user has explicitly asked you to inspect, search,
            run, or modify something. A short message like "hi", "ola", "tudo bem",
            or "thanks" is conversation — answer in one line, no tools.

            When the user does ask for repo work, your built-in tools are available.
            File edits are gated by Zion's `chat.cliAllowEdits` setting; if the user
            asked you to modify files and you find you cannot, tell them to enable
            "Allow file edits" in Settings → AI → Subscription CLIs.

            Output style: concise. Code blocks for commands, paths, hashes.
            """
        default:
            base = """
            You are Zion's coding assistant, embedded in a native macOS git client.

            Default behavior: respond conversationally to the user's message. Match
            the register and language of what they wrote. Casual messages get
            short conversational answers — do NOT ask the user to run any
            command just to greet them or chit-chat.

            When the user asks for repo work (review a diff, explain code,
            propose a plan, etc.), use the tools available to you. The MCP
            harness gives you:
            - `repo_map` — high-level project structure
            - `find_symbol` — locate types / functions by name
            - `read_file` — read any file inside the active repository
            - `list_dir` — enumerate a directory
            - `web_fetch` — fetch http(s) URLs the user shared
            Call them yourself when you need context. DO NOT beg the user to
            run `/status` or `/diff` before answering — you already have tools.

            Slash commands (/diff /log /status /file /commit) are OPTIONAL user
            shortcuts. If the user invokes one, its fenced output is appended
            to the message. Otherwise reach for the tools above.

            File edits: respect Zion's `chat.cliAllowEdits` setting. When edits
            are allowed, emit SEARCH/REPLACE blocks per the edit harness section
            below. When not allowed, propose changes as a plan instead.

            Context: repository state (repo · branch · HEAD · uncommitted count)
            is prepended to every user message. Treat it as ground truth.

            Output style: concise. Code blocks for commands, file paths, hashes.
            Never invent file paths or commit SHAs you haven't seen in context.
            """
        }

        // Edit harness: append SEARCH/REPLACE directive when enabled
        if editHarnessEnabled {
            base += "\n\n## File edits\n" + editHarnessDirective
        }

        // Phase 6.3 — extensibility directive. Surfaces install_mcp_server
        // + create_skill so the model knows it can act on natural-language
        // requests like "save this as a skill" / "add the filesystem MCP".
        base += """


        ## Extending Zion (skills + MCP)
        You have two extensibility tools available:

        - `create_skill(name, description, body, scope?, triggers?)` — write a
          reusable workflow as SKILL.md under `~/.zion/skills/` (user) or
          `<repo>/.zion/skills/` (project). Use when the user asks to:
            • "save this as a skill" / "transform this into a skill"
            • "create a skill that <does X>"
            • "remember this workflow" / "reuse this in the future"
          When the request is "save this session as a skill", summarise the
          recent steps the user just walked through (you have them in the
          turn history) into a step-by-step body, derive a kebab-case slug
          from the user-supplied title, and write it. Scope defaults to
          `user`; switch to `project` when the user says "for this repo".

        - `install_mcp_server(json)` — accepts the standard MCP JSON shapes
          (`{mcpServers: {...}}`, single named, or `{id, command, args}`).
          Use when the user pastes config OR names a server ("add the
          filesystem MCP at /tmp"). For named-only requests, propose the
          canonical npm package and ask before installing.

        Skills are provider-agnostic (Anthropic / OpenAI / Gemini / local
        all consume them via SkillIndex).
        Do NOT ask the user to edit JSON files by hand or open Settings panes — that is what these tools exist to remove.
        """

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

// MARK: - Skill Injection Helper

extension ChatService {
    /// Detects if `text` starts with /<skill-id>; if so and the index has it,
    /// returns the injected payload "[skill: <name>]\n<body>\n\n<rest>".
    /// Returns nil if no skill matched.
    nonisolated static func injectSkillIfMatched(
        text: String,
        skills: [Skill]
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstToken = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init),
              firstToken.hasPrefix("/")
        else { return nil }
        let id = String(firstToken.dropFirst())
        guard !id.isEmpty, let skill = skills.first(where: { $0.id == id }) else { return nil }
        let rest = String(trimmed.dropFirst(firstToken.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "[skill: \(skill.name)]\n\(skill.body)\n\n\(rest)"
    }
}
