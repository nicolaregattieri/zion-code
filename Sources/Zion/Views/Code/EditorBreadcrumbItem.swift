import SwiftUI

struct EditorBreadcrumbItem: Identifiable {
    let id: String
    let title: String
    let targetPath: String?
    let isFile: Bool
    let isEllipsis: Bool
}

struct BreadcrumbFolderSegmentButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.Typography.monoLabel)
                .lineLimit(1)
                .foregroundStyle(isHovered ? Color.primary : DesignSystem.Colors.textSecondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(isHovered ? DesignSystem.Colors.glassHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(DesignSystem.Motion.detail) {
                isHovered = hovering
            }
        }
    }
}
