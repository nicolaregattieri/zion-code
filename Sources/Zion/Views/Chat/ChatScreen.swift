import SwiftUI

// MARK: - ChatScreen

struct ChatScreen: View {

    @Bindable var chat: ChatService
    let repoURL: URL?
    let branch: String

    @State private var composerText: String = ""

    @AppStorage("chat.threadListVisible") private var threadListVisible: Bool = true

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
                Text("\(chat.thread.messages.count)")
                    .font(DesignSystem.Typography.monoLabelBold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.glassSubtle)
                    .clipShape(Capsule())
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
                Task {
                    await chat.send(
                        text: textToSend,
                        provider: provider,
                        apiKey: apiKey,
                        mode: mode,
                        repoURL: url,
                        branch: branch
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
