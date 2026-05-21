import SwiftUI

struct ChatEmptyState: View {
    let onPickPrompt: (String) -> Void

    private let examples: [String] = [
        L10n("chat.emptyState.example.history"),
        L10n("chat.emptyState.example.branch"),
        L10n("chat.emptyState.example.diff")
    ]

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sectionGap) {
            Spacer()
            Text(L10n("chat.emptyState.headline"))
                .font(DesignSystem.Typography.sectionTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)
            VStack(spacing: DesignSystem.Spacing.standard) {
                ForEach(examples, id: \.self) { example in
                    Button {
                        onPickPrompt(example)
                    } label: {
                        Text(example)
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .padding(DesignSystem.Spacing.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DesignSystem.Colors.glassBackground)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                                    .stroke(DesignSystem.Colors.glassBorder, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 440)
            Spacer()
        }
        .padding(DesignSystem.Spacing.sectionGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
