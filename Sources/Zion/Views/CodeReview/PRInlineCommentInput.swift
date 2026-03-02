import SwiftUI

struct PRInlineCommentInput: View {
    let path: String
    let line: Int
    let onPost: (String) -> Void
    let onCancel: () -> Void
    @State private var commentBody: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: "plus.bubble")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.info)
                Text("\(path):\(line)")
                    .font(DesignSystem.Typography.monoMeta)
                    .foregroundStyle(.tertiary)
            }

            TextField(L10n("pr.comment.placeholder"), text: $commentBody, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
                .font(DesignSystem.Typography.bodySmall)

            HStack {
                Spacer()
                Button(L10n("pr.comment.cancel"), action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                Button(L10n("pr.comment.post")) {
                    guard !commentBody.isEmpty else { return }
                    onPost(commentBody)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(DesignSystem.Colors.actionPrimary)
                .disabled(commentBody.isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.standard)
        .background(DesignSystem.Colors.glassElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                .stroke(DesignSystem.Colors.info.opacity(0.3), lineWidth: 1)
        )
    }
}
