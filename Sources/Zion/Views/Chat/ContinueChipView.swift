import SwiftUI

/// Phase 4 — inline `Continue (+10 hops)` chip rendered beneath an
/// assistant bubble that exhausted its per-turn tool-call budget. Tapping
/// the chip calls `chat.continueWithExtraHops(_:)` which bumps the budget
/// and resumes the loop on the same thread.
struct ContinueChipView: View {

    let onContinue: () -> Void

    var body: some View {
        Button(action: onContinue) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.ai)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n("chat.continue.plus10"))
                        .font(DesignSystem.Typography.bodySemibold)
                        .foregroundStyle(DesignSystem.Colors.ai)
                    Text(L10n("chat.continue.plus10.subtitle"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(DesignSystem.Colors.ai.opacity(DesignSystem.Opacity.dim))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(L10n("chat.continue.plus10.subtitle"))
    }
}
