import SwiftUI

// MARK: - AutoInjectionChip

struct AutoInjectionChip: View {

    let intentLabel: String

    // MARK: - Body

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.micro) {
            Image(systemName: "sparkles")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text(L10n("chat.harness.autoIncluded", intentLabel))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }
}
