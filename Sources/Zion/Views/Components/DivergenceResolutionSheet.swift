import SwiftUI

struct DivergenceResolutionSheet: View {
    let context: DivergenceContext
    let onResolve: (DivergenceResolution) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(DesignSystem.Typography.decorativeIcon)
                    .foregroundStyle(DesignSystem.Colors.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("divergence.title")).font(DesignSystem.Typography.sheetTitle)
                    Text(L10n("divergence.subtitle", context.branch))
                        .font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if context.localAhead > 0 || context.remoteAhead > 0 {
                    HStack(spacing: 12) {
                        statusBadge(
                            icon: "arrow.up",
                            label: L10n("divergence.localAhead", context.localAhead),
                            color: DesignSystem.Colors.info,
                            background: DesignSystem.Colors.statusBlueBg
                        )
                        statusBadge(
                            icon: "arrow.down",
                            label: L10n("divergence.remoteAhead", context.remoteAhead),
                            color: DesignSystem.Colors.warning,
                            background: DesignSystem.Colors.statusOrangeBg
                        )
                    }
                    .padding(.bottom, DesignSystem.Spacing.micro)
                }

                optionButton(
                    icon: "arrow.triangle.merge",
                    title: L10n("divergence.option.rebase"),
                    description: L10n("divergence.option.rebase.desc"),
                    color: DesignSystem.Colors.success
                ) {
                    onResolve(.rebase)
                }

                optionButton(
                    icon: "arrow.triangle.branch",
                    title: L10n("divergence.option.merge"),
                    description: L10n("divergence.option.merge.desc"),
                    color: DesignSystem.Colors.info
                ) {
                    onResolve(.merge)
                }

                Divider().padding(.vertical, DesignSystem.Spacing.micro)

                optionButton(
                    icon: "exclamationmark.triangle.fill",
                    title: L10n("divergence.option.forceAlign"),
                    description: L10n("divergence.option.forceAlign.desc"),
                    color: DesignSystem.Colors.destructive,
                    isDestructive: true
                ) {
                    onResolve(.forceAlign)
                }
            }
            .padding(20)

            Divider()

            HStack {
                Spacer()
                Button(L10n("Cancelar")) { dismiss() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(16)
        }
        .frame(width: 480)
    }

    private func statusBadge(icon: String, label: String, color: Color, background: Color) -> some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Image(systemName: icon)
                .font(DesignSystem.Typography.label)
            Text(label)
                .font(DesignSystem.Typography.monoSmallBold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(background)
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private func optionButton(
        icon: String,
        title: String,
        description: String,
        color: Color,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DesignSystem.Typography.bodySemibold)
                    Text(description).font(DesignSystem.Typography.bodySmall).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isDestructive ? DesignSystem.Colors.dangerBackground : DesignSystem.Colors.glassOverlay)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                .stroke(isDestructive ? DesignSystem.Colors.dangerBorder : .clear, lineWidth: 1)
        )
    }
}
