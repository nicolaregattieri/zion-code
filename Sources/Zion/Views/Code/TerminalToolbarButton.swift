import SwiftUI

struct TerminalToolbarButton: View {
    let icon: String
    let color: Color
    let tooltip: String
    var accessLabel: String? = nil
    var disabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignSystem.IconSize.toolbar)
                .foregroundStyle(color)
                .frame(width: DesignSystem.IconSize.terminalToolbarFrame.width,
                       height: DesignSystem.IconSize.terminalToolbarFrame.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? DesignSystem.Interactive.hoverBackground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))
        .onHover { h in isHovered = h }
        .help(tooltip)
        .accessibilityLabel(accessLabel ?? tooltip)
        .disabled(disabled)
    }
}
