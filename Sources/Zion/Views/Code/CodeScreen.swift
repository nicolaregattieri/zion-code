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

struct CodeScreen: View {
    @Bindable var model: RepositoryViewModel
    var onOpenFolder: (() -> Void)? = nil
    @State private var isQuickOpenVisible: Bool = false
    @State private var isFileBrowserVisible: Bool = true
    @State private var layout: EditorTerminalLayout = .split

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                editorToolbar
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(model.selectedTheme.colors.background)
                    .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)

                Divider()

                HSplitView {
                    if isFileBrowserVisible {
                        fileBrowserPane
                            .frame(minWidth: 200, idealWidth: 260, maxWidth: 400)
                    }

                    VStack(spacing: 0) {
                        GeometryReader { geo in
                            if layout == .split {
                                VSplitView {
                                    editorPane
                                        .frame(minHeight: 100, maxHeight: .infinity)
                                    terminalContainer
                                        .frame(minHeight: 100, maxHeight: .infinity)
                                }
                            } else {
                                VStack(spacing: 0) {
                                    if layout == .editorOnly {
                                        editorPane
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    } else {
                                        terminalContainer
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }
                            }
                        }
                    }
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if isQuickOpenVisible {
                QuickOpenOverlay(
                    model: model,
                    isVisible: $isQuickOpenVisible
                )
            }
        }
        .padding(12)
        .background(DesignSystem.Colors.background)
        .background {
            Button("") { isQuickOpenVisible.toggle() }
                .keyboardShortcut("p", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)

            Button("") { withAnimation(.easeInOut(duration: 0.2)) { isFileBrowserVisible.toggle() } }
                .keyboardShortcut("b", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)

            // Toggle terminal visibility (Cmd+J)
            Button("") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    layout = layout == .editorOnly ? .split : .editorOnly
                }
            }
            .keyboardShortcut("j", modifiers: .command)
            .frame(width: 0, height: 0).opacity(0)

            // Maximize terminal (Cmd+Shift+J)
            Button("") {
                withAnimation(.easeInOut(duration: 0.15)) {
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
        }
    }
    
    private var editorToolbar: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isFileBrowserVisible.toggle() }
            } label: {
                Image(systemName: "sidebar.left").font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(isFileBrowserVisible ? Color.accentColor : .secondary)
            .help(L10n("Alternar painel de arquivos") + " (⌘B)")

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
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Size & Spacing group
            HStack(spacing: 6) {
                Stepper(value: $model.editorFontSize, in: 8...32, step: 1) {
                    Text("\(Int(model.editorFontSize))pt")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 30)
                }

                Divider().frame(height: 14)

                Slider(value: $model.editorLineSpacing, in: 0.8...3.0, step: 0.1)
                    .frame(width: 60)
                Text(String(format: "%.1fx", model.editorLineSpacing))
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 30)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                model.isLineWrappingEnabled.toggle()
            } label: {
                Image(systemName: model.isLineWrappingEnabled ? "text.alignleft" : "text.line.first.and.arrowtriangle.forward")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(model.isLineWrappingEnabled ? Color.accentColor : .secondary)
            .help(L10n("Quebra de Linha Automática"))

            Button {
                model.toggleBlame()
            } label: {
                Image(systemName: "person.text.rectangle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(model.isBlameVisible ? Color.accentColor : .secondary)
            .help(L10n("Git Blame"))
            .disabled(model.activeFileID == nil)

            Divider().frame(height: 14).padding(.horizontal, 4)

            // Layout toggle: editor / split / terminal
            HStack(spacing: 2) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { layout = .editorOnly }
                } label: {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(layout == .editorOnly ? Color.accentColor : .secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .help(L10n("Somente editor") + " (⌘J)")

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { layout = .split }
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(layout == .split ? Color.accentColor : .secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .help(L10n("Editor e terminal"))

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { layout = .terminalOnly }
                } label: {
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(layout == .terminalOnly ? Color.accentColor : .secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .help(L10n("Somente terminal") + " (⇧⌘J)")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            Button {
                model.createNewFile()
            } label: {
                Image(systemName: "doc.badge.plus")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .help(L10n("Novo Arquivo") + " (⌘N)")

            if model.activeFileID != nil {
                Button {
                    model.saveCurrentFileAs()
                } label: {
                    Image(systemName: "arrow.down.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .help(L10n("Salvar Como...") + " (⇧⌘S)")

                Button {
                    model.saveCurrentCodeFile()
                } label: {
                    Label(L10n("Salvar"), systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(model.selectedTheme.isLightAppearance ? Color.blue : Color.accentColor)
                .help(L10n("Salvar") + " (⌘S)")
            }
        }
        .controlSize(.small)
    }
    
    private var fileBrowserPane: some View {
        VStack(spacing: 0) {
            // File tree header
            CardHeader(L10n("Arquivos"), icon: "folder.fill") {
                Button { model.refreshFileTree() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).contentShape(Rectangle()).foregroundStyle(.secondary)
                    .help(L10n("Atualizar arvore de arquivos"))
            }
            .padding(12)

            Divider()

            // File tree scroll — fills available space
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
                        }
                    }

                    ClipboardDrawer(model: model)
                        .padding(.top, 8)
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
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

                Divider()

                if model.isBlameVisible && !model.blameEntries.isEmpty {
                    BlameView(entries: model.blameEntries, fileName: model.selectedCodeFile?.name ?? "", model: model) { commitHash in
                        model.selectCommit(commitHash)
                        model.navigateToGraphRequested = true
                    }
                    .background(model.selectedTheme.colors.background)
                } else {
                    SourceCodeEditor(
                        text: $model.codeFileContent,
                        theme: model.selectedTheme,
                        fontSize: model.editorFontSize,
                        fontFamily: model.editorFontFamily,
                        lineSpacing: model.editorLineSpacing,
                        isLineWrappingEnabled: model.isLineWrappingEnabled,
                        activeFileID: model.activeFileID,
                        fileExtension: model.selectedCodeFile?.url.pathExtension ?? ""
                    )
                }
            } else {
                emptyEditorView
                    .background(model.selectedTheme.colors.background)
                    .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)
            }
        }
        .background {
            Button("") { model.saveCurrentCodeFile() }
                .keyboardShortcut("s", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)
        }
    }

    private var codeTabBar: some View {
        let accentColor = model.selectedTheme.isLightAppearance ? Color.blue : Color.accentColor
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
            Image(systemName: "pencil.and.outline").font(.system(size: 40)).foregroundStyle(Color.gray.opacity(0.3))
            Text(L10n("Selecione um arquivo")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var terminalContainer: some View {
        VStack(spacing: 0) {
            terminalTabBar

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
                            model: model
                        )
                        .opacity(tab.id == model.activeTabID ? 1 : 0)
                        .allowsHitTesting(tab.id == model.activeTabID)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
            .dropDestination(for: String.self) { items, _ in
                guard let text = items.first, !text.isEmpty else { return false }
                model.sendTextToActiveTerminal(text)
                return true
            }
        }
        .background(model.selectedTheme.terminalPalette.backgroundSwiftUI)
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
        }
    }

    private var terminalTabBar: some View {
        let accentColor = model.selectedTheme.isLightAppearance ? Color.blue : Color.accentColor
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
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))

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
            .padding(.trailing, 8)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(model.selectedTheme.terminalPalette.accentSwiftUI.opacity(0.25)).frame(height: 1)
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
                .fill(hasAlive ? Color.green : Color.red)
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
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
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
                        Text("Hack Nerd Font").tag("HackNerdFontMono-Regular")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }

                if !model.isTerminalFontAvailable {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text(L10n("Fonte nao encontrada, usando fallback"))
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
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

    var body: some View {
        switch node.content {
        case .terminal(let session):
            TerminalTabView(
                session: session,
                theme: theme,
                fontSize: fontSize,
                fontFamily: fontFamily,
                model: model
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
                            TerminalPaneView(node: child, theme: theme, fontSize: fontSize, fontFamily: fontFamily, focusedSessionID: focusedSessionID, model: model)
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
                            TerminalPaneView(node: child, theme: theme, fontSize: fontSize, fontFamily: fontFamily, focusedSessionID: focusedSessionID, model: model)
                                .frame(height: max(0, paneHeight))
                        }
                    }
                }
            }
        }
    }
}

struct CodeTab: View {
    var model: RepositoryViewModel
    let file: FileItem
    let isActive: Bool
    let accentColor: Color
    let onActivate: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false

    private var isUnsaved: Bool { model.unsavedFiles.contains(file.id) }

    var body: some View {
        HStack(spacing: 8) {
            if isUnsaved {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
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
            .contentShape(Rectangle())
            .opacity(isActive || isHovering ? 1.0 : 0.0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? model.selectedTheme.colors.background : (isHovering ? DesignSystem.Colors.glassElevated : Color.clear))
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle().fill(accentColor).frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            if !isActive {
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1).padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onActivate() }
        .onHover { h in isHovering = h }
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
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
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
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }

    private func selectCurrentFile() {
        let files = filteredFiles
        guard selectedIndex < files.count else { return }
        model.selectCodeFile(files[selectedIndex])
        isVisible = false
    }
}

struct FileTreeNodeView: View {
    var model: RepositoryViewModel
    let item: FileItem
    let level: Int
    @State private var isHovering = false

    var body: some View {
        let isExpanded = model.expandedPaths.contains(item.id)
        let isSelected = model.activeFileID == item.id
        let isDark = model.selectedTheme.isDark
        let isModified = model.uncommittedChanges.contains { $0.hasSuffix(item.name) }

        VStack(alignment: .leading, spacing: 0) {
            Button {
                if item.isDirectory {
                    withAnimation(.snappy(duration: 0.2)) { model.toggleExpansion(for: item.id) }
                } else { model.selectCodeFile(item) }
            } label: {
                HStack(spacing: 6) {
                    if item.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary.opacity(0.5)).frame(width: 12)
                    } else { Spacer().frame(width: 12) }

                    if item.isDirectory {
                        FolderIcon(
                            isOpen: isExpanded,
                            color: isModified ? .orange : (isDark ? Color.accentColor : .blue),
                            size: 14
                        )
                    } else {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                            .foregroundStyle(isModified ? Color.orange : .secondary)
                    }

                    Text(item.name)
                        .font(.system(size: 12, weight: isSelected ? .bold : .regular, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? (isDark ? .white : Color.blue) : (isModified ? Color.orange : .primary))
                }
                .padding(.horizontal, 12).padding(.vertical, 6).padding(.leading, CGFloat(level) * 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(isSelected ? Color.blue.opacity(0.15) : (isHovering ? DesignSystem.Colors.glassHover : Color.clear))
            }
            .buttonStyle(.plain)
            .onHover { h in isHovering = h }
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
