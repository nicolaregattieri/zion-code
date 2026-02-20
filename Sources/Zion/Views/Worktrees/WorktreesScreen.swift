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
                    HStack(spacing: 8) {
                        Image(systemName: "plus.square")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L10n("Adicionar worktree"))
                                .font(.headline)
                            Text(L10n("Defina caminho e branch opcional"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    
                    HStack(spacing: 8) {
                        TextField(L10n("/caminho/para/worktree"), text: $model.worktreePathInput)
                            .textFieldStyle(.roundedBorder)
                        TextField(L10n("branch (opcional)"), text: $model.worktreeBranchInput)
                            .textFieldStyle(.roundedBorder)
                        Button(L10n("Adicionar")) {
                            performGitAction(L10n("Adicionar worktree"), L10n("Criar o novo worktree com os parametros informados?"), false) {
                                model.addWorktree()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(L10n("Prune")) {
                            performGitAction(L10n("Prune worktrees"), L10n("Remover metadados de worktrees obsoletos?"), true) {
                                model.pruneWorktrees()
                            }
                        }
                        .buttonStyle(.bordered)
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
                                            NSWorkspace.shared.open(URL(fileURLWithPath: worktree.path))
                                        },
                                        onRemove: {
                                            performGitAction(L10n("Remover worktree"), L10n("Deseja remover o worktree %@?", worktree.path), true) {
                                                model.removeWorktreeAndCloseTerminal(worktree)
                                            }
                                        },
                                        onOpenTerminal: {
                                            model.openWorktreeTerminal(worktree)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(worktree.path)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                if worktree.isCurrent {
                    Text(L10n("ATUAL"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18))
                        .clipShape(Capsule())
                }

                Spacer()

                if let onOpenTerminal {
                    Button { onOpenTerminal() } label: {
                        Label(L10n("Terminal"), systemImage: "terminal.fill")
                    }
                    .buttonStyle(.bordered)
                }
                Button(L10n("Abrir")) { onOpen() }
                    .buttonStyle(.bordered)
                Button(L10n("Remover")) { onRemove() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }

            HStack(spacing: 12) {
                Text("\(L10n("branch")): \(worktree.branch)")
                Text("\(L10n("head")): \(worktree.head)")
                if worktree.isDetached { Text(L10n("detached")) }
                if worktree.isLocked { Text(L10n("locked")) }
                if worktree.isPrunable { Text(L10n("prunable")) }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }
}
