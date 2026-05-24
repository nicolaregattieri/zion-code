import SwiftUI
import AppKit

struct ChatMessageBubble: View {

    let message: ChatMessage

    var body: some View {
        Group {
            if message.role == .user {
                userRow
            } else {
                assistantRow
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, DesignSystem.Spacing.compact)
    }

    // MARK: - User row (right-aligned compact bubble)

    private var userRow: some View {
        VStack(alignment: .trailing, spacing: DesignSystem.Spacing.compact) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.standard) {
                Spacer(minLength: DesignSystem.Spacing.sectionGap)
                Text(message.content)
                    .chatScaledFont(role: .body)
                    .chatLineSpacing()
                    .foregroundStyle(DesignSystem.Colors.brandWhite)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, DesignSystem.Spacing.standard)
                    .padding(.vertical, DesignSystem.Spacing.compact)
                    .frame(maxWidth: DesignSystem.Spacing.chatUserBubbleMaxWidth, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [DesignSystem.Colors.brandPrimary, DesignSystem.Colors.brandInk],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: DesignSystem.Colors.brandPrimary.opacity(DesignSystem.Opacity.dim), radius: DesignSystem.Spacing.standard, x: 0, y: 2)
                    )
            }
            if let intent = message.autoInjectedIntent {
                AutoInjectionChip(intentLabel: intent)
            }
        }
    }

    // MARK: - Assistant row (full-width Claude/ChatGPT style)

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.standard) {
            assistantAvatar
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
                if let events = message.toolEvents, !events.isEmpty {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                        ForEach(events) { event in
                            ChatToolEventBadge(event: event)
                        }
                    }
                }
                if let helpPayload = message.helpCardPayload {
                    SlashHelpCard(payload: helpPayload)
                } else if message.isStreaming && message.content.isEmpty {
                    ChatThinkingIndicator()
                } else {
                    AssistantMarkdown(content: message.content)
                    if message.isStreaming {
                        StreamingDot()
                    } else if !message.content.isEmpty {
                        MessageCopyButton(content: message.content)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var assistantAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [DesignSystem.Colors.brandPrimary, DesignSystem.Colors.brandInk],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: DesignSystem.Spacing.chatAvatarSize, height: DesignSystem.Spacing.chatAvatarSize)
            Image(systemName: "sparkles")
                .font(DesignSystem.Typography.label.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.brandWhite)
        }
        .overlay(
            Circle()
                .strokeBorder(DesignSystem.Colors.glassBorder, lineWidth: 1)
        )
    }
}

private struct StreamingDot: View {
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(DesignSystem.Colors.brandPrimary)
            .frame(width: DesignSystem.Spacing.streamingDotSize, height: DesignSystem.Spacing.streamingDotSize)
            .opacity(pulse ? DesignSystem.Opacity.dim : DesignSystem.Opacity.visible)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

private struct MessageCopyButton: View {
    let content: String
    @State private var copied = false

    var body: some View {
        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(content, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                Text(copied ? L10n("chat.message.copied") : L10n("chat.message.copy"))
            }
            .font(DesignSystem.Typography.metaSemibold)
            .foregroundStyle(copied ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }
}
