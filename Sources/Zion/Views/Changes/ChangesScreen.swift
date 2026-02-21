import SwiftUI

struct ChangesScreen: View {
    var model: RepositoryViewModel

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

    // MARK: - File List

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
                    model.stageAllFiles()
                } label: {
                    Label(L10n("Stage All"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered).controlSize(.mini)
                .help(L10n("Adicionar todos ao stage"))

                Button {
                    model.unstageAllFiles()
                } label: {
                    Label(L10n("Unstage All"), systemImage: "minus.circle.fill")
                }
                .buttonStyle(.bordered).controlSize(.mini)
                .help(L10n("Remover todos do stage"))

                Button {
                    model.refreshRepository()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.plain).cursorArrow().help(L10n("Atualizar"))
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
        let isStaged = indexStatus != " " && indexStatus != "?"

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

                if isStaged {
                    Text(L10n("Staged"))
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
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
        .contextMenu {
            Button {
                model.stageFile(file)
            } label: {
                Label(L10n("Stage"), systemImage: "plus.circle")
            }
            Button {
                model.unstageFile(file)
            } label: {
                Label(L10n("Unstage"), systemImage: "minus.circle")
            }
            Divider()
            Button {
                model.openFileInEditor(relativePath: file)
            } label: {
                Label(L10n("Abrir no Editor"), systemImage: "pencil.and.outline")
            }
            Divider()
            Button(role: .destructive) {
                model.discardChanges(in: file)
            } label: {
                Label(L10n("Descartar Mudanças"), systemImage: "trash")
            }
        }
    }

    // MARK: - Diff Viewer

    private var diffViewerPane: some View {
        GlassCard(spacing: 0) {
            if let file = model.selectedChangeFile {
                diffHeader(file: file)

                Divider()

                if !model.currentFileDiffHunks.isEmpty {
                    HunkDiffView(model: model, file: file, hunks: model.currentFileDiffHunks)
                } else {
                    // Fallback to raw diff display
                    rawDiffView
                }
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

    private func diffHeader(file: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
                Text(file).font(.system(.subheadline, design: .monospaced)).fontWeight(.bold)
                Spacer()
                if model.isAIConfigured {
                    Button {
                        model.explainDiffDetailed(fileName: file, diff: model.currentFileDiff)
                    } label: {
                        if model.isExplainingDiff {
                            ProgressView().controlSize(.small).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(model.isExplainingDiff)
                    .help(L10n("Explicar diff com IA"))
                }
                Button {
                    model.unstageFile(file)
                } label: {
                    Label(L10n("Unstage"), systemImage: "minus")
                }.buttonStyle(.bordered).controlSize(.small)
                Button {
                    model.stageFile(file)
                } label: {
                    Label(L10n("Stage"), systemImage: "plus")
                }.buttonStyle(.bordered).controlSize(.small)
            }
            .padding(12)

            // Detailed diff explanation card (Phase 2)
            if let explanation = model.currentDiffExplanation {
                DiffExplanationCard(explanation: explanation) {
                    model.currentDiffExplanation = nil
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            } else if model.isExplainingDiff {
                DiffExplanationShimmer()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else if !model.aiDiffExplanation.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple)
                    Text(model.aiDiffExplanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        model.aiDiffExplanation = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .cursorArrow()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
    }

    private var rawDiffView: some View {
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

    // MARK: - Helpers

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
