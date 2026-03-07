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
    private var isMissing: Bool { model.missingOpenFileIDs.contains(file.id) }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            if isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.destructive)
                    .help(L10n("editor.tab.missingTooltip"))
            } else if isUnsaved {
                Circle().fill(DesignSystem.Colors.warning).frame(width: 6, height: 6)
            }

            Image(systemName: "doc.text")
                .font(DesignSystem.Typography.bodySmall)
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
        .animation(DesignSystem.Motion.snappy, value: isActive)
        .contextMenu {
            Button { onClose() } label: {
                Label(L10n("editor.tab.close"), systemImage: "xmark")
            }
            Button { model.closeOtherFiles(keepingID: file.id) } label: {
                Label(L10n("editor.tab.closeOthers"), systemImage: "square.on.square")
            }
            .disabled(model.openedFiles.count <= 1)

            Button { model.closeFilesToTheLeft(ofID: file.id) } label: {
                Label(L10n("editor.tab.closeLeft"), systemImage: "arrow.left.to.line")
            }
            .disabled(model.openedFiles.first?.id == file.id)

            Button { model.closeFilesToTheRight(ofID: file.id) } label: {
                Label(L10n("editor.tab.closeRight"), systemImage: "arrow.right.to.line")
            }
            .disabled(model.openedFiles.last?.id == file.id)

            Divider()

            Button { model.closeAllFiles() } label: {
                Label(L10n("editor.tab.closeAll"), systemImage: "xmark.square")
            }
        }
    }
}
