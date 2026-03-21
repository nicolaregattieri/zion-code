import SwiftUI
import AppKit

// MARK: - Remotes Card

struct OpsRemotesCard: View {
    @Bindable var model: RepositoryViewModel
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void

    var body: some View {
        GlassCard(spacing: 10, expanding: true) {
            CardHeader(L10n("Remotes"), icon: "network", subtitle: L10n("Repositorios remotos conectados"))

            VStack(spacing: 8) {
                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    TextField(L10n("nome"), text: $model.remoteNameInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    TextField("URL", text: $model.remoteURLInput)
                        .textFieldStyle(.roundedBorder)
                    Button(action: {
                        model.addRemote()
                    }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.actionPrimary)
                    .accessibilityLabel(L10n("accessibility.remote.add"))
                }

                Divider().opacity(0.1)

                if model.remotes.isEmpty {
                    Text(L10n("Nenhum remote configurado")).font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                } else {
                    ForEach(model.remotes) { remote in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(remote.name).font(DesignSystem.Typography.monoLabel).fontWeight(.bold)
                                Text(remote.url).font(DesignSystem.Typography.monoMeta).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                                Button {
                                    model.testRemote(named: remote.name)
                                } label: {
                                    Image(systemName: "antenna.radiowaves.left.and.right").font(DesignSystem.Typography.meta)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(DesignSystem.Colors.info.opacity(0.7))
                                .accessibilityLabel(L10n("accessibility.remote.testConnection"))
                                .help(L10n("Testar conexao"))

                                Button(role: .destructive) {
                                    performGitAction(L10n("Remover remote"), String(format: L10n("Deseja remover o remote %@?"), remote.name), true) {
                                        model.removeRemote(named: remote.name)
                                    }
                                } label: {
                                    Image(systemName: "trash").font(DesignSystem.Typography.meta)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(DesignSystem.Colors.destructiveMuted)
                                .accessibilityLabel(L10n("accessibility.remote.delete"))
                            }
                        }
                        .padding(6)
                        .background(DesignSystem.Colors.glassMinimal)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                    }
                }
            }
        }
    }
}

// MARK: - Worktree Card

struct OpsWorktreeCard: View {
    @Bindable var model: RepositoryViewModel
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void

    var body: some View {
        GlassCard(spacing: 10, expanding: true) {
            CardHeader(L10n("Worktrees"), icon: "square.split.2x2", subtitle: L10n("Contextos paralelos")) {
                Text("\(model.worktrees.count)")
                    .font(DesignSystem.Typography.monoLabelBold)
                    .foregroundStyle(.secondary)
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
                }.buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.actionPrimary)
                    .disabled(!model.canSmartCreateWorktree)

                Button(L10n("Prune")) {
                    performGitAction(L10n("Prune worktrees"), L10n("Remover metadados de worktrees obsoletos?"), true) {
                        model.pruneWorktrees()
                    }
                }.buttonStyle(.bordered)
            }

            if !model.derivedWorktreeBranch.isEmpty || !model.derivedWorktreePath.isEmpty {
                HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                    if !model.derivedWorktreeBranch.isEmpty {
                        Text("branch: \(model.derivedWorktreeBranch)")
                            .font(DesignSystem.Typography.monoLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !model.derivedWorktreePath.isEmpty {
                        Text(model.derivedWorktreePath)
                            .font(DesignSystem.Typography.monoLabel)
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

            if !model.worktrees.isEmpty {
                Divider().opacity(0.1)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
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
                    }.padding(.vertical, 4)
                }.frame(maxHeight: 250)
            }
        }
    }
}
