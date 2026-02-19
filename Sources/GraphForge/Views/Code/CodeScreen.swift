import SwiftUI

struct CodeScreen: View {
    @ObservedObject var model: RepositoryViewModel
    
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
            
            Spacer()
            
            if model.selectedCodeFile != nil {
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
                        Text(L10n("Nenhum arquivo encontrado")).font(.caption).foregroundStyle(.secondary).padding(20)
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
            if let file = model.selectedCodeFile {
                HStack {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                    Text(file.url.path.replacingOccurrences(of: model.repositoryURL?.path ?? "", with: ""))
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                    Spacer()
                    Text(L10n("Editando")).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(10)
                .background(model.selectedTheme.colors.background)
                .environment(\.colorScheme, model.selectedTheme.isLightAppearance ? .light : .dark)

                Divider()

                SourceCodeEditor(
                    text: $model.codeFileContent,
                    theme: model.selectedTheme,
                    fontSize: model.editorFontSize,
                    fontFamily: model.editorFontFamily,
                    lineSpacing: model.editorLineSpacing
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
    
    private var emptyEditorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil.and.outline").font(.system(size: 40)).foregroundStyle(Color.gray.opacity(0.3))
            Text(L10n("Selecione um arquivo")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var terminalContainer: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "terminal.fill").font(.caption).foregroundStyle(model.selectedTheme.isLightAppearance ? Color.blue : Color.accentColor)
                Text("Vibe Terminal (zsh)").font(.system(size: 11, weight: .bold))
                Spacer()
                Text("Interativo").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            
            Divider()
            
            TerminalView(model: model, theme: model.selectedTheme)
        }
        .background(Color.black.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
