import SwiftUI

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
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.brandWhite)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, DesignSystem.Spacing.standard)
                    .padding(.vertical, DesignSystem.Spacing.compact)
                    .frame(maxWidth: 560, alignment: .leading)
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
                            ToolEventBadge(event: event)
                        }
                    }
                }
                assistantContent
                if message.isStreaming {
                    StreamingDot()
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
                .multilineTextAlignment(.leading)
        } else {
            Text(message.content)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
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
