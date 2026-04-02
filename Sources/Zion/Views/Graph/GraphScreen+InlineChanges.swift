import SwiftUI

extension GraphScreen {
    var inlineChangesPane: some View {
        DraggableSplitView(
            axis: .vertical,
            ratio: $inlineSplitRatio,
            minLeading: DesignSystem.Layout.graphInlineSplitMinLeading,
            minTrailing: DesignSystem.Layout.graphInlineSplitMinTrailing
        ) {
            inlineFileList
                .padding(.bottom, 6)
        } trailing: {
            inlineDiffViewer
                .padding(.top, 6)
        }
    }

    var inlineFileList: some View {
        GlassCard(spacing: 0) {
            CardHeader(L10n("Changes"), icon: "pencil.circle", subtitle: "\(model.uncommittedCount) \(L10n("arquivos modificados"))") {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Button {
                        model.stageAllFiles()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help(L10n("Stage All"))
                    .accessibilityLabel(L10n("Stage All"))
                    .disabled(model.uncommittedChanges.isEmpty)

                    Button {
                        model.unstageAllFiles()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help(L10n("Unstage All"))
                    .accessibilityLabel(L10n("Unstage All"))
                    .disabled(!model.hasStagedChanges)

                    if model.isAIConfigured && !model.uncommittedChanges.isEmpty {
                        Button { model.summarizePendingChanges() } label: {
                            if model.isLoadingPendingChangesSummary && !model.hasVisiblePendingChangesSummary {
                                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(L10n("Resumo IA das mudancas"))
                                }
                                .font(DesignSystem.Typography.bodySmallSemibold)
                            } else {
                                Label(L10n("Resumo IA das mudancas"), systemImage: "sparkles")
                                    .font(DesignSystem.Typography.bodySmallSemibold)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(DesignSystem.Colors.ai)
                        .help(L10n("Resumo IA das mudancas"))
                        .accessibilityLabel(L10n("Resumo IA das mudancas"))
                        .disabled(model.isLoadingPendingChangesSummary)
                    }
                    Button { model.refreshRepository() } label: {
                        Image(systemName: "arrow.clockwise")
                    }.buttonStyle(.plain).cursorArrow().help(L10n("Atualizar")).accessibilityLabel(L10n("Atualizar"))
                }
            }
            .padding(12)

            if !model.uncommittedChanges.isEmpty {
                inlineChangesSummaryBar
            }

            if showPendingChangesSummaryCard {
                pendingChangesSummaryCard
            }

            Divider()
            if model.uncommittedChanges.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(DesignSystem.Typography.largeIcon).foregroundStyle(DesignSystem.Colors.success.opacity(0.6))
                    Text(L10n("Tudo limpo!")).font(DesignSystem.Typography.sheetTitle)
                    Text(L10n("Nenhuma alteração pendente no momento.")).font(DesignSystem.Typography.label).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.uncommittedChanges, id: \.self) { line in
                            inlineFileRow(line: line)
                        }
                    }.padding(8)
                }
            }
        }
    }

    func inlineFileRow(line: String) -> some View {
        let (indexStatus, workTreeStatus, file) = parseInlineGitStatus(line)
        let isSelected = model.selectedChangeFile == file
        let isHovered = hoveredInlineFilePath == file
        return Button {
            model.selectChangeFile(file)
        } label: {
            HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                inlineStatusIcon(index: indexStatus, worktree: workTreeStatus).font(DesignSystem.Typography.bodyLarge)
                Text(file).font(isSelected ? DesignSystem.Typography.monoBodyBold : DesignSystem.Typography.monoBody).lineLimit(1).truncationMode(.middle)
                Spacer()
                if indexStatus != " " && indexStatus != "?" {
                    Circle().fill(DesignSystem.Colors.fileStaged).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                    .fill(isSelected ? DesignSystem.Colors.selectionBackground : (isHovered ? DesignSystem.Colors.glassHover : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                    .stroke(isSelected ? DesignSystem.Colors.selectionBorder : (isHovered ? DesignSystem.Colors.glassBorderDark : Color.clear), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .onHover { hovering in
            hoveredInlineFilePath = hovering ? file : nil
        }
        .onNativeDoubleClick {
            model.openFileInEditor(relativePath: file)
        }
        .contextMenu {
            Button {
                model.stageFile(file)
            } label: {
                Label(L10n("Stage"), systemImage: "plus.circle")
            }
            .disabled(indexStatus != " " && indexStatus != "?")
            Button {
                model.unstageFile(file)
            } label: {
                Label(L10n("Unstage"), systemImage: "minus.circle")
            }
            .disabled(indexStatus == " " || indexStatus == "?")
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

    var inlineDiffViewer: some View {
        GlassCard(spacing: 0) {
            if let file = model.selectedChangeFile {
                let isStaged = model.statusEntry(for: file)?.isStaged ?? false
                HStack {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                    Text(file).font(DesignSystem.Typography.monoSmallBold)
                    Spacer()
                    Button { model.unstageFile(file) } label: {
                        Label(L10n("Unstage"), systemImage: "minus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isStaged)
                    Button { model.stageFile(file) } label: {
                        Label(L10n("Stage"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isStaged)
                }.padding(12)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.currentFileDiffLines.enumerated()), id: \.offset) { _, line in
                            inlineDiffLine(line)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.background(DesignSystem.Colors.glassInset)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass").font(DesignSystem.Typography.emptyStateIcon).foregroundStyle(.tertiary)
                    Text(L10n("Selecione um arquivo para ver as mudanças.")).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    func inlineDiffLine(_ line: String) -> some View {
        let backgroundColor: Color
        let textColor: Color
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            backgroundColor = DesignSystem.Colors.diffAdditionBgRaw; textColor = DesignSystem.Colors.diffAddition
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            backgroundColor = DesignSystem.Colors.diffDeletionBgRaw; textColor = DesignSystem.Colors.diffDeletion
        } else if line.hasPrefix("@@") {
            backgroundColor = DesignSystem.Colors.diffHunkHeaderBg; textColor = DesignSystem.Colors.diffHunkHeader
        } else {
            backgroundColor = Color.clear; textColor = .primary.opacity(0.8)
        }
        return Text(line).font(DesignSystem.Typography.monoBody).padding(.horizontal, 8).padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading).background(backgroundColor).foregroundStyle(textColor)
    }

    func parseInlineGitStatus(_ line: String) -> (String, String, String) {
        guard let entry = RepositoryViewModel.parsePorcelainStatusLine(line) else {
            return (" ", " ", line.trimmingCharacters(in: .whitespaces))
        }
        return (entry.indexStatus, entry.worktreeStatus, entry.path)
    }

    var showPendingChangesSummaryCard: Bool {
        model.isAIConfigured
            && !model.uncommittedChanges.isEmpty
            && (model.isLoadingPendingChangesSummary || model.hasVisiblePendingChangesSummary)
    }

    var pendingChangesSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.iconTextGap) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.iconLabelGap) {
                    Image(systemName: "sparkles")
                        .font(DesignSystem.Typography.bodySemibold)
                        .foregroundStyle(DesignSystem.Colors.ai)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n("map.ai.summary.title"))
                            .font(DesignSystem.Typography.bodySemibold)
                            .foregroundStyle(.primary)
                        if model.isLoadingPendingChangesSummary {
                            Text(L10n("Analisando mudancas..."))
                                .font(DesignSystem.Typography.bodySmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if model.isLoadingPendingChangesSummary {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    model.dismissPendingChangesSummary()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .cursorArrow()
                .help(L10n("Fechar"))
                .accessibilityLabel(L10n("accessibility.dismiss"))
            }

            if model.hasVisiblePendingChangesSummary {
                Text(model.aiPendingChangesSummary)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Button {
                    model.commitMessageInput = model.aiPendingChangesSummary
                } label: {
                    Label(L10n("Usar como mensagem de commit"), systemImage: "text.insert")
                        .font(DesignSystem.Typography.bodySmallSemibold)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.hasVisiblePendingChangesSummary)

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .fill(DesignSystem.Colors.glassSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    var inlineChangesSummaryBar: some View {
        HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
            summaryChip(
                title: L10n("changes.summary.staged"),
                count: model.stagedChangesCount,
                color: DesignSystem.Colors.fileStaged,
                icon: "checkmark.circle.fill"
            )
            summaryChip(
                title: L10n("changes.summary.pending"),
                count: model.unstagedChangesCount,
                color: DesignSystem.Colors.warning,
                icon: "pencil.circle.fill"
            )
            if model.untrackedChangesCount > 0 {
                summaryChip(
                    title: L10n("changes.summary.untracked"),
                    count: model.untrackedChangesCount,
                    color: .secondary,
                    icon: "plus.circle"
                )
            }
            Spacer()
            if model.stagedChangesCount == 0 {
                Label(L10n("changes.summary.stageHint"), systemImage: "info.circle")
                    .font(DesignSystem.Typography.metaSemibold)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    func summaryChip(title: String, count: Int, color: Color, icon: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
            Image(systemName: icon)
            Text("\(title) \(count)")
        }
        .font(DesignSystem.Typography.metaSemibold)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    func quickCommitScopeChip(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: icon)
                Text(title)
            }
            .font(DesignSystem.Typography.labelSemibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                    .fill(isSelected ? DesignSystem.Colors.selectionBackground : DesignSystem.Colors.glassSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                    .stroke(isSelected ? DesignSystem.Colors.selectionBorder : DesignSystem.Colors.glassBorderDark, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .cursorArrow()
    }

    @ViewBuilder
    func inlineStatusIcon(index: String, worktree: String) -> some View {
        if index != " " && index != "?" {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(DesignSystem.Colors.fileStaged)
        } else {
            switch worktree {
            case "?": Image(systemName: "plus.circle").foregroundStyle(.secondary)
            case "M": Image(systemName: "pencil.circle").foregroundStyle(DesignSystem.Colors.fileModified)
            case "D": Image(systemName: "minus.circle").foregroundStyle(DesignSystem.Colors.fileDeleted)
            default: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
    }
}
