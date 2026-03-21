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
    @Environment(\.zionModeEnabled) private var zionModeEnabled
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
    @State var isMarkdownPreviewVisible: Bool = false
    @FocusState var isTerminalSearchFocused: Bool
    @State var isSymbolResultsVisible: Bool = false
    @State var symbolResultsMode: EditorSymbolResultsMode = .definitions
    @State var symbolResultsQuery: String = ""
    @State var symbolResults: [EditorSymbolLocation] = []

    // Find in Files
    enum SidebarMode { case fileTree, findInFiles }
    @State var sidebarMode: SidebarMode = .fileTree
    @State var findInFilesQuery: String = ""
    @State var findInFilesInclude: String = ""
    @State var findInFilesExclude: String = ""
    @State var findInFilesResults: [FindInFilesFileResult] = []
    @State var isFindInFilesSearching: Bool = false
    @State var findInFilesScopePath: String? = nil

    @AppStorage(UserDefaultsKeys.Terminal.opacity) var terminalOpacity: Double = 0.92

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

                // IMPORTANT: editorTerminalContent must always occupy the same structural
                // slot to preserve NSView identity of terminal views. The file browser is
                // layered alongside it rather than wrapping it in a conditional.
                StableFileBrowserSplit(
                    isVisible: isFileBrowserVisible && !isZenMode,
                    ratio: $fileBrowserRatio,
                    sidebar: { fileBrowserPane },
                    content: { editorTerminalContent }
                )
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

            // Maximize terminal (Ctrl+Cmd+J)
            Button("") {
                guard !isZenMode else { return }
                withAnimation(DesignSystem.Motion.detail) {
                    layout = layout == .terminalOnly ? .split : .terminalOnly
                }
            }
            .keyboardShortcut("j", modifiers: [.command, .control])
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
                    closeFindInFilesPanel()
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

            // Priority Escape routing for code screen overlays/panels
            Button("") { handleEscapeShortcut() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0).opacity(0)
        }
        .onChange(of: model.activeFileID) { _, _ in
            isMarkdownPreviewVisible = false
            if !isTextEditorActive {
                closeSearch()
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

    private var editorTerminalContent: some View {
        // IMPORTANT: Both editorPane and terminalContainer must always exist in the
        // same structural position to preserve NSView identity. Using if/else branches
        // causes SwiftUI to destroy and recreate NSViewRepresentable views (TerminalTabView),
        // which triggers expensive make/dismantle storms on layout changes and repo switches.
        StableEditorTerminalSplit(
            layout: layout,
            terminalRatio: $terminalRatio,
            editor: { editorPane },
            terminal: { terminalContainer }
        )
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
            .disabled(!isTextEditorActive)

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
            .disabled(!isTextEditorActive)

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
            .disabled(!isTextEditorActive)

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
                .disabled(!isTextEditorActive)

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
            .disabled(model.activeFileID == nil || !isTextEditorActive)

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
            .disabled(model.activeFileID == nil || !isTextEditorActive || !CodeFormatter.canFormat(fileExtension: model.selectedCodeFile?.url.pathExtension ?? ""))

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
                .help(L10n("Somente terminal") + " (⌃⌘J)")
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
                .disabled(!isTextEditorActive)

                Button {
                    model.saveCurrentCodeFile()
                } label: {
                    Label(L10n("Salvar"), systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(model.selectedTheme.isLightAppearance ? DesignSystem.Colors.info : Color.accentColor)
                .help(L10n("Salvar") + " (⌘S)")
                .disabled(!isTextEditorActive)
            }
        }
        .controlSize(.small)
    }

    var editorPane: some View {
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
                            axis: .horizontal,
                            ratio: $markdownPreviewRatio,
                            minLeading: DesignSystem.Layout.markdownPreviewMinLeading,
                            minTrailing: DesignSystem.Layout.markdownPreviewMinTrailing
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

    var isMarkdownFile: Bool {
        model.selectedEditorContentKind == .markdown
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
        .padding(.leading, 36)
        .frame(height: 38)
        .background(model.selectedTheme.colors.background)
        .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)
    }

    var emptyEditorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil.and.outline").font(.system(size: 40)).foregroundStyle(.secondary)
            Text(L10n("Selecione um arquivo")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var unsupportedFileView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.questionmark")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(L10n("editor.file.unsupported"))
                .font(DesignSystem.Typography.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
final class FileBrowserResponderReference: ObservableObject {
    weak var responder: FileBrowserShortcutResponderView?
}

struct FileBrowserShortcutResponderHost: NSViewRepresentable {
    let reference: FileBrowserResponderReference
    var canDeleteSelectedFiles: () -> Bool
    var onDeleteSelectedFiles: () -> Void
    var canRenameSelectedFile: () -> Bool
    var onRenameSelectedFile: () -> Void
    var onMoveSelection: (FileBrowserNavigationDirection, Bool) -> Void

    func makeNSView(context: Context) -> FileBrowserShortcutResponderView {
        let view = FileBrowserShortcutResponderView()
        view.reference = reference
        view.canDeleteSelectedFiles = canDeleteSelectedFiles
        view.onDeleteSelectedFiles = onDeleteSelectedFiles
        view.canRenameSelectedFile = canRenameSelectedFile
        view.onRenameSelectedFile = onRenameSelectedFile
        view.onMoveSelection = onMoveSelection
        reference.responder = view
        return view
    }

    func updateNSView(_ nsView: FileBrowserShortcutResponderView, context: Context) {
        nsView.reference = reference
        nsView.canDeleteSelectedFiles = canDeleteSelectedFiles
        nsView.onDeleteSelectedFiles = onDeleteSelectedFiles
        nsView.canRenameSelectedFile = canRenameSelectedFile
        nsView.onRenameSelectedFile = onRenameSelectedFile
        nsView.onMoveSelection = onMoveSelection
        if reference.responder !== nsView {
            reference.responder = nsView
        }
    }

}

final class FileBrowserShortcutResponderView: NSView {
    weak var reference: FileBrowserResponderReference?
    var canDeleteSelectedFiles: () -> Bool = { false }
    var onDeleteSelectedFiles: () -> Void = {}
    var canRenameSelectedFile: () -> Bool = { false }
    var onRenameSelectedFile: () -> Void = {}
    var onMoveSelection: (FileBrowserNavigationDirection, Bool) -> Void = { _, _ in }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reference?.responder = self
    }

    @objc
    func zionDeleteSelectedFiles(_ sender: Any?) {
        guard canDeleteSelectedFiles() else { return }
        onDeleteSelectedFiles()
    }

    override func insertNewline(_ sender: Any?) {
        guard canRenameSelectedFile() else {
            super.insertNewline(sender)
            return
        }
        onRenameSelectedFile()
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func moveUp(_ sender: Any?) {
        onMoveSelection(.up, false)
    }

    override func moveDown(_ sender: Any?) {
        onMoveSelection(.down, false)
    }

    override func moveLeft(_ sender: Any?) {
        onMoveSelection(.left, false)
    }

    override func moveRight(_ sender: Any?) {
        onMoveSelection(.right, false)
    }

    override func moveUpAndModifySelection(_ sender: Any?) {
        onMoveSelection(.up, true)
    }

    override func moveDownAndModifySelection(_ sender: Any?) {
        onMoveSelection(.down, true)
    }

    override func moveLeftAndModifySelection(_ sender: Any?) {
        onMoveSelection(.left, true)
    }

    override func moveRightAndModifySelection(_ sender: Any?) {
        onMoveSelection(.right, true)
    }
}
