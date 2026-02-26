import SwiftUI

struct FolderIcon: View {
    let isOpen: Bool
    let color: Color
    let size: CGFloat

    init(isOpen: Bool = false, color: Color = .accentColor, size: CGFloat = 12) {
        self.isOpen = isOpen
        self.color = color
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            // Tab on top-left
            let tabWidth = w * 0.42
            let tabHeight = h * 0.22
            let tabRadius = min(w, h) * 0.08

            var tabPath = Path()
            tabPath.addRoundedRect(
                in: CGRect(x: 0, y: 0, width: tabWidth, height: tabHeight + tabRadius),
                cornerRadii: .init(topLeading: tabRadius, topTrailing: tabRadius)
            )
            context.fill(tabPath, with: .color(color))

            if isOpen {
                // Open folder: body slightly lower, front face tilted
                let bodyTop = tabHeight * 0.6
                let bodyRadius = min(w, h) * 0.1

                // Back panel
                var backPath = Path()
                backPath.addRoundedRect(
                    in: CGRect(x: 0, y: bodyTop, width: w, height: h - bodyTop),
                    cornerRadii: .init(topLeading: 0, bottomLeading: bodyRadius, bottomTrailing: bodyRadius, topTrailing: bodyRadius)
                )
                context.fill(backPath, with: .color(color.opacity(0.5)))

                // Front flap (tilted)
                var flapPath = Path()
                let flapTop = bodyTop + (h - bodyTop) * 0.15
                flapPath.move(to: CGPoint(x: w * 0.05, y: h))
                flapPath.addLine(to: CGPoint(x: w * 0.15, y: flapTop))
                flapPath.addLine(to: CGPoint(x: w, y: flapTop))
                flapPath.addLine(to: CGPoint(x: w, y: h))
                flapPath.closeSubpath()
                context.fill(flapPath, with: .color(color.opacity(0.85)))
            } else {
                // Closed folder: simple body
                let bodyTop = tabHeight * 0.6
                let bodyRadius = min(w, h) * 0.1

                var bodyPath = Path()
                bodyPath.addRoundedRect(
                    in: CGRect(x: 0, y: bodyTop, width: w, height: h - bodyTop),
                    cornerRadii: .init(topLeading: 0, bottomLeading: bodyRadius, bottomTrailing: bodyRadius, topTrailing: bodyRadius)
                )
                context.fill(bodyPath, with: .color(color))
            }
        }
        .frame(width: size, height: size * 0.82)
    }
}

enum EditorTerminalLayout: String, CaseIterable {
    case editorOnly
    case split
    case terminalOnly
}

private enum EditorSymbolResultsMode {
    case definitions
    case references
}

private struct EditorBreadcrumbItem: Identifiable {
    let id: String
    let title: String
    let targetPath: String?
    let isFile: Bool
    let isEllipsis: Bool
}

private struct BreadcrumbFolderSegmentButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
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
    @State private var markdownPreviewRatio: CGFloat = 0.5
    @State private var isMarkdownPreviewVisible: Bool = false
    @FocusState private var isTerminalSearchFocused: Bool
    @State private var isSymbolResultsVisible: Bool = false
    @State private var symbolResultsMode: EditorSymbolResultsMode = .definitions
    @State private var symbolResultsQuery: String = ""
    @State private var symbolResults: [EditorSymbolLocation] = []

    @AppStorage("terminal.transparencyEnabled") private var transparencyEnabled: Bool = false
    @AppStorage("terminal.opacity") private var terminalOpacity: Double = 0.92

    /// Ghostty-style terminal transparency: enabled via Settings toggle or automatically by Zion Mode
    private var isTerminalTransparent: Bool {
        transparencyEnabled || zionModeEnabled
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
        .padding(isZenMode ? 0 : 12)
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
            HStack(spacing: 6) {
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
        HStack(spacing: 6) {
            Button {
                withAnimation(DesignSystem.Motion.panel) { isFileBrowserVisible.toggle() }
            } label: {
                Image(systemName: "sidebar.left").font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(isFileBrowserVisible ? Color.accentColor : .secondary)
            .help(L10n("Alternar painel de arquivos") + " (⌘B)")
            .accessibilityLabel(L10n("Alternar painel de arquivos"))

            // Theme & Font group
            HStack(spacing: 6) {
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
            HStack(spacing: 6) {
                Stepper(value: $model.editorFontSize, in: 8...32, step: 1) {
                    Text("\(Int(model.editorFontSize))pt")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 30)
                }

                Divider().frame(height: 14)

                Slider(value: $model.editorLineSpacing, in: 0.0...20.0, step: 0.5)
                    .frame(width: 60)
                Text(String(format: "%.1fpt", model.editorLineSpacing))
                    .font(.system(size: 10, design: .monospaced))
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
                    .font(.caption)
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
                        .font(.caption)
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
                    .font(.caption)
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
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .help(L10n("filehistory.title"))
            .accessibilityLabel(L10n("filehistory.title"))
            .disabled(model.activeFileID == nil)

            Button {
                model.formatCurrentFile()
            } label: {
                Image(systemName: "text.alignleft")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .help(L10n("format.document") + " (⇧⌥F)")
            .accessibilityLabel(L10n("format.document"))
            .disabled(model.activeFileID == nil || !CodeFormatter.canFormat(fileExtension: model.selectedCodeFile?.url.pathExtension ?? ""))

            Divider().frame(height: 14).padding(.horizontal, 4)

            // Layout toggle: editor / split / terminal
            HStack(spacing: 2) {
                Button {
                    withAnimation(DesignSystem.Motion.detail) { layout = .editorOnly }
                } label: {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(layout == .editorOnly ? Color.accentColor : .secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .help(L10n("Somente editor") + " (⌘J)")
                .accessibilityLabel(L10n("Somente editor"))

                Button {
                    withAnimation(DesignSystem.Motion.detail) { layout = .split }
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(layout == .split ? Color.accentColor : .secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .help(L10n("Editor e terminal"))
                .accessibilityLabel(L10n("Editor e terminal"))

                Button {
                    withAnimation(DesignSystem.Motion.detail) { layout = .terminalOnly }
                } label: {
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(layout == .terminalOnly ? Color.accentColor : .secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
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
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 9))
                    Text(".zion")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
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
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .help(L10n("Novo Arquivo") + " (⌘N)")
            .accessibilityLabel(L10n("Novo Arquivo"))

            if model.activeFileID != nil {
                Button {
                    model.saveCurrentFileAs()
                } label: {
                    Image(systemName: "arrow.down.doc")
                        .font(.caption)
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
            HStack(spacing: 4) {
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
                .font(.system(size: 10, weight: .regular, design: .monospaced))
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
            // File tree header
            CardHeader(L10n("Arquivos"), icon: "folder.fill") {
                Button { model.refreshFileTree() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).cursorArrow().foregroundStyle(.secondary)
                    .help(L10n("Atualizar arvore de arquivos"))
                    .accessibilityLabel(L10n("Atualizar arvore de arquivos"))
            }
            .padding(12)

            Divider()

            // File tree scroll — fills available space
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.repositoryFiles.isEmpty {
                            VStack(spacing: 16) {
                                Text(L10n("Nenhum arquivo encontrado")).font(.caption).foregroundStyle(.secondary)
                                Button {
                                    onOpenFolder?()
                                } label: {
                                    Label(L10n("Selecionar Pasta"), systemImage: "folder.badge.plus")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(model.repositoryFiles) { item in
                                FileTreeNodeView(model: model, item: item, level: 0)
                                    .id(item.id)
                            }
                        }

                        ClipboardDrawer(model: model)
                            .padding(.top, 8)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, DesignSystem.Spacing.clipboardDrawerClearance)
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
                        // Collapse folder
                        if selectedBrowserIndex >= 0 && selectedBrowserIndex < flatFiles.count {
                            let item = flatFiles[selectedBrowserIndex]
                            if item.isDirectory && model.expandedPaths.contains(item.id) {
                                withAnimation(DesignSystem.Motion.snappy) { model.toggleExpansion(for: item.id) }
                            }
                        }
                        return
                    case .right:
                        // Expand folder
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
                        if !item.isDirectory {
                            model.selectCodeFile(item)
                        }
                        withAnimation { scrollProxy.scrollTo(item.id, anchor: .center) }
                    }
                }
            }
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

            // Find (Cmd+F)
            Button("") { openSearch(applySeedIfPresent: false) }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)

            // Find alias (Ctrl+F)
            Button("") { openSearch(applySeedIfPresent: false) }
                .keyboardShortcut("f", modifiers: .control)
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
            HStack(spacing: 8) {
                Label(L10n("editor.markdown.preview"), systemImage: "doc.text.image")
                    .font(.system(size: 11, weight: .semibold))
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
            HStack(spacing: 8) {
                // Toggle replace visibility
                Button {
                    withAnimation(DesignSystem.Motion.detail) { isReplaceVisible.toggle() }
                } label: {
                    Image(systemName: isReplaceVisible ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
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
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
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
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 50)
                }

                // Nav buttons
                Button { navigateToPreviousMatch() } label: {
                    Image(systemName: "chevron.up").font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(matchCount == 0)
                .help(L10n("editor.search.previous") + " (⇧Enter)")
                .accessibilityLabel(L10n("editor.search.previous"))

                Button { navigateToNextMatch() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(matchCount == 0)
                .help(L10n("editor.search.next") + " (Enter)")
                .accessibilityLabel(L10n("editor.search.next"))

                Spacer()

                // Close
                Button { closeSearch() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
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
                HStack(spacing: 8) {
                    Spacer().frame(width: 32)

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        TextField(L10n("editor.replace.placeholder"), text: $replaceQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
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
                .font(.headline)
            HStack(spacing: 8) {
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
        .padding(20)
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField(L10n("Buscar no terminal..."), text: $terminalSearchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($isTerminalSearchFocused)
                .onSubmit { terminalFindNext() }

            if !terminalSearchQuery.isEmpty {
                Button { terminalFindPrevious() } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(L10n("Resultado anterior"))

                Button { terminalFindNext() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(L10n("Proximo resultado"))
            }

            Button { closeTerminalSearch() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n("Fechar busca"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(model.selectedTheme.terminalPalette.backgroundSwiftUI.opacity(0.9))
    }

    private func toggleTerminalSearch() {
        withAnimation(DesignSystem.Motion.detail) {
            isTerminalSearchVisible.toggle()
            if isTerminalSearchVisible {
                isTerminalSearchFocused = true
            } else {
                closeTerminalSearch()
            }
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
                        Text(L10n("Nenhum terminal aberto")).font(.caption).foregroundStyle(.secondary)
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
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .dropDestination(for: String.self) { items, _ in
                guard let text = items.first, !text.isEmpty else { return false }
                model.sendTextToActiveTerminal(text)
                model.focusActiveTerminal()
                return true
            }
        }
        .padding(.top, 12)
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

            // Terminal Search (Cmd+F when terminal focused)
            Button("") { toggleTerminalSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)

            // Close terminal search (Escape)
            Button("") { closeTerminalSearch() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0).opacity(0)
        }
    }

    private var terminalTabBar: some View {
        let accentColor = model.selectedTheme.isLightAppearance ? DesignSystem.Colors.info : Color.accentColor
        return HStack(spacing: 0) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(model.selectedTheme.terminalPalette.accentSwiftUI.opacity(0.7))
                .padding(.leading, 10)
                .padding(.trailing, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
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

            Spacer()

            // Split buttons grouped
            HStack(spacing: 2) {
                Button {
                    model.splitFocusedTerminal(direction: .vertical)
                } label: {
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
                .help(L10n("Dividir verticalmente") + " (⇧⌘D)")
                .accessibilityLabel(L10n("Dividir verticalmente"))

                Button {
                    model.splitFocusedTerminal(direction: .horizontal)
                } label: {
                    Image(systemName: "square.split.1x2")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
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
            Button { model.quickCreateWorktree() } label: {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accentColor)
            }
            .buttonStyle(.borderless)
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
            .help(L10n("Criar worktree rapido"))
            .accessibilityLabel(L10n("Criar worktree rapido"))
            .disabled(model.repositoryURL == nil)

            // New tab
            Button {
                let url = model.repositoryURL ?? URL(fileURLWithPath: NSHomeDirectory())
                let label = model.currentBranch.isEmpty ? "zsh" : model.currentBranch
                model.createTerminalSession(workingDirectory: url, label: label)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accentColor)
            }
            .buttonStyle(.borderless)
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
            .help(L10n("Novo terminal") + " (⌘T)")
            .accessibilityLabel(L10n("Novo terminal"))
            .padding(.trailing, 8)

            if isZenMode {
                Spacer()
                    .frame(width: 12)

                zenModeExitButton(showsDismissGlyph: true)
                .padding(.trailing, 16)
            }
        }
        .padding(.vertical, 8)
    }
}

struct EditorSettingsPopoverButton: View {
    @Bindable var model: RepositoryViewModel
    @Binding var showBreadcrumbPath: Bool
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(isPresented ? Color.accentColor : .secondary)
        .help(L10n("settings.editor.popover.title"))
        .accessibilityLabel(L10n("settings.editor.popover.title"))
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n("settings.editor.popover.title"))
                    .font(.system(size: 11, weight: .semibold))

                // Editing section
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n("settings.editor.editing"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text(L10n("settings.editor.tabSize"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $model.editorTabSize) {
                            Text("2").tag(2)
                            Text("4").tag(4)
                            Text("8").tag(8)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }

                    Toggle(L10n("settings.editor.useTabs"), isOn: $model.editorUseTabs)
                        .font(.system(size: 11))

                    Toggle(L10n("settings.editor.autoCloseBrackets"), isOn: $model.editorAutoCloseBrackets)
                        .font(.system(size: 11))

                    Toggle(L10n("settings.editor.autoCloseQuotes"), isOn: $model.editorAutoCloseQuotes)
                        .font(.system(size: 11))

                    Toggle(L10n("settings.editor.bracketPairHighlight"), isOn: $model.editorBracketPairHighlight)
                        .font(.system(size: 11))
                }

                Divider()

                // Display section
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n("settings.editor.display"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Toggle(L10n("settings.editor.lineWrap"), isOn: $model.isLineWrappingEnabled)
                        .font(.system(size: 11))

                    Toggle(L10n("settings.editor.showBreadcrumb"), isOn: $showBreadcrumbPath)
                        .font(.system(size: 11))

                    Toggle(L10n("settings.editor.highlightCurrentLine"), isOn: $model.editorHighlightCurrentLine)
                        .font(.system(size: 11))

                    Toggle(L10n("settings.editor.showIndentGuides"), isOn: $model.editorShowIndentGuides)
                        .font(.system(size: 11))

                    Toggle(L10n("settings.editor.showRuler"), isOn: $model.editorShowRuler)
                        .font(.system(size: 11))

                    if model.editorShowRuler {
                        HStack(spacing: 6) {
                            Text(L10n("settings.editor.rulerColumn"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $model.editorRulerColumn) {
                                Text("80").tag(80)
                                Text("100").tag(100)
                                Text("120").tag(120)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }
                    }
                }

                Divider()

                // Formatting section
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n("settings.editor.formatting"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Toggle(L10n("settings.editor.formatOnSave"), isOn: $model.editorFormatOnSave)
                        .font(.system(size: 11))

                    Toggle(L10n("settings.editor.jsonSortKeys"), isOn: $model.editorJsonSortKeys)
                        .font(.system(size: 11))
                }

                Divider()

                // Line spacing
                HStack(spacing: 6) {
                    Text(L10n("settings.editor.lineSpacing"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(value: $model.editorLineSpacing, in: 0.0...20.0, step: 0.5)
                        .frame(width: 100)
                    Text(String(format: "%.1fpt", model.editorLineSpacing))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 42)
                }

                Divider()

                // Letter spacing
                HStack(spacing: 6) {
                    Text(L10n("settings.editor.letterSpacing"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(value: $model.editorLetterSpacing, in: -1.0...5.0, step: 0.1)
                        .frame(width: 100)
                    Text(String(format: "%.1f", model.editorLetterSpacing))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 30)
                }
            }
            .controlSize(.small)
            .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
            .tint(DesignSystem.Colors.actionPrimary)
            .padding(12)
            .frame(width: 260)
        }
    }
}

struct TerminalTabChip: View {
    let tab: TerminalPaneNode
    let isActive: Bool
    let accentColor: Color
    let onActivate: () -> Void
    let onClose: () -> Void

    private var sessions: [TerminalSession] { tab.allSessions() }
    private var title: String { sessions.first?.title ?? "zsh" }
    private var hasAlive: Bool { sessions.contains(where: { $0.isAlive }) }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(hasAlive ? DesignSystem.Colors.success : DesignSystem.Colors.destructive)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.system(size: 10, weight: isActive ? .bold : .regular, design: .monospaced))
                .lineLimit(1)

            if sessions.count > 1 {
                Text("\(sessions.count)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? accentColor.opacity(0.25) : DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                .stroke(isActive ? accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onActivate() }
    }
}

struct TerminalFontPopoverButton: View {
    @Bindable var model: RepositoryViewModel
    let accentColor: Color
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "textformat.size")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accentColor)
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 24)
        .contentShape(Rectangle())
        .help(L10n("Fonte do terminal"))
        .accessibilityLabel(L10n("Fonte do terminal"))
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n("Fonte do terminal"))
                    .font(.system(size: 11, weight: .semibold))

                HStack(spacing: 6) {
                    Text(L10n("Fonte"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $model.terminalFontFamily) {
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Monaco").tag("Monaco")
                        Text("Fira Code").tag("Fira Code")
                        Text("JetBrains Mono").tag("JetBrains Mono")
                        Text("Hack").tag("Hack")
                        Text("Roboto Mono").tag("Roboto Mono")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }

                if !model.isTerminalFontAvailable {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.Colors.warning)
                        Text(L10n("Fonte nao encontrada, usando fallback"))
                            .font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.warning)
                    }
                }

                HStack(spacing: 6) {
                    Text(L10n("Tamanho"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Stepper(value: $model.terminalFontSize, in: 8...32, step: 1) {
                        Text("\(Int(model.terminalFontSize))pt")
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
            .controlSize(.small)
            .padding(12)
            .frame(width: 240)
        }
    }
}

struct TerminalPaneView: View {
    let node: TerminalPaneNode
    var theme: EditorTheme
    var fontSize: Double
    var fontFamily: String
    var focusedSessionID: UUID?
    var model: RepositoryViewModel
    var transparentBackground: Bool = false

    var body: some View {
        switch node.content {
        case .terminal(let session):
            TerminalTabView(
                session: session,
                theme: theme,
                fontSize: fontSize,
                fontFamily: fontFamily,
                model: model,
                transparentBackground: transparentBackground
            )
            .overlay(alignment: .topLeading) {
                if focusedSessionID == session.id, model.terminalSessions.count > 1 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 20)
                        .padding(.top, 4)
                        .padding(.leading, 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if model.terminalSessions.count > 1 {
                    Button { model.closeTerminalSession(session) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .help(L10n("Fechar painel") + " (⇧⌘W)")
                    .accessibilityLabel(L10n("Fechar painel"))
                    .padding(4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.focusedSessionID = session.id }

        case .split(let direction, _, _):
            let children = node.flattenedChildren(forDirection: direction)
            let dividerThickness: CGFloat = 1
            GeometryReader { geometry in
                if direction == .vertical {
                    let totalDividers = dividerThickness * CGFloat(children.count - 1)
                    let paneWidth = (geometry.size.width - totalDividers) / CGFloat(children.count)
                    HStack(spacing: 0) {
                        ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                            if index > 0 {
                                Divider().frame(width: dividerThickness)
                            }
                            TerminalPaneView(node: child, theme: theme, fontSize: fontSize, fontFamily: fontFamily, focusedSessionID: focusedSessionID, model: model, transparentBackground: transparentBackground)
                                .frame(width: max(0, paneWidth))
                        }
                    }
                } else {
                    let totalDividers = dividerThickness * CGFloat(children.count - 1)
                    let paneHeight = (geometry.size.height - totalDividers) / CGFloat(children.count)
                    VStack(spacing: 0) {
                        ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                            if index > 0 {
                                Divider().frame(height: dividerThickness)
                            }
                            TerminalPaneView(node: child, theme: theme, fontSize: fontSize, fontFamily: fontFamily, focusedSessionID: focusedSessionID, model: model, transparentBackground: transparentBackground)
                                .frame(height: max(0, paneHeight))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Visual Effect Blur (Ghostty-style terminal)

private struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

private struct FindSearchTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusRequestID: Int
    let onEnter: () -> Void
    let onShiftEnter: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> KeyAwareTextField {
        let field = KeyAwareTextField(frame: .zero)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.lineBreakMode = .byClipping
        field.maximumNumberOfLines = 1
        field.usesSingleLineMode = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: KeyAwareTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder

        if focusRequestID != context.coordinator.lastFocusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FindSearchTextField
        var lastFocusRequestID: Int = 0

        init(_ parent: FindSearchTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .shift, .control]) ?? []
                if flags.contains(.shift) {
                    parent.onShiftEnter()
                } else {
                    parent.onEnter()
                }
                return true
            }

            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onShiftEnter()
                return true
            }

            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onEnter()
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }

            return false
        }
    }

    final class KeyAwareTextField: NSTextField {}
}

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
        HStack(spacing: 8) {
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
                    .font(.system(size: 8, weight: .bold))
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

struct QuickOpenOverlay: View {
    var model: RepositoryViewModel
    @Binding var isVisible: Bool
    @State private var query: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedIndex: Int = 0
    @State private var eventMonitor: Any?

    private var filteredFiles: [FileItem] {
        let allFiles = model.allFlatFiles()
        guard !query.isEmpty else { return Array(allFiles.prefix(15)) }
        let q = query.lowercased()

        return allFiles
            .map { file -> (FileItem, Int) in
                let path = file.url.path.lowercased()
                let name = file.name.lowercased()
                var score = 0
                if name == q { score = 1000 }
                else if name.hasPrefix(q) { score = 500 }
                else if name.contains(q) { score = 200 }
                else if path.contains(q) { score = 100 }
                else {
                    var qi = q.startIndex
                    for ch in name {
                        if qi < q.endIndex && ch == q[qi] {
                            qi = q.index(after: qi)
                            score += 1
                        }
                    }
                    if qi < q.endIndex { score = 0 }
                }
                return (file, score)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(15)
            .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L10n("Buscar arquivo..."), text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($isSearchFocused)
                        .onSubmit { selectCurrentFile() }
                }
                .padding(12)

                Divider()

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            let files = filteredFiles
                            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                                quickOpenRow(file: file, isSelected: index == selectedIndex)
                                    .id(index)
                                    .onTapGesture {
                                        model.selectCodeFile(file)
                                        isVisible = false
                                    }
                            }
                            if files.isEmpty {
                                Text(L10n("Nenhum arquivo encontrado"))
                                    .foregroundStyle(.secondary)
                                    .padding(20)
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                    .onChange(of: selectedIndex) { _, idx in
                        scrollProxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
            .frame(width: 500)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius, style: .continuous).stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 60)
        .background(Color.black.opacity(0.3))
        .contentShape(Rectangle())
        .onTapGesture { isVisible = false }
        .onAppear {
            query = ""
            selectedIndex = 0
            isSearchFocused = true
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    private func installKeyMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53: // Escape
                isVisible = false
                return nil
            case 125: // Down arrow
                let max = filteredFiles.count
                if selectedIndex < max - 1 { selectedIndex += 1 }
                return nil
            case 126: // Up arrow
                if selectedIndex > 0 { selectedIndex -= 1 }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func quickOpenRow(file: FileItem, isSelected: Bool) -> some View {
        let relativePath: String = {
            guard let repoURL = model.repositoryURL else { return file.name }
            return file.url.path.replacingOccurrences(of: repoURL.path + "/", with: "")
        }()

        return HStack(spacing: 10) {
            Image(systemName: "doc.text").foregroundStyle(.secondary).font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.system(size: 13, weight: .medium))
                Text(relativePath).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? DesignSystem.Colors.selectionBackground : Color.clear)
        .contentShape(Rectangle())
    }

    private func selectCurrentFile() {
        let files = filteredFiles
        guard selectedIndex < files.count else { return }
        model.selectCodeFile(files[selectedIndex])
        isVisible = false
    }
}

struct SymbolResultsSheet: View {
    let title: String
    let emptyText: String
    let locations: [EditorSymbolLocation]
    let onSelect: (EditorSymbolLocation) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            if locations.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(locations) { location in
                    Button {
                        onSelect(location)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(location.relativePath):\(location.line)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Text(location.preview)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 760, height: 460)
    }
}

struct FileTreeNodeView: View {
    var model: RepositoryViewModel
    let item: FileItem
    let level: Int
    @State private var isHovered = false

    var body: some View {
        let isExpanded = model.expandedPaths.contains(item.id)
        let isSelected = model.activeFileID == item.id
        let isDark = model.selectedTheme.isDark
        let isModified = model.uncommittedChanges.contains { $0.hasSuffix(item.name) }

        VStack(alignment: .leading, spacing: 0) {
            Button {
                if item.isDirectory {
                    withAnimation(DesignSystem.Motion.snappy) { model.toggleExpansion(for: item.id) }
                } else { model.selectCodeFile(item) }
            } label: {
                HStack(spacing: 6) {
                    if item.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary.opacity(0.5)).frame(width: 12)
                    } else { Spacer().frame(width: 12) }

                    if item.isDirectory {
                        FolderIcon(
                            isOpen: isExpanded,
                            color: isModified ? DesignSystem.Colors.warning : (isDark ? Color.accentColor : DesignSystem.Colors.info),
                            size: 14
                        )
                    } else {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                            .foregroundStyle(isModified ? DesignSystem.Colors.warning : .secondary)
                    }

                    Text(item.name)
                        .font(.system(size: 12, weight: isSelected ? .bold : .regular, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? (isDark ? .white : DesignSystem.Colors.info) : (isModified ? DesignSystem.Colors.warning : .primary))
                }
                .padding(.horizontal, 12).padding(.vertical, 6).padding(.leading, CGFloat(level) * 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(isSelected ? DesignSystem.Colors.selectionBackground : (isHovered ? DesignSystem.Colors.glassHover : Color.clear))
            }
            .buttonStyle(.plain)
            .onHover { h in isHovered = h }
            .draggable(TerminalShellEscaping.quotePath(item.url.path))
            .contextMenu {
                if item.isDirectory {
                    Button { model.createNewFileInFolder(parentURL: item.url) } label: {
                        Label(L10n("Novo Arquivo"), systemImage: "doc.badge.plus")
                    }
                    Button { model.createNewFolder(parentURL: item.url) } label: {
                        Label(L10n("Nova Pasta"), systemImage: "folder.badge.plus")
                    }

                    Divider()

                    Button { model.copyFileItem(item) } label: {
                        Label(L10n("Copiar"), systemImage: "doc.on.doc")
                    }
                    Button { model.cutFileItem(item) } label: {
                        Label(L10n("Recortar"), systemImage: "scissors")
                    }
                    if model.hasFileBrowserClipboard {
                        Button { model.pasteFileItem(into: item.url) } label: {
                            Label(L10n("Colar"), systemImage: "doc.on.clipboard")
                        }
                    }

                    Divider()

                    Button { model.renameFileItem(item) } label: {
                        Label(L10n("Renomear..."), systemImage: "pencil")
                    }
                    Button { model.duplicateFileItem(item) } label: {
                        Label(L10n("Duplicar"), systemImage: "plus.square.on.square")
                    }

                    Divider()

                    Button(role: .destructive) { model.deleteFileItem(item) } label: {
                        Label(L10n("Excluir"), systemImage: "trash")
                    }

                    Divider()

                    Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                        Label(L10n("Revelar no Finder"), systemImage: "folder")
                    }
                } else {
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

                    Button { model.copyFileItem(item) } label: {
                        Label(L10n("Copiar"), systemImage: "doc.on.doc")
                    }
                    Button { model.cutFileItem(item) } label: {
                        Label(L10n("Recortar"), systemImage: "scissors")
                    }
                    if model.hasFileBrowserClipboard {
                        Button { model.pasteFileItem(into: item.url.deletingLastPathComponent()) } label: {
                            Label(L10n("Colar"), systemImage: "doc.on.clipboard")
                        }
                    }

                    Divider()

                    Button { model.renameFileItem(item) } label: {
                        Label(L10n("Renomear..."), systemImage: "pencil")
                    }
                    Button { model.duplicateFileItem(item) } label: {
                        Label(L10n("Duplicar"), systemImage: "plus.square.on.square")
                    }

                    Divider()

                    Button(role: .destructive) { model.deleteFileItem(item) } label: {
                        Label(L10n("Excluir"), systemImage: "trash")
                    }

                    Divider()

                    Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                        Label(L10n("Revelar no Finder"), systemImage: "folder")
                    }
                }
            }

            if item.isDirectory && isExpanded, let children = item.children {
                ForEach(children) { child in
                    FileTreeNodeView(model: model, item: child, level: level + 1)
                }
            }
        }
    }
}
