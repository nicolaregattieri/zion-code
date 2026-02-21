import SwiftUI

struct CodeReviewStatsBar: View {
    let stats: CodeReviewStats
    let source: String
    let target: String

    var body: some View {
        HStack(spacing: 16) {
            // Branch flow
            HStack(spacing: 6) {
                Text(source.isEmpty ? "?" : source)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(target.isEmpty ? "?" : target)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            }

            Divider().frame(height: 20)

            // Stats chips
            statChip(icon: "doc.text", value: "\(stats.totalFiles)", label: L10n("codereview.stats.files"), color: .secondary)
            statChip(icon: "plus", value: "+\(stats.totalAdditions)", label: nil, color: .green)
            statChip(icon: "minus", value: "-\(stats.totalDeletions)", label: nil, color: .red)

            if stats.commitCount > 0 {
                statChip(icon: "number", value: "\(stats.commitCount)", label: L10n("codereview.stats.commits"), color: .blue)
            }

            Spacer()

            // Overall risk badge
            HStack(spacing: 4) {
                Image(systemName: stats.overallRisk == .risky ? "exclamationmark.octagon.fill" :
                                  stats.overallRisk == .moderate ? "exclamationmark.triangle.fill" :
                                  "checkmark.shield.fill")
                    .font(.system(size: 10))
                Text(stats.overallRisk.label)
                    .font(.system(size: 10, weight: .bold))
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
                .font(.system(size: 9))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            if let label {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(color)
    }
}
