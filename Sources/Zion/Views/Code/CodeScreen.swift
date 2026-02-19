import SwiftUI

struct CodeScreen: View {
    @ObservedObject var model: RepositoryViewModel
    var onOpenFolder: (() -> Void)? = nil
    @State private var isQuickOpenVisible: Bool = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                editorToolbar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(model.selectedTheme.colors.background)
                    .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)

                Divider()

                HSplitView {
                    fileBrowserPane
                        .frame(minWidth: 200, idealWidth: 260, maxWidth: 400)

                    VSplitView {
                        editorPane
                            .frame(minWidth: 400, idealWidth: 800, maxWidth: .infinity, minHeight: 300)

                        terminalContainer
                            .frame(minWidth: 400, idealWidth: 800, maxWidth: .infinity, minHeight: 150, maxHeight: 600)
                    }
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
        }
    }
    
    private var editorToolbar: some View {
        HStack(spacing: 6) {
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

                Slider(value: $model.editorLineSpacing, in: 0.8...2.0, step: 0.1)
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

            Spacer()

            if model.activeFileID != nil {
                Button {
                    model.saveCurrentCodeFile()
                } label: {
                    Label(L10n("Salvar"), systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(model.selectedTheme.isLightAppearance ? Color.blue : Color.accentColor)
            }
        }
        .controlSize(.small)
    }
    
    private var fileBrowserPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(L10n("Arquivos"), icon: "folder.fill") {
                Button { model.refreshFileTree() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(12)
            
            Divider()
            
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
                }
                .padding(.vertical, 8)
            }
        }
        .background(DesignSystem.Colors.background.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private var editorPane: some View {
        VStack(spacing: 0) {
            if !model.openedFiles.isEmpty {
                codeTabBar

                Divider()

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
            } else {
                emptyEditorView
                    .background(model.selectedTheme.colors.background)
                    .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
                if model.terminalSessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "terminal").font(.title).foregroundStyle(.secondary.opacity(0.4))
                        Text(L10n("Nenhum terminal aberto")).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(model.terminalSessions) { session in
                        TerminalTabView(session: session, theme: model.selectedTheme)
                            .opacity(session.id == model.activeTerminalID ? 1 : 0)
                            .allowsHitTesting(session.id == model.activeTerminalID)
                    }
                }
            }
        }
        .background(model.selectedTheme.terminalPalette.backgroundSwiftUI)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            model.createDefaultTerminalSession(repositoryURL: model.repositoryURL, branchName: model.currentBranch.isEmpty ? "zsh" : model.currentBranch)
        }
        .background {
            Button("") {
                guard let url = model.repositoryURL else { return }
                model.createTerminalSession(workingDirectory: url, label: model.currentBranch.isEmpty ? "zsh" : model.currentBranch)
            }
            .keyboardShortcut("t", modifiers: .command)
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
                    ForEach(model.terminalSessions) { session in
                        TerminalTab(
                            session: session,
                            isActive: session.id == model.activeTerminalID,
                            accentColor: accentColor,
                            onActivate: { model.activateTerminalSession(session) },
                            onClose: { model.closeTerminalSession(session) },
                            onRestart: { session.isAlive = true }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer()

            Button {
                guard let url = model.repositoryURL else { return }
                let label = model.currentBranch.isEmpty ? "zsh" : model.currentBranch
                model.createTerminalSession(workingDirectory: url, label: label)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(model.selectedTheme.terminalPalette.accentSwiftUI.opacity(0.25)).frame(height: 1)
        }
    }
}

struct TerminalTab: View {
    @ObservedObject var session: TerminalSession
    let isActive: Bool
    let accentColor: Color
    let onActivate: () -> Void
    let onClose: () -> Void
    let onRestart: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.isAlive ? Color.green : Color.red)
                .frame(width: 6, height: 6)

            Text(session.title)
                .font(.system(size: 10, weight: isActive ? .bold : .regular, design: .monospaced))
                .lineLimit(1)

            if !session.isAlive {
                Button {
                    onRestart()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? accentColor.opacity(0.25) : Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onActivate() }
    }
}

struct CodeTab: View {
    @ObservedObject var model: RepositoryViewModel
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
            .opacity(isActive || isHovering ? 1.0 : 0.0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? model.selectedTheme.colors.background : (isHovering ? Color.white.opacity(0.06) : Color.clear))
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
    @ObservedObject var model: RepositoryViewModel
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
                    .onChange(of: selectedIndex) { idx in
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
        .onChange(of: query) { _ in selectedIndex = 0 }
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
    @ObservedObject var model: RepositoryViewModel
    let item: FileItem
    let level: Int
    
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
                    
                    Image(systemName: item.isDirectory ? (isExpanded ? "folder.badge.minus" : "folder.fill") : "doc.text")
                        .font(.system(size: 12))
                        .foregroundStyle(isModified ? Color.orange : (item.isDirectory ? (isDark ? Color.accentColor : Color.blue) : .secondary))
                    
                    Text(item.name)
                        .font(.system(size: 12, weight: isSelected ? .bold : .regular, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? (isDark ? .white : Color.blue) : (isModified ? Color.orange : .primary))
                }
                .padding(.horizontal, 12).padding(.vertical, 6).padding(.leading, CGFloat(level) * 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
            }
            .buttonStyle(.plain)
            
            if item.isDirectory && isExpanded, let children = item.children {
                ForEach(children) { child in
                    FileTreeNodeView(model: model, item: child, level: level + 1)
                }
            }
        }
    }
}
