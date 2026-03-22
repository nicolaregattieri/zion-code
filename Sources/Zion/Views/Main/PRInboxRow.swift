import SwiftUI

struct PRInboxRow: View {
    let item: PRReviewItem
    var model: RepositoryViewModel
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                authorAvatar

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Text("#\(item.pr.number)")
                            .font(DesignSystem.Typography.monoLabelBold)
                            .foregroundStyle(.secondary)
                        Text(item.pr.title)
                            .font(DesignSystem.Typography.bodyMedium)
                            .lineLimit(1)
                    }

                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                        Text("@\(item.pr.author)")
                            .font(DesignSystem.Typography.monoMeta)
                            .foregroundStyle(.tertiary)

                        if !item.severitySummary.isEmpty {
                            Text(item.severitySummary)
                                .font(DesignSystem.Typography.metaSemibold)
                                .foregroundStyle(item.status == .reviewed ? DesignSystem.Colors.warning : DesignSystem.Colors.success)
                        }

                        if let reviewedAt = item.reviewedAt {
                            Text(reviewedAt, style: .relative)
                                .font(DesignSystem.Typography.meta)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer(minLength: 4)

                // Status indicator
                statusBadge

                Image(systemName: "chevron.right")
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                    .fill(isHovered ? DesignSystem.Colors.glassHover : DesignSystem.Colors.glassMinimal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
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
                Label(L10n("pr.inbox.openProvider"), systemImage: "link")
            }
        }
    }

    @ViewBuilder
    private var authorAvatar: some View {
        if let avatar = model.avatarImage(forUsername: item.pr.author, prURL: item.pr.url) {
            Image(nsImage: avatar)
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(Circle())
        }
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
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.warning)
        case .clean:
            Image(systemName: "checkmark.seal.fill")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.success)
        case .pending:
            Image(systemName: "clock")
                .font(DesignSystem.Typography.bodySmall)
                .foregroundStyle(.secondary)
        }
    }
}
