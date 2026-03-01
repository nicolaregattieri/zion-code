import SwiftUI

struct SearchNavButton: View {
    let icon: String
    let tooltip: String
    var isSecondary: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(isSecondary ? .secondary : .primary)
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .background(isHovered ? DesignSystem.Interactive.hoverBackground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))
        .contentShape(Rectangle())
        .onHover { h in isHovered = h }
        .help(tooltip)
        .accessibilityLabel(tooltip)
    }
}
