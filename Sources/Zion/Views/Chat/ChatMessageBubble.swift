import SwiftUI

// MARK: - ChatMessageBubble

struct ChatMessageBubble: View {

    let message: ChatMessage

    // MARK: - Body

    var body: some View {
        HStack(alignment: .bottom, spacing: DesignSystem.Spacing.compact) {
            if message.role == .user {
                Spacer(minLength: DesignSystem.Spacing.sectionGap)
                bubbleContent
                    .bubbleStyle(isUser: true)
            } else {
                bubbleContent
                    .bubbleStyle(isUser: false)
                Spacer(minLength: DesignSystem.Spacing.sectionGap)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, DesignSystem.Spacing.micro)
    }

    // MARK: - Bubble Content

    @ViewBuilder
    private var bubbleContent: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading,
               spacing: DesignSystem.Spacing.micro) {
            if message.role == .assistant, let events = message.toolEvents, !events.isEmpty {
                toolEventBadges(events)
            }
            messageText
            if message.isStreaming {
                streamingIndicator
            }
            if message.role == .user, let intent = message.autoInjectedIntent {
                HStack {
                    Spacer()
                    AutoInjectionChip(intentLabel: intent)
                }
            }
        }
    }

    // MARK: - Tool Event Badges

    @ViewBuilder
    private func toolEventBadges(_ events: [ChatToolEvent]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
            ForEach(events) { event in
                ToolEventBadge(event: event)
            }
        }
    }

    // MARK: - Message Text

    @ViewBuilder
    private var messageText: some View {
        if message.role == .assistant {
            assistantText
        } else {
            Text(message.content)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.brandWhite)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var assistantText: some View {
        if let attributed = try? AttributedString(markdown: message.content,
                                                  options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
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

    // MARK: - Streaming Indicator

    private var streamingIndicator: some View {
        StreamingDot()
    }
}

// MARK: - Bubble Style Modifier

private struct BubbleStyleModifier: ViewModifier {
    let isUser: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DesignSystem.Spacing.cardPadding)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                    .fill(isUser ? DesignSystem.Colors.brandPrimary.opacity(DesignSystem.Opacity.muted) : DesignSystem.Colors.glassElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                            .strokeBorder(
                                isUser ? DesignSystem.Colors.brandPrimary.opacity(DesignSystem.Opacity.dim) : DesignSystem.Colors.glassBorder,
                                lineWidth: 1
                            )
                    )
            )
    }
}

private extension View {
    func bubbleStyle(isUser: Bool) -> some View {
        modifier(BubbleStyleModifier(isUser: isUser))
    }
}

// MARK: - Streaming Dot

private struct StreamingDot: View {
    @State private var opacity: Double = DesignSystem.Opacity.visible

    var body: some View {
        Circle()
            .fill(DesignSystem.Colors.ai)
            .frame(width: DesignSystem.Spacing.compact, height: DesignSystem.Spacing.compact)
            .opacity(opacity)
            .onAppear {
                withAnimation(DesignSystem.Motion.glowPulse) {
                    opacity = DesignSystem.Opacity.dim
                }
            }
    }
}
