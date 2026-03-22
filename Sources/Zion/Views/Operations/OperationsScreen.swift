import SwiftUI
import AppKit

struct OperationsScreen: View {
    @Bindable var model: RepositoryViewModel
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void
    let branchContextMenu: (String) -> AnyView
    @Environment(\.zionModeEnabled) private var zionModeEnabled

    var body: some View {
        GeometryReader { geo in
            let useHorizontal = geo.size.width >= 700
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n("ops.title"))
                                .font(DesignSystem.Typography.screenTitle)
                            Text(L10n("Gerencie branches, tags, stashes e alteracoes de historico."))
                                .font(DesignSystem.Typography.subtitle)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        if model.repositoryURL != nil {
                            HStack(spacing: 12) {
                                StatPill(title: L10n("Branches"), value: "\(model.branches.count)", icon: "arrow.triangle.branch")
                                StatPill(title: L10n("Stash"), value: "\(model.stashes.count)", icon: "archivebox")
                            }
                        }
                    }
                    .padding(.bottom, 10)

                    OpsCommitCard(model: model, performGitAction: performGitAction, zionModeEnabled: zionModeEnabled)

                    SectionLabel(title: L10n("Operacoes Principais"), icon: "arrow.triangle.turn.up.right.diamond")
                    adaptivePair(horizontal: useHorizontal) {
                        OpsBranchCard(model: model, performGitAction: performGitAction, branchContextMenu: branchContextMenu)
                    } right: {
                        OpsHistoryCard(model: model, performGitAction: performGitAction)
                    }

                    SectionLabel(title: L10n("Snapshots"), icon: "camera")
                    VStack(alignment: .leading, spacing: 12) {
                        adaptivePair(horizontal: useHorizontal) {
                            OpsStashCard(model: model, performGitAction: performGitAction)
                        } right: {
                            OpsTagsCard(model: model, performGitAction: performGitAction)
                        }
                        OpsRecoveryVaultCard(model: model, performGitAction: performGitAction)
                    }

                    SectionLabel(title: L10n("Infraestrutura"), icon: "network")
                    adaptivePair(horizontal: useHorizontal) {
                        OpsRemotesCard(model: model, performGitAction: performGitAction)
                    } right: {
                        OpsWorktreeCard(model: model, performGitAction: performGitAction)
                    }

                    if model.isAIConfigured {
                        SectionLabel(title: L10n("Inteligencia Artificial"), icon: "sparkles")
                        adaptivePair(horizontal: useHorizontal) {
                            OpsChangelogCard(model: model)
                        } right: {
                            OpsCodeReviewCard(model: model)
                        }
                    }

                    SectionLabel(title: L10n("Informacoes"), icon: "info.circle")
                    adaptivePair(horizontal: useHorizontal) {
                        SubmodulesCard(model: model)
                    } right: {
                        RepositoryStatsCard(model: model)
                    }

                    SectionLabel(title: L10n("Manutencao"), icon: "wrench.and.screwdriver")
                    OpsMaintenanceCard(model: model, performGitAction: performGitAction)
                }
                .padding(DesignSystem.Spacing.screenEdge)
                .padding(.bottom, DesignSystem.Spacing.cardPadding)
                .frame(maxWidth: DesignSystem.Layout.operationsContentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private func adaptivePair<Left: View, Right: View>(
        horizontal: Bool,
        spacing: CGFloat = DesignSystem.Spacing.sectionGap,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        if horizontal {
            HStack(alignment: .top, spacing: spacing) {
                left()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                right()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                left()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                right()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func SectionLabel(title: String, icon: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            Image(systemName: icon)
                .font(DesignSystem.Typography.label)
            Text(title)
                .font(DesignSystem.Typography.bodyMedium)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .foregroundStyle(.tertiary)
        .padding(.leading, 4)
        .padding(.top, 12)
    }
}

struct FileStatusRow: View {
    var model: RepositoryViewModel
    let line: String
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void

    var body: some View {
        let (indexStatus, workTreeStatus, file) = parseGitStatus(line)
        let isStaged = indexStatus != " " && indexStatus != "?"

        HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
            Button {
                if isStaged {
                    model.unstageFile(file)
                } else {
                    model.stageFile(file)
                }
            } label: {
                statusIcon(index: indexStatus, worktree: workTreeStatus)
                    .font(DesignSystem.Typography.bodyLarge)
            }
            .buttonStyle(.plain)

            Text(file)
                .font(DesignSystem.Typography.monoLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isStaged ? .primary : .secondary)

            Spacer()

            if isStaged {
                Text(L10n("STAGED"))
                    .font(DesignSystem.Typography.micro)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(DesignSystem.Colors.fileStaged.opacity(0.2))
                    .foregroundStyle(DesignSystem.Colors.fileStaged)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isStaged ? DesignSystem.Colors.glassElevated : DesignSystem.Colors.glassMinimal)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        .contextMenu {
            Button {
                model.openFileInEditor(relativePath: file)
            } label: {
                Label(L10n("Abrir no Editor"), systemImage: "pencil.and.outline")
            }
            Divider()
            Button(L10n("Descartar alteracoes"), role: .destructive) {
                performGitAction(L10n("Descartar"), L10n("Deseja reverter todas as mudancas neste arquivo? Isso nao pode ser desfeito."), true) {
                    model.discardChanges(in: file)
                }
            }
            Divider()
            Button(L10n("Adicionar ao .gitignore")) {
                model.addToGitIgnore(path: file)
            }
        }
    }

    private func parseGitStatus(_ line: String) -> (String, String, String) {
        guard let entry = RepositoryViewModel.parsePorcelainStatusLine(line) else {
            return (" ", " ", line.trimmingCharacters(in: .whitespaces))
        }
        return (entry.indexStatus, entry.worktreeStatus, entry.path)
    }

    @ViewBuilder
    private func statusIcon(index: String, worktree: String) -> some View {
        if index != " " && index != "?" {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignSystem.Colors.fileStaged)
        } else {
            switch worktree {
            case "?":
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
            case "M":
                Image(systemName: "pencil.circle")
                    .foregroundStyle(DesignSystem.Colors.fileModified)
            case "D":
                Image(systemName: "minus.circle")
                    .foregroundStyle(DesignSystem.Colors.fileDeleted)
            default:
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PreCommitCheckCard: View {
    var model: RepositoryViewModel
    let onCommitAnyway: () -> Void
    let onFixIssues: () -> Void

    private var criticalCount: Int {
        model.aiReviewFindings.filter { $0.severity == .critical }.count
    }
    private var warningCount: Int {
        model.aiReviewFindings.filter { $0.severity == .warning }.count
    }
    private var safeCount: Int {
        model.aiReviewFindings.filter { $0.severity == .suggestion }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Image(systemName: "shield.checkered")
                    .font(DesignSystem.Typography.subtitle)
                    .foregroundStyle(criticalCount > 0 ? DesignSystem.Colors.destructive : DesignSystem.Colors.ai)
                Text(L10n("precommit.gate.title"))
                    .font(DesignSystem.Typography.bodyBold)
                Spacer()
                Button { onFixIssues() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n("accessibility.dismiss"))
            }

            HStack(spacing: 12) {
                if criticalCount > 0 {
                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Image(systemName: "xmark.octagon.fill").font(DesignSystem.Typography.label)
                            .foregroundStyle(DesignSystem.Colors.destructive)
                        Text("\(criticalCount) \(L10n("Critico"))")
                            .font(DesignSystem.Typography.labelBold)
                            .foregroundStyle(DesignSystem.Colors.destructive)
                    }
                }
                if warningCount > 0 {
                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Image(systemName: "exclamationmark.triangle.fill").font(DesignSystem.Typography.label)
                            .foregroundStyle(DesignSystem.Colors.warning)
                        Text("\(warningCount) \(L10n("Aviso"))")
                            .font(DesignSystem.Typography.labelBold)
                            .foregroundStyle(DesignSystem.Colors.warning)
                    }
                }
                if safeCount > 0 {
                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Image(systemName: "checkmark.circle.fill").font(DesignSystem.Typography.label)
                            .foregroundStyle(DesignSystem.Colors.info)
                        Text("\(safeCount) \(L10n("Sugestao"))")
                            .font(DesignSystem.Typography.labelBold)
                            .foregroundStyle(DesignSystem.Colors.info)
                    }
                }
            }

            ForEach(model.aiReviewFindings.prefix(5)) { finding in
                HStack(alignment: .top, spacing: DesignSystem.Spacing.iconTextGap) {
                    Image(systemName: finding.severity.icon)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(finding.severity.color)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        if finding.file != "general" {
                            Text(finding.file)
                                .font(DesignSystem.Typography.monoMeta)
                                .foregroundStyle(.secondary)
                        }
                        Text(finding.message)
                            .font(DesignSystem.Typography.label)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(finding.severity.color.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
            }

            if model.aiReviewFindings.count > 5 {
                Text(L10n("precommit.moreFindings") + " \(model.aiReviewFindings.count - 5)")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                Button(action: onFixIssues) {
                    Label(L10n("precommit.fixIssues"), systemImage: "wrench.and.screwdriver")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(action: onCommitAnyway) {
                    Label(L10n("precommit.commitAnyway"), systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(criticalCount > 0 ? DesignSystem.Colors.warning : DesignSystem.Colors.actionPrimary)
            }
        }
        .padding(12)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius)
                .stroke(criticalCount > 0 ? DesignSystem.Colors.dangerBorder : DesignSystem.Colors.ai.opacity(0.3), lineWidth: 1)
        )
    }
}
