import SwiftUI

struct ChangesScreen: View {
    @ObservedObject var model: RepositoryViewModel
    
    var body: some View {
        HSplitView {
            fileListPane
                .frame(minWidth: 250, idealWidth: 350, maxWidth: 500)
                .layoutPriority(1)
            
            diffViewerPane
                .frame(minWidth: 600, idealWidth: 1000, maxWidth: .infinity)
                .layoutPriority(2)
        }
        .padding(12)
    }
    
    private var fileListPane: some View {
        GlassCard(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n("Changes")).font(.headline)
                    Text("\(model.uncommittedCount) \(L10n("arquivos modificados"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.refreshRepository()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.plain).help(L10n("Atualizar"))
            }
            .padding(12)
            
            Divider()
            
            if model.uncommittedChanges.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green.opacity(0.6))
                    Text(L10n("Tudo limpo!"))
                        .font(.headline)
                    Text(L10n("Nenhuma alteração pendente no momento."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.uncommittedChanges, id: \.self) { line in
                            fileRow(line: line)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }
    
    private func fileRow(line: String) -> some View {
        let (indexStatus, workTreeStatus, file) = parseGitStatus(line)
        let isSelected = model.selectedChangeFile == file
        
        return Button {
            model.selectChangeFile(file)
        } label: {
            HStack(spacing: 10) {
                statusIcon(index: indexStatus, worktree: workTreeStatus)
                    .font(.system(size: 14))
                
                Text(file)
                    .font(.system(size: 12, weight: isSelected ? .bold : .regular, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                if indexStatus != " " && indexStatus != "?" {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var diffViewerPane: some View {
        GlassCard(spacing: 0) {
            if let file = model.selectedChangeFile {
                HStack {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                    Text(file).font(.system(.subheadline, design: .monospaced)).fontWeight(.bold)
                    Spacer()
                    Button {
                        model.stageFile(file)
                    } label: {
                        Label(L10n("Stage"), systemImage: "plus")
                    }.buttonStyle(.bordered).controlSize(.small)
                }
                .padding(12)
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let lines = model.currentFileDiff.split(separator: "\n", omittingEmptySubsequences: false)
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            diffLine(String(line))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.black.opacity(0.2))
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text(L10n("Selecione um arquivo para ver as mudanças."))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func diffLine(_ line: String) -> some View {
        let backgroundColor: Color
        let textColor: Color
        
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            backgroundColor = Color.green.opacity(0.15)
            textColor = Color.green
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            backgroundColor = Color.red.opacity(0.15)
            textColor = Color.red
        } else if line.hasPrefix("@@") {
            backgroundColor = Color.blue.opacity(0.1)
            textColor = Color.blue.opacity(0.8)
        } else {
            backgroundColor = Color.clear
            textColor = .primary.opacity(0.8)
        }
        
        return Text(line)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .foregroundStyle(textColor)
    }
    
    private func parseGitStatus(_ line: String) -> (String, String, String) {
        if line.count < 3 { return (" ", " ", line) }
        let index = String(line.prefix(1))
        let worktree = String(line.prefix(2).suffix(1))
        let file = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return (index, worktree, file)
    }
    
    @ViewBuilder
    private func statusIcon(index: String, worktree: String) -> some View {
        if index != " " && index != "?" {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            switch worktree {
            case "?": Image(systemName: "plus.circle").foregroundStyle(.secondary)
            case "M": Image(systemName: "pencil.circle").foregroundStyle(.orange)
            case "D": Image(systemName: "minus.circle").foregroundStyle(.red)
            default: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
    }
}
