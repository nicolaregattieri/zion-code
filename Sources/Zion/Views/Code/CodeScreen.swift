import SwiftUI

enum EditorTerminalLayout: String, CaseIterable {
    case editorOnly
    case split
    case terminalOnly
}

private enum EditorSymbolResultsMode {
    case definitions
    case references
}

struct CodeScreen: View {
    @Bindable var model: RepositoryViewModel
    var onOpenFolder: (() -> Void)? = nil
    var isZenMode: Bool = false
    @Environment(\.zionModeEnabled) private var zionModeEnabled
    @AppStorage("editor.showBreadcrumb") private var showBreadcrumbPath: Bool = true
    @State private var isQuickOpenVisible: Bool = false
    @State private var isFileBrowserVisible: Bool = true
    @State private var fileBrowserRatio: CGFloat = 0.25
    @State private var terminalRatio: CGFloat = 0.6
    @State private var layout: EditorTerminalLayout = .split
    @State private var previousLayoutBeforeZen: EditorTerminalLayout?
    @State private var isSearchVisible: Bool = false
    @State private var isReplaceVisible: Bool = false
    @State private var searchQuery: String = ""
    @State private var seededFindQuery: String = ""
    @State private var replaceQuery: String = ""
    @State private var matchCount: Int = 0
    @State private var currentMatchIndex: Int = 0
    @State private var findSearchFocusRequestID: Int = 0
    @FocusState private var isFileBrowserFocused: Bool
    @State private var selectedBrowserIndex: Int = -1
    @State private var fileBrowserScrollTargetID: String?
    @State private var fileBrowserScrollRequestID: Int = 0
    @State private var showGoToLine: Bool = false
    @State private var goToLineNumber: String = ""
    @State private var goToLineTarget: Int = 0
    @State private var goToLineRequestID: Int = 0
    @State private var isTerminalSearchVisible: Bool = false
    @State private var terminalSearchQuery: String = ""
    @State private var voiceToggleRequestID: Int = 0
    @State private var markdownPreviewRatio: CGFloat = 0.5
    @State private var isMarkdownPreviewVisible: Bool = false
    @FocusState private var isTerminalSearchFocused: Bool
    @State private var isSymbolResultsVisible: Bool = false
    @State private var symbolResultsMode: EditorSymbolResultsMode = .definitions
    @State private var symbolResultsQuery: String = ""
    @State private var symbolResults: [EditorSymbolLocation] = []

    // Find in Files
    enum SidebarMode { case fileTree, findInFiles }
    @State private var sidebarMode: SidebarMode = .fileTree
    @State private var findInFilesQuery: String = ""
    @State private var findInFilesInclude: String = ""
    @State private var findInFilesExclude: String = ""
    @State private var findInFilesResults: [FindInFilesFileResult] = []
    @State private var isFindInFilesSearching: Bool = false
    @State private var findInFilesScopePath: String? = nil

    @AppStorage("terminal.opacity") private var terminalOpacity: Double = 0.92

    /// Ghostty-style terminal transparency: automatically enabled in Zen Mode
    private var isTerminalTransparent: Bool {
        zionModeEnabled
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !isZenMode {
                    editorToolbar
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(model.selectedTheme.colors.background)
                        .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)
                }

                if isFileBrowserVisible && !isZenMode {
                    DraggableSplitView(
                        axis: .horizontal,
                        ratio: $fileBrowserRatio,
                        minLeading: 200,
                        minTrailing: 400
                    ) {
                        fileBrowserPane
                    } trailing: {
                        editorTerminalContent
                    }
                } else {
                    editorTerminalContent
                }
            }

            if isQuickOpenVisible {
                QuickOpenOverlay(
                    model: model,
                    isVisible: $isQuickOpenVisible
                )
                .transition(DesignSystem.Motion.fadeScale)
            }
        }
        .padding(isZenMode ? 0 : DesignSystem.Spacing.cardPadding)
        .background(DesignSystem.Colors.background)
        .sheet(isPresented: $showGoToLine) {
            goToLineSheet
        }
        .sheet(isPresented: $isSymbolResultsVisible) {
            SymbolResultsSheet(
                title: symbolResultsMode == .definitions
                    ? L10n("editor.navigation.definitions.title", symbolResultsQuery)
                    : L10n("editor.navigation.references.title", symbolResultsQuery),
                emptyText: L10n("editor.navigation.noResults"),
                locations: symbolResults
            ) { location in
                model.openEditorLocation(location)
                isSymbolResultsVisible = false
            }
        }
        .sheet(isPresented: $model.isFileHistoryVisible) {
            if let file = model.selectedCodeFile {
                FileHistorySheet(model: model, fileName: file.name)
            }
        }
        .background {
            Button("") { withAnimation(DesignSystem.Motion.detail) { isQuickOpenVisible.toggle() } }
                .keyboardShortcut("p", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)

            Button("") {
                guard !isZenMode else { return }
                withAnimation(DesignSystem.Motion.panel) { isFileBrowserVisible.toggle() }
            }
                .keyboardShortcut("b", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)

            // Toggle terminal visibility (Cmd+J)
            Button("") {
                guard !isZenMode else { return }
                withAnimation(DesignSystem.Motion.detail) {
                    layout = layout == .editorOnly ? .split : .editorOnly
                }
            }
            .keyboardShortcut("j", modifiers: .command)
            .frame(width: 0, height: 0).opacity(0)

            // Maximize terminal (Cmd+Shift+J)
            Button("") {
                guard !isZenMode else { return }
                withAnimation(DesignSystem.Motion.detail) {
                    layout = layout == .terminalOnly ? .split : .terminalOnly
                }
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
            .frame(width: 0, height: 0).opacity(0)

            // New File (Cmd+N)
            Button("") { model.createNewFile() }
                .keyboardShortcut("n", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)

            // Save As (Cmd+Shift+S)
            Button("") { model.saveCurrentFileAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .frame(width: 0, height: 0).opacity(0)

            // Go to Line (Cmd+G)
            Button("") {
                if isSearchVisible, !searchQuery.isEmpty {
                    navigateToNextMatch()
                } else {
                    showGoToLine = true
                    goToLineNumber = ""
                }
            }
            .keyboardShortcut("g", modifiers: .command)
            .frame(width: 0, height: 0).opacity(0)

            // Previous find result (Shift+Cmd+G) while find UI is visible.
            Button("") {
                guard isSearchVisible, !searchQuery.isEmpty else { return }
                navigateToPreviousMatch()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .frame(width: 0, height: 0).opacity(0)

            // Toggle dotfiles visibility (Shift+Cmd+H)
            Button("") { model.showDotfiles.toggle() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .frame(width: 0, height: 0).opacity(0)

            // Find in Files (Cmd+Shift+F) — toggle
            Button("") {
                guard !isZenMode else { return }
                if sidebarMode == .findInFiles && isFileBrowserVisible {
                    sidebarMode = .fileTree
                } else {
                    sidebarMode = .findInFiles
                    if !isFileBrowserVisible {
                        withAnimation(DesignSystem.Motion.panel) { isFileBrowserVisible = true }
                    }
                }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .frame(width: 0, height: 0).opacity(0)

            // Focus-aware Cmd+F routing
            Button("") { routeFindShortcut() }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)

            // Focus-aware Ctrl+F alias
            Button("") { routeFindShortcut() }
                .keyboardShortcut("f", modifiers: .control)
                .frame(width: 0, height: 0).opacity(0)
        }
        .onChange(of: model.activeFileID) { _, _ in
            isMarkdownPreviewVisible = false
        }
        .onChange(of: model.editorJumpToken) { _, _ in
            goToLineTarget = model.editorJumpLineTarget
            goToLineRequestID += 1
        }
        .onChange(of: searchQuery) { _, _ in
            recomputeFindMatches()
        }
        .onChange(of: model.codeFileContent) { _, _ in
            guard isSearchVisible, !searchQuery.isEmpty else { return }
            recomputeFindMatches()
        }
        .onChange(of: isSearchVisible) { _, visible in
            guard visible else { return }
            recomputeFindMatches()
        }
        .onChange(of: model.editorFindSeedRequestID) { _, _ in
            let query = model.editorFindSeedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            seededFindQuery = query
            openSearch(applySeedIfPresent: true)
        }
        .onAppear {
            applyZenModeState(isZenMode)
        }
        .onChange(of: isZenMode) { _, enabled in
            withAnimation(DesignSystem.Motion.panel) {
                applyZenModeState(enabled)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .formatDocument)) { _ in
            model.formatCurrentFile()
        }
    }

    private var focusModeExitBar: some View {
        HStack {
            Spacer(minLength: 0)
            zenModeExitButton(showsShortcutHint: true)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func zenModeExitButton(showsDismissGlyph: Bool = false, showsShortcutHint: Bool = false) -> some View {
        Button {
            NotificationCenter.default.post(name: .toggleZenMode, object: nil)
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(DesignSystem.IconSize.toolbar)
                Text(L10n("zen.exit"))
                    .font(DesignSystem.Typography.bodyMedium)
                if showsShortcutHint {
                    Text("⌃⌘J")
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
        .help(L10n("zen.exit") + " (⌃⌘J)")
        .accessibilityLabel(L10n("zen.exit"))
    }
    
    @ViewBuilder
    private var editorTerminalContent: some View {
        if layout == .split {
            DraggableSplitView(
                axis: .vertical,
                ratio: $terminalRatio,
                minLeading: 100,
                minTrailing: 100
            ) {
                editorPane
            } trailing: {
                terminalContainer
            }
        } else if layout == .editorOnly {
            editorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            terminalContainer
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func applyZenModeState(_ enabled: Bool) {
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

    private var editorToolbar: some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            Button {
                withAnimation(DesignSystem.Motion.panel) { isFileBrowserVisible.toggle() }
            } label: {
                Image(systemName: "sidebar.left").font(DesignSystem.Typography.label)
            }
            .buttonStyle(.bordered)
            .tint(isFileBrowserVisible ? Color.accentColor : .secondary)
            .help(L10n("Alternar painel de arquivos") + " (⌘B)")
            .accessibilityLabel(L10n("Alternar painel de arquivos"))

            // Theme & Font group
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Picker("", selection: $model.selectedTheme) {
                    ForEach(EditorTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Picker("", selection: $model.editorFontFamily) {
                    Text("SF Mono").tag("SF Mono")
                    Text("Menlo").tag("Menlo")
                    Text("Monaco").tag("Monaco")
                    Text("Courier").tag("Courier")
                    Text("Fira Code").tag("Fira Code")
                    Text("JetBrains Mono").tag("JetBrains Mono")
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))

            // Size & Spacing group
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Stepper(value: $model.editorFontSize, in: 8...32, step: 1) {
                    Text("\(Int(model.editorFontSize))pt")
                        .font(DesignSystem.Typography.monoSmall)
                        .frame(width: 30)
                }

                Divider().frame(height: 14)

                Slider(value: $model.editorLineSpacing, in: 0.0...20.0, step: 0.5)
                    .frame(width: 60)
                Text(String(format: "%.1fpt", model.editorLineSpacing))
                    .font(DesignSystem.Typography.monoLabel)
                    .frame(width: 40)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))

            Button {
                model.isLineWrappingEnabled.toggle()
            } label: {
                Image(systemName: model.isLineWrappingEnabled ? "arrow.turn.down.left" : "arrow.right.to.line")
                    .font(DesignSystem.Typography.label)
            }
            .buttonStyle(.bordered)
            .tint(model.isLineWrappingEnabled ? Color.accentColor : .secondary)
            .help(L10n("Quebra de Linha Automática"))
            .accessibilityLabel(L10n("Quebra de Linha Automática"))

            if isMarkdownFile {
                Button {
                    withAnimation(DesignSystem.Motion.detail) {
                        isMarkdownPreviewVisible.toggle()
                    }
                } label: {
                    Image(systemName: isMarkdownPreviewVisible ? "doc.richtext.fill" : "doc.richtext")
                        .font(DesignSystem.Typography.label)
                }
                .buttonStyle(.bordered)
                .tint(isMarkdownPreviewVisible ? Color.accentColor : .secondary)
                .help(L10n(isMarkdownPreviewVisible ? "editor.markdown.hidePreview" : "editor.markdown.showPreview"))
                .accessibilityLabel(L10n("editor.markdown.preview"))
            }

            EditorSettingsPopoverButton(model: model, showBreadcrumbPath: $showBreadcrumbPath)

            Button {
                model.toggleBlame()
            } label: {
                Image(systemName: "person.text.rectangle")
                    .font(DesignSystem.Typography.label)
            }
            .buttonStyle(.bordered)
            .tint(model.isBlameVisible ? Color.accentColor : .secondary)
            .help(L10n("Git Blame"))
            .accessibilityLabel(L10n("Git Blame"))
            .disabled(model.activeFileID == nil)

            Button {
                if let file = model.selectedCodeFile, let repoURL = model.repositoryURL {
                    let relativePath = file.url.path.replacingOccurrences(of: repoURL.path + "/", with: "")
                    model.loadFileHistory(for: relativePath)
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(DesignSystem.Typography.label)
            }
            .buttonStyle(.bordered)
            .help(L10n("filehistory.title"))
            .accessibilityLabel(L10n("filehistory.title"))
            .disabled(model.activeFileID == nil)

            Button {
                model.formatCurrentFile()
            } label: {
                Image(systemName: "text.alignleft")
                    .font(DesignSystem.Typography.label)
            }
            .buttonStyle(.bordered)
            .help(L10n("format.document") + " (⇧⌥F)")
            .accessibilityLabel(L10n("format.document"))
            .disabled(model.activeFileID == nil || !CodeFormatter.canFormat(fileExtension: model.selectedCodeFile?.url.pathExtension ?? ""))

            Divider().frame(height: 14).padding(.horizontal, 4)

            // Layout toggle: editor / split / terminal
            HStack(spacing: DesignSystem.Spacing.iconGroupedGap) {
                Button {
                    withAnimation(DesignSystem.Motion.detail) { layout = .editorOnly }
                } label: {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(DesignSystem.Typography.bodyMedium)
                        .frame(width: DesignSystem.IconSize.editorToolbarFrame.width,
                               height: DesignSystem.IconSize.editorToolbarFrame.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(layout == .editorOnly ? Color.accentColor : .secondary)
                .help(L10n("Somente editor") + " (⌘J)")
                .accessibilityLabel(L10n("Somente editor"))

                Button {
                    withAnimation(DesignSystem.Motion.detail) { layout = .split }
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                        .font(DesignSystem.Typography.bodyMedium)
                        .frame(width: DesignSystem.IconSize.editorToolbarFrame.width,
                               height: DesignSystem.IconSize.editorToolbarFrame.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(layout == .split ? Color.accentColor : .secondary)
                .help(L10n("Editor e terminal"))
                .accessibilityLabel(L10n("Editor e terminal"))

                Button {
                    withAnimation(DesignSystem.Motion.detail) { layout = .terminalOnly }
                } label: {
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                        .font(DesignSystem.Typography.bodyMedium)
                        .frame(width: DesignSystem.IconSize.editorToolbarFrame.width,
                               height: DesignSystem.IconSize.editorToolbarFrame.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(layout == .terminalOnly ? Color.accentColor : .secondary)
                .help(L10n("Somente terminal") + " (⇧⌘J)")
                .accessibilityLabel(L10n("Somente terminal"))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))

            if showBreadcrumbPath, !breadcrumbItems.isEmpty {
                breadcrumbPathBar
            }

            Spacer()

            if model.hasRepoEditorConfig {
                HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(DesignSystem.Typography.meta)
                    Text(".zion")
                        .font(DesignSystem.Typography.monoMeta)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DesignSystem.Colors.glassSubtle)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                .help(L10n("editor.repoConfig.active"))
                .accessibilityLabel(L10n("editor.repoConfig.active"))
            }

            Button {
                model.createNewFile()
            } label: {
                Image(systemName: "doc.badge.plus")
                    .font(DesignSystem.Typography.label)
            }
            .buttonStyle(.bordered)
            .help(L10n("Novo Arquivo") + " (⌘N)")
            .accessibilityLabel(L10n("Novo Arquivo"))

            if model.activeFileID != nil {
                Button {
                    model.saveCurrentFileAs()
                } label: {
                    Image(systemName: "arrow.down.doc")
                        .font(DesignSystem.Typography.label)
                }
                .buttonStyle(.bordered)
                .help(L10n("Salvar Como...") + " (⇧⌘S)")
                .accessibilityLabel(L10n("Salvar Como..."))

                Button {
                    model.saveCurrentCodeFile()
                } label: {
                    Label(L10n("Salvar"), systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(model.selectedTheme.isLightAppearance ? DesignSystem.Colors.info : Color.accentColor)
                .help(L10n("Salvar") + " (⌘S)")
            }
        }
        .controlSize(.small)
    }

    private var breadcrumbPathBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                ForEach(Array(breadcrumbItems.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    breadcrumbSegmentView(item)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 140, idealWidth: 300, maxWidth: 520)
        .layoutPriority(1)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        .help(L10n("editor.breadcrumb.path"))
        .accessibilityLabel(L10n("editor.breadcrumb.path"))
    }

    @ViewBuilder
    private func breadcrumbSegmentView(_ item: EditorBreadcrumbItem) -> some View {
        if item.isEllipsis {
            Text("...")
                .font(DesignSystem.Typography.monoLabel)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        } else if !item.isFile, let path = item.targetPath {
            BreadcrumbFolderSegmentButton(title: item.title) {
                revealBreadcrumbTarget(path: path, isFile: false)
            }
        } else {
            Text(item.title)
                .font(.system(size: 10, weight: item.isFile ? .semibold : .regular, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(item.isFile ? Color.primary : DesignSystem.Colors.textSecondary)
        }
    }

    private var breadcrumbItems: [EditorBreadcrumbItem] {
        guard let fileURL = model.selectedCodeFile?.url else { return [] }
        let full = fullBreadcrumbItems(for: fileURL)
        guard full.count > 4 else { return full }

        let ellipsis = EditorBreadcrumbItem(
            id: "ellipsis-\(full.count)-\(full.last?.id ?? "")",
            title: "...",
            targetPath: nil,
            isFile: false,
            isEllipsis: true
        )

        return [full[0], full[1], ellipsis, full[full.count - 2], full[full.count - 1]]
    }

    private func fullBreadcrumbItems(for fileURL: URL) -> [EditorBreadcrumbItem] {
        let relativePath = relativePathForBreadcrumb(fileURL: fileURL)
        let segments = relativePath.split(separator: "/").map(String.init)
        guard !segments.isEmpty else { return [] }

        var items: [EditorBreadcrumbItem] = []
        var partial = ""
        for (index, segment) in segments.enumerated() {
            if partial.isEmpty {
                partial = segment
            } else {
                partial += "/\(segment)"
            }
            let targetPath = model.repositoryURL?.appendingPathComponent(partial).path
            let isFile = index == segments.count - 1
            items.append(
                EditorBreadcrumbItem(
                    id: "\(index)-\(partial)",
                    title: segment,
                    targetPath: targetPath,
                    isFile: isFile,
                    isEllipsis: false
                )
            )
        }
        return items
    }

    private func relativePathForBreadcrumb(fileURL: URL) -> String {
        guard let repositoryURL = model.repositoryURL else {
            return fileURL.lastPathComponent
        }

        let repoPath = repositoryURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = repoPath.hasSuffix("/") ? repoPath : repoPath + "/"
        guard filePath.hasPrefix(prefix) else {
            return fileURL.lastPathComponent
        }
        return String(filePath.dropFirst(prefix.count))
    }

    private func revealBreadcrumbTarget(path: String, isFile: Bool) {
        withAnimation(DesignSystem.Motion.panel) {
            isFileBrowserVisible = true
        }

        guard let repositoryURL = model.repositoryURL else { return }

        let repoPath = repositoryURL.standardizedFileURL.path
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard normalizedPath.hasPrefix(repoPath) else { return }

        let relativePath = String(normalizedPath.dropFirst(repoPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return }

        var currentURL = repositoryURL
        let foldersToExpand = isFile ? max(components.count - 1, 0) : components.count
        if foldersToExpand > 0 {
            for index in 0..<foldersToExpand {
                currentURL = currentURL.appendingPathComponent(components[index])
                let folderPath = currentURL.path
                if !model.expandedPaths.contains(folderPath) {
                    model.toggleExpansion(for: folderPath)
                }
            }
        }

        if isFile {
            let item = FileItem(url: URL(fileURLWithPath: normalizedPath), isDirectory: false, children: nil)
            model.selectCodeFile(item)
        }

        requestFileBrowserAutoScroll(targetPath: normalizedPath)
    }

    private func requestFileBrowserAutoScroll(targetPath: String) {
        Task { @MainActor in
            for _ in 0..<24 {
                if model.visibleFlatFiles().contains(where: { $0.id == targetPath }) {
                    fileBrowserScrollTargetID = targetPath
                    fileBrowserScrollRequestID += 1
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
    
    private var fileBrowserPane: some View {
        VStack(spacing: 0) {
            // Sidebar mode bar
            HStack(spacing: 0) {
                sidebarModeButton(mode: .fileTree, icon: "folder.fill", tooltip: L10n("Arquivos"))
                sidebarModeButton(mode: .findInFiles, icon: "magnifyingglass", tooltip: L10n("Buscar nos Arquivos") + " (⇧⌘F)")

                Spacer()

                if sidebarMode == .fileTree {
                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Button { model.showDotfiles.toggle() } label: {
                            Image(systemName: model.showDotfiles ? "eye" : "eye.slash")
                                .frame(width: DesignSystem.IconSize.editorToolbarFrame.width,
                                       height: DesignSystem.IconSize.editorToolbarFrame.height)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).cursorArrow().foregroundStyle(.secondary)
                        .help(L10n("fileBrowser.toggleHidden") + " (⇧⌘H)")
                        .accessibilityLabel(L10n("fileBrowser.toggleHidden"))

                        Button { model.refreshFileTree() } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: DesignSystem.IconSize.editorToolbarFrame.width,
                                       height: DesignSystem.IconSize.editorToolbarFrame.height)
                                .contentShape(Rectangle())
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

            if sidebarMode == .findInFiles {
                FindInFilesView(
                    model: model,
                    query: $findInFilesQuery,
                    includePattern: $findInFilesInclude,
                    excludePattern: $findInFilesExclude,
                    results: $findInFilesResults,
                    isSearching: $isFindInFilesSearching,
                    scopePath: $findInFilesScopePath
                )
            } else {

            // File tree scroll — fills available space
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.repositoryFiles.isEmpty {
                            VStack(spacing: 16) {
                                Text(L10n("Nenhum arquivo encontrado")).font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                                Button {
                                    onOpenFolder?()
                                } label: {
                                    Label(L10n("Selecionar Pasta"), systemImage: "folder.badge.plus")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(DesignSystem.Spacing.sectionGap)
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(model.repositoryFiles) { item in
                                FileTreeNodeView(model: model, item: item, level: 0)
                                    .id(item.id)
                            }
                        }

                    }
                    .padding(.top, DesignSystem.Spacing.standard)
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { model.clearFileSelection() }
                    }
                }
                .focusable()
                .focused($isFileBrowserFocused)
                .focusEffectDisabled()
                .onChange(of: fileBrowserScrollRequestID) { _, _ in
                    guard let target = fileBrowserScrollTargetID else { return }
                    withAnimation(DesignSystem.Motion.snappy) {
                        scrollProxy.scrollTo(target, anchor: .center)
                    }
                }
                .onMoveCommand { direction in
                    let flatFiles = model.visibleFlatFiles()
                    guard !flatFiles.isEmpty else { return }
                    // Sync index with the actual selection when out of sync
                    if let clickedID = model.lastClickedFileID,
                       (selectedBrowserIndex < 0 || selectedBrowserIndex >= flatFiles.count || flatFiles[selectedBrowserIndex].id != clickedID),
                       let idx = flatFiles.firstIndex(where: { $0.id == clickedID }) {
                        selectedBrowserIndex = idx
                    }
                    let isShift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
                    switch direction {
                    case .up:
                        if selectedBrowserIndex > 0 {
                            selectedBrowserIndex -= 1
                        }
                    case .down:
                        if selectedBrowserIndex < flatFiles.count - 1 {
                            selectedBrowserIndex += 1
                        }
                    case .left:
                        if selectedBrowserIndex >= 0 && selectedBrowserIndex < flatFiles.count {
                            let item = flatFiles[selectedBrowserIndex]
                            if item.isDirectory && model.expandedPaths.contains(item.id) {
                                withAnimation(DesignSystem.Motion.snappy) { model.toggleExpansion(for: item.id) }
                            }
                        }
                        return
                    case .right:
                        if selectedBrowserIndex >= 0 && selectedBrowserIndex < flatFiles.count {
                            let item = flatFiles[selectedBrowserIndex]
                            if item.isDirectory && !model.expandedPaths.contains(item.id) {
                                withAnimation(DesignSystem.Motion.snappy) { model.toggleExpansion(for: item.id) }
                            }
                        }
                        return
                    @unknown default: break
                    }
                    if selectedBrowserIndex >= 0 && selectedBrowserIndex < flatFiles.count {
                        let item = flatFiles[selectedBrowserIndex]
                        if isShift {
                            model.extendSelection(to: item)
                        } else {
                            model.plainClickFile(item)
                        }
                        withAnimation { scrollProxy.scrollTo(item.id, anchor: .center) }
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
                model.findInFilesScopeRequest = nil
            }
        }
        .onChange(of: model.repositoryURL) { _, _ in
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

    private var editorPane: some View {
        VStack(spacing: 0) {
            if !model.openedFiles.isEmpty {
                codeTabBar
                    .zIndex(2)

                Divider()
                    .zIndex(2)

                if isSearchVisible {
                    findReplaceBar
                        .transition(DesignSystem.Motion.slideFromTop)
                        .background(model.selectedTheme.colors.background)
                        .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)
                        .zIndex(2)
                }

                Group {
                    if model.isBlameVisible && !model.blameEntries.isEmpty {
                        BlameView(entries: model.blameEntries, fileName: model.selectedCodeFile?.name ?? "", model: model) { commitHash in
                            model.selectCommit(commitHash)
                            model.navigateToGraphRequested = true
                        }
                        .background(model.selectedTheme.colors.background)
                    } else if isMarkdownPreviewActive {
                        DraggableSplitView(
                            axis: .horizontal,
                            ratio: $markdownPreviewRatio,
                            minLeading: 320,
                            minTrailing: 300
                        ) {
                            sourceEditorView
                        } trailing: {
                            markdownPreviewPane
                        }
                    } else {
                        sourceEditorView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .zIndex(0)
            } else {
                emptyEditorView
                    .background(model.selectedTheme.colors.background)
                    .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let fileURLs = urls.filter { !$0.hasDirectoryPath }
            guard !fileURLs.isEmpty else { return false }
            model.openExternalFiles(fileURLs)
            return true
        }
        .background {
            Button("") { model.saveCurrentCodeFile() }
                .keyboardShortcut("s", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)

            // Replace (Cmd+H)
            Button("") { toggleReplace() }
                .keyboardShortcut("h", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)

            // Format Document (Shift+Option+F)
            Button("") { model.formatCurrentFile() }
                .keyboardShortcut("f", modifiers: [.shift, .option])
                .frame(width: 0, height: 0).opacity(0)
        }
    }

    private var isMarkdownFile: Bool {
        let ext = model.selectedCodeFile?.url.pathExtension.lowercased() ?? ""
        return ext == "md" || ext == "markdown"
    }

    private var isMarkdownPreviewActive: Bool {
        isMarkdownFile && isMarkdownPreviewVisible
    }

    private var sourceEditorView: some View {
        SourceCodeEditor(
            text: $model.codeFileContent,
            theme: model.effectiveTheme,
            fontSize: model.effectiveFontSize,
            fontFamily: model.editorFontFamily,
            lineSpacing: model.effectiveLineSpacing,
            isLineWrappingEnabled: model.isLineWrappingEnabled,
            activeFileID: model.activeFileID,
            fileExtension: model.selectedCodeFile?.url.pathExtension ?? "",
            tabSize: model.effectiveTabSize,
            useTabs: model.effectiveUseTabs,
            autoCloseBrackets: model.editorAutoCloseBrackets,
            autoCloseQuotes: model.editorAutoCloseQuotes,
            letterSpacing: model.editorLetterSpacing,
            highlightCurrentLine: model.editorHighlightCurrentLine,
            showRuler: model.effectiveShowRuler,
            rulerColumn: model.effectiveRulerColumn,
            bracketPairHighlight: model.editorBracketPairHighlight,
            showIndentGuides: model.effectiveShowIndentGuides,
            searchQuery: isSearchVisible ? searchQuery : "",
            currentMatchIndex: currentMatchIndex,
            onMatchCountChanged: { count in
                matchCount = count
                if count == 0, isSearchVisible, !searchQuery.isEmpty {
                    // Keep UI count/navigation in sync even if editor callback lags behind rendered highlights.
                    recomputeFindMatches()
                }
            },
            goToLine: goToLineTarget,
            goToLineRequestID: goToLineRequestID,
            currentFilePath: model.selectedCodeFile?.url.path,
            onRequestDefinition: { query in handleDefinitionRequest(query) },
            onRequestReferences: { query in handleReferencesRequest(query) },
            onFindSeedFromMultiSelect: { query in
                seededFindQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            },
            onToggleFindUI: { openSearch(applySeedIfPresent: true) },
            onFindNextShortcut: {
                if isSearchVisible, !searchQuery.isEmpty {
                    navigateToNextMatch()
                } else {
                    showGoToLine = true
                    goToLineNumber = ""
                }
            },
            onFindPreviousShortcut: {
                guard isSearchVisible, !searchQuery.isEmpty else { return }
                navigateToPreviousMatch()
            }
        )
        .help(L10n("help.code.navigation"))
    }

    private var markdownPreviewPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Label(L10n("editor.markdown.preview"), systemImage: "doc.text.image")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(model.effectiveTheme.colors.background)

            Divider()

            MarkdownPreviewView(
                markdownText: model.codeFileContent,
                fileURL: model.selectedCodeFile?.url,
                repositoryURL: model.repositoryURL,
                theme: model.effectiveTheme
            )
        }
        .background(model.effectiveTheme.colors.background)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DesignSystem.Colors.glassBorderDark)
                .frame(width: 1)
        }
    }

    // MARK: - Find/Replace Bar

    private var findReplaceBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                // Toggle replace visibility
                Button {
                    withAnimation(DesignSystem.Motion.detail) { isReplaceVisible.toggle() }
                } label: {
                    Image(systemName: isReplaceVisible ? "chevron.down" : "chevron.right")
                        .font(DesignSystem.Typography.metaBold)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 24)
                        .background(DesignSystem.Colors.glassSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 26)
                .contentShape(Rectangle())
                .help(L10n("editor.replace.placeholder"))

                // Search field
                HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                    Image(systemName: "magnifyingglass")
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                    FindSearchTextField(
                        text: $searchQuery,
                        placeholder: L10n("editor.search.placeholder"),
                        focusRequestID: findSearchFocusRequestID,
                        onEnter: { navigateToNextMatch() },
                        onShiftEnter: { navigateToPreviousMatch() },
                        onCancel: { closeSearch() }
                    )
                    .frame(height: 18)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DesignSystem.Colors.glassSubtle)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                .frame(maxWidth: 280)

                // Match count
                if !searchQuery.isEmpty {
                    Text(matchCount > 0 ? "\(currentMatchIndex + 1)/\(matchCount)" : L10n("editor.search.noResults"))
                        .font(DesignSystem.Typography.monoLabel)
                        .foregroundStyle(.secondary)
                        .frame(width: 50)
                }

                // Nav buttons
                Button { navigateToPreviousMatch() } label: {
                    Image(systemName: "chevron.up").font(DesignSystem.Typography.labelMedium)
                }
                .buttonStyle(.borderless)
                .disabled(matchCount == 0)
                .help(L10n("editor.search.previous") + " (⇧Enter)")
                .accessibilityLabel(L10n("editor.search.previous"))

                Button { navigateToNextMatch() } label: {
                    Image(systemName: "chevron.down").font(DesignSystem.Typography.labelMedium)
                }
                .buttonStyle(.borderless)
                .disabled(matchCount == 0)
                .help(L10n("editor.search.next") + " (Enter)")
                .accessibilityLabel(L10n("editor.search.next"))

                Spacer()

                // Close
                Button { closeSearch() } label: {
                    Image(systemName: "xmark").font(DesignSystem.Typography.labelBold).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .help(L10n("Esc"))
                .accessibilityLabel(L10n("Esc"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if isReplaceVisible {
                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    Spacer().frame(width: 32)

                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Image(systemName: "arrow.2.squarepath")
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.secondary)
                        TextField(L10n("editor.replace.placeholder"), text: $replaceQuery)
                            .textFieldStyle(.plain)
                            .font(DesignSystem.Typography.body)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DesignSystem.Colors.glassSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                    .frame(maxWidth: 280)

                    Button(L10n("editor.replace.one")) { replaceCurrent() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(matchCount == 0)

                    Button(L10n("editor.replace.all")) { replaceAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(matchCount == 0)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            Divider()
        }
    }

    private var goToLineSheet: some View {
        VStack(spacing: 12) {
            Text(L10n("Ir para Linha"))
                .font(DesignSystem.Typography.sheetTitle)
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                TextField(L10n("Numero da linha..."), text: $goToLineNumber)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onSubmit { performGoToLine() }
                Button(L10n("Ir")) { performGoToLine() }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.actionPrimary)
                    .disabled(Int(goToLineNumber) == nil)
            }
        }
        .padding(DesignSystem.Spacing.sectionGap)
    }

    private func performGoToLine() {
        guard let line = Int(goToLineNumber), line > 0 else { return }
        goToLineTarget = line
        goToLineRequestID += 1
        showGoToLine = false
    }

    private func handleDefinitionRequest(_ query: EditorSymbolQuery) {
        Task {
            let definitions = await model.findEditorDefinitions(for: query)
            await MainActor.run {
                guard !definitions.isEmpty else {
                    model.statusMessage = L10n("editor.navigation.definition.notFound", query.symbol)
                    return
                }

                if definitions.count == 1, let target = definitions.first {
                    model.openEditorLocation(target)
                    model.statusMessage = L10n("editor.navigation.definition.opened", query.symbol)
                    return
                }

                symbolResultsMode = .definitions
                symbolResultsQuery = query.symbol
                symbolResults = definitions
                isSymbolResultsVisible = true
            }
        }
    }

    private func handleReferencesRequest(_ query: EditorSymbolQuery) {
        Task {
            let references = await model.findEditorReferences(for: query)
            await MainActor.run {
                guard !references.isEmpty else {
                    model.statusMessage = L10n("editor.navigation.references.notFound", query.symbol)
                    return
                }

                symbolResultsMode = .references
                symbolResultsQuery = query.symbol
                symbolResults = references
                isSymbolResultsVisible = true
                model.statusMessage = L10n("editor.navigation.references.found", "\(references.count)", query.symbol)
            }
        }
    }

    private func sidebarModeButton(mode: SidebarMode, icon: String, tooltip: String) -> some View {
        Button {
            withAnimation(DesignSystem.Motion.detail) { sidebarMode = mode }
        } label: {
            Image(systemName: icon)
                .font(DesignSystem.Typography.bodySmall)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .foregroundStyle(sidebarMode == mode ? .primary : .secondary)
                .background(sidebarMode == mode ? DesignSystem.Colors.selectionBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    /// Routes Cmd+F / Ctrl+F to the correct pane based on current focus.
    private func routeFindShortcut() {
        if layout == .terminalOnly {
            toggleTerminalSearch()
        } else if layout == .editorOnly {
            toggleSearch()
        } else {
            // Split: if terminal search is already visible, keep toggling it
            // (the search TextField has focus, not TerminalView itself)
            if isTerminalSearchVisible || isTerminalFocused() {
                toggleTerminalSearch()
            } else {
                toggleSearch()
            }
        }
    }

    /// Walks the responder chain to detect if a SwiftTerm TerminalView has focus.
    private func isTerminalFocused() -> Bool {
        guard let window = NSApp.keyWindow,
              let resp = window.firstResponder as? NSView else { return false }
        var current: NSView? = resp
        while let v = current {
            if String(describing: type(of: v)).contains("TerminalView") { return true }
            current = v.superview
        }
        return false
    }

    private func openSearch(applySeedIfPresent: Bool) {
        withAnimation(DesignSystem.Motion.detail) {
            isSearchVisible = true
        }

        if applySeedIfPresent, !seededFindQuery.isEmpty, searchQuery != seededFindQuery {
            searchQuery = seededFindQuery
            currentMatchIndex = 0
        }

        recomputeFindMatches()
        findSearchFocusRequestID += 1
    }

    private func toggleSearch() {
        if isSearchVisible {
            withAnimation(DesignSystem.Motion.detail) {
                closeSearch()
            }
        } else {
            openSearch(applySeedIfPresent: true)
        }
    }

    private func toggleReplace() {
        withAnimation(DesignSystem.Motion.detail) {
            if !isSearchVisible { isSearchVisible = true }
            isReplaceVisible.toggle()
        }
    }

    private func closeSearch() {
        isSearchVisible = false
        isReplaceVisible = false
        searchQuery = ""
        replaceQuery = ""
        matchCount = 0
        currentMatchIndex = 0
    }

    private func navigateToNextMatch() {
        if matchCount == 0 {
            recomputeFindMatches()
        }
        guard matchCount > 0 else { return }
        if currentMatchIndex < 0 || currentMatchIndex >= matchCount {
            currentMatchIndex = 0
        }
        currentMatchIndex = (currentMatchIndex + 1) % matchCount
    }

    private func navigateToPreviousMatch() {
        if matchCount == 0 {
            recomputeFindMatches()
        }
        guard matchCount > 0 else { return }
        if currentMatchIndex < 0 || currentMatchIndex >= matchCount {
            currentMatchIndex = 0
        }
        currentMatchIndex = (currentMatchIndex - 1 + matchCount) % matchCount
    }

    private func recomputeFindMatches() {
        guard isSearchVisible, !searchQuery.isEmpty else {
            matchCount = 0
            currentMatchIndex = 0
            return
        }
        let escaped = NSRegularExpression.escapedPattern(for: searchQuery)
        guard let regex = try? NSRegularExpression(pattern: escaped, options: .caseInsensitive) else {
            matchCount = 0
            currentMatchIndex = 0
            return
        }
        let nsString = model.codeFileContent as NSString
        let matches = regex.matches(in: model.codeFileContent, options: [], range: NSRange(location: 0, length: nsString.length))
        matchCount = matches.count
        if matchCount == 0 {
            currentMatchIndex = 0
        } else if currentMatchIndex >= matchCount {
            currentMatchIndex = matchCount - 1
        }
    }

    private func replaceCurrent() {
        guard matchCount > 0, !searchQuery.isEmpty else { return }
        let escaped = NSRegularExpression.escapedPattern(for: searchQuery)
        guard let regex = try? NSRegularExpression(pattern: escaped, options: .caseInsensitive) else { return }
        let nsString = model.codeFileContent as NSString
        let matches = regex.matches(in: model.codeFileContent, options: [], range: NSRange(location: 0, length: nsString.length))
        guard currentMatchIndex < matches.count else { return }

        let range = matches[currentMatchIndex].range
        guard let swiftRange = Range(range, in: model.codeFileContent) else { return }
        model.codeFileContent.replaceSubrange(swiftRange, with: replaceQuery)

        // Recalculate after replacement
        if currentMatchIndex >= matchCount - 1 {
            currentMatchIndex = max(0, matchCount - 2)
        }
    }

    private func replaceAll() {
        guard !searchQuery.isEmpty else { return }
        let escaped = NSRegularExpression.escapedPattern(for: searchQuery)
        guard let regex = try? NSRegularExpression(pattern: escaped, options: .caseInsensitive) else { return }
        let nsString = model.codeFileContent as NSString
        model.codeFileContent = regex.stringByReplacingMatches(in: model.codeFileContent, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: NSRegularExpression.escapedTemplate(for: replaceQuery))
        currentMatchIndex = 0
    }

    // MARK: - Terminal Search

    private var terminalSearchBar: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Image(systemName: "magnifyingglass")
                .font(DesignSystem.IconSize.inline)
                .foregroundStyle(.secondary)

            TextField(L10n("Buscar no terminal..."), text: $terminalSearchQuery)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.monoBody)
                .focused($isTerminalSearchFocused)
                .onSubmit { terminalFindNext() }

            if !terminalSearchQuery.isEmpty {
                SearchNavButton(icon: "chevron.up", tooltip: L10n("Resultado anterior"), action: terminalFindPrevious)
                SearchNavButton(icon: "chevron.down", tooltip: L10n("Proximo resultado"), action: terminalFindNext)
            }

            SearchNavButton(icon: "xmark", tooltip: L10n("Fechar busca"), isSecondary: true, action: closeTerminalSearch)
        }
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, 6)
        .background(model.selectedTheme.terminalPalette.backgroundSwiftUI.opacity(0.9))
    }

    private func toggleTerminalSearch() {
        withAnimation(DesignSystem.Motion.detail) {
            isTerminalSearchVisible.toggle()
            if isTerminalSearchVisible {
                isTerminalSearchFocused = true
            } else {
                terminalSearchQuery = ""
                isTerminalSearchFocused = false
                model.terminalClearSearch()
            }
        }
        if !isTerminalSearchVisible {
            model.focusActiveTerminal()
        }
    }

    private func closeTerminalSearch() {
        guard isTerminalSearchVisible else { return }
        withAnimation(DesignSystem.Motion.detail) {
            isTerminalSearchVisible = false
            terminalSearchQuery = ""
            isTerminalSearchFocused = false
            model.terminalClearSearch()
        }
    }

    private func terminalFindNext() {
        guard !terminalSearchQuery.isEmpty else { return }
        model.terminalFindNext(terminalSearchQuery)
    }

    private func terminalFindPrevious() {
        guard !terminalSearchQuery.isEmpty else { return }
        model.terminalFindPrevious(terminalSearchQuery)
    }

    private var codeTabBar: some View {
        let accentColor = model.selectedTheme.isLightAppearance ? DesignSystem.Colors.info : Color.accentColor
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(model.openedFiles) { file in
                    CodeTab(
                        model: model,
                        file: file,
                        isActive: file.id == model.activeFileID,
                        accentColor: accentColor,
                        onActivate: { model.selectCodeFile(file) },
                        onClose: { model.closeFile(id: file.id) }
                    )
                }
            }
        }
        .padding(.leading, 36)
        .frame(height: 38)
        .background(model.selectedTheme.colors.background)
        .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)
    }
    
    private var emptyEditorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil.and.outline").font(.system(size: 40)).foregroundStyle(.secondary)
            Text(L10n("Selecione um arquivo")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var terminalContainer: some View {
        VStack(spacing: 0) {
            terminalTabBar

            if isTerminalSearchVisible {
                terminalSearchBar
                    .transition(DesignSystem.Motion.slideFromTop)
            }

            Divider()

            ZStack {
                if model.terminalTabs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "terminal").font(.title).foregroundStyle(.secondary)
                        Text(L10n("Nenhum terminal aberto")).font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(model.terminalTabs) { tab in
                        TerminalPaneView(
                            node: tab,
                            theme: model.selectedTheme,
                            fontSize: model.terminalFontSize,
                            fontFamily: model.terminalFontFamily,
                            focusedSessionID: model.focusedSessionID,
                            model: model,
                            transparentBackground: isTerminalTransparent
                        )
                        .opacity(tab.id == model.activeTabID ? 1 : 0)
                        .allowsHitTesting(tab.id == model.activeTabID)
                    }
                }
            }
            .padding(.bottom, DesignSystem.Spacing.compact)
            .dropDestination(for: String.self) { items, _ in
                guard let text = items.first, !text.isEmpty else { return false }
                model.sendTextToActiveTerminal(text)
                model.focusActiveTerminal()
                return true
            }
            .dropDestination(for: URL.self) { urls, _ in
                let paths = urls.filter { $0.isFileURL }.map { TerminalShellEscaping.quotePath($0.path) }
                guard !paths.isEmpty else { return false }
                model.sendTextToActiveTerminal(paths.joined(separator: " "))
                model.focusActiveTerminal()
                return true
            }
        }
        .padding(.top, DesignSystem.Spacing.cardPadding)
        .background {
            if isTerminalTransparent {
                ZStack {
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    model.selectedTheme.terminalPalette.backgroundSwiftUI.opacity(terminalOpacity)
                }
            } else {
                model.selectedTheme.terminalPalette.backgroundSwiftUI
            }
        }
        .onAppear {
            model.createDefaultTerminalSession(repositoryURL: model.repositoryURL, branchName: model.currentBranch.isEmpty ? "zsh" : model.currentBranch)
        }
        .background {
            // New tab
            Button("") {
                let url = model.repositoryURL ?? URL(fileURLWithPath: NSHomeDirectory())
                model.createTerminalSession(workingDirectory: url, label: model.currentBranch.isEmpty ? "zsh" : model.currentBranch)
            }
            .keyboardShortcut("t", modifiers: .command)
            .frame(width: 0, height: 0).opacity(0)

            // Vertical split
            Button("") { model.splitFocusedTerminal(direction: .vertical) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .frame(width: 0, height: 0).opacity(0)

            // Horizontal split
            Button("") { model.splitFocusedTerminal(direction: .horizontal) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .frame(width: 0, height: 0).opacity(0)

            // Terminal zoom in (Ctrl+=)
            Button("") {
                model.terminalFontSize = min(32, model.terminalFontSize + 1)
            }
            .keyboardShortcut("=", modifiers: .control)
            .frame(width: 0, height: 0).opacity(0)

            // Terminal zoom out (Ctrl+-)
            Button("") {
                model.terminalFontSize = max(8, model.terminalFontSize - 1)
            }
            .keyboardShortcut("-", modifiers: .control)
            .frame(width: 0, height: 0).opacity(0)

            // Close focused split pane (Cmd+Shift+W)
            Button("") { model.closeFocusedTerminalPane() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .frame(width: 0, height: 0).opacity(0)

            // Git Blame (Cmd+Shift+B)
            Button("") { model.toggleBlame() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .frame(width: 0, height: 0).opacity(0)

            // Close terminal search (Escape)
            Button("") { closeTerminalSearch() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0).opacity(0)

            // Voice input toggle (⌘⌥X)
            Button("") { voiceToggleRequestID += 1 }
                .keyboardShortcut("x", modifiers: [.command, .option])
                .frame(width: 0, height: 0).opacity(0)
        }
    }

    private var terminalTabBar: some View {
        let accentColor = model.selectedTheme.isLightAppearance ? DesignSystem.Colors.info : Color.accentColor
        return HStack(alignment: .center, spacing: 0) {
            Image(systemName: "terminal.fill")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(model.selectedTheme.terminalPalette.accentSwiftUI.opacity(0.7))
                .padding(.leading, 10)
                .padding(.trailing, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.iconGroupedGap) {
                    ForEach(model.terminalTabs) { tab in
                        TerminalTabChip(
                            tab: tab,
                            isActive: tab.id == model.activeTabID,
                            accentColor: accentColor,
                            onActivate: {
                                model.activeTabID = tab.id
                                model.focusedSessionID = tab.allSessions().first?.id
                            },
                            onClose: { model.closeTab(tab) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer()

            // Split buttons grouped
            HStack(spacing: DesignSystem.Spacing.iconGroupedGap) {
                Button {
                    model.splitFocusedTerminal(direction: .vertical)
                } label: {
                    Image(systemName: "square.split.2x1")
                        .font(DesignSystem.Typography.bodyMedium)
                        .frame(width: DesignSystem.IconSize.editorToolbarFrame.width,
                               height: DesignSystem.IconSize.editorToolbarFrame.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(L10n("Dividir verticalmente") + " (⇧⌘D)")
                .accessibilityLabel(L10n("Dividir verticalmente"))

                Button {
                    model.splitFocusedTerminal(direction: .horizontal)
                } label: {
                    Image(systemName: "square.split.1x2")
                        .font(DesignSystem.Typography.bodyMedium)
                        .frame(width: DesignSystem.IconSize.editorToolbarFrame.width,
                               height: DesignSystem.IconSize.editorToolbarFrame.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(L10n("Dividir horizontalmente") + " (⇧⌘E)")
                .accessibilityLabel(L10n("Dividir horizontalmente"))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))

            // Font popover
            TerminalFontPopoverButton(model: model, accentColor: accentColor)
                .padding(.horizontal, 4)

            // Quick worktree
            TerminalToolbarButton(
                icon: "arrow.triangle.branch",
                color: accentColor,
                tooltip: L10n("Criar worktree rapido"),
                disabled: model.repositoryURL == nil
            ) { model.quickCreateWorktree() }

            // New tab
            TerminalToolbarButton(
                icon: "plus",
                color: accentColor,
                tooltip: L10n("Novo terminal") + " (⌘T)"
            ) {
                let url = model.repositoryURL ?? URL(fileURLWithPath: NSHomeDirectory())
                let label = model.currentBranch.isEmpty ? "zsh" : model.currentBranch
                model.createTerminalSession(workingDirectory: url, label: label)
            }
            .padding(.trailing, DesignSystem.Spacing.toolbarTrailing)

            VoiceInputButton(
                model: model,
                accentColor: accentColor,
                isTerminalSearchVisible: isTerminalSearchVisible,
                voiceToggleRequestID: voiceToggleRequestID
            )
            .padding(.trailing, DesignSystem.Spacing.toolbarTrailing)

            ClipboardPopoverButton(model: model, accentColor: accentColor)
                .padding(.trailing, DesignSystem.Spacing.toolbarTrailing)

            if isZenMode {
                Spacer()
                    .frame(width: 12)

                zenModeExitButton(showsDismissGlyph: true)
                .padding(.trailing, 16)
            }
        }
        .padding(.vertical, 4)
    }
}

