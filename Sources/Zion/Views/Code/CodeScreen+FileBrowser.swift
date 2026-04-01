import SwiftUI

extension CodeScreen {

    // MARK: - File Browser Pane

    var fileBrowserPane: some View {
        VStack(spacing: 0) {
            // Sidebar mode bar
            HStack(spacing: 0) {
                sidebarModeButton(mode: .fileTree, icon: "folder.fill", tooltip: L10n("Arquivos"))
                sidebarModeButton(mode: .findInFiles, icon: "magnifyingglass", tooltip: L10n("Buscar nos Arquivos") + " (⇧⌘F)")

                Spacer()

                if sidebarMode == .fileTree {
                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Button {
                            withAnimation(DesignSystem.Motion.detail) {
                                isFileBrowserFilterVisible.toggle()
                                if !isFileBrowserFilterVisible {
                                    fileBrowserFilterText = ""
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .iconHitTarget(DesignSystem.IconSize.editorToolbarFrame)
                        }
                        .buttonStyle(.plain).cursorArrow()
                        .foregroundStyle(isFileBrowserFilterVisible ? Color.accentColor : .secondary)
                        .help(L10n("fileBrowser.filter"))
                        .accessibilityLabel(L10n("fileBrowser.filter"))

                        Button { model.showDotfiles.toggle() } label: {
                            Image(systemName: model.showDotfiles ? "eye" : "eye.slash")
                                .iconHitTarget(DesignSystem.IconSize.editorToolbarFrame)
                        }
                        .buttonStyle(.plain).cursorArrow().foregroundStyle(.secondary)
                        .help(L10n("fileBrowser.toggleHidden") + " (⇧⌘H)")
                        .accessibilityLabel(L10n("fileBrowser.toggleHidden"))

                        Button { model.refreshFileTree() } label: {
                            Image(systemName: "arrow.clockwise")
                                .iconHitTarget(DesignSystem.IconSize.editorToolbarFrame)
                        }
                        .buttonStyle(.plain).cursorArrow().foregroundStyle(.secondary)
                        .help(L10n("Atualizar arvore de arquivos"))
                        .accessibilityLabel(L10n("Atualizar arvore de arquivos"))
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.cardPadding)
            .padding(.vertical, 6)

            Divider()

            if isFileBrowserFilterVisible && sidebarMode == .fileTree {
                HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                    Image(systemName: "magnifyingglass")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(.tertiary)
                    TextField(L10n("fileBrowser.filter.placeholder"), text: $fileBrowserFilterText)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.body)
                        .focused($isFileBrowserFilterFocused)
                        .onExitCommand {
                            fileBrowserFilterText = ""
                            isFileBrowserFilterVisible = false
                        }
                }
                .padding(.horizontal, DesignSystem.Spacing.cardPadding)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.glassSubtle)
                Divider()
            }

            if sidebarMode == .findInFiles {
                FindInFilesView(
                    model: model,
                    query: $findInFilesQuery,
                    includePattern: $findInFilesInclude,
                    excludePattern: $findInFilesExclude,
                    results: $findInFilesResults,
                    isSearching: $isFindInFilesSearching,
                    scopePath: $findInFilesScopePath,
                    focusRequestID: findInFilesFocusRequestID,
                    onClose: { closeFindInFilesPanel() }
                )
            } else {

            // File tree scroll — fills available space
            ScrollViewReader { scrollProxy in
                ZStack(alignment: .topLeading) {
                    FileBrowserShortcutResponderHost(
                        reference: fileBrowserResponderReference,
                        canDeleteSelectedFiles: canDeleteFileBrowserSelection,
                        onDeleteSelectedFiles: handleFileBrowserDeleteShortcut,
                        canRenameSelectedFile: canRenameFileBrowserSelection,
                        onRenameSelectedFile: handleFileBrowserRenameShortcut,
                        onMoveSelection: moveFileBrowserSelection
                    )
                    .frame(width: 0, height: 0)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            let displayFiles = filteredRepositoryFiles
                            if displayFiles.isEmpty {
                                VStack(spacing: 16) {
                                    Text(L10n("Nenhum arquivo encontrado")).font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                                    if !isFileBrowserFilterVisible {
                                        Button {
                                            onOpenFolder?()
                                        } label: {
                                            Label(L10n("Selecionar Pasta"), systemImage: "folder.badge.plus")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(DesignSystem.Spacing.sectionGap)
                                .frame(maxWidth: .infinity)
                            } else {
                                ForEach(displayFiles) { item in
                                    FileTreeNodeView(
                                        model: model,
                                        item: item,
                                        level: 0,
                                        onActivate: focusFileBrowserResponder
                                    )
                                    .id(item.id)
                                }
                            }

                        }
                        .padding(.top, DesignSystem.Spacing.standard)
                        .background {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    focusFileBrowserResponder()
                                    model.clearFileSelection()
                                }
                        }
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let repoURL = model.repositoryURL else { return false }
                        model.handleFileDrop(urls, into: repoURL)
                        return true
                    }
                }
                .onChange(of: fileBrowserScrollRequestID) { _, _ in
                    guard let target = fileBrowserScrollTargetID else { return }
                    withAnimation(DesignSystem.Motion.snappy) {
                        scrollProxy.scrollTo(target, anchor: .center)
                    }
                }
                .onChange(of: model.revealFileInBrowserRequestID) { _, _ in
                    guard let target = model.lastClickedFileID else { return }
                    withAnimation(DesignSystem.Motion.snappy) {
                        scrollProxy.scrollTo(target, anchor: .center)
                    }
                }
            }
            } // end else (fileTree mode)

            ClipboardDrawer(model: model)
                .frame(maxHeight: 280, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: model.findInFilesScopeRequest) { _, newValue in
            if let scope = newValue {
                findInFilesScopePath = scope
                sidebarMode = .findInFiles
                if !isFileBrowserVisible {
                    withAnimation(DesignSystem.Motion.panel) { isFileBrowserVisible = true }
                }
                findInFilesFocusRequestID += 1
                model.findInFilesScopeRequest = nil
            }
        }
        .onChange(of: isFileBrowserFilterVisible) { _, isVisible in
            guard sidebarMode == .fileTree else { return }
            if isVisible {
                Task { @MainActor in
                    isFileBrowserFilterFocused = true
                }
            } else {
                isFileBrowserFilterFocused = false
            }
        }
        .onChange(of: fileBrowserFilterText) { _, _ in
            recomputeFileBrowserFilter()
        }
        .onChange(of: model.repositoryURL) { _, _ in
            cachedFilteredFiles = nil
            sidebarMode = .fileTree
            findInFilesQuery = ""
            findInFilesInclude = ""
            findInFilesExclude = ""
            findInFilesResults = []
            isFindInFilesSearching = false
            findInFilesScopePath = nil
            selectedBrowserIndex = -1
        }
        .background(DesignSystem.Colors.background.opacity(0.3))
        .contextMenu {
            if let repoURL = model.repositoryURL {
                Button { model.createNewFileInFolder(parentURL: repoURL) } label: {
                    Label(L10n("Novo Arquivo"), systemImage: "doc.badge.plus")
                }
                Button { model.createNewFolder(parentURL: repoURL) } label: {
                    Label(L10n("Nova Pasta"), systemImage: "folder.badge.plus")
                }
                if model.hasFileBrowserClipboard {
                    Divider()
                    Button { model.pasteFileItem(into: repoURL) } label: {
                        Label(L10n("Colar"), systemImage: "doc.on.clipboard")
                    }
                }
            }
        }
    }

    func sidebarModeButton(mode: SidebarMode, icon: String, tooltip: String) -> some View {
        Button {
            withAnimation(DesignSystem.Motion.detail) { sidebarMode = mode }
            if mode == .findInFiles {
                findInFilesFocusRequestID += 1
            }
        } label: {
            Image(systemName: icon)
                .font(DesignSystem.Typography.bodySmall)
                .iconHitTarget(CGSize(width: 26, height: 22))
                .foregroundStyle(sidebarMode == mode ? .primary : .secondary)
                .background(sidebarMode == mode ? DesignSystem.Colors.selectionBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    var filteredRepositoryFiles: [FileItem] {
        if fileBrowserFilterText.isEmpty { return model.repositoryFiles }
        return cachedFilteredFiles ?? model.repositoryFiles
    }

    func recomputeFileBrowserFilter() {
        filterDebounceTask?.cancel()
        guard !fileBrowserFilterText.isEmpty else {
            cachedFilteredFiles = nil
            return
        }
        let query = fileBrowserFilterText.lowercased()
        let files = model.repositoryFiles
        let task = DispatchWorkItem { [self] in
            cachedFilteredFiles = files.compactMap { EditorHelpers.filterFileTree($0, query: query) }
        }
        filterDebounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.fileBrowserFilterDebounce, execute: task)
    }

    func closeFindInFilesPanel() {
        guard sidebarMode == .findInFiles else { return }
        withAnimation(DesignSystem.Motion.detail) {
            sidebarMode = .fileTree
        }
    }

    func selectedFileBrowserItems() -> [FileItem] {
        let flat = model.visibleFlatFiles()
        if !model.selectedFileIDs.isEmpty {
            return flat.filter { model.selectedFileIDs.contains($0.id) }
        }
        if let lastClicked = model.lastClickedFileID,
           let item = flat.first(where: { $0.id == lastClicked }) {
            return [item]
        }
        return []
    }

    func handleFileBrowserDeleteShortcut() {
        guard isFileBrowserVisible, sidebarMode == .fileTree else { return }
        let items = selectedFileBrowserItems()
        guard !items.isEmpty else { return }
        model.deleteFileItems(items)
    }

    func canDeleteFileBrowserSelection() -> Bool {
        guard isFileBrowserVisible, sidebarMode == .fileTree else { return false }
        return !selectedFileBrowserItems().isEmpty
    }

    func handleFileBrowserRenameShortcut() {
        guard canRenameFileBrowserSelection() else { return }
        guard let item = selectedFileBrowserItems().first else { return }
        model.renameFileItem(item)
    }

    func canRenameFileBrowserSelection() -> Bool {
        guard isFileBrowserVisible, sidebarMode == .fileTree else { return false }
        return selectedFileBrowserItems().count == 1
    }

    func focusFileBrowserResponder() {
        DispatchQueue.main.async {
            guard let responder = fileBrowserResponderReference.responder,
                  let window = responder.window else { return }
            window.makeFirstResponder(responder)
        }
    }

    func moveFileBrowserSelection(_ direction: FileBrowserNavigationDirection, isExtendingSelection: Bool) {
        let flatFiles = model.visibleFlatFiles()
        guard !flatFiles.isEmpty else { return }

        syncSelectedBrowserIndex(with: flatFiles)

        switch direction {
        case .up:
            if selectedBrowserIndex == -1 {
                selectedBrowserIndex = flatFiles.count - 1
            } else if selectedBrowserIndex > 0 {
                selectedBrowserIndex -= 1
            }
        case .down:
            if selectedBrowserIndex == -1 {
                selectedBrowserIndex = 0
            } else if selectedBrowserIndex < flatFiles.count - 1 {
                selectedBrowserIndex += 1
            }
        case .left:
            guard selectedBrowserIndex >= 0, selectedBrowserIndex < flatFiles.count else { return }
            let item = flatFiles[selectedBrowserIndex]
            guard item.isDirectory, model.expandedPaths.contains(item.id) else { return }
            withAnimation(DesignSystem.Motion.snappy) {
                model.toggleExpansion(for: item.id)
            }
            return
        case .right:
            guard selectedBrowserIndex >= 0, selectedBrowserIndex < flatFiles.count else { return }
            let item = flatFiles[selectedBrowserIndex]
            if item.isDirectory {
                guard !model.expandedPaths.contains(item.id) else { return }
                withAnimation(DesignSystem.Motion.snappy) {
                    model.toggleExpansion(for: item.id)
                }
            } else {
                model.selectCodeFile(item)
            }
            return
        }

        guard selectedBrowserIndex >= 0, selectedBrowserIndex < flatFiles.count else { return }
        let item = flatFiles[selectedBrowserIndex]
        if isExtendingSelection {
            model.extendSelection(to: item)
        } else {
            model.selectedFileIDs = [item.id]
            model.lastClickedFileID = item.id
        }
        fileBrowserScrollTargetID = item.id
        fileBrowserScrollRequestID += 1
    }

    func syncSelectedBrowserIndex(with flatFiles: [FileItem]) {
        if let clickedID = model.lastClickedFileID,
           let index = flatFiles.firstIndex(where: { $0.id == clickedID }) {
            selectedBrowserIndex = index
            return
        }

        if let selectedID = model.selectedFileIDs.first,
           let index = flatFiles.firstIndex(where: { $0.id == selectedID }) {
            selectedBrowserIndex = index
            return
        }

        selectedBrowserIndex = -1
    }
}
