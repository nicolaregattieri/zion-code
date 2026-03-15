import SwiftUI

extension GraphScreen {
    var pendingChangesRow: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: commitGraphColumnWidth, height: 102)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                    .fill(showingPendingChanges ? DesignSystem.Colors.statusOrangeBg : DesignSystem.Colors.warning.opacity(0.05))
                    .frame(height: 86)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                            .stroke(showingPendingChanges ? DesignSystem.Colors.warning.opacity(0.5) : DesignSystem.Colors.warning.opacity(0.2), lineWidth: 1.5)
                    )

                HStack(spacing: 12) {
                    Image(systemName: "pencil.circle.fill").font(DesignSystem.Typography.iconLarge).foregroundStyle(DesignSystem.Colors.warning.opacity(0.8))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(L10n("Alteracoes Pendentes")).font(DesignSystem.Typography.sectionTitle).foregroundStyle(.primary.opacity(0.9))
                        Text("\(model.uncommittedCount) \(L10n("arquivos modificados"))").font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                        Button {
                            quickCommitIncludesAllChanges = false
                            isShowingQuickCommit = true
                        } label: {
                            Label(L10n("Commit"), systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.actionPrimary)
                        .controlSize(.small)
                        .sheet(isPresented: $isShowingQuickCommit) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(L10n("Criar Commit Rapido")).font(.title3.bold())

                                HStack(spacing: 8) {
                                    quickCommitScopeChip(
                                        title: L10n("Staged"),
                                        icon: "checkmark.circle.fill",
                                        isSelected: !quickCommitIncludesAllChanges
                                    ) {
                                        quickCommitIncludesAllChanges = false
                                    }
                                    quickCommitScopeChip(
                                        title: L10n("Stage All"),
                                        icon: "plus.circle.fill",
                                        isSelected: quickCommitIncludesAllChanges
                                    ) {
                                        quickCommitIncludesAllChanges = true
                                    }
                                    Spacer()
                                }
                                Text(
                                    quickCommitIncludesAllChanges
                                        ? L10n("commit.mode.allChanges.hint")
                                        : L10n("commit.mode.stagedOnly.hint")
                                )
                                .font(DesignSystem.Typography.label)
                                .foregroundStyle(.secondary)

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
                                            .frame(minHeight: 180, maxHeight: 220)

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
                                            ProgressView().controlSize(.small).frame(width: 12, height: 12)
                                        } else {
                                            Image(systemName: "sparkles").font(DesignSystem.Typography.body)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(DesignSystem.Colors.ai)
                                    .disabled(model.isGeneratingAIMessage)
                                    .help(model.isAIConfigured ? L10n("Gerar mensagem com IA") : L10n("Sugerir mensagem de commit"))
                                    .accessibilityLabel(L10n("Gerar mensagem com IA"))
                                    .onChange(of: model.suggestedCommitMessage) { _, newValue in
                                        if !newValue.isEmpty {
                                            model.commitMessageInput = newValue
                                        }
                                    }
                                }

                                if model.aiQuotaExceeded {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(DesignSystem.Typography.label)
                                            Text(L10n("Cota da API excedida. Usando sugestao local."))
                                                .font(DesignSystem.Typography.labelMedium)
                                        }

                                        SettingsLink {
                                            Label(L10n("settings.ai.recovery.openSettings"), systemImage: "gearshape")
                                                .font(DesignSystem.Typography.label)
                                        }
                                        .buttonStyle(.bordered)
                                        .simultaneousGesture(TapGesture().onEnded {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                NotificationCenter.default.post(name: .openAISettings, object: nil)
                                            }
                                        })
                                    }
                                    .foregroundStyle(DesignSystem.Colors.warning)
                                    .padding(.top, -8)
                                }

                                HStack {
                                    Button(L10n("Cancelar")) {
                                        quickCommitIncludesAllChanges = false
                                        isShowingQuickCommit = false
                                    }
                                        .buttonStyle(.bordered)
                                        .keyboardShortcut(.escape, modifiers: [])

                                    Spacer()

                                    Button(L10n("Commit")) {
                                        model.commit(
                                            message: model.commitMessageInput,
                                            scope: quickCommitIncludesAllChanges ? .allChanges : .stagedOnly
                                        )
                                        quickCommitIncludesAllChanges = false
                                        isShowingQuickCommit = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(DesignSystem.Colors.actionPrimary)
                                    .disabled(
                                        model.commitMessageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                        (!quickCommitIncludesAllChanges && !model.hasStagedChanges)
                                    )
                                    .keyboardShortcut(.return, modifiers: [.command])
                                }
                            }
                            .padding(24)
                            .frame(width: 560)
                            .frame(minHeight: 360)
                        }

                        Button {
                            isShowingCreateBranchFromPending = true
                        } label: {
                            Label(L10n("pending.createBranchHere"), systemImage: "arrow.triangle.branch")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .sheet(isPresented: $isShowingCreateBranchFromPending) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(L10n("pending.createBranchHere"))
                                    .font(.title3.bold())
                                Text(L10n("pending.createBranchHere.subtitle"))
                                    .font(DesignSystem.Typography.label)
                                    .foregroundStyle(.secondary)

                                TextField(L10n("pending.createBranch.placeholder"), text: $pendingBranchNameInput)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        createBranchFromPending()
                                    }

                                HStack {
                                    Button(L10n("Cancelar")) {
                                        isShowingCreateBranchFromPending = false
                                    }
                                    .buttonStyle(.bordered)
                                    .keyboardShortcut(.escape, modifiers: [])

                                    Spacer()

                                    Button(L10n("Criar branch")) {
                                        createBranchFromPending()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(DesignSystem.Colors.actionPrimary)
                                    .disabled(pendingBranchNameInput.clean.isEmpty)
                                    .keyboardShortcut(.return, modifiers: [])
                                }
                            }
                            .padding(24)
                            .frame(width: 420)
                        }

                        Menu {
                            pendingTransferMenuItems()
                        } label: {
                            Label(L10n("pending.copyChanges"), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        // STASH MENU - COMBINED
                        Menu {
                            Button(role: .destructive) {
                                performGitAction(
                                    L10n("Descartar Mudanças"),
                                    L10n("discardAll.confirm.current"),
                                    true
                                ) {
                                    model.discardAllChanges()
                                    showingPendingChanges = true
                                    model.selectCommit(nil)
                                }
                            } label: {
                                Label(L10n("Descartar"), systemImage: "trash.slash.fill")
                            }

                            Divider()

                            Button {
                                isShowingQuickStash = true
                            } label: {
                                Label(L10n("Criar Novo Stash"), systemImage: "plus.square.fill")
                            }

                            if !model.stashes.isEmpty {
                                Divider()
                                Button {
                                    isShowingStashList = true
                                } label: {
                                    Label(L10n("Gerenciar Stashes..."), systemImage: "list.bullet.rectangle.stack")
                                }
                            }
                        } label: {
                            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                                Image(systemName: "archivebox.fill")
                                Text(L10n("Stash"))
                                if !model.stashes.isEmpty {
                                    Text("\(model.stashes.count)")
                                        .font(DesignSystem.Typography.metaBold)
                                        .padding(.horizontal, 4)
                                        .background(DesignSystem.Colors.info.opacity(0.5))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .sheet(isPresented: $isShowingQuickStash) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(L10n("Salvar no Stash")).font(.title3.bold())
                                TextField(L10n("Mensagem do stash (opcional)"), text: $model.stashMessageInput)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        model.createStash(message: model.stashMessageInput)
                                        model.stashMessageInput = ""
                                        isShowingQuickStash = false
                                    }

                                HStack {
                                    Button(L10n("Cancelar")) { isShowingQuickStash = false }
                                        .buttonStyle(.bordered)
                                        .keyboardShortcut(.escape, modifiers: [])
                                    Spacer()
                                    Button(L10n("Salvar")) {
                                        model.createStash(message: model.stashMessageInput)
                                        model.stashMessageInput = ""
                                        isShowingQuickStash = false
                                    }.buttonStyle(.borderedProminent)
                                    .tint(DesignSystem.Colors.actionPrimary)
                                    .keyboardShortcut(.return, modifiers: [])
                                }
                            }
                            .padding(24).frame(width: 400)
                        }
                        .sheet(isPresented: $isShowingStashList) {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Text(L10n("Stashes Recentes")).font(.title3.bold())
                                    Spacer()
                                    Button(L10n("Fechar")) { isShowingStashList = false }.buttonStyle(.bordered).keyboardShortcut(.escape, modifiers: [])
                                }

                                ScrollView {
                                    VStack(spacing: 10) {
                                        ForEach(model.stashes, id: \.self) { stash in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(stash).font(DesignSystem.Typography.monoBody).lineLimit(2)
                                                }
                                                Spacer()
                                                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                                                    Button(L10n("Apply")) { model.selectedStash = stash; model.applySelectedStash(); isShowingStashList = false }.buttonStyle(.bordered).controlSize(.small)
                                                    Button(L10n("Pop")) { model.selectedStash = stash; model.popSelectedStash(); isShowingStashList = false }.buttonStyle(.bordered).controlSize(.small)
                                                    Button { model.selectedStash = stash; model.dropSelectedStash() } label: { Image(systemName: "trash") }.buttonStyle(.bordered).tint(DesignSystem.Colors.destructive).controlSize(.small).accessibilityLabel(L10n("Drop Stash"))
                                                }
                                            }
                                            .padding(10).background(DesignSystem.Colors.glassSubtle).cornerRadius(DesignSystem.Spacing.elementCornerRadius)
                                        }
                                    }
                                }.frame(maxHeight: 400)
                            }
                            .padding(24).frame(width: 550)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 102)
        .contentShape(Rectangle())
        .onTapGesture {
            showingPendingChanges = true
            model.selectCommit(nil)
        }
        .contextMenu {
            Button {
                isShowingCreateBranchFromPending = true
            } label: {
                Label(L10n("pending.createBranchHere"), systemImage: "arrow.triangle.branch")
            }

            Divider()

            pendingTransferMenuItems()

            Divider()

            Button(role: .destructive) {
                performGitAction(
                    L10n("Descartar Mudanças"),
                    L10n("discardAll.confirm.current"),
                    true
                ) {
                    model.discardAllChanges()
                    showingPendingChanges = true
                    model.selectCommit(nil)
                }
            } label: {
                Label(L10n("Descartar"), systemImage: "trash.slash.fill")
            }
        }
    }

    var nonCurrentWorktrees: [WorktreeItem] {
        model.worktrees.filter { !$0.isCurrent }
    }

    func createBranchFromPending() {
        let branchName = pendingBranchNameInput.clean
        guard !branchName.isEmpty else { return }
        model.createBranch(named: branchName, from: "HEAD", andCheckout: true)
        pendingBranchNameInput = ""
        isShowingCreateBranchFromPending = false
        showingPendingChanges = true
        model.selectCommit(nil)
    }

    @ViewBuilder
    func pendingTransferMenuItems() -> some View {
        if nonCurrentWorktrees.isEmpty {
            Button(L10n("pending.transfer.noWorktrees")) {}
                .disabled(true)
        } else {
            Menu(L10n("pending.transfer.copy")) {
                ForEach(nonCurrentWorktrees) { worktree in
                    Button(worktree.branch.isEmpty ? URL(fileURLWithPath: worktree.path).lastPathComponent : worktree.branch) {
                        transferPendingChanges(to: worktree, keepInCurrentWorktree: true)
                    }
                }
            }

            Divider()

            Menu(L10n("pending.transfer.move")) {
                ForEach(nonCurrentWorktrees) { worktree in
                    Button(worktree.branch.isEmpty ? URL(fileURLWithPath: worktree.path).lastPathComponent : worktree.branch) {
                        transferPendingChanges(to: worktree, keepInCurrentWorktree: false)
                    }
                }
            }
        }
    }

    func transferPendingChanges(to worktree: WorktreeItem, keepInCurrentWorktree: Bool) {
        let performTransfer = {
            model.transferPendingChanges(toWorktree: worktree, keepInCurrentWorktree: keepInCurrentWorktree)
            showingPendingChanges = true
            model.selectCommit(nil)
        }

        if keepInCurrentWorktree {
            performTransfer()
            return
        }

        let targetName = worktree.branch.isEmpty ? URL(fileURLWithPath: worktree.path).lastPathComponent : worktree.branch
        performGitAction(
            L10n("pending.transfer.move.short"),
            L10n("pending.transfer.move.confirm", targetName),
            true
        ) {
            performTransfer()
        }
    }
}
