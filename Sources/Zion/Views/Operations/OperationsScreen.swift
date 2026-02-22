import SwiftUI
import AppKit

struct OperationsScreen: View {
    @Bindable var model: RepositoryViewModel
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
                        if model.isAIConfigured {
                            changelogCard
                            codeReviewCard
                        }
                        worktreeCard
                        SubmodulesCard(model: model)
                        RepositoryStatsCard(model: model)
                        cleanupCard
                        resetCard
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .padding(.bottom, 32)
        }
    }

    private var commitCard: some View {
        GlassCard(spacing: 12) {
            CardHeader(L10n("Novo Commit"), icon: "plus.square.on.square", subtitle: L10n("Gravar alteracoes no repositorio"))

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
                                    FileStatusRow(model: model, line: change, performGitAction: performGitAction)
                                }
                            }
                        }
                        .frame(maxHeight: 160)
                        .padding(4)
                        .background(DesignSystem.Colors.glassOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
                    }
                }

                HStack(alignment: .bottom, spacing: 8) {
                    ScrollView(.vertical) {
                        TextField(L10n("Mensagem do commit..."), text: $model.commitMessageInput, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...)
                    }
                    .frame(maxHeight: 120)
                    .padding(12)
                    .background(DesignSystem.Colors.glassInset)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignSystem.Colors.glassStroke, lineWidth: 1))

                    Button {
                        model.suggestCommitMessage()
                    } label: {
                        if model.isGeneratingAIMessage {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isGeneratingAIMessage)
                    .help(model.isAIConfigured ? L10n("Gerar mensagem com IA") : L10n("Sugerir mensagem de commit"))
                    .onChange(of: model.suggestedCommitMessage) { _, newValue in
                        if !newValue.isEmpty {
                            model.commitMessageInput = newValue
                        }
                    }
                }

                HStack {
                    Toggle(L10n("Corrigir ultimo commit (Amend)"), isOn: $model.amendLastCommit)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    Spacer()

                    if model.isAIConfigured {
                        Button {
                            model.reviewStagedChanges()
                        } label: {
                            if model.isGeneratingAIMessage && !model.isReviewVisible {
                                ProgressView().controlSize(.small).frame(width: 12, height: 12)
                            } else {
                                Label(L10n("Review"), systemImage: "sparkles")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(DesignSystem.Colors.ai)
                        .disabled(model.isGeneratingAIMessage)
                        .help(L10n("Revisar codigo com IA"))

                        Button {
                            model.suggestCommitSplit()
                        } label: {
                            if model.isGeneratingAIMessage && !model.isSplitVisible {
                                ProgressView().controlSize(.small).frame(width: 12, height: 12)
                            } else {
                                Label(L10n("Split"), systemImage: "sparkles")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(DesignSystem.Colors.commitSplit)
                        .disabled(model.isGeneratingAIMessage)
                        .help(L10n("Sugerir divisao de commits com IA"))
                    }
                }

                // AI Code Review Results
                if model.isReviewVisible && !model.aiReviewFindings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "sparkles").foregroundStyle(DesignSystem.Colors.ai)
                            Text(L10n("Code Review")).font(.system(size: 11, weight: .bold))
                            Spacer()
                            Button { model.isReviewVisible = false } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                        ForEach(model.aiReviewFindings) { finding in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: finding.severity.icon)
                                    .font(.system(size: 10))
                                    .foregroundStyle(finding.severity.color)
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 2) {
                                    if finding.file != "general" {
                                        Text(finding.file)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(finding.message)
                                        .font(.system(size: 10))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(finding.severity.color.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(finding.severity.color.opacity(0.2)))
                        }
                    }
                    .padding(10)
                    .background(DesignSystem.Colors.glassSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // AI Commit Split Suggestions
                if model.isSplitVisible && !model.aiCommitSplitSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "sparkles").foregroundStyle(DesignSystem.Colors.commitSplit)
                            Text(L10n("Sugestao de Split")).font(.system(size: 11, weight: .bold))
                            Spacer()
                            Button { model.isSplitVisible = false } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                        ForEach(model.aiCommitSplitSuggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.message)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                HStack(spacing: 4) {
                                    ForEach(suggestion.files, id: \.self) { file in
                                        Text(file)
                                            .font(.system(size: 9, design: .monospaced))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(DesignSystem.Colors.commitSplit.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DesignSystem.Colors.glassMinimal)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(10)
                    .background(DesignSystem.Colors.glassSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

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
            CardHeader(L10n("Branches"), icon: "arrow.triangle.branch", subtitle: L10n("Checkout e integracao"))

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L10n("Selecionar branch ou hash..."), text: $model.branchInput)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(8).background(DesignSystem.Colors.glassInset).clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))

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
            if model.branchInfos.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.title3).foregroundStyle(.secondary)
                    Text(L10n("Nenhuma branch encontrada")).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignSystem.Colors.glassStroke, lineWidth: 1))
            } else {
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
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignSystem.Colors.glassStroke, lineWidth: 1))
            }
        }
    }

    private var stashCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("Stash"), icon: "archivebox", subtitle: L10n("Salvar e restaurar alteracoes temporarias"))
            HStack(spacing: 8) {
                TextField(L10n("mensagem do stash"), text: $model.stashMessageInput).textFieldStyle(.roundedBorder)
                if model.isAIConfigured {
                    Button {
                        model.suggestStashMessage()
                    } label: {
                        if model.isGeneratingAIMessage {
                            ProgressView().controlSize(.small).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isGeneratingAIMessage)
                    .help(L10n("Gerar mensagem com IA"))
                }
                Button(L10n("Criar stash")) {
                    performGitAction(L10n("Criar stash"), L10n("Salvar alteracoes locais no stash?"), false) { model.createStash() }
                }.buttonStyle(.borderedProminent)
            }
            Picker(L10n("Stash"), selection: $model.selectedStash) {
                ForEach(model.stashes, id: \.self) { stash in Text(stash).tag(stash) }
            }.pickerStyle(.menu).disabled(model.stashes.isEmpty)
            HStack {
                Button(L10n("Apply")) { performGitAction(L10n("Apply stash"), L10n("Aplicar o stash selecionado?"), false) { model.applySelectedStash() } }.buttonStyle(.bordered)
                Button(L10n("Pop")) { performGitAction(L10n("Pop stash"), L10n("Aplicar e remover o stash selecionado?"), false) { model.popSelectedStash() } }.buttonStyle(.bordered)
                Button(L10n("Drop")) { performGitAction(L10n("Drop stash"), L10n("Deseja remover permanentemente o stash selecionado?"), true) { model.dropSelectedStash() } }.buttonStyle(.bordered).tint(.pink)
            }.disabled(model.stashes.isEmpty)
        }
    }

    private var tagsCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("Tags"), icon: "tag", subtitle: L10n("Marcar pontos importantes no historico"))
            HStack(spacing: 8) {
                TextField("v1.0.0", text: $model.tagInput).textFieldStyle(.roundedBorder)
                Button(L10n("Criar")) { performGitAction(L10n("Criar tag"), L10n("Criar tag no commit atual?"), false) { model.createTag() } }.buttonStyle(.borderedProminent)
                Button(L10n("Remover")) { performGitAction(L10n("Remover tag"), L10n("Deseja remover a tag informada?"), true) { model.deleteTag() } }.buttonStyle(.bordered).tint(.pink)
            }
        }
    }

    private var historyCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("Historico"), icon: "clock.arrow.circlepath", subtitle: L10n("Rebase e cherry-pick"))
            HStack(spacing: 8) {
                TextField(L10n("rebase target"), text: $model.rebaseTargetInput).textFieldStyle(.roundedBorder)
                Button(L10n("Rebase")) { performGitAction(L10n("Rebase"), L10n("Rebasear a branch atual no target informado?"), true) { model.rebaseOntoTarget() } }.buttonStyle(.bordered).tint(.orange)
            }
            HStack(spacing: 8) {
                TextField(L10n("cherry-pick hash"), text: $model.cherryPickInput).textFieldStyle(.roundedBorder)
                Button(L10n("Cherry-pick")) { performGitAction(L10n("Cherry-pick"), L10n("Aplicar o commit informado na branch atual?"), false) { model.cherryPick() } }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var remotesCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("Remotes"), icon: "network", subtitle: L10n("Repositorios remotos conectados"))
            
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
                                    Image(systemName: "antenna.radiowaves.left.and.right").font(.caption2)
                                }.buttonStyle(.plain).foregroundStyle(DesignSystem.Colors.info.opacity(0.7))
                                .help(L10n("Testar conexao"))

                                Button(role: .destructive) {
                                    performGitAction(L10n("Remover remote"), String(format: L10n("Deseja remover o remote %@?"), remote.name), true) {
                                        model.removeRemote(named: remote.name)
                                    }
                                } label: {
                                    Image(systemName: "trash").font(.caption2)
                                }.buttonStyle(.plain).foregroundStyle(DesignSystem.Colors.destructiveMuted)
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

    private var worktreeCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("Worktrees"), icon: "square.split.2x2", subtitle: L10n("Contextos paralelos")) {
                Text("\(model.worktrees.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
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
                }.buttonStyle(.borderedProminent)
                Button(L10n("Prune")) {
                    performGitAction(L10n("Prune worktrees"), L10n("Remover metadados de worktrees obsoletos?"), true) {
                        model.pruneWorktrees()
                    }
                }.buttonStyle(.bordered)
            }

            if !model.worktrees.isEmpty {
                Divider().opacity(0.1)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
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
                    }.padding(.vertical, 4)
                }.frame(maxHeight: 250)
            }
        }
    }

    private var changelogCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("Changelog"), icon: "sparkles", subtitle: L10n("Gerar notas de release com IA"))
            HStack(spacing: 8) {
                TextField(L10n("De (tag/hash)"), text: $model.changelogFromRef)
                    .textFieldStyle(.roundedBorder)
                TextField(L10n("Ate (tag/hash)"), text: $model.changelogToRef)
                    .textFieldStyle(.roundedBorder)
                Button {
                    model.generateChangelog()
                } label: {
                    if model.isGeneratingAIMessage {
                        ProgressView().controlSize(.small).frame(width: 12, height: 12)
                    } else {
                        Label(L10n("Gerar"), systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isGeneratingAIMessage)
                .help(L10n("Gerar notas de release com IA"))
            }
        }
        .sheet(isPresented: $model.isChangelogSheetVisible) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n("Changelog")).font(.title3.bold())
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.aiChangelog, forType: .string)
                    } label: {
                        Label(L10n("Copiar"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button(L10n("Fechar")) { model.isChangelogSheetVisible = false }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.escape, modifiers: [])
                }
                ScrollView {
                    Text(model.aiChangelog)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .frame(width: 550, height: 450)
        }
    }

    private var codeReviewCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("codereview.card.title"), icon: "magnifyingglass", subtitle: L10n("codereview.card.subtitle"))

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("branch.review.target"))
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $model.branchReviewTarget) {
                        Text(L10n("Selecionar...")).tag("")
                        ForEach(model.branches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .labelsHidden()
                }

                Image(systemName: "arrow.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("branch.review.source"))
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $model.branchReviewSource) {
                        Text(L10n("Selecionar...")).tag("")
                        ForEach(model.branches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .labelsHidden()
                }
            }

            Button {
                model.startCodeReview(source: model.branchReviewSource, target: model.branchReviewTarget)
            } label: {
                Label(L10n("codereview.startReview"), systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.codeReview)
            .disabled(model.branchReviewSource.isEmpty || model.branchReviewTarget.isEmpty)
            .help(L10n("codereview.startReview.hint"))
        }
    }

    private var cleanupCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("Limpeza"), icon: "leaf.fill", subtitle: L10n("Remover branches locais que ja foram mescladas na main."))
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
        GlassCard(spacing: 12, borderTint: DesignSystem.Colors.dangerBorder) {
            CardHeader(L10n("Danger Zone"), icon: "exclamationmark.octagon.fill")
                .foregroundStyle(.pink)

            Text(L10n("CUIDADO: Operacoes de reset descartam alteracoes."))
                .font(.caption)
                .foregroundStyle(.pink.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.dangerBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))

            HStack(spacing: 8) {
                TextField("HEAD~1", text: $model.resetTargetInput).textFieldStyle(.roundedBorder)
                Button(role: .destructive) {
                    performGitAction(L10n("Reset --hard"), L10n("Esta acao e IRREVERSIVEL. Deseja continuar?"), true) { model.hardReset() }
                } label: { Label(L10n("Reset --hard"), systemImage: "trash.fill") }.buttonStyle(.borderedProminent).tint(.pink)
            }
        }
        .padding(.top, 8)
    }
}

struct FileStatusRow: View {
    var model: RepositoryViewModel
    let line: String
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void
    
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
                Text(L10n("STAGED"))
                    .font(.system(size: 7, weight: .black))
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
                .foregroundStyle(DesignSystem.Colors.fileStaged)
        } else {
            // Nothing staged, show what's in worktree
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
