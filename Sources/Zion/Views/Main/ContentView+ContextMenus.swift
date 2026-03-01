import SwiftUI

extension ContentView {

    func performGitAction(title: String, message: String, destructive: Bool = false, action: @escaping () -> Void) {
        if shouldConfirmAction(destructive: destructive) {
            let alert = NSAlert()
            alert.alertStyle = destructive ? .warning : .informational
            alert.messageText = title; alert.informativeText = message
            alert.addButton(withTitle: destructive ? L10n("Confirmar") : L10n("Continuar")); alert.addButton(withTitle: L10n("Cancelar"))
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        action()
    }

    func shouldConfirmAction(destructive: Bool) -> Bool {
        let mode = ConfirmationMode(rawValue: confirmationModeRaw) ?? .destructiveOnly
        switch mode {
        case .never: return false
        case .destructiveOnly: return destructive
        case .all: return true
        }
    }

    @ViewBuilder
    func commitContextMenu(for commit: Commit) -> some View {
        let isStash = commit.decorations.contains { $0.contains("refs/stash") }

        if isStash {
            Button(L10n("Apply Stash")) {
                performGitAction(title: L10n("Apply Stash"), message: L10n("Aplicar as mudancas deste stash na branch atual?"), destructive: false) {
                    model.selectedStash = commit.id // Use the hash
                    model.applySelectedStash()
                }
            }
            Button(L10n("Pop Stash")) {
                performGitAction(title: L10n("Pop Stash"), message: L10n("Aplicar as mudancas deste stash e REMOVER da lista?"), destructive: false) {
                    model.selectedStash = commit.id // Use the hash
                    model.popSelectedStash()
                }
            }
            Divider()
            Button(L10n("Drop Stash"), role: .destructive) {
                performGitAction(title: L10n("Drop Stash"), message: L10n("Remover permanentemente este stash?"), destructive: true) {
                    model.selectedStash = commit.id // Use the hash
                    model.dropSelectedStash()
                }
            }
            Divider()
            Button(L10n("Checkout Stash (Inspecionar)")) {
                model.checkout(reference: commit.id)
            }
        } else {
            Button(L10n("Reset Branch to here (Soft)")) {
                performGitAction(title: L10n("Reset --soft"), message: L10n("Resetar a branch atual para este commit mantendo as mudancas no stage?"), destructive: true) {
                    model.resetToCommit(commit.id, shouldHardReset: false)
                }
            }
            Button(L10n("Reset Branch to here (Hard)"), role: .destructive) {
                performGitAction(title: L10n("Reset --hard"), message: L10n("AVISO: Isso apagara todas as mudancas nao salvas. Continuar?"), destructive: true) {
                    model.resetToCommit(commit.id, shouldHardReset: true)
                }
            }
            Divider()
            Button(L10n("Adicionar Tag...")) { if let name = promptForText(title: L10n("Nova tag"), message: L10n("Nome:"), defaultValue: "v") { model.createTag(named: name, at: commit.id) } }
            Button(L10n("Criar Branch...")) { if let res = promptForBranchCreation(from: commit.shortHash) { model.createBranch(named: res.name, from: commit.id, andCheckout: res.checkout) } }
            Divider()
            Button(L10n("Cherry-pick")) {
                performGitAction(title: L10n("Cherry-pick"), message: L10n("Aplicar este commit na branch atual?"), destructive: false) {
                    model.cherryPick(commitHash: commit.id)
                }
            }
            Button(L10n("Revert")) {
                performGitAction(title: L10n("Revert"), message: L10n("Reverter este commit criando um novo commit?"), destructive: false) {
                    model.revert(commitHash: commit.id)
                }
            }
            Divider()
            Button(L10n("Rebase Interativo a partir daqui...")) {
                model.prepareInteractiveRebase(from: commit.id)
            }
        }

        Divider()
        Button(L10n("Copiar Assunto")) { copyToPasteboard(commit.subject) }
        Button(L10n("Copiar Hash")) { copyToPasteboard(commit.id) }
    }

    @ViewBuilder
    func branchContextMenu(for branch: String) -> some View {
        Button(L10n("Copiar Nome da Branch")) { copyToPasteboard(branch) }
        Divider()
        Button(L10n("Checkout")) { model.checkout(reference: branch) }

        let info = model.branchInfo(named: branch)
        let isRemote = info?.isRemote ?? (branch.contains("/") && !branch.hasPrefix("feature/") && !branch.hasPrefix("bugfix/"))

        if isRemote {
            Button(L10n("Pull")) { model.pullIntoCurrent(fromRemoteBranch: branch) }
        } else if let upstream = info?.upstream, !upstream.isEmpty {
            Button(L10n("Pull")) { model.pullIntoCurrent(fromRemoteBranch: upstream) }
        }

        Button(L10n("Merge into Current")) {
            performGitAction(title: L10n("Merge into Current"), message: L10n("Fazer merge da branch informada na atual?"), destructive: false) {
                model.mergeBranch(named: branch)
            }
        }
        Button(L10n("Rebase Current onto This")) {
            performGitAction(title: L10n("Rebase Current onto This"), message: L10n("Rebasear a branch atual no target informado?"), destructive: true) {
                model.rebaseCurrentBranch(onto: branch)
            }
        }
        Divider()
        Button(L10n("New Branch")) {
            if let res = promptForBranchCreation(from: branch) {
                model.createBranch(named: res.name, from: branch, andCheckout: res.checkout)
            }
        }
        Divider()

        if !isRemote {
            Button(L10n("Criar Pull Request...")) {
                model.isPRSheetVisible = true
            }
        }

        if model.isAIConfigured {
            Divider()
            Button {
                model.summarizeBranch(branch)
            } label: {
                if model.isGeneratingAIMessage {
                    Label(L10n("Resumindo..."), systemImage: "sparkles")
                } else if let summary = model.branchSummaries[branch] {
                    Label(summary, systemImage: "sparkles")
                } else {
                    Label(L10n("Resumir com IA"), systemImage: "sparkles")
                }
            }
            .disabled(model.isGeneratingAIMessage)
        }

        Divider()

        if isRemote {
            Button(L10n("Remover branch remota"), role: .destructive) {
                performGitAction(title: L10n("Remover branch remota"), message: String(format: L10n("Deseja remover permanentemente a branch remota %@?"), branch), destructive: true) {
                    model.deleteRemoteBranch(reference: branch)
                }
            }
        } else {
            Button(L10n("Push to Remote")) {
                model.pushBranch(branch, to: "origin", setUpstream: true, mode: .normal)
            }
            Divider()
            Button(L10n("Remover branch local"), role: .destructive) {
                performGitAction(title: L10n("Remover branch local"), message: String(format: L10n("Deseja remover a branch local %@?"), branch), destructive: true) {
                    model.deleteLocalBranch(branch, force: false)
                }
            }
            Button(L10n("Remover branch local (Force)"), role: .destructive) {
                performGitAction(title: L10n("Remover branch local (Force)"), message: String(format: L10n("Deseja remover FORCADO a branch local %@?"), branch), destructive: true) {
                    model.deleteLocalBranch(branch, force: true)
                }
            }
        }
    }

    @ViewBuilder
    func tagContextMenu(for tag: String) -> some View {
        Button(L10n("Remover tag"), role: .destructive) {
            performGitAction(title: L10n("Remover tag"), message: String(format: L10n("Deseja remover a tag informada?"), tag), destructive: true) {
                model.tagInput = tag
                model.deleteTag()
            }
        }
    }

    func copyToPasteboard(_ value: String) {
        let pb = NSPasteboard.general; pb.clearContents(); pb.setString(value, forType: .string)
    }

    func promptForText(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: L10n("OK")); alert.addButton(withTitle: L10n("Cancelar"))
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24); alert.accessoryView = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func promptForBranchCreation(from source: String) -> (name: String, checkout: Bool)? {
        let alert = NSAlert()
        alert.messageText = L10n("Nova branch")
        alert.informativeText = L10n("Nome da branch a partir de %@", source)
        alert.addButton(withTitle: L10n("Criar")); alert.addButton(withTitle: L10n("Cancelar"))
        let field = NSTextField(string: "feature/")
        let check = NSButton(checkboxWithTitle: L10n("Fazer checkout"), target: nil, action: nil); check.state = .on
        let stack = NSStackView(views: [field, check]); stack.orientation = .vertical; stack.alignment = .leading; stack.frame = NSRect(x: 0, y: 0, width: 320, height: 60); alert.accessoryView = stack
        return alert.runModal() == .alertFirstButtonReturn ? (field.stringValue, check.state == .on) : nil
    }
}
