import SwiftUI

struct FileTreeNodeView: View {
    var model: RepositoryViewModel
    let item: FileItem
    let level: Int
    var isFiltering: Bool = false
    var onActivate: (() -> Void)? = nil
    @State private var isHovered = false
    @State private var isDropTarget = false

    var body: some View {
        let isExpanded = isFiltering || model.expandedPaths.contains(item.id)
        let isSelected = model.selectedFileIDs.contains(item.id) ||
                         (model.selectedFileIDs.isEmpty && model.activeFileID == item.id)
        let isDark = model.selectedTheme.isDark
        let isModified: Bool = {
            guard let repoPath = model.repositoryURL?.path else { return false }
            let relativePath = item.url.path.replacingOccurrences(of: repoPath + "/", with: "")
            if item.isDirectory {
                return model.uncommittedDirectoryPrefixes.contains(relativePath + "/")
            } else {
                return model.uncommittedFilePaths.contains(relativePath)
            }
        }()
        let isIgnored = item.isGitIgnored

        VStack(alignment: .leading, spacing: 0) {
            Button {
                onActivate?()
                let flags = NSApp.currentEvent?.modifierFlags.intersection([.command, .shift]) ?? []
                if flags.contains(.command) {
                    model.toggleFileSelection(item)
                } else if flags.contains(.shift) {
                    model.rangeSelectFile(item)
                } else {
                    model.plainClickFile(item)
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    if item.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(DesignSystem.Typography.micro).foregroundStyle(.secondary.opacity(0.5)).frame(width: 12)
                    } else { Spacer().frame(width: 12) }

                    if item.isDirectory {
                        FolderIcon(
                            isOpen: isExpanded,
                            color: isModified ? DesignSystem.Colors.warning : (isDark ? Color.accentColor : DesignSystem.Colors.info),
                            size: 14
                        )
                    } else {
                        Image(systemName: "doc.text")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(isModified ? DesignSystem.Colors.warning : .secondary)
                    }

                    Text(item.name)
                        .font(isSelected ? DesignSystem.Typography.monoBodyBold : DesignSystem.Typography.monoBody)
                        .lineLimit(1)
                        .help(item.name)
                        .foregroundStyle(isSelected ? (isDark ? .white : DesignSystem.Colors.info) : (isModified ? DesignSystem.Colors.warning : .primary))
                }
                .opacity((isIgnored || model.isFileInCutClipboard(item.id)) && !isSelected ? 0.5 : 1.0)
                .padding(.horizontal, 12).padding(.vertical, 6).padding(.leading, CGFloat(level) * 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(isSelected ? DesignSystem.Colors.selectionBackground : (isHovered ? DesignSystem.Colors.glassHover : Color.clear))
            }
            .buttonStyle(.plain)
            .onHover { h in isHovered = h }
            .onDrag {
                let urls: [URL]
                if model.selectedFileIDs.contains(item.id), model.selectedFileIDs.count > 1 {
                    urls = model.selectedFileItems().map(\.url)
                } else {
                    urls = [item.url]
                }
                let provider = NSItemProvider(object: item.url as NSURL)
                if let data = try? JSONEncoder().encode(urls) {
                    provider.registerDataRepresentation(
                        forTypeIdentifier: "dev.zioncode.file-items",
                        visibility: .ownProcess
                    ) { completion in
                        completion(data, nil)
                        return nil
                    }
                }
                return provider
            }
            .background(
                Group {
                    if item.isDirectory {
                        RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .opacity(isDropTarget ? 1 : 0)
                    }
                }
            )
            .modifier(FolderDropTarget(
                isDirectory: item.isDirectory,
                folderURL: item.url,
                model: model,
                isDropTarget: $isDropTarget
            ))
            .contextMenu {
                let effectiveSelection: [FileItem] = {
                    if model.selectedFileIDs.contains(item.id) && model.selectedFileIDs.count > 1 {
                        return model.selectedFileItems()
                    }
                    return [item]
                }()
                let isMulti = effectiveSelection.count > 1
                let pasteTarget = item.isDirectory ? item.url : item.url.deletingLastPathComponent()

                if item.isDirectory && !isMulti {
                    Button { model.createNewFileInFolder(parentURL: item.url) } label: {
                        Label(L10n("Novo Arquivo"), systemImage: "doc.badge.plus")
                    }
                    Button { model.createNewFolder(parentURL: item.url) } label: {
                        Label(L10n("Nova Pasta"), systemImage: "folder.badge.plus")
                    }

                    Divider()
                }

                if !item.isDirectory && !isMulti {
                    Button { model.selectCodeFile(item) } label: {
                        Label(L10n("Abrir no Editor"), systemImage: "pencil.and.outline")
                    }

                    Button {
                        if let repoURL = model.repositoryURL {
                            let relativePath = item.url.path.replacingOccurrences(of: repoURL.path + "/", with: "")
                            model.loadFileHistory(for: relativePath)
                        }
                    } label: {
                        Label(L10n("filehistory.title"), systemImage: "clock.arrow.circlepath")
                    }

                    Divider()

                    Button { model.createNewFileInFolder(parentURL: item.url.deletingLastPathComponent()) } label: {
                        Label(L10n("Novo Arquivo"), systemImage: "doc.badge.plus")
                    }
                    Button { model.createNewFolder(parentURL: item.url.deletingLastPathComponent()) } label: {
                        Label(L10n("Nova Pasta"), systemImage: "folder.badge.plus")
                    }

                    Divider()
                }

                // Copy / Cut / Paste
                Button { model.copyFileItems(effectiveSelection) } label: {
                    Label(isMulti ? String(format: L10n("Copiar %d Itens"), effectiveSelection.count) : L10n("Copiar"), systemImage: "doc.on.doc")
                }
                Button { model.cutFileItems(effectiveSelection) } label: {
                    Label(isMulti ? String(format: L10n("Recortar %d Itens"), effectiveSelection.count) : L10n("Recortar"), systemImage: "scissors")
                }
                if model.hasFileBrowserClipboard && !isMulti {
                    Button { model.pasteFileItem(into: pasteTarget) } label: {
                        Label(L10n("Colar"), systemImage: "doc.on.clipboard")
                    }
                }

                Divider()

                // Rename (single only) / Duplicate
                if !isMulti {
                    Button { model.renameFileItem(item) } label: {
                        Label(L10n("Renomear..."), systemImage: "pencil")
                    }
                }
                Button { model.duplicateFileItems(effectiveSelection) } label: {
                    Label(isMulti ? String(format: L10n("Duplicar %d Itens"), effectiveSelection.count) : L10n("Duplicar"), systemImage: "plus.square.on.square")
                }

                Divider()

                // Delete
                Button(role: .destructive) { model.deleteFileItems(effectiveSelection) } label: {
                    Label(isMulti ? String(format: L10n("Excluir %d Itens"), effectiveSelection.count) : L10n("Excluir"), systemImage: "trash")
                }

                Divider()

                // Reveal in Finder
                Button { NSWorkspace.shared.activateFileViewerSelecting(effectiveSelection.map(\.url)) } label: {
                    Label(L10n("Revelar no Finder"), systemImage: "folder")
                }

                // Find in Folder (directory only, single only)
                if item.isDirectory && !isMulti {
                    Divider()

                    Button {
                        model.findInFilesScopeRequest = item.url.path
                    } label: {
                        Label(L10n("Buscar na Pasta"), systemImage: "magnifyingglass")
                    }
                }

                // Add to .gitignore
                if let repoURL = model.repositoryURL {
                    let nonIgnoredItems = effectiveSelection.filter { !$0.isGitIgnored }
                    if !nonIgnoredItems.isEmpty {
                        Divider()

                        Button {
                            for fileItem in nonIgnoredItems {
                                let relativePath = fileItem.url.path.replacingOccurrences(of: repoURL.path + "/", with: "")
                                model.addToGitIgnore(path: relativePath)
                            }
                        } label: {
                            Label(L10n("Adicionar ao .gitignore"), systemImage: "eye.slash")
                        }
                    }
                }
            }

            if item.isDirectory && isExpanded, let children = item.children {
                ForEach(children) { child in
                    FileTreeNodeView(
                        model: model,
                        item: child,
                        level: level + 1,
                        isFiltering: isFiltering,
                        onActivate: onActivate
                    )
                }
            }
        }
    }
}

// MARK: - Folder Drop Target

private struct FolderDropTarget: ViewModifier {
    let isDirectory: Bool
    let folderURL: URL
    var model: RepositoryViewModel
    @Binding var isDropTarget: Bool

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                let target = isDirectory ? folderURL : folderURL.deletingLastPathComponent()
                model.handleFileDrop(urls, into: target)
                return true
            } isTargeted: { targeted in
                isDropTarget = isDirectory ? targeted : false
            }
    }
}
