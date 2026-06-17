import AppKit
import SwiftUI

enum EditorTerminalLayout: String, CaseIterable {
    case editorOnly
    case split
    case terminalOnly
}

enum EditorSymbolResultsMode {
    case definitions
    case references
}

enum FileBrowserNavigationDirection {
    case up
    case down
    case left
    case right
}

struct CodeScreen: View {
    @Bindable var model: RepositoryViewModel
    var onOpenFolder: (() -> Void)? = nil
    var isZenMode: Bool = false
    var zenTerminalFullscreen: Bool = false
    var isVisible: Bool = true
    @Environment(\.zionModeEnabled) private var zionModeEnabled
    @EnvironmentObject var shortcutRegistry: ShortcutRegistry
    @AppStorage(UserDefaultsKeys.Editor.showBreadcrumb) var showBreadcrumbPath: Bool = true
    @State var isQuickOpenVisible: Bool = false
    @State var isFileBrowserVisible: Bool = true
    @State var fileBrowserRatio: CGFloat = 0.25
    @State var terminalRatio: CGFloat = 0.6
    @State var layout: EditorTerminalLayout = .split
    @State var previousLayoutBeforeZen: EditorTerminalLayout?
    @State var isSearchVisible: Bool = false
    @State var isReplaceVisible: Bool = false
    @State var searchQuery: String = ""
    @State var seededFindQuery: String = ""
    @State var replaceQuery: String = ""
    @State var matchCount: Int = 0
    @State var currentMatchIndex: Int = 0
    @State var searchScrollRequestID: Int = 0
    @State var findSearchFocusRequestID: Int = 0
    @State var isMatchCase: Bool = false
    @State var isRegexSearch: Bool = false
    @State var isWholeWord: Bool = false
    @State var fileBrowserFilterText: String = ""
    @State var isFileBrowserFilterVisible: Bool = false
    @FocusState var isFileBrowserFilterFocused: Bool
    @State var cachedFilteredFiles: [FileItem]?
    @State var filterDebounceTask: DispatchWorkItem?
    @StateObject var fileBrowserResponderReference = FileBrowserResponderReference()
    @State var selectedBrowserIndex: Int = -1
    @State var fileBrowserScrollTargetID: String?
    @State var fileBrowserScrollRequestID: Int = 0
    @State var showGoToLine: Bool = false
    @State var goToLineNumber: String = ""
    @State var goToLineTarget: Int = 0
    @State var goToLineRequestID: Int = 0
    @State var isTerminalSearchVisible: Bool = false
    @State var terminalSearchQuery: String = ""
    @State var voiceToggleRequestID: Int = 0
    @State var speechService = SpeechRecognitionService()
    @State var markdownPreviewRatio: CGFloat = 0.5
    @State var markdownPreviewVerticalRatio: CGFloat = 0.58
    @State var isMarkdownPreviewVisible: Bool = false
    @State var isMarkdownFullscreen: Bool = false
    @State var isMarkdownReaderSidebarVisible: Bool = false
    @State var markdownReaderSidebarSearch: String = ""
    @FocusState var isTerminalSearchFocused: Bool
    @State var isSymbolResultsVisible: Bool = false
    @State var symbolResultsMode: EditorSymbolResultsMode = .definitions
    @State var symbolResultsQuery: String = ""
    @State var symbolResults: [EditorSymbolLocation] = []
    @State var contentWidth: CGFloat = DesignSystem.Layout.windowMinWidth
    @State var didAutoCollapseFileBrowserForCompactWidth = false

    // Find in Files
    enum SidebarMode { case fileTree, findInFiles }
    @State var sidebarMode: SidebarMode = .fileTree
    @State var findInFilesQuery: String = ""
    @State var findInFilesInclude: String = ""
    @State var findInFilesExclude: String = ""
    @State var findInFilesResults: [FindInFilesFileResult] = []
    @State var isFindInFilesSearching: Bool = false
    @State var findInFilesScopePath: String? = nil
    @State var findInFilesFocusRequestID: Int = 0

    @AppStorage(UserDefaultsKeys.Terminal.opacity) var terminalOpacity: Double = 0.92
    var layoutProfile: CodeScreenLayoutProfile {
        CodeScreenLayoutProfile(width: contentWidth)
    }

    /// Ghostty-style terminal transparency: automatically enabled in Zen Mode
    var isTerminalTransparent: Bool {
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

                StableFileBrowserSplit(
                    isVisible: isFileBrowserVisible && !isZenMode,
                    ratio: $fileBrowserRatio,
                    sidebar: { fileBrowserPane },
                    content: { editorTerminalContent }
                )
                .animation(DesignSystem.Motion.panel, value: isFileBrowserVisible)
            }

            if model.isRepositorySwitchRefreshingInBackground {
                ZionLoadingOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius))
                    .allowsHitTesting(false)
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
                .applyShortcutBinding(shortcutRegistry.binding(for: .quickOpen))
                .frame(width: 0, height: 0).opacity(0)

            Button("") {
                if isZenMode {
                    NotificationCenter.default.post(name: .toggleZenMode, object: nil)
                    return
                }
                withAnimation(DesignSystem.Motion.panel) { isFileBrowserVisible.toggle() }
            }
                .applyShortcutBinding(shortcutRegistry.binding(for: .toggleSidebar))
                .frame(width: 0, height: 0).opacity(0)

            Button("") {
                if isZenMode {
                    NotificationCenter.default.post(name: .toggleZenMode, object: nil)
                    return
                }
                withAnimation(DesignSystem.Motion.detail) {
                    layout = layout == .editorOnly ? .split : .editorOnly
                }
            }
            .applyShortcutBinding(shortcutRegistry.binding(for: .toggleTerminal))
            .frame(width: 0, height: 0).opacity(0)

            Button("") {
                if isZenMode {
                    NotificationCenter.default.post(name: .toggleZenMode, object: nil)
                    return
                }
                withAnimation(DesignSystem.Motion.detail) {
                    layout = layout == .terminalOnly ? .split : .terminalOnly
                }
            }
            .applyShortcutBinding(shortcutRegistry.binding(for: .maximizeTerminal))
            .frame(width: 0, height: 0).opacity(0)

            Button("") { model.createNewFile() }
                .applyShortcutBinding(shortcutRegistry.binding(for: .newFile))
                .frame(width: 0, height: 0).opacity(0)

            Button("") { model.saveCurrentFileAs() }
                .applyShortcutBinding(shortcutRegistry.binding(for: .saveAs))
                .frame(width: 0, height: 0).opacity(0)

            Button("") {
                if isSearchVisible, !searchQuery.isEmpty {
                    navigateToNextMatch()
                } else {
                    showGoToLine = true
                    goToLineNumber = ""
                }
            }
            .applyShortcutBinding(shortcutRegistry.binding(for: .goToLine))
            .frame(width: 0, height: 0).opacity(0)

            Button("") {
                guard isSearchVisible, !searchQuery.isEmpty else { return }
                navigateToPreviousMatch()
            }
            .applyShortcutBinding(shortcutRegistry.binding(for: .findPrevious))
            .frame(width: 0, height: 0).opacity(0)

            Button("") { model.showDotfiles.toggle() }
                .applyShortcutBinding(shortcutRegistry.binding(for: .toggleDotfiles))
                .frame(width: 0, height: 0).opacity(0)

            Button("") {
                if isZenMode {
                    NotificationCenter.default.post(name: .toggleZenMode, object: nil)
                    return
                }
                if sidebarMode == .findInFiles && isFileBrowserVisible {
                    closeFindInFilesPanel()
                } else {
                    sidebarMode = .findInFiles
                    if !isFileBrowserVisible {
                        withAnimation(DesignSystem.Motion.panel) { isFileBrowserVisible = true }
                    }
                    findInFilesFocusRequestID += 1
                }
            }
            .applyShortcutBinding(shortcutRegistry.binding(for: .findInFiles))
            .frame(width: 0, height: 0).opacity(0)

            Button("") { routeFindShortcut() }
                .applyShortcutBinding(shortcutRegistry.binding(for: .find))
                .frame(width: 0, height: 0).opacity(0)

            Button("") { routeFindShortcut() }
                .applyShortcutBinding(shortcutRegistry.binding(for: .findAlias))
                .frame(width: 0, height: 0).opacity(0)

            Button("") { handleEscapeShortcut() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0).opacity(0)
        }
        .onChange(of: model.activeFileID) { _, newActiveID in
            let newIsMarkdown = isNewFileMarkdown(newActiveID)
            let keepPreview = isMarkdownPreviewVisible && newIsMarkdown
            if !keepPreview {
                isMarkdownPreviewVisible = false
                isMarkdownFullscreen = false
            }
            if !isTextEditorActive {
                closeSearch()
            }
            if let newActiveID, isFileBrowserVisible, sidebarMode == .fileTree {
                model.revealFileInBrowser(newActiveID)
            }
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
        .onChange(of: model.lastClickedFileID) { _, fileID in
            guard fileID != nil, isFileBrowserVisible, sidebarMode == .fileTree else { return }
            focusFileBrowserResponder()
        }
        .onAppear {
            applyZenModeState(zenTerminalFullscreen)
            applyResponsiveCodeLayout(for: contentWidth)
        }
        .onChange(of: zenTerminalFullscreen) { _, enabled in
            applyZenModeState(enabled)
        }
        .background(contentWidthReader)
        .onReceive(NotificationCenter.default.publisher(for: .formatDocument)) { _ in
            model.formatCurrentFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zionFind)) { _ in
            routeFindShortcut()
        }
    }

    private var editorTerminalContent: some View {
        StableEditorTerminalSplit(
            layout: layout,
            terminalRatio: $terminalRatio,
            editor: { editorPane },
            terminal: { terminalContainer }
        )
        .animation(DesignSystem.Motion.detail, value: layout)
    }

    var editorPane: some View {
        ZStack {
        VStack(spacing: 0) {
            if !model.openedFiles.isEmpty {
                codeTabBar
                    .zIndex(2)

                Divider()
                    .zIndex(2)

                if isSearchVisible && isTextEditorActive {
                    findReplaceBar
                        .transition(DesignSystem.Motion.slideFromTop)
                        .background(model.selectedTheme.colors.background)
                        .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)
                        .zIndex(2)
                }

                if isMarkdownFile && !isMarkdownPreviewVisible {
                    markdownBanner
                        .background(model.selectedTheme.colors.background)
                        .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)
                        .zIndex(1)
                }

                Group {
                    if model.isBlameVisible && !model.blameEntries.isEmpty {
                        BlameView(entries: model.blameEntries, fileName: model.selectedCodeFile?.name ?? "", model: model) { commitHash in
                            model.selectCommit(commitHash)
                            model.navigateToGraphRequested = true
                        }
                        .background(model.selectedTheme.colors.background)
                    } else if isImagePreviewActive {
                        ImagePreviewView(
                            fileURL: model.selectedCodeFile?.url,
                            theme: model.effectiveTheme
                        )
                    } else if isMarkdownPreviewActive {
                        DraggableSplitView(
                            axis: layoutProfile.prefersVerticalMarkdownPreview ? .vertical : .horizontal,
                            ratio: layoutProfile.prefersVerticalMarkdownPreview ? $markdownPreviewVerticalRatio : $markdownPreviewRatio,
                            minLeading: layoutProfile.prefersVerticalMarkdownPreview
                                ? DesignSystem.Layout.markdownPreviewVerticalMinLeading
                                : DesignSystem.Layout.markdownPreviewMinLeading,
                            minTrailing: layoutProfile.prefersVerticalMarkdownPreview
                                ? DesignSystem.Layout.markdownPreviewVerticalMinTrailing
                                : DesignSystem.Layout.markdownPreviewMinTrailing
                        ) {
                            sourceEditorView
                        } trailing: {
                            markdownPreviewPane
                        }
                    } else if isTextEditorActive {
                        sourceEditorView
                    } else {
                        unsupportedFileView
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
                .applyShortcutBinding(shortcutRegistry.binding(for: .save))
                .frame(width: 0, height: 0).opacity(0)

            Button("") { toggleReplace() }
                .applyShortcutBinding(shortcutRegistry.binding(for: .findReplace))
                .frame(width: 0, height: 0).opacity(0)

            Button("") { model.formatCurrentFile() }
                .applyShortcutBinding(shortcutRegistry.binding(for: .formatDocument))
                .frame(width: 0, height: 0).opacity(0)

            Button("") {
                guard isMarkdownFile else { return }
                withAnimation(DesignSystem.Motion.detail) {
                    if isMarkdownFullscreen {
                        isMarkdownFullscreen = false
                    } else {
                        isMarkdownPreviewVisible = true
                        isMarkdownFullscreen = true
                    }
                }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .frame(width: 0, height: 0).opacity(0)
        }

        if isMarkdownFullscreen {
            markdownFullscreenOverlay
                .transition(DesignSystem.Motion.fadeScale)
        }
        } // ZStack
    }

    private var markdownFullscreenOverlay: some View {
        ZStack {
            model.effectiveTheme.colors.background
                .ignoresSafeArea()

            Button("") {
                withAnimation(DesignSystem.Motion.detail) {
                    isMarkdownFullscreen = false
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)

            Button("") {
                withAnimation(DesignSystem.Motion.detail) {
                    isMarkdownReaderSidebarVisible.toggle()
                }
            }
            .keyboardShortcut("o", modifiers: [.command])
            .frame(width: 0, height: 0)
            .opacity(0)

            HStack(spacing: 0) {
                if isMarkdownReaderSidebarVisible {
                    MarkdownReaderSidebar(
                        model: model,
                        searchText: $markdownReaderSidebarSearch
                    ) { file in
                        model.selectCodeFile(file)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                        Button {
                            withAnimation(DesignSystem.Motion.detail) {
                                isMarkdownReaderSidebarVisible.toggle()
                            }
                        } label: {
                            Image(systemName: isMarkdownReaderSidebarVisible ? "sidebar.leading" : "list.bullet.indent")
                                .font(DesignSystem.Typography.body)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L10n("editor.markdown.reader.toggleSidebar"))

                        Image(systemName: "doc.text.image")
                            .foregroundStyle(.secondary)
                        Text(model.selectedCodeFile?.name ?? L10n("editor.markdown.preview"))
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundStyle(.secondary)
                        Text(L10n("editor.markdown.readerMode"))
                            .font(DesignSystem.Typography.metaSemibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.accent.opacity(0.15))
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .clipShape(Capsule())
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(DesignSystem.Motion.detail) {
                                isMarkdownFullscreen = false
                                isMarkdownPreviewVisible = false
                            }
                        } label: {
                            Label(L10n("editor.markdown.edit"), systemImage: "pencil")
                                .font(DesignSystem.Typography.bodySmall)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(L10n("editor.markdown.edit.help"))
                        Button {
                            withAnimation(DesignSystem.Motion.detail) {
                                isMarkdownFullscreen = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(DesignSystem.Typography.body)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L10n("editor.markdown.exitFullscreen"))
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(model.effectiveTheme.colors.background)
            }
        }
    }

    var isMarkdownFile: Bool {
        model.selectedEditorContentKind == .markdown
    }

    private func isNewFileMarkdown(_ fileID: FileItem.ID?) -> Bool {
        guard let id = fileID,
              let file = model.openedFiles.first(where: { $0.id == id }) else { return false }
        return model.editorContentKind(for: file.url) == .markdown
    }

    var isTextEditorActive: Bool {
        model.selectedEditorContentKind == .text || model.selectedEditorContentKind == .markdown
    }

    var isImagePreviewActive: Bool {
        model.selectedEditorContentKind == .image
    }

    private var isMarkdownPreviewActive: Bool {
        isMarkdownFile && isMarkdownPreviewVisible
    }

    var sourceEditorView: some View {
        SourceCodeEditor(
            text: $model.codeFileContent,
            theme: model.effectiveTheme,
            fontSize: model.effectiveFontSize,
            fontFamily: model.editorFontFamily,
            lineSpacing: model.effectiveLineSpacing,
            isLineWrappingEnabled: model.isLineWrappingEnabled,
            activeFileID: model.activeFileID,
            fileExtension: model.selectedCodeFile.map { model.editorFileExtension(for: $0.url) } ?? "",
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
            renderWhitespace: model.editorRenderWhitespace,
            topPadding: model.editorTopPadding,
            scrollPastEnd: model.editorScrollPastEnd,
            searchMatchCase: isMatchCase,
            searchRegex: isRegexSearch,
            searchWholeWord: isWholeWord,
            searchQuery: isSearchVisible ? searchQuery : "",
            currentMatchIndex: currentMatchIndex,
            searchScrollRequestID: searchScrollRequestID,
            onMatchCountChanged: { count in
                matchCount = count
                if count == 0, isSearchVisible, !searchQuery.isEmpty {
                    // Keep UI count/navigation in sync even if editor callback lags behind rendered highlights.
                    recomputeFindMatches()
                }
            },
            goToLine: goToLineTarget,
            goToLineRequestID: goToLineRequestID,
            focusRequestID: model.editorFocusRequestID,
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
            },
            isEditorVisible: !zenTerminalFullscreen && layout != .terminalOnly,
            onCaptureBufferState: { fileID, range, scrollY in
                model.editorBufferStates[fileID] = RepositoryViewModel.EditorBufferState(
                    selectedRange: range,
                    scrollY: scrollY
                )
            },
            onRestoreBufferState: { fileID in
                guard let state = model.editorBufferStates[fileID] else { return nil }
                return (state.selectedRange, state.scrollY)
            },
            diffMarkers: model.editorDiffMarkers,
            diffOriginalByLine: model.editorDiffOriginalByLine,
            diffMarkersVersion: model.editorDiffMarkersVersion
        )
        .help(L10n("help.code.navigation"))
    }

    private var markdownBanner: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Image(systemName: "doc.text")
                .font(DesignSystem.Typography.bodySmall)
                .foregroundStyle(.tertiary)

            Text("Markdown")
                .font(DesignSystem.Typography.bodySmall)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                withAnimation(DesignSystem.Motion.detail) {
                    isMarkdownPreviewVisible = true
                }
            } label: {
                Label(L10n("editor.markdown.preview"), systemImage: "eye")
                    .font(DesignSystem.Typography.bodySmall)
                    .frame(height: DesignSystem.Spacing.standard * 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                withAnimation(DesignSystem.Motion.detail) {
                    isMarkdownPreviewVisible = true
                    isMarkdownFullscreen = true
                }
            } label: {
                Label(L10n("editor.markdown.fullscreen"), systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(DesignSystem.Typography.bodySmall)
                    .frame(height: DesignSystem.Spacing.standard * 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, DesignSystem.Spacing.iconTextGap)
    }

    private var markdownPreviewPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Button {
                    withAnimation(DesignSystem.Motion.detail) {
                        isMarkdownPreviewVisible = false
                    }
                } label: {
                    Label(L10n("editor.markdown.preview"), systemImage: "eye.fill")
                        .font(DesignSystem.Typography.bodyMedium)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L10n("editor.markdown.hidePreview"))
                Spacer(minLength: 0)
                Button {
                    withAnimation(DesignSystem.Motion.detail) {
                        isMarkdownFullscreen = true
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n("editor.markdown.fullscreen"))
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

    var codeTabBar: some View {
        let accentColor = model.selectedTheme.isLightAppearance ? DesignSystem.Colors.info : Color.accentColor
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
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
                        .id(file.id)
                    }
                }
            }
            .onAppear {
                guard let activeID = model.activeFileID else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(activeID, anchor: .center)
                }
            }
            .onChange(of: model.activeFileID) { _, activeID in
                guard let activeID else { return }
                withAnimation(DesignSystem.Motion.snappy) {
                    proxy.scrollTo(activeID, anchor: .center)
                }
            }
        }
        .padding(.leading, DesignSystem.Spacing.tabBarLeading)
        .frame(height: 38)
        .background(model.selectedTheme.colors.background)
        .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)
    }

    var emptyEditorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil.and.outline").font(DesignSystem.Typography.onboardingFeatureIcon).foregroundStyle(.secondary)
            Text(L10n("Selecione um arquivo")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var unsupportedFileView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.questionmark")
                .font(DesignSystem.Typography.onboardingTitle)
                .foregroundStyle(.secondary)
            Text(L10n("editor.file.unsupported"))
                .font(DesignSystem.Typography.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentWidthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    updateContentWidth(proxy.size.width)
                }
                .onChange(of: proxy.size) { _, size in
                    updateContentWidth(size.width)
                }
        }
    }

    func updateContentWidth(_ width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        let roundedWidth = width.rounded(.toNearestOrAwayFromZero)
        guard roundedWidth != contentWidth else { return }
        contentWidth = roundedWidth
        applyResponsiveCodeLayout(for: roundedWidth)
    }

    func applyResponsiveCodeLayout(for width: CGFloat) {
        let profile = CodeScreenLayoutProfile(width: width)
        if profile.prefersAutoCollapsedFileBrowser {
            if isFileBrowserVisible && !didAutoCollapseFileBrowserForCompactWidth {
                withAnimation(DesignSystem.Motion.panel) {
                    isFileBrowserVisible = false
                }
            }
            didAutoCollapseFileBrowserForCompactWidth = true
            return
        }

        didAutoCollapseFileBrowserForCompactWidth = false
    }
}
