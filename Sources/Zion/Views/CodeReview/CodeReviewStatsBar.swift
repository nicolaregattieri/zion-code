import SwiftUI

struct CodeReviewStatsBar: View {
    let stats: CodeReviewStats
    let source: String
    let target: String

    var body: some View {
        HStack(spacing: 16) {
            // Branch flow
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Text(source.isEmpty ? "?" : source)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.success)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                Text(target.isEmpty ? "?" : target)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.info)
                    .lineLimit(1)
            }

            Divider().frame(height: 20)

            // Stats chips
            statChip(icon: "doc.text", value: "\(stats.totalFiles)", label: L10n("codereview.stats.files"), color: .secondary)
            statChip(icon: "plus", value: "+\(stats.totalAdditions)", label: nil, color: DesignSystem.Colors.diffAddition)
            statChip(icon: "minus", value: "-\(stats.totalDeletions)", label: nil, color: DesignSystem.Colors.diffDeletion)

            if stats.commitCount > 0 {
                statChip(icon: "number", value: "\(stats.commitCount)", label: L10n("codereview.stats.commits"), color: DesignSystem.Colors.info)
            }

            Spacer()

            // Overall risk badge
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: stats.overallRisk == .risky ? "exclamationmark.octagon.fill" :
                                  stats.overallRisk == .moderate ? "exclamationmark.triangle.fill" :
                                  "checkmark.shield.fill")
                    .font(DesignSystem.Typography.label)
                Text(stats.overallRisk.label)
                    .font(DesignSystem.Typography.labelBold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(stats.overallRisk.color.opacity(0.15))
            .foregroundStyle(stats.overallRisk.color)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func statChip(icon: String, value: String, label: String?, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(DesignSystem.Typography.meta)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            if let label {
                Text(label)
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(color)
    }
}
