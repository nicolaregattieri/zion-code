import SwiftUI

// MARK: - ChatScreen

struct ChatScreen: View {

    @Bindable var chat: ChatService
    let repoURL: URL?
    let branch: String

    @State private var composerText: String = ""

    @AppStorage(UserDefaultsKeys.AI.provider) private var providerRaw: String = AIProvider.none.rawValue
    @AppStorage(UserDefaultsKeys.AI.mode) private var modeRaw: String = AIMode.efficient.rawValue

    private var provider: AIProvider { AIProvider(rawValue: providerRaw) ?? .none }
    private var mode: AIMode { AIMode(rawValue: modeRaw) ?? .efficient }
    private var apiKey: String { AIClient.loadAPIKey(for: provider) ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if repoURL != nil {
                composerArea
            }
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
                            ChatMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.standard)
                .frame(maxWidth: 900)
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
    }

    // MARK: - Helpers

    private func scrollToLast(proxy: ScrollViewProxy) {
        guard let lastID = chat.thread.messages.last?.id else { return }
        withAnimation {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}
