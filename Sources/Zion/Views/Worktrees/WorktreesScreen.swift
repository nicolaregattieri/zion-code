import SwiftUI
import AppKit

struct WorktreesScreen: View {
    @Bindable var model: RepositoryViewModel
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n("Worktrees"))
                            .font(.title2.weight(.semibold))
                        Text(L10n("Gerencie contextos paralelos sem trocar branch no diretorio principal."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                GlassCard(spacing: 10) {
                    HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                        Image(systemName: "plus.square")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L10n("worktree.smart.new"))
                                .font(.headline)
                            Text(L10n("worktree.smart.subtitle"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

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
                            performGitAction(L10n("Adicionar worktree"), L10n("worktree.smart.confirm"), false) {
                                model.smartCreateWorktree()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.actionPrimary)
                        .disabled(!model.canSmartCreateWorktree)

                        Button(L10n("Prune")) {
                            performGitAction(L10n("Prune worktrees"), L10n("Remover metadados de worktrees obsoletos?"), true) {
                                model.pruneWorktrees()
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if !model.derivedWorktreeBranch.isEmpty || !model.derivedWorktreePath.isEmpty {
                        HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                            if !model.derivedWorktreeBranch.isEmpty {
                                Text("branch: \(model.derivedWorktreeBranch)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if !model.derivedWorktreePath.isEmpty {
                                Text(model.derivedWorktreePath)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
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
                        .font(.system(size: 10, weight: .semibold))
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

                GlassCard(spacing: 10) {
                    HStack {
                        Text(L10n("Worktrees disponiveis"))
                            .font(.headline)
                        Spacer()
                        Text("\(model.worktrees.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if model.worktrees.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "square.split.2x2")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                    Text(L10n("Nenhum worktree encontrado"))
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 26)
                            } else {
                                ForEach(model.worktrees) { worktree in
                                    WorktreeCardView(
                                        worktree: worktree,
                                        onOpen: {
                                            model.openWorktreeInZion(worktree)
                                        },
                                        onRemove: {
                                            model.requestWorktreeRemoval(worktree)
                                        },
                                        onOpenTerminal: {
                                            model.openWorktreeTerminal(worktree)
                                        },
                                        onRevealInFinder: {
                                            NSWorkspace.shared.open(URL(fileURLWithPath: worktree.path))
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WorktreeCardView: View {
    let worktree: WorktreeItem
    let onOpen: () -> Void
    let onRemove: () -> Void
    var onOpenTerminal: (() -> Void)? = nil
    var onRevealInFinder: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(worktree.path)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                if worktree.isMainWorktree {
                    Text(L10n("worktree.main.badge"))
                        .font(DesignSystem.Typography.monoMeta)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.success.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
                        .foregroundStyle(DesignSystem.Colors.success)
                        .help(L10n("worktree.main.hint"))
                }

                if worktree.isCurrent {
                    Text(L10n("ATUAL"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.selectionBackground)
                        .clipShape(Capsule())
                }

                Spacer()

                if let onOpenTerminal {
                    Button { onOpenTerminal() } label: {
                        Label(L10n("Terminal"), systemImage: "terminal.fill")
                    }
                    .buttonStyle(.bordered)
                }
                Button(L10n("Abrir no Zion Code")) { onOpen() }
                    .buttonStyle(.bordered)
                if let onRevealInFinder {
                    Menu {
                        Button(L10n("Abrir")) { onRevealInFinder() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                }
                if !worktree.isMainWorktree {
                    Button(L10n("Remover")) { onRemove() }
                        .buttonStyle(.bordered)
                        .tint(DesignSystem.Colors.destructive)
                }
            }

            HStack(spacing: 12) {
                Text("\(L10n("branch")): \(worktree.branch)")
                Text("\(L10n("head")): \(worktree.head)")
                Text("● \(worktree.uncommittedCount)")
                if worktree.hasConflicts { Text("⚠") }
                if worktree.isDetached { Text(L10n("detached")) }
                if worktree.isLocked { Text(L10n("locked")) }
                if worktree.isPrunable { Text(L10n("prunable")) }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(DesignSystem.Colors.glassElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
        )
    }
}
