import SwiftUI

struct AIQuotaExceededBanner: View {
    @Bindable var model: RepositoryViewModel

    var body: some View {
        if model.aiQuotaExceeded {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignSystem.Colors.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n("ai.quota.exceeded.title"))
                        .font(DesignSystem.Typography.bodySmallBold)
                    Text(L10n("ai.quota.exceeded.message", model.aiProvider.label))
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(L10n("ai.quota.exceeded.switchProvider")) {
                    NotificationCenter.default.post(name: .init("openSettings"), object: nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(L10n("ai.quota.exceeded.retry")) {
                    model.aiQuotaExceeded = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(DesignSystem.Spacing.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                    .fill(DesignSystem.Colors.warning.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                            .stroke(DesignSystem.Colors.warning.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
}
