import SwiftUI

struct PRCommentThread: View {
    let comments: [PRComment]
    let onReply: (String) -> Void
    @State private var replyText: String = ""
    @State private var isReplying: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
            ForEach(comments) { comment in
                PRCommentBubble(comment: comment)
            }

            if isReplying {
                HStack(spacing: DesignSystem.Spacing.compact) {
                    TextField(L10n("pr.comment.placeholder"), text: $replyText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)

                    Button(L10n("pr.comment.post")) {
                        guard !replyText.isEmpty else { return }
                        onReply(replyText)
                        replyText = ""
                        isReplying = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(DesignSystem.Colors.actionPrimary)
                    .disabled(replyText.isEmpty)

                    Button(L10n("pr.comment.cancel")) {
                        replyText = ""
                        isReplying = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, DesignSystem.Spacing.micro)
            } else {
                Button {
                    isReplying = true
                } label: {
                    Label(L10n("pr.comment.reply"), systemImage: "arrowshape.turn.up.left")
                        .font(DesignSystem.Typography.label)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(DesignSystem.Spacing.standard)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
    }
}

private struct PRCommentBubble: View {
    let comment: PRComment

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                authorAvatar

                Text("@\(comment.author)")
                    .font(DesignSystem.Typography.monoLabelBold)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(comment.createdAt, style: .relative)
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(.tertiary)
            }

            Text(comment.body)
                .font(DesignSystem.Typography.bodySmall)
                .textSelection(.enabled)
        }
        .padding(.vertical, DesignSystem.Spacing.micro)
    }

    private var authorAvatar: some View {
        let initial = comment.author.prefix(1).uppercased()
        let hue = Double(abs(comment.author.hashValue) % 360) / 360.0

        return Text(initial)
            .font(DesignSystem.Typography.micro)
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color(hue: hue, saturation: 0.6, brightness: 0.8)))
    }
}
