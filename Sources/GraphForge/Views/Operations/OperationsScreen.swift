import SwiftUI
import AppKit

struct OperationsScreen: View {
    @ObservedObject var model: RepositoryViewModel
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void
    let branchContextMenu: (String) -> AnyView
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("Centro de Operacoes"))
                            .font(.system(size: 28, weight: .bold))
                        Text(L10n("Gerencie branches, tags, stashes e alteracoes de historico."))
                            .font(.subheadline)
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

                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 20) {
                        commitCard
                        branchCard
                        stashCard
                        tagsCard
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 20) {
                        historyCard
                        remotesCard
                        cleanupCard
                        resetCard
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
    }

    private var commitCard: some View {
        GlassCard(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "plus.square.on.square").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n("Novo Commit")).font(.headline)
                    Text(L10n("Gravar alteracoes no repositorio")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(spacing: 10) {
                if !model.uncommittedChanges.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n("Arquivos alterados")).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            HStack(spacing: 12) {
                                Button(L10n("Selecionar Tudo")) { model.stageAllFiles() }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                                
                                Button(L10n("Desmarcar Tudo")) { model.unstageAllFiles() }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(model.uncommittedChanges, id: \.self) { change in
                                    FileStatusRow(model: model, line: change)
                                }
                            }
                        }
                        .frame(maxHeight: 160)
                        .padding(4)
                        .background(Color.black.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                TextField(L10n("Mensagem do commit..."), text: $model.commitMessageInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))

                Button(action: {
                    performGitAction(L10n("Commit"), L10n("Deseja realizar o commit de todas as alterações?"), false) {
                        model.commit(message: model.commitMessageInput)
                    }
                }) {
                    Label(L10n("Fazer Commit"), systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.commitMessageInput.clean.isEmpty)
            }
        }
    }

    private var branchCard: some View {
        GlassCard(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n("Branches")).font(.headline)
                    Text(L10n("Checkout e integracao")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L10n("Selecionar branch ou hash..."), text: $model.branchInput)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(8).background(Color.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 10) {
                    Button(action: {
                        performGitAction(L10n("Checkout"), L10n("Fazer checkout da referencia informada?"), false) {
                            model.checkoutBranch()
                        }
                    }) {
                        Label(L10n("Checkout"), systemImage: "arrow.right.circle.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large)

                    Button(action: {
                        performGitAction(L10n("Merge"), L10n("Fazer merge da branch informada na atual?"), false) {
                            model.mergeBranch()
                        }
                    }) {
                        Label(L10n("Merge"), systemImage: "arrow.merge").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).controlSize(.large)
                }
            }

            branchListView
        }
    }

    private var branchListView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n("Branches locais/remotas")).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.branchInfos) { branch in
                        Button {
                            model.branchInput = branch.name
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    if branch.name == model.currentBranch {
                                        Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
                                    }
                                    Text(branch.name).font(.system(.caption, design: .monospaced))
                                        .fontWeight(branch.name == model.currentBranch ? .bold : .regular)
                                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    if branch.isRemote { Image(systemName: "icloud").font(.caption2).foregroundStyle(.secondary) }
                                }
                                Text("HEAD \(branch.shortHead)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onTapGesture(count: 2) {
                            performGitAction(L10n("Checkout branch"), L10n("Fazer checkout da branch %@?", branch.name), false) {
                                model.checkout(reference: branch.name)
                            }
                        }
                        .contextMenu { branchContextMenu(branch.name) }
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 180)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.09), lineWidth: 1))
        }
    }

    private var stashCard: some View {
        GlassCard(spacing: 10) {
            Label(L10n("Stash"), systemImage: "archivebox").font(.headline)
            HStack(spacing: 8) {
                TextField(L10n("mensagem do stash"), text: $model.stashMessageInput).textFieldStyle(.roundedBorder)
                Button(L10n("Criar stash")) {
                    performGitAction(L10n("Criar stash"), L10n("Salvar alteracoes locais no stash?"), false) { model.createStash() }
                }.buttonStyle(.borderedProminent)
            }
            Picker("Stash", selection: $model.selectedStash) {
                ForEach(model.stashes, id: \.self) { stash in Text(stash).tag(stash) }
            }.pickerStyle(.menu).disabled(model.stashes.isEmpty)
            HStack {
                Button(L10n("Apply")) { performGitAction(L10n("Apply stash"), L10n("Aplicar o stash selecionado?"), false) { model.applySelectedStash() } }.buttonStyle(.bordered)
                Button(L10n("Pop")) { performGitAction(L10n("Pop stash"), L10n("Aplicar e remover o stash selecionado?"), false) { model.popSelectedStash() } }.buttonStyle(.bordered)
                Button(L10n("Drop")) { performGitAction(L10n("Drop stash"), L10n("Deseja remover permanentemente o stash selecionado?"), true) { model.dropSelectedStash() } }.buttonStyle(.bordered)
            }.disabled(model.stashes.isEmpty)
        }
    }

    private var tagsCard: some View {
        GlassCard(spacing: 10) {
            Label(L10n("Tags"), systemImage: "tag").font(.headline)
            HStack(spacing: 8) {
                TextField("v1.0.0", text: $model.tagInput).textFieldStyle(.roundedBorder)
                Button(L10n("Criar")) { performGitAction(L10n("Criar tag"), L10n("Criar tag no commit atual?"), false) { model.createTag() } }.buttonStyle(.borderedProminent)
                Button(L10n("Remover")) { performGitAction(L10n("Remover tag"), L10n("Deseja remover a tag informada?"), true) { model.deleteTag() } }.buttonStyle(.bordered)
            }
        }
    }

    private var historyCard: some View {
        GlassCard(spacing: 10) {
            Label(L10n("Historico"), systemImage: "clock.arrow.circlepath").font(.headline)
            HStack(spacing: 8) {
                TextField(L10n("rebase target"), text: $model.rebaseTargetInput).textFieldStyle(.roundedBorder)
                Button(L10n("Rebase")) { performGitAction(L10n("Rebase"), L10n("Rebasear a branch atual no target informado?"), false) { model.rebaseOntoTarget() } }.buttonStyle(.borderedProminent)
            }
            HStack(spacing: 8) {
                TextField(L10n("cherry-pick hash"), text: $model.cherryPickInput).textFieldStyle(.roundedBorder)
                Button(L10n("Cherry-pick")) { performGitAction(L10n("Cherry-pick"), L10n("Aplicar o commit informado na branch atual?"), false) { model.cherryPick() } }.buttonStyle(.bordered)
            }
        }
    }

    private var remotesCard: some View {
        GlassCard(spacing: 10) {
            Label(L10n("Remotes"), systemImage: "network").font(.headline)
            
            VStack(spacing: 8) {
                HStack(spacing: 8) {
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
                }
                
                Divider().opacity(0.1)
                
                if model.remotes.isEmpty {
                    Text(L10n("Nenhum remote configurado")).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(model.remotes) { remote in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(remote.name).font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                                Text(remote.url).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                Button {
                                    model.testRemote(named: remote.name)
                                } label: {
                                    Image(systemName: " antenna.radiowaves.left.and.right").font(.caption2)
                                }.buttonStyle(.plain).foregroundStyle(.blue.opacity(0.7))
                                .help(L10n("Testar conexao"))

                                Button(role: .destructive) {
                                    performGitAction(L10n("Remover remote"), String(format: L10n("Deseja remover o remote %@?"), remote.name), true) {
                                        model.removeRemote(named: remote.name)
                                    }
                                } label: {
                                    Image(systemName: "trash").font(.caption2)
                                }.buttonStyle(.plain).foregroundStyle(.red.opacity(0.7))
                            }
                        }
                        .padding(6)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private var cleanupCard: some View {
        GlassCard(spacing: 10) {
            Label(L10n("Limpeza"), systemImage: "sparkles").font(.headline)
            Text(L10n("Remover branches locais que ja foram mescladas na main.")).font(.caption).foregroundStyle(.secondary)
            Button(action: {
                performGitAction(L10n("Prune"), L10n("Deseja remover todas as branches locais ja mescladas?"), true) {
                    model.pruneMergedBranches()
                }
            }) {
                Label(L10n("Prune Merged"), systemImage: "broom.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).controlSize(.large)
        }
    }

    private var resetCard: some View {
        GlassCard(spacing: 12) {
            HStack {
                Label(L10n("Danger Zone"), systemImage: "exclamationmark.octagon.fill").font(.headline).foregroundStyle(.red)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n("CUIDADO: Operacoes de reset descartam alteracoes.")).font(.caption).foregroundStyle(.red.opacity(0.8))
                HStack(spacing: 8) {
                    TextField("HEAD~1", text: $model.resetTargetInput).textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        performGitAction(L10n("Reset --hard"), L10n("Esta acao e IRREVERSIVEL. Deseja continuar?"), true) { model.hardReset() }
                    } label: { Label(L10n("Reset --hard"), systemImage: "trash.fill") }.buttonStyle(.borderedProminent).tint(.red)
                }
            }
        }
    }
}

struct FileStatusRow: View {
    @ObservedObject var model: RepositoryViewModel
    let line: String
    
    var body: some View {
        let (indexStatus, workTreeStatus, file) = parseGitStatus(line)
        let isStaged = indexStatus != " " && indexStatus != "?"
        
        HStack(spacing: 10) {
            Button {
                if isStaged {
                    model.unstageFile(file)
                } else {
                    model.stageFile(file)
                }
            } label: {
                statusIcon(index: indexStatus, worktree: workTreeStatus)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)

            Text(file)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isStaged ? .primary : .secondary)
            
            Spacer()
            
            if isStaged {
                Text("STAGED")
                    .font(.system(size: 7, weight: .black))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(isStaged ? 0.06 : 0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
            // Something is staged
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            // Nothing staged, show what's in worktree
            switch worktree {
            case "?":
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
            case "M":
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.orange)
            case "D":
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
            default:
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
