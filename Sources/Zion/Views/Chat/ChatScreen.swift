import SwiftUI

// MARK: - ChatScreen

struct ChatScreen: View {

    @Bindable var chat: ChatService
    let repoURL: URL?
    let branch: String

    @State private var composerText: String = ""
    @State private var planMode: PlanModeState = PlanModeState.current()
    /// Memory monitor instance — lifetime tied to ChatScreen. Polls every 5s,
    /// watches local-server RSS when the LocalLLMConfig port is configured.
    @State private var memoryMonitor = MemoryMonitor()
    @State private var localConfig: LocalLLMConfig = AIClient.loadLocalConfig() ?? LocalLLMConfig()
    /// Suppress the auto-start banner for the rest of this session (policy=.ask
    /// + user clicked "Not now"). Reset on app relaunch.
    @State private var autoStartBannerDismissed: Bool = false
    /// Candidates surfaced by ProjectGuidanceImporter (CLAUDE.md / AGENTS.md / etc.)
    /// for the active repo. Reloaded whenever the chat screen appears or the
    /// repo URL changes. Empty + decided → banner hides.
    @State private var guidanceCandidates: [ProjectGuidanceImporter.Candidate] = []
    @State private var guidanceDecisionMade: Bool = false

    @Environment(\.zionActiveSection) private var activeSection: AppSection?

    @AppStorage("chat.threadListVisible") private var threadListVisible: Bool = true
    @AppStorage(ZionTalksAppearance.fontSizeKey) private var fontSizePx: Int = ZionTalksAppearance.defaultFontSizePx
    @AppStorage(ZionTalksAppearance.lineSpacingKey) private var lineSpacingPx: Int = ZionTalksAppearance.defaultLineSpacingPx

    @AppStorage(UserDefaultsKeys.AI.provider) private var providerRaw: String = AIProvider.none.rawValue
    @AppStorage(UserDefaultsKeys.AI.mode) private var modeRaw: String = AIMode.efficient.rawValue

    private var provider: AIProvider { AIProvider(rawValue: providerRaw) ?? .none }
    private var mode: AIMode { AIMode(rawValue: modeRaw) ?? .efficient }
    private var apiKey: String { AIClient.loadAPIKey(for: provider) ?? "" }

    var body: some View {
        VStack(spacing: 14) {
            pageHeader

            HStack(alignment: .top, spacing: 14) {
                conversationCard
                if threadListVisible {
                    historyCard
                        .frame(width: 300)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .environment(\.chatFontSizePx, fontSizePx)
        .environment(\.chatLineSpacingPx, lineSpacingPx)
        .onChange(of: activeSection) { _, newSection in
            // ChatScreen stays mounted (ZStack-overlay layout) when the user
            // switches to Code / Graph / Operations. Pause the memory monitor
            // poll loop while we're off-screen so we don't spawn `lsof`/`ps`
            // subprocesses every 5s for a UI nobody is looking at.
            if newSection == .chat {
                memoryMonitor.resume()
            } else {
                memoryMonitor.pause()
                // Floating NSPanel singletons / instances anchored at the
                // composer caret do NOT auto-hide when their host view gets
                // `.disabled`. They keep painting over whatever section the
                // user switched into (Tree / Code / Graph / Operations).
                // Tear them down explicitly here so the slash menu and the
                // @mention picker disappear the moment Chat loses focus.
                SlashAutocompletePanel.shared.dismiss()
                for window in NSApplication.shared.windows
                    where window is MentionAutocompletePanel && window.isVisible {
                    window.orderOut(nil)
                }
            }
        }
    }

    // MARK: - Page header

    private var pageHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("chat.screen.title"))
                    .font(DesignSystem.Typography.screenTitle)
                Text(L10n("chat.screen.subtitle"))
                    .foregroundStyle(.secondary)
                    .font(DesignSystem.Typography.subtitle)
            }
            Spacer()
            Button {
                planMode = (planMode == .planFirst) ? .autoApply : .planFirst
                PlanModeState.set(planMode)
            } label: {
                Image(systemName: "wand.and.rays")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(planMode == .planFirst ? DesignSystem.Colors.ai : DesignSystem.Colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n("chat.plan.mode.label"))
            Button {
                threadListVisible.toggle()
            } label: {
                Image(systemName: threadListVisible ? "sidebar.right" : "sidebar.left")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n("chat.thread.sidebar.toggle"))
        }
    }

    // MARK: - Conversation card (main content)

    private var conversationCard: some View {
        GlassCard(spacing: 8, expanding: true) {
            CardHeader(L10n("chat.card.conversation"), icon: "bubble.left.and.bubble.right.fill") {
                HStack(spacing: 6) {
                    AgentStepIndicator(agentRuntime: chat.agentRuntime)
                    SpendMeterPill()
                    let totalTokens = chat.thread.totalInputTokens + chat.thread.totalOutputTokens
                    if totalTokens > 0 {
                        Text(Self.formatTokens(totalTokens))
                            .font(DesignSystem.Typography.monoLabelBold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.glassSubtle)
                            .clipShape(Capsule())
                            .help(L10n("chat.tokens.tooltip"))
                    }
                    if chat.thread.totalCostUSD > 0 {
                        Text(String(format: "$%.3f", chat.thread.totalCostUSD))
                            .font(DesignSystem.Typography.monoLabelBold)
                            .foregroundStyle(DesignSystem.Colors.brandPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.glassSubtle)
                            .clipShape(Capsule())
                            .help(L10n("chat.cost.tooltip"))
                    }
                    Text("\(chat.thread.messages.count)")
                        .font(DesignSystem.Typography.monoLabelBold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.glassSubtle)
                        .clipShape(Capsule())
                }
            }
            messageList
            if repoURL != nil {
                composerArea
            }
        }
    }

    // MARK: - History card (trailing column)

    private var historyCard: some View {
        GlassCard(spacing: 8, expanding: true) {
            CardHeader(L10n("chat.card.history"), icon: "clock.arrow.circlepath") {
                Text("\(chat.threads.count)")
                    .font(DesignSystem.Typography.monoLabelBold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.glassSubtle)
                    .clipShape(Capsule())
            }
            ChatThreadList(
                threads: chat.threads,
                activeThreadID: chat.activeThreadID,
                streamingThreadIDs: chat.streamingThreadIDs,
                onSelect: { id in chat.selectThread(id) },
                onNew: { chat.createThread() },
                onDelete: { id in chat.deleteThread(id) },
                onRename: { id, title in chat.renameThread(id, title: title) },
                isCollapsed: .constant(false)
            )
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if chat.thread.messages.isEmpty {
                        ChatEmptyState(repoURL: repoURL) { pickedPrompt in
                            composerText = pickedPrompt
                        }
                    } else {
                        let latestStreamingAssistantID = chat.thread.messages.last(where: { $0.role == .assistant && $0.isStreaming })?.id
                        // Precompute applyAllState for every assistant message once — O(n) total
                        // instead of O(n * m) from calling chat.applyAllState(for:) per row.
                        let applyAllStateByID: [UUID: ApplyAllState] = Dictionary(
                            uniqueKeysWithValues: chat.thread.messages.compactMap { msg -> (UUID, ApplyAllState)? in
                                guard msg.role == .assistant, let blocks = msg.editBlocks, !blocks.isEmpty else { return nil }
                                return (msg.id, chat.applyAllState(for: msg.id))
                            }
                        )
                        ForEach(chat.thread.messages) { message in
                            if message.role == .assistant && message.isStreaming && message.id == latestStreamingAssistantID && !chat.pendingToolEvents.isEmpty {
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
                                    ForEach(chat.pendingToolEvents) { event in
                                        ChatToolEventBadge(event: event)
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                                .padding(.horizontal, DesignSystem.Spacing.cardPadding)
                                .padding(.top, DesignSystem.Spacing.compact)
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: chat.pendingToolEvents.count)
                            }
                            ChatMessageBubble(message: message)
                                .id(message.id)
                            // Render the Plan card ONLY when no structured
                            // EditBlocks have arrived yet. Once edits land,
                            // they ARE the implementation of the plan — the
                            // user clicks Apply on each edit card, so the
                            // plan card becomes a redundant second Apply
                            // surface (Image #39 — two Apply buttons for the
                            // same change). The plan intent is preserved in
                            // the assistant text bubble above.
                            if message.role == .assistant,
                               let plan = message.plan,
                               (message.editBlocks?.isEmpty ?? true) {
                                let msgID = message.id
                                PlanCard(plan: plan, isStreaming: message.isStreaming) { action in
                                    switch action {
                                    case .apply:
                                        chat.applyPlan(messageID: msgID)
                                    case .reject:
                                        chat.rejectPlan(messageID: msgID)
                                    case .reedit(let xml):
                                        chat.editPlan(messageID: msgID, xml: xml)
                                    }
                                }
                                .padding(.horizontal, DesignSystem.Spacing.cardPadding)
                                .padding(.vertical, DesignSystem.Spacing.compact)
                            }
                            if message.role == .assistant, let blocks = message.editBlocks, !blocks.isEmpty {
                                let msgID = message.id
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
                                    // Per-file cards — collapse to summary lines when >= 4 files
                                    if blocks.count < 4 {
                                        ForEach(blocks) { block in
                                            EditPreviewCard(block: block, isStreaming: message.isStreaming) { action in
                                                switch action {
                                                case .apply:
                                                    Task { await chat.applyEditBlock(blockID: block.id, in: msgID) }
                                                case .reject:
                                                    chat.rejectEditBlock(blockID: block.id, in: msgID)
                                                case .editRaw(let raw):
                                                    chat.replaceEditBlock(blockID: block.id, in: msgID, rawXML: raw)
                                                }
                                            }
                                        }
                                    } else {
                                        // Collapsed: show first 2 cards at reduced opacity + "N more" label
                                        ForEach(blocks.prefix(2)) { block in
                                            EditPreviewCard(block: block, isStreaming: message.isStreaming) { action in
                                                switch action {
                                                case .apply:
                                                    Task { await chat.applyEditBlock(blockID: block.id, in: msgID) }
                                                case .reject:
                                                    chat.rejectEditBlock(blockID: block.id, in: msgID)
                                                case .editRaw(let raw):
                                                    chat.replaceEditBlock(blockID: block.id, in: msgID, rawXML: raw)
                                                }
                                            }
                                            .opacity(DesignSystem.Opacity.dim)
                                        }
                                        Text(L10n("chat.multifileDiff.moreFiles", "\(blocks.count - 2)"))
                                            .font(DesignSystem.Typography.label)
                                            .foregroundStyle(.secondary)
                                    }
                                    // Multi-file summary card rendered AFTER per-file cards so the
                                    // Approve all / Reject all controls stay near the composer.
                                    if blocks.count >= 2 {
                                        MultiFileDiffSummary(
                                            blocks: blocks,
                                            onReviewAll: {
                                                // Sheet is handled inside MultiFileDiffSummary.
                                            },
                                            onApproveAll: {
                                                Task { await chat.applyAllEdits(messageID: msgID) }
                                            },
                                            onRejectAll: {
                                                chat.rejectAllEdits(messageID: msgID)
                                            },
                                            onApplyBlock: { block in
                                                Task { await chat.applyEditBlock(blockID: block.id, in: msgID) }
                                            },
                                            onRejectBlock: { block in
                                                chat.rejectEditBlock(blockID: block.id, in: msgID)
                                            }
                                        )
                                    }
                                    // Single-file flow keeps the ApplyAll button; multi-file uses summary buttons
                                    if blocks.count < 2 {
                                        ApplyAllButton(
                                            blocks: blocks,
                                            isStreaming: message.isStreaming,
                                            state: applyAllStateByID[msgID] ?? .ready(blocks.count)
                                        ) {
                                            Task { await chat.applyAllEdits(messageID: msgID) }
                                        }
                                    }
                                }
                                .padding(.horizontal, DesignSystem.Spacing.cardPadding)
                                .padding(.vertical, DesignSystem.Spacing.compact)
                            }
                        }
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.standard)
                .frame(maxWidth: DesignSystem.Spacing.chatContentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: chat.thread.messages.count) {
                scrollToLast(proxy: proxy)
            }
            .onChange(of: chat.thread.messages.last?.content) {
                scrollToLast(proxy: proxy)
            }
        }
    }

    // MARK: - Composer Area

    /// True when Smart Auto could benefit from the local LLM but the server
    /// is not running AND the user hasn't opted out. Drives banner visibility.
    private var shouldOfferLocalAutoStart: Bool {
        guard provider == .auto else { return false }
        guard !autoStartBannerDismissed else { return false }
        guard LocalAutoStartPolicy.current() == .ask else { return false }
        guard localConfig.engineKind != .custom else { return false }
        guard !modelNameEmpty(localConfig.modelName) else { return false }
        // Local NOT running = no RSS sample. Server-up case is handled by
        // LocalServerStatusBar instead.
        return memoryMonitor.localServerRSSBytes == nil
    }

    private func modelNameEmpty(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Spawn the local LLM server via `LocalServerLauncher` and immediately
    /// poll the monitor so the status bar surfaces RSS within ~5s. Banner is
    /// dismissed for the session regardless of outcome.
    private func spawnLocal() {
        autoStartBannerDismissed = true
        let cfg = localConfig
        Task {
            _ = await LocalServerLauncher().ensureRunning(config: cfg, engine: cfg.engineKind)
            await memoryMonitor.pollOnce()
        }
    }

    private var composerArea: some View {
        composerView
            .onAppear {
            // Reload config + wire monitor whenever the chat screen appears.
            localConfig = AIClient.loadLocalConfig() ?? LocalLLMConfig()
            memoryMonitor.setMonitoredPort(URL(string: localConfig.serverURL)?.port)
            memoryMonitor.start()
            // Hand the active repo URL to the mention panel fallback so '@'
            // autocomplete works even before SymbolIndexer finishes cold scan.
            MentionAutocompletePanel.repoURL = repoURL
            // Scan for project guidance files (CLAUDE.md, AGENTS.md,
            // GEMINI.md, .cursorrules, .cursor/rules/*) so the chat can
            // offer to import them as hidden context. Already-decided
            // repos skip the banner.
            if let repo = repoURL {
                let scan = ProjectGuidanceImporter.shared.scan(repoURL: repo)
                guidanceCandidates = scan.candidates
                guidanceDecisionMade = ProjectGuidanceImporter.shared.hasDecided(for: repo)
            }
        }
        .onDisappear {
            memoryMonitor.stop()
        }
    }

    private var composerView: some View {
        ChatComposer(
            chat: chat,
            text: $composerText,
            onSend: {
                let textToSend = composerText
                let activeID = chat.activeThreadID
                let pendingAttachments = chat.threadAttachments[activeID] ?? []
                composerText = ""
                chat.threadDrafts.removeValue(forKey: activeID)
                chat.threadAttachments.removeValue(forKey: activeID)
                guard let url = repoURL else { return }
                let modelOverride = ProviderModelCatalog.selectedModel(for: provider)
                Task {
                    await chat.send(
                        text: textToSend,
                        provider: provider,
                        apiKey: apiKey,
                        mode: mode,
                        repoURL: url,
                        branch: branch,
                        modelOverride: modelOverride.isEmpty ? nil : modelOverride,
                        attachments: pendingAttachments
                    )
                }
            },
            onStop: {
                chat.stop()
            },
            onNewChat: {
                chat.newThread()
                composerText = ""
            },
            topSlot: AnyView(composerTopSlot),
            repoURL: repoURL
        )
        .frame(maxWidth: DesignSystem.Spacing.chatContentMaxWidth)
        .frame(maxWidth: .infinity)
        // Save the composer draft into the OLD thread before switching, then
        // load the draft (if any) saved for the NEW thread. Empty drafts are
        // not persisted so the dictionary stays tight.
        .onChange(of: chat.activeThreadID) { oldID, newID in
            if composerText.isEmpty {
                chat.threadDrafts.removeValue(forKey: oldID)
            } else {
                chat.threadDrafts[oldID] = composerText
            }
            composerText = chat.threadDrafts[newID] ?? ""
        }
        .onAppear {
            // Restore any draft saved for whatever thread is active when the
            // screen mounts (covers re-entry from another tab).
            if composerText.isEmpty,
               let restored = chat.threadDrafts[chat.activeThreadID],
               !restored.isEmpty {
                composerText = restored
            }
        }
        // Phase 6 — recompute the auto-context chip row whenever the
        // composer text settles. Debounced via `.task(id:)` so each new
        // keystroke supersedes the previous query without piling tasks.
        .task(id: composerText) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            await chat.refreshPendingContext(for: composerText)
        }
    }

    /// Renders the auto-start banner and the local-server status bar inside
    /// the composer card so they share its width / padding.
    @ViewBuilder private var composerTopSlot: some View {
        // Phase 6.2 — leading alignment so the auto-context chip row
        // (collapsed pill, expanded list, loading skeleton) all anchor
        // to the same left edge. Without this the parent VStack
        // defaulted to `.center` and the collapsed pill drifted right
        // every retrieval cycle (UX audit Issue 1).
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
            // Pre-flight chip row lives below the composer (see body) — do not
            // re-mount here to avoid the duplicated "Mode: Permission:" row.
            if !guidanceCandidates.isEmpty && !guidanceDecisionMade, let repo = repoURL {
                ProjectGuidanceImportBanner(
                    candidates: guidanceCandidates,
                    onImport: { selected in
                        _ = ProjectGuidanceImporter.shared.importCandidates(selected, for: repo)
                        guidanceDecisionMade = true
                    },
                    onDismiss: {
                        ProjectGuidanceImporter.shared.dismiss(for: repo)
                        guidanceDecisionMade = true
                    }
                )
            }
            if shouldOfferLocalAutoStart {
                LocalAutoStartBanner(
                    modelName: localConfig.modelName,
                    onStartOnce: { spawnLocal() },
                    onStartAlways: {
                        LocalAutoStartPolicy.set(.always)
                        spawnLocal()
                    },
                    onDismiss: { autoStartBannerDismissed = true },
                    onNever: {
                        LocalAutoStartPolicy.set(.never)
                        autoStartBannerDismissed = true
                    }
                )
            }
            if memoryMonitor.localServerRSSBytes != nil {
                LocalServerStatusBar(
                    model: .init(
                        modelName: localConfig.modelName,
                        systemPressure: memoryMonitor.systemPressure,
                        totalBytes: memoryMonitor.totalBytes,
                        usedBytes: memoryMonitor.usedBytes,
                        serverRSSBytes: memoryMonitor.localServerRSSBytes,
                        isStreaming: chat.isStreaming,
                        // When the last turn went somewhere OTHER than the
                        // local server (Smart Auto routed to Claude CLI, say,
                        // because the user message was easy and the cheap
                        // chain was cheaper), surface that fact next to the
                        // RSS so the user doesn't conflate "memory in use"
                        // with "local was queried this turn".
                        idleLastProviderLabel: {
                            guard let p = chat.resolvedProvider, p != .local else { return nil }
                            return p.label
                        }()
                    ),
                    onDisconnect: {
                        // Stop the server AND suppress local for the session so
                        // the next Auto turn falls through to the cheap CLI (Haiku)
                        // instead of silently resurrecting the local LLM.
                        chat.localSessionSuppressed = true
                        Task {
                            _ = await LocalServerLauncher().stop(config: localConfig)
                            await memoryMonitor.pollOnce()
                        }
                    }
                )
            }
            // Pre-flight chip row — sits directly above the input field so
            // Modo / Permissão / (Rodar comandos) are the last things the user
            // sees before hitting Send. Stays visible mid-thread so the user
            // can switch on the fly.
            ChatPreflightChipRow(compact: true)
            // Phase 6 — auto-context chip row. Sits between the preflight
            // policy chips above and the input below; renders the chunks the
            // hybrid retrieval picked for the upcoming message. Collapsed
            // by default; user expands or dismisses individual chips.
            ChatContextChipRow(
                hits: chat.pendingContextHits,
                isLoading: chat.isPendingContextLoading,
                onRemove: { chat.removePendingContext($0) }
            )
        }
    }

    // MARK: - Helpers

    private static func formatTokens(_ count: Int) -> String {
        if count < 1_000 { return "\(count) tok" }
        if count < 10_000 { return String(format: "%.1fk tok", Double(count) / 1_000) }
        return "\(count / 1_000)k tok"
    }

    private func scrollToLast(proxy: ScrollViewProxy) {
        guard let lastID = chat.thread.messages.last?.id else { return }
        // Phase 6.2 — when there is only one message (just-sent first
        // turn) anchor `.top` so the user keeps seeing their question;
        // anchoring `.bottom` on a single bubble scrolls the
        // LazyVStack origin past the leading edge and the top of the
        // conversation disappears until any tap forces a re-layout
        // (user screenshot #57 + verbal "some definitivamente").
        let anchor: UnitPoint = chat.thread.messages.count <= 1 ? .top : .bottom
        // Defer one runloop tick so the LazyVStack has measured the new
        // bubble before we anchor. Without this the scrollTo runs
        // against stale layout, overshoots, and the leading message
        // ends up hidden above the viewport (user only sees it back
        // after clicking — confirms it is a layout-timing bug, not a
        // state-loss bug).
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(lastID, anchor: anchor)
            }
        }
    }
}

// MARK: - Bool Binding Inverse

private extension Binding where Value == Bool {
    /// Returns a Binding<Bool> that inverts the wrapped value.
    var inverse: Binding<Bool> {
        Binding<Bool>(
            get: { !self.wrappedValue },
            set: { self.wrappedValue = !$0 }
        )
    }
}
