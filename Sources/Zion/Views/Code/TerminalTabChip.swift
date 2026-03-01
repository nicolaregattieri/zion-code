import SwiftUI

struct TerminalTabChip: View {
    let tab: TerminalPaneNode
    let isActive: Bool
    let accentColor: Color
    let onActivate: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    private var sessions: [TerminalSession] { tab.allSessions() }
    private var title: String { sessions.first?.title ?? "zsh" }
    private var hasAlive: Bool { sessions.contains(where: { $0.isAlive }) }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            Circle()
                .fill(hasAlive ? DesignSystem.Colors.success : DesignSystem.Colors.destructive)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.system(size: 10, weight: isActive ? .bold : .regular, design: .monospaced))
                .lineLimit(1)

            if sessions.count > 1 {
                Text("\(sessions.count)")
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? accentColor.opacity(0.25) : (isHovered ? DesignSystem.Colors.glassHover : DesignSystem.Colors.glassSubtle))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                .stroke(isActive ? DesignSystem.Colors.selectionBorder : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onActivate() }
        .onHover { h in isHovered = h }
    }
}
