import SwiftUI

extension ContentView {

    var statusBar: some View {
        HStack(spacing: 12) {
            if model.isBusy { ProgressView().controlSize(.small) }
            Text(model.statusMessage).lineLimit(1).font(.caption).foregroundStyle(.secondary)

            statusBarQuickNavigation

            Spacer()

            if model.repositoryURL != nil && !model.isRepositorySwitching {
                // Branch pill
                HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                    Text(model.currentBranch)
                        .lineLimit(1)
                }
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(zionModeEnabled ? DesignSystem.ZionMode.neonMagenta.opacity(0.12) : DesignSystem.Colors.statusGreenBg)
                .foregroundStyle(zionModeEnabled ? DesignSystem.ZionMode.neonMagenta : DesignSystem.Colors.success)
                .clipShape(Capsule())

                // Ahead remote badge
                if model.aheadRemoteCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 9))
                        Text("\(model.aheadRemoteCount)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        zionModeEnabled
                            ? DesignSystem.ZionMode.neonGold.opacity(0.12)
                            : (model.behindRemoteCount > 0 ? DesignSystem.Colors.statusOrangeBg : DesignSystem.Colors.statusBlueBg)
                    )
                    .foregroundStyle(
                        zionModeEnabled
                            ? DesignSystem.ZionMode.neonGold
                            : (model.behindRemoteCount > 0 ? DesignSystem.Colors.warning : DesignSystem.Colors.info)
                    )
                    .clipShape(Capsule())
                }

                // Behind remote badge
                if model.behindRemoteCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 9))
                        Text("\(model.behindRemoteCount)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(zionModeEnabled ? DesignSystem.ZionMode.neonOrange.opacity(0.12) : DesignSystem.Colors.statusOrangeBg)
                    .foregroundStyle(zionModeEnabled ? DesignSystem.ZionMode.neonOrange : DesignSystem.Colors.warning)
                    .clipShape(Capsule())
                }

                // Uncommitted changes count
                if model.uncommittedCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 9))
                        Text("\(model.uncommittedCount)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DesignSystem.Colors.statusBlueBg)
                    .foregroundStyle(DesignSystem.Colors.info)
                    .clipShape(Capsule())
                }
            }

            if let repositoryURL = model.repositoryURL {
                Text(repositoryURL.path).lineLimit(1).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            if zionModeEnabled {
                ZStack {
                    DesignSystem.ZionMode.neonBase
                    Rectangle().fill(.ultraThinMaterial)
                }
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .top) {
            if zionModeEnabled {
                if model.isBusy {
                    NeonProgressLine(mode: .shimmer)
                        .transition(.opacity.animation(.easeOut(duration: 0.3)))
                } else {
                    DesignSystem.ZionMode.neonMagenta.opacity(0.25)
                        .frame(height: 1)
                        .transition(.opacity.animation(.easeIn(duration: 0.5)))
                }
            } else {
                Divider().opacity(0.45)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.isBusy)
    }

    var statusBarQuickNavigation: some View {
        HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
            statusBarSectionButton(.code)
            statusBarSectionButton(.graph)
            statusBarSectionButton(.operations)

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            statusBarSettingsButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(zionModeEnabled ? DesignSystem.ZionMode.neonMagenta.opacity(0.03) : DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                .stroke(zionModeEnabled ? DesignSystem.ZionMode.neonMagenta.opacity(0.12) : DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
    }

    func statusBarSectionButton(_ section: AppSection) -> some View {
        let isSelected = selectedSection == section
        let isDisabled = section != .code && model.repositoryURL == nil

        return Button {
            route(.requestSection(section))
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: section.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(statusBarSectionLabel(section))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                    .fill(isSelected ? (zionModeEnabled ? DesignSystem.ZionMode.neonMagenta.opacity(0.12) : DesignSystem.Colors.selectionBackground) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                    .stroke(isSelected ? (zionModeEnabled ? DesignSystem.ZionMode.neonMagenta.opacity(0.15) : DesignSystem.Colors.selectionBorder) : Color.clear, lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                if isSelected && zionModeEnabled {
                    DesignSystem.ZionMode.neonGradient
                        .frame(height: DesignSystem.ZionMode.neonLineHeight)
                        .padding(.horizontal, 4)
                        .clipShape(Capsule())
                        .opacity(0.7)
                        .shadow(color: DesignSystem.ZionMode.neonMagenta.opacity(0.2),
                                radius: 1, y: 1)
                        .transition(.opacity)
                        .animation(DesignSystem.Motion.detail, value: isSelected)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .help(statusBarSectionLabel(section))
        .accessibilityLabel(statusBarSectionLabel(section))
    }

    var statusBarSettingsButton: some View {
        SettingsLink {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: "gearshape")
                    .font(.system(size: 9, weight: .semibold))
                Text(L10n("status.nav.settings"))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n("settings.open.hint"))
        .accessibilityLabel(L10n("status.nav.settings"))
    }

    func statusBarSectionLabel(_ section: AppSection) -> String {
        L10n(section.title)
    }
}
