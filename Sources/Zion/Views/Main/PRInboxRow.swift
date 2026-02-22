import SwiftUI

struct PRInboxRow: View {
    let item: PRReviewItem
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Author initial in colored circle
                authorAvatar

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("#\(item.pr.number)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(item.pr.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Text("@\(item.pr.author)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)

                        if !item.severitySummary.isEmpty {
                            Text(item.severitySummary)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(item.status == .reviewed ? DesignSystem.Colors.warning : DesignSystem.Colors.success)
                        }

                        if let reviewedAt = item.reviewedAt {
                            Text(reviewedAt, style: .relative)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer(minLength: 4)

                // Status indicator
                statusBadge

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? DesignSystem.Colors.glassHover : DesignSystem.Colors.glassMinimal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignSystem.Colors.glassHover, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in isHovered = h }
        .contextMenu {
            Button {
                if let url = URL(string: item.pr.url) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(L10n("pr.inbox.openGitHub"), systemImage: "link")
            }
        }
    }

    private var authorAvatar: some View {
        let initial = item.pr.author.prefix(1).uppercased()
        let hue = Double(abs(item.pr.author.hashValue) % 360) / 360.0

        return Text(initial)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color(hue: hue, saturation: 0.6, brightness: 0.8)))
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .reviewing:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)
        case .reviewed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.warning)
        case .clean:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.success)
        case .pending:
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
