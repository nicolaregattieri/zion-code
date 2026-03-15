import SwiftUI

extension CodeScreen {

    // MARK: - Zen Mode

    var focusModeExitBar: some View {
        HStack {
            Spacer(minLength: 0)
            zenModeExitButton(showsShortcutHint: true)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    func zenModeExitButton(showsDismissGlyph: Bool = false, showsShortcutHint: Bool = false) -> some View {
        Button {
            NotificationCenter.default.post(name: .toggleZenMode, object: nil)
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(DesignSystem.IconSize.toolbar)
                Text(L10n("zen.exit"))
                    .font(DesignSystem.Typography.bodyMedium)
                if showsShortcutHint {
                    Text("⇧⌘J")
                        .font(DesignSystem.Typography.monoLabel)
                        .foregroundStyle(.secondary)
                }
                if showsDismissGlyph {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignSystem.IconSize.toolbar)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                    .fill(DesignSystem.Colors.glassSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                    .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(L10n("zen.exit") + " (⇧⌘J)")
        .accessibilityLabel(L10n("zen.exit"))
    }

    func applyZenModeState(_ enabled: Bool) {
        if enabled {
            if previousLayoutBeforeZen == nil {
                previousLayoutBeforeZen = layout
            }
            layout = .terminalOnly
        } else if let previousLayoutBeforeZen {
            layout = previousLayoutBeforeZen
            self.previousLayoutBeforeZen = nil
        }
    }
}
