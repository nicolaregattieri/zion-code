import SwiftUI

extension ContentView {

    var statusBar: some View {
        HStack(spacing: 12) {
            Text(model.statusMessage).lineLimit(1).font(DesignSystem.Typography.label).foregroundStyle(.secondary)

            statusBarQuickNavigation

            Spacer()

            if model.repositoryURL != nil && !model.isRepositorySwitching {
                // Branch pill
                HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(DesignSystem.Typography.meta)
                    Text(model.currentBranch)
                        .lineLimit(1)
                }
                .font(DesignSystem.Typography.monoLabel)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(zionModeEnabled ? DesignSystem.ZionMode.neonMagenta.opacity(0.12) : DesignSystem.Colors.statusGreenBg)
                .foregroundStyle(zionModeEnabled ? DesignSystem.ZionMode.neonMagenta : DesignSystem.Colors.success)
                .clipShape(Capsule())

                // Ahead remote badge
                if model.aheadRemoteCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(DesignSystem.Typography.meta)
                        Text("\(model.aheadRemoteCount)")
                    }
                    .font(DesignSystem.Typography.label)
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
                            .font(DesignSystem.Typography.meta)
                        Text("\(model.behindRemoteCount)")
                    }
                    .font(DesignSystem.Typography.label)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(zionModeEnabled ? DesignSystem.ZionMode.neonOrange.opacity(0.12) : DesignSystem.Colors.statusOrangeBg)
                    .foregroundStyle(zionModeEnabled ? DesignSystem.ZionMode.neonOrange : DesignSystem.Colors.warning)
                    .clipShape(Capsule())
                }

                // Bisect pill
                if model.isBisectActive {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.trianglehead.branch")
                            .font(DesignSystem.Typography.meta)
                        Text(bisectPillLabel)
                    }
                    .font(DesignSystem.Typography.label)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(bisectPillBg)
                    .foregroundStyle(bisectPillFg)
                    .clipShape(Capsule())
                }

                // Uncommitted changes count
                if model.uncommittedCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "pencil.circle.fill")
                            .font(DesignSystem.Typography.meta)
                        Text("\(model.uncommittedCount)")
                    }
                    .font(DesignSystem.Typography.label)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DesignSystem.Colors.statusBlueBg)
                    .foregroundStyle(DesignSystem.Colors.info)
                    .clipShape(Capsule())
                }

                // Mobile Access indicator (only when prevent-sleep is active)
                if model.isMobileAccessEnabled && model.isPreventingSleep {
                    SettingsLink {
                        HStack(spacing: 3) {
                            Image(systemName: mobileAccessIcon)
                                .font(DesignSystem.Typography.meta)
                            if case .connected(let count) = model.mobileAccessConnectionState {
                                Text("\(count)")
                            }
                            if let expiresAt = model.keepAwakeExpiresAt, expiresAt > .now {
                                Text(expiresAt, style: .timer)
                                    .monospacedDigit()
                            }
                        }
                        .font(DesignSystem.Typography.label)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(mobileAccessBadgeBg)
                        .foregroundStyle(mobileAccessBadgeFg)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(mobileAccessTooltip)
                    .simultaneousGesture(TapGesture().onEnded {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NotificationCenter.default.post(name: .openMobileAccessSettings, object: nil)
                        }
                    })
                }
            }

            if let repositoryURL = model.repositoryURL {
                Text(repositoryURL.path).lineLimit(1).font(DesignSystem.Typography.monoLabel).foregroundStyle(.tertiary)
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
            if model.isBusy {
                NeonProgressLine(mode: .shimmer)
                    .transition(.opacity.animation(.easeOut(duration: 0.3)))
            } else {
                if zionModeEnabled {
                    DesignSystem.ZionMode.neonMagenta.opacity(0.25)
                        .frame(height: 1)
                        .transition(.opacity.animation(.easeIn(duration: 0.5)))
                } else {
                    Divider().opacity(DesignSystem.Opacity.subtle)
                }
            }
        }
        .animation(DesignSystem.Motion.panel, value: model.isBusy)
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
                    .font(DesignSystem.Typography.metaSemibold)
                Text(statusBarSectionLabel(section))
                    .font(DesignSystem.Typography.labelSemibold)
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
                        .opacity(DesignSystem.Opacity.visible)
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
                    .font(DesignSystem.Typography.metaSemibold)
                Text(L10n("status.nav.settings"))
                    .font(DesignSystem.Typography.labelSemibold)
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

    // MARK: - Bisect Pill Helpers

    private var bisectPillLabel: String {
        switch model.bisectPhase {
        case .awaitingGoodCommit:
            return L10n("bisect.pill.pickGood")
        case .active(_, let steps):
            return L10n("bisect.pill.active", "\(steps)")
        case .foundCulprit(let hash):
            return L10n("bisect.pill.found", String(hash.prefix(8)))
        case .inactive:
            return ""
        }
    }

    private var bisectPillBg: Color {
        if case .foundCulprit = model.bisectPhase {
            return zionModeEnabled ? DesignSystem.ZionMode.neonOrange.opacity(0.12) : DesignSystem.Colors.destructiveBg
        }
        return zionModeEnabled ? DesignSystem.ZionMode.neonCyan.opacity(0.12) : DesignSystem.Colors.statusBlueBg
    }

    private var bisectPillFg: Color {
        if case .foundCulprit = model.bisectPhase {
            return zionModeEnabled ? DesignSystem.ZionMode.neonOrange : DesignSystem.Colors.destructive
        }
        return zionModeEnabled ? DesignSystem.ZionMode.neonCyan : DesignSystem.Colors.info
    }

    // MARK: - Mobile Access Badge Helpers

    private var mobileAccessIcon: String {
        if case .error = model.mobileAccessConnectionState {
            return "iphone.slash"
        }
        return "iphone.radiowaves.left.and.right"
    }

    private var mobileAccessBadgeBg: Color {
        switch model.mobileAccessConnectionState {
        case .disabled:
            return .clear
        case .starting:
            return zionModeEnabled ? DesignSystem.ZionMode.neonCyan.opacity(0.12) : DesignSystem.Colors.statusBlueBg
        case .waitingForPairing:
            return zionModeEnabled ? DesignSystem.ZionMode.neonOrange.opacity(0.12) : DesignSystem.Colors.statusOrangeBg
        case .connected:
            return zionModeEnabled ? DesignSystem.ZionMode.neonCyan.opacity(0.12) : DesignSystem.Colors.statusGreenBg
        case .error:
            return zionModeEnabled ? DesignSystem.ZionMode.neonOrange.opacity(0.12) : DesignSystem.Colors.error.opacity(0.12)
        }
    }

    private var mobileAccessBadgeFg: Color {
        switch model.mobileAccessConnectionState {
        case .disabled:
            return .secondary
        case .starting:
            return zionModeEnabled ? DesignSystem.ZionMode.neonCyan : DesignSystem.Colors.info
        case .waitingForPairing:
            return zionModeEnabled ? DesignSystem.ZionMode.neonOrange : DesignSystem.Colors.warning
        case .connected:
            return zionModeEnabled ? DesignSystem.ZionMode.neonCyan : DesignSystem.Colors.success
        case .error:
            return zionModeEnabled ? DesignSystem.ZionMode.neonOrange : DesignSystem.Colors.error
        }
    }

    private var mobileAccessTooltip: String {
        switch model.mobileAccessConnectionState {
        case .disabled:
            return ""
        case .starting:
            return L10n("mobile.status.starting")
        case .waitingForPairing:
            return L10n("mobile.status.waitingForPairing")
        case .connected(let count):
            return L10n("mobile.status.connected", count)
        case .error:
            return L10n("mobile.status.error")
        }
    }
}
