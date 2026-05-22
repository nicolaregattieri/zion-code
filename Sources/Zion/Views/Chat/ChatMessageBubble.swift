import SwiftUI

struct ChatMessageBubble: View {

    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.standard) {
            if message.role == .user {
                Spacer(minLength: 48)
                userBubble
            } else {
                assistantAvatar
                assistantBubble
                Spacer(minLength: 48)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, DesignSystem.Spacing.compact)
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
                .frame(width: 28, height: 28)
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.brandWhite)
        }
        .overlay(
            Circle()
                .strokeBorder(DesignSystem.Colors.glassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var userBubble: some View {
        Text(message.content)
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.brandWhite)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [DesignSystem.Colors.brandPrimary, DesignSystem.Colors.brandInk],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: DesignSystem.Colors.brandPrimary.opacity(0.25), radius: 8, x: 0, y: 2)
            )
    }

    @ViewBuilder
    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
            if message.isStreaming && message.content.isEmpty {
                ChatThinkingIndicator()
            } else {
                assistantContent
                if message.isStreaming {
                    StreamingDot()
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.standard)
        .padding(.vertical, DesignSystem.Spacing.compact)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignSystem.Colors.glassHover)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.glassBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var assistantContent: some View {
        if let attributed = try? AttributedString(
            markdown: message.content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(message.content)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StreamingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(DesignSystem.Colors.brandPrimary)
            .frame(width: 6, height: 6)
            .opacity(pulse ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
