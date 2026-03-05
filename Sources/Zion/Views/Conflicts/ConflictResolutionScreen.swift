import SwiftUI

struct ConflictResolutionScreen: View {
    @Bindable var model: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var splitRatio: CGFloat = 0.25
    @State private var unresolvedJumpRequestID: Int = 0
    @State private var handledUnresolvedJumpRequestID: Int = 0
    @State private var unresolvedJumpTargetFile: String?
    @State private var unresolvedJumpTargetRegionID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            DraggableSplitView(
                axis: .horizontal,
                ratio: $splitRatio,
                minLeading: DesignSystem.Layout.conflictFileListMinWidth,
                minTrailing: DesignSystem.Layout.conflictViewerMinWidth
            ) {
                fileListPane
            } trailing: {
                conflictViewerPane
            }
        }
        .frame(minWidth: DesignSystem.Layout.conflictMinWidth, minHeight: DesignSystem.Layout.conflictMinHeight)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DesignSystem.Typography.iconLarge)
                .foregroundStyle(DesignSystem.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Resolver Conflitos"))
                    .font(DesignSystem.Typography.sheetTitle)
                if !model.activeOperationLabel.isEmpty {
                    Text(model.activeOperationLabel)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            if model.allConflictsResolved {
                Label(L10n("Todos os conflitos resolvidos!"), systemImage: "checkmark.circle.fill")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.success)
            } else {
                Button {
                    jumpToNextUnresolvedConflict()
                } label: {
                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Text("\(model.unresolvedConflictCount) \(L10n("conflitos restantes"))")
                        Image(systemName: "arrow.down.forward")
                            .font(DesignSystem.Typography.metaBold)
                    }
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.warning)
                }
                .buttonStyle(.plain)
                .help(L10n("conflicts.jump.unresolved"))
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DesignSystem.Typography.sheetTitle)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel(L10n("accessibility.dismiss"))
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
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Image(systemName: file.isResolved ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(file.isResolved ? DesignSystem.Colors.success : DesignSystem.Colors.destructive)
                Text(file.path)
                    .font(DesignSystem.Typography.monoSmall)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                model.selectedConflictFile == file.path
                    ? DesignSystem.Colors.selectionBackground
                    : (file.isResolved ? DesignSystem.Colors.success.opacity(0.05) : Color.clear)
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
        .tint(DesignSystem.Colors.success)
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
                                    .font(DesignSystem.Typography.bodySmallSemibold)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(DesignSystem.Colors.success)
                        }
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(model.conflictBlocks.enumerated()), id: \.offset) { _, block in
                                    conflictBlockView(block)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onChange(of: unresolvedJumpRequestID) { _, _ in
                            scrollToFirstUnresolvedRegionIfNeeded(using: proxy)
                        }
                        .onChange(of: model.conflictBlocks.map(\.id)) { _, _ in
                            scrollToFirstUnresolvedRegionIfNeeded(using: proxy)
                        }
                        .onChange(of: model.selectedConflictFile) { _, _ in
                            scrollToFirstUnresolvedRegionIfNeeded(using: proxy)
                        }
                    }
                }
                .padding(8)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.left.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(L10n("Selecione um arquivo com conflito"))
                        .font(DesignSystem.Typography.subtitle)
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
                            .font(DesignSystem.Typography.monoSmall)
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
                    applyConflictChoice(choice, for: region.id)
                },
                model: model
            )
            .id(region.id)
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

    private func applyConflictChoice(_ choice: ConflictChoice, for regionID: UUID) {
        model.resolveRegion(regionID, choice: choice)
        guard model.currentFileAllRegionsChosen, let selectedPath = model.selectedConflictFile else {
            return
        }
        model.saveAndMarkResolved(selectedPath)
    }

    private func jumpToNextUnresolvedConflict() {
        guard let targetFile = model.unresolvedConflictSelectionCandidate(preferCurrentSelection: true) else {
            return
        }

        unresolvedJumpTargetFile = targetFile
        unresolvedJumpTargetRegionID = nil

        if targetFile != model.selectedConflictFile {
            model.selectConflictFile(targetFile)
        }

        unresolvedJumpRequestID += 1
    }

    private func scrollToFirstUnresolvedRegionIfNeeded(using proxy: ScrollViewProxy) {
        guard unresolvedJumpRequestID > handledUnresolvedJumpRequestID else {
            return
        }

        guard model.selectedConflictFile == unresolvedJumpTargetFile else {
            return
        }

        if unresolvedJumpTargetRegionID == nil {
            unresolvedJumpTargetRegionID = model.firstUndecidedRegionIDInSelectedConflictFile
        }

        guard let regionID = unresolvedJumpTargetRegionID else {
            handledUnresolvedJumpRequestID = unresolvedJumpRequestID
            unresolvedJumpTargetFile = nil
            return
        }

        handledUnresolvedJumpRequestID = unresolvedJumpRequestID
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            proxy.scrollTo(regionID, anchor: .top)
        }
        unresolvedJumpTargetFile = nil
        unresolvedJumpTargetRegionID = nil
    }
}
