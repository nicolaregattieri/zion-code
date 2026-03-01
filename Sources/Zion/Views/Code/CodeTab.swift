import SwiftUI

struct CodeTab: View {
    var model: RepositoryViewModel
    let file: FileItem
    let isActive: Bool
    let accentColor: Color
    let onActivate: () -> Void
    let onClose: () -> Void
    @State private var isHovered = false

    private var isUnsaved: Bool { model.unsavedFiles.contains(file.id) }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            if isUnsaved {
                Circle().fill(DesignSystem.Colors.warning).frame(width: 6, height: 6)
            }

            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? accentColor : .secondary)

            Text(file.name)
                .font(.system(size: 11, weight: isActive ? .bold : .regular))
                .lineLimit(1)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .cursorArrow()
            .opacity(isActive || isHovered ? 1.0 : 0.0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? model.selectedTheme.colors.background : (isHovered ? DesignSystem.Colors.glassElevated : Color.clear))
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle().fill(accentColor).frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            if !isActive {
                Rectangle().fill(DesignSystem.Colors.glassHover).frame(width: 1).padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onActivate() }
        .onHover { h in isHovered = h }
    }
}
