import SwiftUI

struct CodeScreen: View {
    @ObservedObject var model: RepositoryViewModel
    var onOpenFolder: (() -> Void)? = nil
    
    var body: some View {
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
        .padding(12)
        .background(DesignSystem.Colors.background)
    }
    
    private var editorToolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "paintpalette.fill").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $model.selectedTheme) {
                    ForEach(EditorTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
            }
            
            Divider().frame(height: 16)
            
            HStack(spacing: 8) {
                Image(systemName: "textformat").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $model.editorFontFamily) {
                    Text("SF Mono").tag("SF Mono")
                    Text("Menlo").tag("Menlo")
                    Text("Monaco").tag("Monaco")
                    Text("Courier").tag("Courier")
                    Text("Fira Code").tag("Fira Code")
                    Text("JetBrains Mono").tag("JetBrains Mono")
                }
                .pickerStyle(.menu)
                .frame(width: 130)
            }
            
            Divider().frame(height: 16)
            
            HStack(spacing: 8) {
                Image(systemName: "textformat.size").font(.caption).foregroundStyle(.secondary)
                Stepper(value: $model.editorFontSize, in: 8...32, step: 1) {
                    Text("\(Int(model.editorFontSize))pt")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 35)
                }
            }
            
            Divider().frame(height: 16)
            
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal").font(.caption).foregroundStyle(.secondary)
                Slider(value: $model.editorLineSpacing, in: 0.8...2.0, step: 0.1)
                    .frame(width: 80)
                Text(String(format: "%.1fx", model.editorLineSpacing))
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 35)
            }
            
            Divider().frame(height: 16)

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
            HStack {
                Text(L10n("Arquivos")).font(.headline)
                Spacer()
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
                    activeFileID: model.activeFileID
                )
            } else {
                emptyEditorView
                    .background(model.selectedTheme.colors.background)
                    .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
        .background(Color.black.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            model.createDefaultTerminalSession(repositoryURL: model.repositoryURL, branchName: model.currentBranch.isEmpty ? "zsh" : model.currentBranch)
        }
    }

    private var terminalTabBar: some View {
        let accentColor = model.selectedTheme.isLightAppearance ? Color.blue : Color.accentColor
        return HStack(spacing: 0) {
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

    var body: some View {
        HStack(spacing: 8) {
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
        .background(isActive ? model.selectedTheme.colors.background : Color.black.opacity(0.15))
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle().fill(accentColor).frame(height: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onActivate() }
        .onHover { h in isHovering = h }
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
