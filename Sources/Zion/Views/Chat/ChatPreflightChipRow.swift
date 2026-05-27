import SwiftUI

/// Pre-flight chip row anchored above the composer. Three menu-style chips
/// let the user choose interaction mode, permission policy, and shell-command
/// policy before sending a message.
///
/// Values persist via `UserDefaults` (`chat.preflight.*` keys). Integration
/// with existing AI mode / shell settings is deferred — the chips currently
/// just store the user's intent.
struct ChatPreflightChipRow: View {
    /// Compact variant collapses to a tighter pill row (used above composer
    /// after the first message). Welcome-state uses the regular size.
    var compact: Bool = false

    @AppStorage("chat.preflight.mode") private var modeRaw: String = PreflightMode.edit.rawValue
    @AppStorage("chat.preflight.permission") private var permissionRaw: String = PreflightPermission.askAlways.rawValue
    @AppStorage("chat.preflight.shellPolicy") private var shellRaw: String = PreflightShell.safe.rawValue

    enum PreflightMode: String, CaseIterable, Identifiable {
        case ask, edit, execute
        var id: String { rawValue }
        var labelKey: String {
            switch self {
            case .ask: return "chat.preflight.mode.ask"
            case .edit: return "chat.preflight.mode.edit"
            case .execute: return "chat.preflight.mode.execute"
            }
        }
    }

    enum PreflightPermission: String, CaseIterable, Identifiable {
        case askAlways, acceptEdits, automatic
        var id: String { rawValue }
        var labelKey: String {
            switch self {
            case .askAlways: return "chat.preflight.permission.askAlways"
            case .acceptEdits: return "chat.preflight.permission.acceptEdits"
            case .automatic: return "chat.preflight.permission.automatic"
            }
        }
        var tint: Color {
            switch self {
            case .askAlways: return .clear
            case .acceptEdits: return Color.orange.opacity(0.15)
            case .automatic: return Color.red.opacity(0.15)
            }
        }
    }

    enum PreflightShell: String, CaseIterable, Identifiable {
        case off, safe, all
        var id: String { rawValue }
        var labelKey: String {
            switch self {
            case .off: return "chat.preflight.shell.off"
            case .safe: return "chat.preflight.shell.safe"
            case .all: return "chat.preflight.shell.all"
            }
        }
    }

    private var mode: PreflightMode {
        PreflightMode(rawValue: modeRaw) ?? .edit
    }

    private var permission: PreflightPermission {
        PreflightPermission(rawValue: permissionRaw) ?? .askAlways
    }

    private var shell: PreflightShell {
        PreflightShell(rawValue: shellRaw) ?? .safe
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.compact) {
            modeChip
            permissionChip
            if mode == .execute {
                shellChip
            }
        }
    }

    private var modeChip: some View {
        Menu {
            ForEach(PreflightMode.allCases) { opt in
                Button {
                    modeRaw = opt.rawValue
                } label: {
                    if opt == mode {
                        Label(L10n(opt.labelKey), systemImage: "checkmark")
                    } else {
                        Text(L10n(opt.labelKey))
                    }
                }
            }
        } label: {
            chipLabel(
                prefix: L10n("chat.preflight.mode"),
                value: L10n(mode.labelKey),
                tint: .clear
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var permissionChip: some View {
        Menu {
            ForEach(PreflightPermission.allCases) { opt in
                Button {
                    permissionRaw = opt.rawValue
                } label: {
                    if opt == permission {
                        Label(L10n(opt.labelKey), systemImage: "checkmark")
                    } else {
                        Text(L10n(opt.labelKey))
                    }
                }
            }
        } label: {
            chipLabel(
                prefix: L10n("chat.preflight.permission"),
                value: L10n(permission.labelKey),
                tint: permission.tint
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var shellChip: some View {
        Menu {
            ForEach(PreflightShell.allCases) { opt in
                Button {
                    shellRaw = opt.rawValue
                } label: {
                    if opt == shell {
                        Label(L10n(opt.labelKey), systemImage: "checkmark")
                    } else {
                        Text(L10n(opt.labelKey))
                    }
                }
            }
        } label: {
            chipLabel(
                prefix: L10n("chat.preflight.shell"),
                value: L10n(shell.labelKey),
                tint: .clear
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private func chipLabel(prefix: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(prefix + ":")
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(compact ? DesignSystem.Typography.label : DesignSystem.Typography.body)
        .padding(.horizontal, compact ? DesignSystem.Spacing.compact : DesignSystem.Spacing.standard)
        .padding(.vertical, compact ? 4 : 6)
        .background(
            Capsule()
                .fill(tint == .clear ? DesignSystem.Colors.glassSubtle : tint)
        )
        .overlay(
            Capsule()
                .strokeBorder(DesignSystem.Colors.glassStroke, lineWidth: 1)
        )
    }
}
