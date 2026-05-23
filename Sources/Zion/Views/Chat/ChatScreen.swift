import SwiftUI

// MARK: - ChatScreen

struct ChatScreen: View {

    @Bindable var chat: ChatService
    let repoURL: URL?
    let branch: String

    @State private var composerText: String = ""
    @State private var planMode: PlanModeState = PlanModeState.current()

    @AppStorage("chat.threadListVisible") private var threadListVisible: Bool = true
    @AppStorage(ZionTalksAppearance.fontSizeKey) private var fontSizeRaw: String = ChatFontSize.medium.rawValue
    private var fontScale: Double { (ChatFontSize(rawValue: fontSizeRaw) ?? .medium).scale }

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
        .environment(\.chatFontScale, fontScale)
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
                        ChatEmptyState { pickedPrompt in
                            composerText = pickedPrompt
                        }
                    } else {
                        ForEach(chat.thread.messages) { message in
                            if message.role == .assistant && message.isStreaming && message.id == chat.thread.messages.last(where: { $0.role == .assistant && $0.isStreaming })?.id && !chat.pendingToolEvents.isEmpty {
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
                            if message.role == .assistant, let plan = message.plan {
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
                                    ApplyAllButton(
                                        blocks: blocks,
                                        isStreaming: message.isStreaming,
                                        state: chat.applyAllState(for: msgID)
                                    ) {
                                        Task { await chat.applyAllEdits(messageID: msgID) }
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

    private var composerArea: some View {
        ChatComposer(
            chat: chat,
            text: $composerText,
            onSend: {
                let textToSend = composerText
                composerText = ""
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
                        modelOverride: modelOverride.isEmpty ? nil : modelOverride
                    )
                }
            },
            onStop: {
                chat.stop()
            },
            onNewChat: {
                chat.newThread()
                composerText = ""
            }
        )
        .frame(maxWidth: DesignSystem.Spacing.chatContentMaxWidth)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private static func formatTokens(_ count: Int) -> String {
        if count < 1_000 { return "\(count) tok" }
        if count < 10_000 { return String(format: "%.1fk tok", Double(count) / 1_000) }
        return "\(count / 1_000)k tok"
    }

    private func scrollToLast(proxy: ScrollViewProxy) {
        guard let lastID = chat.thread.messages.last?.id else { return }
        withAnimation {
            proxy.scrollTo(lastID, anchor: .bottom)
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
