import SwiftUI

struct CodeScreen: View {
    @ObservedObject var model: RepositoryViewModel
    
    var body: some View {
        HSplitView {
            fileBrowserPane
                .frame(minWidth: 200, idealWidth: 280, maxWidth: 400)
                .layoutPriority(1)
            
            VSplitView {
                editorPane
                    .frame(minWidth: 400, idealWidth: 800, maxWidth: .infinity, minHeight: 300)
                    .layoutPriority(2)
                
                terminalContainer
                    .frame(minWidth: 400, idealWidth: 800, maxWidth: .infinity, minHeight: 150, maxHeight: 600)
                    .layoutPriority(1)
            }
        }
        .padding(12)
        .background(model.selectedTheme.isDark ? Color.clear : Color(red: 0.99, green: 0.98, blue: 0.93))
    }
    
    private var fileBrowserPane: some View {
        GlassCard(spacing: 0) {
            HStack {
                Text(L10n("Arquivos"))
                    .font(.headline)
                    .foregroundStyle(model.selectedTheme.isDark ? Color.primary : Color(red: 0.36, green: 0.42, blue: 0.37))
                Spacer()
                Button {
                    model.refreshFileTree()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.selectedTheme.isDark ? Color.secondary : Color.gray)
            }
            .padding(12)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.repositoryFiles.isEmpty {
                        Text(L10n("Nenhum arquivo encontrado"))
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .padding(20)
                    } else {
                        ForEach(model.repositoryFiles) { item in
                            FileTreeNodeView(model: model, item: item, level: 0)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    private var editorPane: some View {
        GlassCard(spacing: 0) {
            if let file = model.selectedCodeFile {
                headerView(for: file)
                
                Divider()
                
                SourceCodeEditor(text: $model.codeFileContent, theme: model.selectedTheme)
                    .background(editorBackgroundColor)
                    .keyboardShortcut("s", modifiers: [.command])
            } else {
                emptyEditorView
            }
        }
    }
    
    private func headerView(for file: FileItem) -> some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(model.selectedTheme.isDark ? Color.secondary : Color.gray)
            Text(file.name)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(model.selectedTheme.isDark ? Color.primary : Color(red: 0.36, green: 0.42, blue: 0.37))
            
            Spacer()
            
            Picker("", selection: $model.selectedTheme) {
                ForEach(EditorTheme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            .controlSize(.small)
            
            Divider().frame(height: 16).padding(.horizontal, 4)
            
            Button {
                model.saveCurrentCodeFile()
            } label: {
                Label(L10n("Salvar"), systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(model.selectedTheme.isDark ? Color.accentColor : Color(red: 0.23, green: 0.58, blue: 0.77))
        }
        .padding(12)
    }
    
    private var emptyEditorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 48))
                .foregroundStyle(Color.gray.opacity(0.5))
            Text(L10n("Selecione um arquivo para editar."))
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var editorBackgroundColor: Color {
        switch model.selectedTheme {
        case .dracula:
            return Color(red: 0.16, green: 0.16, blue: 0.21)
        case .cityLights:
            return Color(red: 0.11, green: 0.15, blue: 0.17)
        case .everforestLight:
            return Color(red: 0.99, green: 0.98, blue: 0.93)
        }
    }
    
    private var terminalContainer: some View {
        GlassCard(spacing: 0) {
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.caption)
                    .foregroundStyle(model.selectedTheme.isDark ? Color.accentColor : Color(red: 0.23, green: 0.58, blue: 0.77))
                Text("Vibe Terminal (zsh)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(model.selectedTheme.isDark ? Color.primary : Color(red: 0.36, green: 0.42, blue: 0.37))
                Spacer()
                Text("Interativo").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            
            Divider()
            
            TerminalView(model: model, theme: model.selectedTheme)
                .background(Color.black.opacity(0.05))
        }
    }
}

struct FileTreeNodeView: View {
    @ObservedObject var model: RepositoryViewModel
    let item: FileItem
    let level: Int
    
    var body: some View {
        let isExpanded = model.expandedPaths.contains(item.id)
        let isSelected = model.selectedCodeFile?.id == item.id
        let isDark = model.selectedTheme.isDark
        
        // Simple check for git status
        let isModified = model.uncommittedChanges.contains { $0.hasSuffix(item.name) }
        
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if item.isDirectory {
                    withAnimation(.snappy(duration: 0.2)) {
                        model.toggleExpansion(for: item.id)
                    }
                } else {
                    model.selectCodeFile(item)
                }
            } label: {
                HStack(spacing: 6) {
                    if item.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .frame(width: 12)
                    } else {
                        Spacer().frame(width: 12)
                    }
                    
                    Image(systemName: item.isDirectory ? (isExpanded ? "folder.badge.minus" : "folder.fill") : "doc.text")
                        .font(.system(size: 12))
                        .foregroundStyle(isModified ? Color.orange : (item.isDirectory ? (isDark ? Color.accentColor : Color(red: 0.23, green: 0.58, blue: 0.77)) : (isDark ? .secondary : .gray)))
                    
                    Text(item.name)
                        .font(.system(size: 12, weight: isSelected ? .bold : .regular, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? (isDark ? .white : Color(red: 0.21, green: 0.45, blue: 0.69)) : (isModified ? Color.orange : (isDark ? .primary : Color(red: 0.36, green: 0.42, blue: 0.37))))
                    
                    if isModified {
                        Circle().fill(Color.orange).frame(width: 4, height: 4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .padding(.leading, CGFloat(level) * 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? (isDark ? Color.accentColor.opacity(0.15) : Color.blue.opacity(0.1)) : Color.clear)
                .contentShape(Rectangle())
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
