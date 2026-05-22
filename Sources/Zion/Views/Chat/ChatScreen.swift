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
        HStack(spacing: 0) {
            // Thread list sidebar
            ChatThreadList(
                threads: chat.threads,
                activeThreadID: chat.activeThreadID,
                onSelect: { id in chat.selectThread(id) },
                onNew: { chat.createThread() },
                onDelete: { id in chat.deleteThread(id) },
                onRename: { id, title in chat.renameThread(id, title: title) },
                isCollapsed: $threadListVisible.inverse
            )

            if threadListVisible {
                Divider().background(DesignSystem.Colors.glassBorder)
            }

            // Chat content
            VStack(spacing: 0) {
                chatHeader
                messageList
                if repoURL != nil {
                    composerArea
                }
            }
        }
    }

    private var chatHeader: some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            Button {
                threadListVisible.toggle()
            } label: {
                Image(systemName: threadListVisible ? "sidebar.left" : "sidebar.right")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: DesignSystem.Spacing.cardPadding, height: DesignSystem.Spacing.cardPadding)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n("chat.thread.sidebar.toggle"))
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, DesignSystem.Spacing.compact)
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
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.bottom, DesignSystem.Spacing.cardPadding)
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
