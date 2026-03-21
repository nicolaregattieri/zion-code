import SwiftUI

extension SidebarView {

    var nonCurrentWorktrees: [WorktreeItem] {
        model.worktrees.filter { !$0.isCurrent }
    }

    var worktreesCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("Worktrees"), icon: "square.split.2x2") {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Text("\(nonCurrentWorktrees.count)")
                        .font(DesignSystem.Typography.labelBold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DesignSystem.Colors.brandPrimary.opacity(0.7)))
                    Button {
                        withAnimation(DesignSystem.Motion.panel) {
                            isNewWorktreeExpanded.toggle()
                        }
                    } label: {
                        Label(L10n("worktree.smart.new"), systemImage: "plus")
                            .font(DesignSystem.Typography.label)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if isNewWorktreeExpanded {
                smartWorktreeInlineForm
            }

            if nonCurrentWorktrees.isEmpty {
                Text(L10n("worktree.smart.empty"))
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(nonCurrentWorktrees) { wt in
                    worktreeRow(wt)
                }
            }
        }
        .padding(.horizontal, 10)
        .featureTourAnchor(.worktrees)
    }

    var smartWorktreeInlineForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Picker(L10n("worktree.smart.prefix"), selection: $model.worktreePrefix) {
                    ForEach(WorktreePrefix.allCases) { prefix in
                        Text(L10n(prefix.l10nKey)).tag(prefix)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                TextField(L10n("worktree.smart.name.placeholder"), text: $model.worktreeNameInput)
                    .textFieldStyle(.roundedBorder)

                Button(L10n("worktree.smart.createOpen")) {
                    model.smartCreateWorktree()
                    selectedSection = .code
                    withAnimation(DesignSystem.Motion.panel) {
                        isNewWorktreeExpanded = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.actionPrimary)
                .disabled(!model.canSmartCreateWorktree)
            }

            if !model.derivedWorktreeBranch.isEmpty || !model.derivedWorktreePath.isEmpty {
                HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                    if !model.derivedWorktreeBranch.isEmpty {
                        Text("branch: \(model.derivedWorktreeBranch)")
                            .font(DesignSystem.Typography.monoMeta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(model.derivedWorktreeBranch)
                    }
                    if !model.derivedWorktreePath.isEmpty {
                        Text(model.derivedWorktreePath)
                            .font(DesignSystem.Typography.monoMeta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(model.derivedWorktreePath)
                    }
                }
            }

            Button {
                withAnimation(DesignSystem.Motion.panel) {
                    model.isWorktreeAdvancedExpanded.toggle()
                }
            } label: {
                Label(
                    L10n("worktree.smart.advanced"),
                    systemImage: model.isWorktreeAdvancedExpanded ? "chevron.down" : "chevron.right"
                )
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if model.isWorktreeAdvancedExpanded {
                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    TextField(L10n("/caminho/para/worktree"), text: $model.worktreePathInput)
                        .textFieldStyle(.roundedBorder)
                    TextField(L10n("branch (opcional)"), text: $model.worktreeBranchInput)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                .fill(DesignSystem.Colors.glassSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
    }

    func worktreeRow(_ wt: WorktreeItem) -> some View {
        let isHovered = hoveredWorktreePath == wt.path

        return HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Button {
                model.openWorktreeInZion(
                    wt,
                    navigateToCode: false,
                    sectionAfterOpen: selectedSection
                )
            } label: {
                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                            Text(wt.branch.isEmpty ? URL(fileURLWithPath: wt.path).lastPathComponent : wt.branch)
                                .font(DesignSystem.Typography.monoBody)
                                .lineLimit(1)
                                .help(wt.branch.isEmpty ? URL(fileURLWithPath: wt.path).lastPathComponent : wt.branch)
                            if wt.isMainWorktree {
                                Text(L10n("worktree.main.badge"))
                                    .font(DesignSystem.Typography.monoMeta)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(DesignSystem.Colors.success.opacity(0.18))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
                                    .foregroundStyle(DesignSystem.Colors.success)
                                    .help(L10n("worktree.main.hint"))
                            }
                        }
                        Text(wt.path)
                            .font(DesignSystem.Typography.monoMeta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(wt.path)
                        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                            Circle()
                                .fill(worktreeStatusColor(wt))
                                .frame(width: 6, height: 6)
                            Text("\(wt.uncommittedCount)")
                                .font(DesignSystem.Typography.monoMeta)
                                .foregroundStyle(.secondary)
                            if wt.hasConflicts {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(DesignSystem.Typography.metaBold)
                                    .foregroundStyle(DesignSystem.Colors.destructive)
                                    .help(L10n("Conflitos"))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .help(L10n("Abrir no Zion Code"))

            Button {
                model.openWorktreeTerminal(wt)
            } label: {
                Image(systemName: "terminal.fill")
                    .font(DesignSystem.Typography.bodySmall)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n("Terminal"))

            if !wt.isMainWorktree {
                Button {
                    model.requestWorktreeRemoval(wt)
                } label: {
                    Image(systemName: "trash")
                        .font(DesignSystem.Typography.bodySmall)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n("Remover worktree"))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                .fill(isHovered ? DesignSystem.Colors.glassHover : DesignSystem.Colors.glassSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                .stroke(isHovered ? DesignSystem.Colors.glassStroke : DesignSystem.Colors.glassHover, lineWidth: 1)
        )
        .onHover { hovering in
            hoveredWorktreePath = hovering ? wt.path : nil
        }
    }

    func worktreeStatusColor(_ worktree: WorktreeItem) -> Color {
        if worktree.hasConflicts { return DesignSystem.Colors.destructive }
        if worktree.uncommittedCount > 0 { return DesignSystem.Colors.warning }
        return DesignSystem.Colors.success
    }

}
