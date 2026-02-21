import SwiftUI

struct ConflictResolutionScreen: View {
    @Bindable var model: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var splitRatio: CGFloat = 0.25

    var body: some View {
        VStack(spacing: 0) {
            header
            DraggableSplitView(
                axis: .horizontal,
                ratio: $splitRatio,
                minLeading: 240,
                minTrailing: 500
            ) {
                fileListPane
            } trailing: {
                conflictViewerPane
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Resolver Conflitos"))
                    .font(.headline)
                if !model.activeOperationLabel.isEmpty {
                    Text(model.activeOperationLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            if model.allConflictsResolved {
                Label(L10n("Todos os conflitos resolvidos!"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("\(model.unresolvedConflictCount) \(L10n("conflitos restantes"))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DesignSystem.Colors.glassOverlay)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - File List

    private var fileListPane: some View {
        VStack(spacing: 0) {
            GlassCard {
                CardHeader(L10n("Conflitos"), icon: "exclamationmark.triangle.fill",
                           subtitle: "\(model.conflictedFiles.count) \(L10n("arquivos"))")

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.conflictedFiles) { file in
                            conflictFileRow(file)
                        }
                    }
                }

                if model.allConflictsResolved {
                    continueButton
                }
            }
            .padding(8)
        }
    }

    private func conflictFileRow(_ file: ConflictFile) -> some View {
        Button {
            if !file.isResolved {
                model.selectConflictFile(file.path)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: file.isResolved ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(file.isResolved ? .green : .red)
                Text(file.path)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                model.selectedConflictFile == file.path
                    ? Color.accentColor.opacity(0.15)
                    : (file.isResolved ? Color.green.opacity(0.05) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        Button {
            model.continueAfterResolution()
        } label: {
            HStack {
                Image(systemName: "play.fill")
                if model.isMerging {
                    Text(L10n("Continuar Merge"))
                } else if model.isRebasing {
                    Text(L10n("Continuar Rebase"))
                } else {
                    Text(L10n("Continuar"))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(.green)
    }

    // MARK: - Conflict Viewer

    private var conflictViewerPane: some View {
        VStack(spacing: 0) {
            if let selectedPath = model.selectedConflictFile {
                GlassCard {
                    CardHeader(selectedPath, icon: "doc.text") {
                        if model.currentFileAllRegionsChosen {
                            Button {
                                model.saveAndMarkResolved(selectedPath)
                            } label: {
                                Label(L10n("Marcar como Resolvido"), systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(.green)
                        }
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(model.conflictBlocks.enumerated()), id: \.element.id) { _, block in
                                conflictBlockView(block)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(8)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.left.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(L10n("Selecione um arquivo com conflito"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func conflictBlockView(_ block: ConflictBlock) -> some View {
        switch block {
        case .context(let lines):
            if !lines.isEmpty && !(lines.count == 1 && lines[0].isEmpty) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .foregroundStyle(.secondary.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 1)
                    }
                }
            }
        case .conflict(let region):
            let idx = conflictRegionIndex(for: region.id)
            ConflictRegionCard(
                region: region,
                index: idx,
                fileName: model.selectedConflictFile ?? "",
                onChoose: { choice in
                    model.resolveRegion(region.id, choice: choice)
                },
                model: model
            )
        }
    }

    private func conflictRegionIndex(for id: UUID) -> Int {
        var idx = 0
        for block in model.conflictBlocks {
            if case .conflict(let r) = block {
                if r.id == id { return idx }
                idx += 1
            }
        }
        return 0
    }
}
