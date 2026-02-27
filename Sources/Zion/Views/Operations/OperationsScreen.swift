import SwiftUI
import AppKit

struct OperationsScreen: View {
    @Bindable var model: RepositoryViewModel
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void
    let branchContextMenu: (String) -> AnyView
    @Environment(\.zionModeEnabled) private var zionModeEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("Centro de Operacoes"))
                            .font(DesignSystem.Typography.screenTitle)
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

                commitCard

                SectionLabel(title: L10n("Operacoes Principais"), icon: "arrow.triangle.turn.up.right.diamond")
                adaptivePair {
                    branchCard
                } right: {
                    historyCard
                }

                SectionLabel(title: L10n("Snapshots"), icon: "camera")
                VStack(alignment: .leading, spacing: 12) {
                    adaptivePair {
                        stashCard
                    } right: {
                        tagsCard
                    }
                    recoveryVaultCard
                }

                SectionLabel(title: L10n("Infraestrutura"), icon: "network")
                adaptivePair {
                    remotesCard
                } right: {
                    worktreeCard
                }

                if model.isAIConfigured {
                    SectionLabel(title: L10n("Inteligencia Artificial"), icon: "sparkles")
                    adaptivePair {
                        changelogCard
                    } right: {
                        codeReviewCard
                    }
                }

                SectionLabel(title: L10n("Informacoes"), icon: "info.circle")
                adaptivePair {
                    SubmodulesCard(model: model)
                } right: {
                    RepositoryStatsCard(model: model)
                }

                SectionLabel(title: L10n("Manutencao"), icon: "wrench.and.screwdriver")
                maintenanceCard
            }
            .padding(DesignSystem.Spacing.screenEdge)
            .padding(.bottom, DesignSystem.Spacing.cardPadding)
            .frame(maxWidth: DesignSystem.Layout.operationsContentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func adaptivePair<Left: View, Right: View>(
        spacing: CGFloat = DesignSystem.Spacing.sectionGap,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                left()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                right()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: spacing) {
                left()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                right()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
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
                                    .font(DesignSystem.Typography.labelBold)
                                    .foregroundStyle(Color.accentColor)
                                
                                Button(L10n("Desmarcar Tudo")) { model.unstageAllFiles() }
                                    .buttonStyle(.plain)
                                    .font(DesignSystem.Typography.labelBold)
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
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $model.commitMessageInput)
                            .font(DesignSystem.Typography.monoBody)
                            .lineSpacing(4)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(DesignSystem.Colors.glassInset)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                                    .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
                            )
                            .frame(minHeight: 130, maxHeight: 170)

                        if model.commitMessageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(L10n("Mensagem do commit..."))
                                .font(DesignSystem.Typography.monoBody)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                    }

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
                    .tint(DesignSystem.Colors.ai)
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
                                    .font(DesignSystem.Typography.labelBold)
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
                                    .font(DesignSystem.Typography.labelBold)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(DesignSystem.Colors.ai)
                        .disabled(model.isGeneratingAIMessage)
                        .help(L10n("Sugerir divisao de commits com IA"))
                    }
                }

                if zionModeEnabled && model.isGeneratingAIMessage {
                    NeonProgressLine(
                        gradient: DesignSystem.ZionMode.neonAIGradient,
                        mode: .pulse
                    )
                    .padding(.top, 4)
                    .transition(.opacity.animation(.easeOut(duration: 0.3)))
                }

                // AI Code Review Results
                if model.isReviewVisible && !model.aiReviewFindings.isEmpty {
                    ReviewFindingsView(
                        findings: model.aiReviewFindings,
                        tintColor: DesignSystem.Colors.ai,
                        onOpenFile: { file, snippet in
                            model.openFileInEditor(relativePath: file, highlightQuery: snippet)
                        },
                        onDismiss: {
                            model.isReviewVisible = false
                        }
                    )
                }

                // AI Commit Split Suggestions
                if model.isSplitVisible && !model.aiCommitSplitSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "sparkles").foregroundStyle(DesignSystem.Colors.commitSplit)
                            Text(L10n("Sugestao de Split")).font(DesignSystem.Typography.bodyMedium)
                            Spacer()
                            Button { model.isSplitVisible = false } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                        ForEach(model.aiCommitSplitSuggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.message)
                                    .font(DesignSystem.Typography.monoSmall)
                                HStack(spacing: 4) {
                                    ForEach(suggestion.files, id: \.self) { file in
                                        Text(file)
                                            .font(DesignSystem.Typography.monoMeta)
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
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                        }
                    }
                    .padding(10)
                    .background(DesignSystem.Colors.glassSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius))
                }

                // Pre-Commit Review Gate Card
                if model.preCommitReviewPending && model.isReviewVisible && !model.aiReviewFindings.isEmpty {
                    PreCommitCheckCard(model: model) {
                        model.dismissPreCommitReview()
                        performGitAction(L10n("Commit"), L10n("Deseja realizar o commit de todas as alterações?"), false) {
                            model.commit(message: model.commitMessageInput)
                        }
                    } onFixIssues: {
                        model.preCommitReviewPending = false
                    }
                }

                if model.preCommitReviewPending && model.isGeneratingAIMessage {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L10n("precommit.reviewing"))
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(DesignSystem.Colors.ai.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius))
                }

                Button(action: {
                    if model.preCommitReviewEnabled && model.isAIConfigured && !model.preCommitReviewPending {
                        model.runPreCommitReview()
                    } else if !model.preCommitReviewPending {
                        performGitAction(L10n("Commit"), L10n("Deseja realizar o commit de todas as alterações?"), false) {
                            model.commit(message: model.commitMessageInput)
                        }
                    }
                }) {
                    Label(L10n("Fazer Commit"), systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(DesignSystem.Colors.actionPrimary)
                .disabled(model.commitMessageInput.clean.isEmpty || model.preCommitReviewPending)
            }
        }
    }

    private var branchCard: some View {
        GlassCard(spacing: 12, expanding: true) {
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
                    }.buttonStyle(.borderedProminent).controlSize(.large).tint(DesignSystem.Colors.actionPrimary)

                    Button(action: {
                        performGitAction(L10n("Merge into Current"), L10n("Fazer merge da branch informada na atual?"), false) {
                            model.mergeBranch()
                        }
                    }) {
                        Label(L10n("Merge into Current"), systemImage: "arrow.merge").frame(maxWidth: .infinity)
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
                .overlay(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius).stroke(DesignSystem.Colors.glassStroke, lineWidth: 1))
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
                                            Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(DesignSystem.Colors.success)
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
                .overlay(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius).stroke(DesignSystem.Colors.glassStroke, lineWidth: 1))
            }
        }
    }

    private var stashCard: some View {
        GlassCard(spacing: 10, expanding: true) {
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
                    .tint(DesignSystem.Colors.ai)
                    .disabled(model.isGeneratingAIMessage)
                    .help(L10n("Gerar mensagem com IA"))
                }
                Button(L10n("Criar stash")) {
                    performGitAction(L10n("Criar stash"), L10n("Salvar alteracoes locais no stash?"), false) { model.createStash() }
                }.buttonStyle(.borderedProminent).tint(DesignSystem.Colors.actionPrimary)
            }
            Picker(L10n("Stash"), selection: $model.selectedStash) {
                ForEach(model.stashes, id: \.self) { stash in Text(stash).tag(stash) }
            }.pickerStyle(.menu).disabled(model.stashes.isEmpty)
            HStack {
                Button(L10n("Apply")) { performGitAction(L10n("Apply stash"), L10n("Aplicar o stash selecionado?"), false) { model.applySelectedStash() } }.buttonStyle(.bordered)
                Button(L10n("Pop")) { performGitAction(L10n("Pop stash"), L10n("Aplicar e remover o stash selecionado?"), false) { model.popSelectedStash() } }.buttonStyle(.bordered)
                Button(L10n("Drop")) {
                    performGitAction(L10n("Drop stash"), dropStashConfirmationMessage, true) { model.dropSelectedStash() }
                }.buttonStyle(.bordered).tint(DesignSystem.Colors.destructive)
            }.disabled(model.stashes.isEmpty)
        }
    }

    private var tagsCard: some View {
        GlassCard(spacing: 10, expanding: true) {
            CardHeader(L10n("Tags"), icon: "tag", subtitle: L10n("Marcar pontos importantes no historico"))
            HStack(spacing: 8) {
                TextField("v1.0.0", text: $model.tagInput).textFieldStyle(.roundedBorder)
                Button(L10n("Criar")) { performGitAction(L10n("Criar tag"), L10n("Criar tag no commit atual?"), false) { model.createTag() } }.buttonStyle(.borderedProminent).tint(DesignSystem.Colors.actionPrimary)
                Button(L10n("Remover")) { performGitAction(L10n("Remover tag"), L10n("Deseja remover a tag informada?"), true) { model.deleteTag() } }.buttonStyle(.bordered).tint(DesignSystem.Colors.destructive)
            }
        }
    }

    private var recoveryVaultCard: some View {
        GlassCard(spacing: 10, expanding: true) {
            CardHeader(L10n("recovery.title"), icon: "lifepreserver", subtitle: L10n("recovery.subtitle")) {
                Button {
                    model.refreshRecoverySnapshots(includeDangling: true)
                } label: {
                    if model.isRecoverySnapshotsLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(DesignSystem.Typography.labelBold)
                    }
                }
                .buttonStyle(.plain)
                .help(L10n("recovery.refresh"))
            }

            if !model.recoverySnapshotsStatus.clean.isEmpty {
                Text(model.recoverySnapshotsStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.recoverySnapshots.isEmpty && !model.isRecoverySnapshotsLoading {
                Text(L10n("recovery.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.recoverySnapshots.prefix(16)) { snapshot in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(snapshot.shortHash)
                                            .font(DesignSystem.Typography.monoLabelBold)
                                            .foregroundStyle(.primary)
                                        Text(L10n(snapshot.source.l10nKey))
                                            .font(DesignSystem.Typography.metaBold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(DesignSystem.Colors.glassInset)
                                            .clipShape(Capsule())
                                    }
                                    Text(snapshot.subject)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                    Text(snapshot.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 8) {
                                    Button(L10n("recovery.copy")) {
                                        model.copyRecoverySnapshotReference(snapshot)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button(L10n("recovery.restore")) {
                                        performGitAction(
                                            L10n("recovery.restore"),
                                            L10n("recovery.restore.confirm", snapshot.shortHash),
                                            true
                                        ) {
                                            model.restoreRecoverySnapshot(snapshot)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .tint(DesignSystem.Colors.actionPrimary)
                                }
                            }
                            .padding(8)
                            .background(DesignSystem.Colors.glassMinimal)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 220)
            }
        }
        .onAppear {
            if model.recoverySnapshots.isEmpty {
                model.refreshRecoverySnapshots(includeDangling: true)
            }
        }
    }

    private var historyCard: some View {
        GlassCard(spacing: 10, expanding: true) {
            CardHeader(L10n("Reescrita"), icon: "arrow.triangle.branch", subtitle: L10n("Rebase e cherry-pick"))
            HStack(spacing: 8) {
                TextField(L10n("rebase target"), text: $model.rebaseTargetInput).textFieldStyle(.roundedBorder)
                    .help(L10n("Nome da branch ou commit onde rebasear (ex: main, origin/main)"))
                Button(L10n("Rebase")) { performGitAction(L10n("Rebase"), L10n("Rebasear a branch atual no target informado?"), true) { model.rebaseOntoTarget() } }.buttonStyle(.bordered).tint(DesignSystem.Colors.warning)
                    .help(L10n("Replay seus commits em cima da branch informada"))
            }
            HStack(spacing: 8) {
                TextField(L10n("cherry-pick hash"), text: $model.cherryPickInput).textFieldStyle(.roundedBorder)
                    .help(L10n("Hash do commit a aplicar (ex: a1b2c3d)"))
                Button(L10n("Cherry-pick")) { performGitAction(L10n("Cherry-pick"), L10n("Aplicar o commit informado na branch atual?"), false) { model.cherryPick() } }.buttonStyle(.borderedProminent).tint(DesignSystem.Colors.actionPrimary)
                    .help(L10n("Copiar um commit de outra branch para a branch atual"))
            }
        }
    }

    private var remotesCard: some View {
        GlassCard(spacing: 10, expanding: true) {
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
                    .tint(DesignSystem.Colors.actionPrimary)
                }

                Divider().opacity(0.1)
                
                if model.remotes.isEmpty {
                    Text(L10n("Nenhum remote configurado")).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(model.remotes) { remote in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(remote.name).font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                                Text(remote.url).font(DesignSystem.Typography.monoMeta).foregroundStyle(.secondary).lineLimit(1)
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
        GlassCard(spacing: 10, expanding: true) {
            CardHeader(L10n("Worktrees"), icon: "square.split.2x2", subtitle: L10n("Contextos paralelos")) {
                Text("\(model.worktrees.count)")
                    .font(DesignSystem.Typography.monoLabelBold)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
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
                HStack(spacing: 10) {
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
                HStack(spacing: 8) {
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

    private var changelogCard: some View {
        GlassCard(spacing: 10, expanding: true) {
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
                .tint(DesignSystem.Colors.ai)
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
            .padding(DesignSystem.Spacing.screenEdge)
            .frame(width: 550, height: 450)
        }
    }

    private var codeReviewCard: some View {
        GlassCard(spacing: 10, expanding: true) {
            CardHeader(L10n("codereview.card.title"), icon: "magnifyingglass", subtitle: L10n("codereview.card.subtitle"))

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("branch.review.target"))
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $model.branchReviewTarget) {
                        Text(L10n("Selecionar...")).tag("")
                        if !model.localBranchOptions.isEmpty {
                            Section(L10n("branch.group.local")) {
                                ForEach(model.localBranchOptions, id: \.self) { branch in
                                    Text(branch).tag(branch)
                                }
                            }
                        }
                        if !model.remoteBranchOptions.isEmpty {
                            Section(L10n("branch.group.remote")) {
                                ForEach(model.remoteBranchOptions, id: \.self) { branch in
                                    Text(branch).tag(branch)
                                }
                            }
                        }
                        if model.localBranchOptions.isEmpty && model.remoteBranchOptions.isEmpty {
                            ForEach(model.branches, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                    }
                    .pickerStyle(.menu)
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
                        if !model.localBranchOptions.isEmpty {
                            Section(L10n("branch.group.local")) {
                                ForEach(model.localBranchOptions, id: \.self) { branch in
                                    Text(branch).tag(branch)
                                }
                            }
                        }
                        if !model.remoteBranchOptions.isEmpty {
                            Section(L10n("branch.group.remote")) {
                                ForEach(model.remoteBranchOptions, id: \.self) { branch in
                                    Text(branch).tag(branch)
                                }
                            }
                        }
                        if model.localBranchOptions.isEmpty && model.remoteBranchOptions.isEmpty {
                            ForEach(model.branches, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            if !model.branchReviewSource.isEmpty
                && !model.branchReviewTarget.isEmpty
                && model.branchReviewSource == model.branchReviewTarget {
                Text(L10n("codereview.sameBranch.inline"))
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                model.startCodeReview(source: model.branchReviewSource, target: model.branchReviewTarget)
            } label: {
                Label(L10n("codereview.startReview"), systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.ai)
            .disabled(
                model.branchReviewSource.isEmpty
                    || model.branchReviewTarget.isEmpty
                    || model.branchReviewSource == model.branchReviewTarget
            )
            .help(L10n("codereview.startReview.hint"))
            .onAppear { model.ensureBranchReviewSelections() }
        }
    }

    private var maintenanceCard: some View {
        GlassCard(spacing: 12, borderTint: DesignSystem.Colors.dangerBorder) {
            CardHeader(L10n("Limpeza"), icon: "leaf.fill", subtitle: L10n("Remover branches locais que ja foram mescladas na main."))

            Button(action: {
                performGitAction(L10n("Prune"), pruneMergedConfirmationMessage, true) {
                    model.pruneMergedBranches()
                }
            }) {
                Label(L10n("Prune Merged"), systemImage: "broom.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).controlSize(.large)

            Divider().opacity(0.3)

            CardHeader(L10n("Danger Zone"), icon: "exclamationmark.octagon.fill")
                .foregroundStyle(DesignSystem.Colors.destructive)

            Text(L10n("CUIDADO: Operacoes de reset descartam alteracoes."))
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.destructiveMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.dangerBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))

            HStack(spacing: 8) {
                TextField("HEAD~1", text: $model.resetTargetInput).textFieldStyle(.roundedBorder)
                    .help(L10n("Referencia do commit (ex: HEAD~1, hash, branch)"))
                Button(role: .destructive) {
                    performGitAction(L10n("Reset --hard"), resetHardConfirmationMessage, true) { model.hardReset() }
                } label: { Label(L10n("Reset --hard"), systemImage: "trash.fill") }.buttonStyle(.bordered).tint(DesignSystem.Colors.destructive)
                    .help(L10n("Descartar TODAS as alteracoes e voltar ao commit informado"))
            }
        }
    }

    private var resetHardConfirmationMessage: String {
        let target = model.resetTargetInput.clean.isEmpty ? "HEAD" : model.resetTargetInput.clean
        return L10n("reset.hard.confirm.withCount", target, "\(model.uncommittedCount)")
    }

    private var dropStashConfirmationMessage: String {
        let reference = model.selectedStash.clean.isEmpty ? "stash@{0}" : model.selectedStash.clean
        return L10n("stash.drop.confirm.withCount", reference, "\(model.stashes.count)")
    }

    private var pruneMergedConfirmationMessage: String {
        let count = model.mergedBranchesPreview.count
        if count == 0 {
            return L10n("prune.merged.confirm.empty")
        }
        return L10n("prune.merged.confirm.withCount", "\(count)")
    }

    private func SectionLabel(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
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
                .font(DesignSystem.Typography.monoLabel)
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
            HStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(criticalCount > 0 ? DesignSystem.Colors.destructive : DesignSystem.Colors.ai)
                Text(L10n("precommit.gate.title"))
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Button { onFixIssues() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                if criticalCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.octagon.fill").font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.destructive)
                        Text("\(criticalCount) \(L10n("Critico"))")
                            .font(DesignSystem.Typography.labelBold)
                            .foregroundStyle(DesignSystem.Colors.destructive)
                    }
                }
                if warningCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.warning)
                        Text("\(warningCount) \(L10n("Aviso"))")
                            .font(DesignSystem.Typography.labelBold)
                            .foregroundStyle(DesignSystem.Colors.warning)
                    }
                }
                if safeCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.info)
                        Text("\(safeCount) \(L10n("Sugestao"))")
                            .font(DesignSystem.Typography.labelBold)
                            .foregroundStyle(DesignSystem.Colors.info)
                    }
                }
            }

            ForEach(model.aiReviewFindings.prefix(5)) { finding in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: finding.severity.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(finding.severity.color)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        if finding.file != "general" {
                            Text(finding.file)
                                .font(DesignSystem.Typography.monoMeta)
                                .foregroundStyle(.secondary)
                        }
                        Text(finding.message)
                            .font(.system(size: 10))
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
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
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
