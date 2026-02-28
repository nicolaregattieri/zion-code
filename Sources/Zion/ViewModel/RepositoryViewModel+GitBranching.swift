import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - Checkout

    func checkout(reference: String) {
        let target = reference.clean
        guard !target.isEmpty else { return }

        // Determine local branch name if it's a remote ref
        var localName = target
        for remote in remotes {
            if target.hasPrefix("\(remote.name)/") {
                localName = String(target.dropFirst(remote.name.count + 1))
                break
            }
        }

        if localBranchExists(named: localName) {
            if let occupied = worktrees.first(where: { !$0.isCurrent && $0.branch.clean == localName }) {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = L10n("checkout.worktree.inUse.title")
                alert.informativeText = L10n("checkout.worktree.inUse.message", localName, occupied.path)
                alert.addButton(withTitle: L10n("checkout.worktree.inUse.open"))
                alert.addButton(withTitle: L10n("Cancelar"))
                if alert.runModal() == .alertFirstButtonReturn {
                    openWorktreeInZion(occupied, navigateToCode: false, sectionAfterOpen: .graph)
                    statusMessage = L10n("checkout.worktree.redirected", localName)
                }
                return
            }
            runGitAction(label: "Checkout", args: ["checkout", localName])
        } else if isRemoteRefName(target) {
            runGitAction(label: "Checkout", args: ["checkout", "-t", target])
        } else {
            runGitAction(label: "Checkout", args: ["checkout", target])
        }
    }

    func checkoutAndPull(reference: String) {
        let target = reference.clean
        guard !target.isEmpty else { return }

        actionTask?.cancel()
        isBusy = true

        let url = repositoryURL
        actionTask = Task {
            do {
                guard let url else { return }

                // 1. Determine local branch name and full remote target
                var localName = target
                var remoteTarget = target

                // Check if target is a known remote branch (e.g. origin/develop)
                for remote in remotes {
                    if target.hasPrefix("\(remote.name)/") {
                        localName = String(target.dropFirst(remote.name.count + 1))
                        remoteTarget = target
                        break
                    }
                }

                // 2. Perform Smart Checkout
                if localBranchExists(named: localName) {
                    // Already exists locally, just checkout and pull
                    let _ = try await worker.runAction(args: ["checkout", localName], in: url)
                } else if isRemoteRefName(remoteTarget) {
                    // New local branch tracking remote
                    let _ = try await worker.runAction(args: ["checkout", "-t", remoteTarget], in: url)
                } else {
                    // Fallback
                    let _ = try await worker.runAction(args: ["checkout", target], in: url)
                }

                // 3. Pull changes
                let _ = try await runActionWithCredentialRetry(
                    label: "Pull",
                    args: ["pull"],
                    in: url,
                    commandSummary: redactedGitCommandSummary(args: ["pull"])
                )

                clearError()
                statusMessage = L10n("Checkout e Pull concluídos para %@", localName)
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func pushBranch(_ branch: String, to remote: String, setUpstream: Bool, mode: PushMode) {
        let branchName = branch.clean
        let remoteName = remote.clean
        guard !branchName.isEmpty, !remoteName.isEmpty else { return }

        var args = ["push"]
        if setUpstream {
            args.append("--set-upstream")
        }
        switch mode {
        case .normal:
            break
        case .forceWithLease:
            args.append("--force-with-lease")
        case .force:
            args.append("--force")
        }
        args.append(remoteName)
        args.append("\(branchName):\(branchName)")
        runGitAction(label: "Push branch", args: args)
    }

    func checkoutBranch() {
        let target = branchInput.clean
        guard !target.isEmpty else { return }
        checkout(reference: target)
    }

    // MARK: - Branch Operations

    func createBranch() {
        let target = branchInput.clean
        guard !target.isEmpty else { return }
        createBranch(named: target, from: "HEAD", andCheckout: true)
    }

    func createBranch(named name: String, from startPoint: String, andCheckout: Bool = true) {
        let targetName = name.clean
        let targetPoint = startPoint.clean
        guard !targetName.isEmpty, !targetPoint.isEmpty else { return }
        if andCheckout {
            runGitAction(label: "Nova branch", args: ["checkout", "-b", targetName, targetPoint])
        } else {
            runGitAction(label: "Nova branch", args: ["branch", targetName, targetPoint])
        }
    }

    func mergeBranch() {
        let target = branchInput.clean
        guard !target.isEmpty else { return }
        mergeBranch(named: target)
    }

    func mergeBranch(named branch: String) {
        let target = branch.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Merge", args: ["merge", target])
    }

    func pullIntoCurrent(fromRemoteBranch remoteBranch: String) {
        let target = remoteBranch.clean
        guard !target.isEmpty else { return }
        let components = target.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard components.count == 2 else { return }
        runGitAction(label: "Pull branch", args: ["pull", String(components[0]), String(components[1])])
    }

    func deleteRemoteBranch(reference: String) {
        let target = reference.clean
        guard isRemoteRefName(target) else { return }
        let parts = target.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return }
        runGitAction(label: "Delete remote branch", args: ["push", String(parts[0]), "--delete", String(parts[1])])
    }

    func renameBranch(oldName: String, newName: String) {
        let old = oldName.clean
        let new = newName.clean
        guard !old.isEmpty, !new.isEmpty else { return }
        runGitAction(label: "Renomear branch", args: ["branch", "-m", old, new])
    }

    // MARK: - Tags

    func createTag() {
        let target = tagInput.clean
        guard !target.isEmpty else { return }
        createTag(named: target, at: "HEAD")
    }

    func createTag(named name: String, at target: String) {
        let tagName = name.clean
        let tagTarget = target.clean
        guard !tagName.isEmpty, !tagTarget.isEmpty else { return }
        runGitAction(label: "Criar tag", args: ["tag", tagName, tagTarget])
    }

    func deleteTag() {
        let target = tagInput.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Remover tag", args: ["tag", "-d", target])
    }

    // MARK: - Worktrees

    func addWorktree() {
        let path = worktreePathInput.clean
        guard !path.isEmpty else { return }

        let branch = worktreeBranchInput.clean
        addWorktree(path: path, branch: branch.isEmpty ? nil : branch)
    }

    func addWorktree(path: String, branch: String?) {
        let cleanedPath = path.clean
        guard !cleanedPath.isEmpty else { return }

        var args = ["worktree", "add", cleanedPath]
        if let branch, !branch.clean.isEmpty {
            args.append(branch.clean)
        }
        runGitAction(label: "Adicionar worktree", args: args)
    }

    func smartCreateWorktree() {
        guard let repositoryURL else { return }

        let manualPath = worktreePathInput.clean
        let manualBranch = worktreeBranchInput.clean
        let slug = worktreeNameSlug

        let resolvedBranch = manualBranch.isEmpty ? "\(worktreePrefix.rawValue)/\(slug)" : manualBranch
        let resolvedPath: String = {
            if !manualPath.isEmpty {
                return manualPath
            }
            guard !slug.isEmpty else { return "" }
            let parentDir = repositoryURL.deletingLastPathComponent()
            let repoName = repositoryURL.lastPathComponent
            let baseName = "\(repoName)-\(worktreePrefix.rawValue)-\(slug)"
            return uniquePath(forBaseName: baseName, in: parentDir).path
        }()

        guard !resolvedPath.isEmpty, !resolvedBranch.clean.isEmpty else {
            statusMessage = L10n("worktree.smart.missing")
            return
        }

        let cleanedBranch = resolvedBranch.clean
        let branchDecision: (branch: String, reuseExisting: Bool)
        if localBranchExists(named: cleanedBranch) {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = L10n("worktree.smart.branchExists.title")
            alert.informativeText = L10n("worktree.smart.branchExists.message", cleanedBranch)
            alert.addButton(withTitle: L10n("worktree.smart.branchExists.reuse"))
            alert.addButton(withTitle: L10n("worktree.smart.branchExists.createSuffix"))
            alert.addButton(withTitle: L10n("Cancelar"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                branchDecision = (cleanedBranch, true)
            } else if response == .alertSecondButtonReturn {
                branchDecision = (uniqueBranchNameForWorktree(from: cleanedBranch), false)
            } else {
                statusMessage = L10n("worktree.smart.branchExists.cancelled")
                return
            }
        } else {
            branchDecision = (cleanedBranch, false)
        }

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let addArgs: [String]
                if branchDecision.reuseExisting {
                    addArgs = ["worktree", "add", resolvedPath, branchDecision.branch]
                } else {
                    addArgs = ["worktree", "add", "-b", branchDecision.branch, resolvedPath]
                }

                let _ = try await worker.runAction(
                    args: addArgs,
                    in: repositoryURL
                )
                try Task.checkCancellation()
                clearError()
                statusMessage = L10n("worktree.smart.created", branchDecision.branch)

                worktreeNameInput = ""
                worktreePathInput = ""
                worktreeBranchInput = ""
                isWorktreeAdvancedExpanded = false

                let created = WorktreeItem(
                    path: resolvedPath,
                    head: "",
                    branch: branchDecision.branch,
                    isMainWorktree: false,
                    isDetached: false,
                    isLocked: false,
                    lockReason: "",
                    isPrunable: false,
                    pruneReason: "",
                    isCurrent: false
                )
                openWorktreeInZion(created)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func uniqueBranchNameForWorktree(from baseBranch: String) -> String {
        let base = baseBranch.clean
        guard !base.isEmpty else { return baseBranch }
        var candidate = base
        var suffix = 2
        while localBranchExists(named: candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    func removeWorktree(_ path: String, force: Bool = false) {
        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(path)
        runGitAction(label: "Remover worktree", args: args)
    }

    func openWorktreeTerminal(_ worktree: WorktreeItem) {
        let url = URL(fileURLWithPath: worktree.path)
        let label = worktree.branch.isEmpty ? url.lastPathComponent : worktree.branch
        createTerminalSession(workingDirectory: url, label: label, worktreeID: worktree.id)
    }

    func openWorktreeInZion(_ worktree: WorktreeItem, navigateToCode: Bool = true, sectionAfterOpen: AppSection? = nil) {
        let url = URL(fileURLWithPath: worktree.path)
        nextSectionAfterRepositoryOpen = sectionAfterOpen
        openRepository(url)
        let label = worktree.branch.isEmpty ? url.lastPathComponent : worktree.branch
        if let existing = terminalSessions.first(where: { $0.workingDirectory.path == url.path }) {
            activateSession(existing)
        } else {
            createTerminalSession(workingDirectory: url, label: label, worktreeID: worktree.id)
        }
        if navigateToCode {
            navigateToCodeRequested = true
        }
    }

    func discardAllChanges() {
        guard let repositoryURL else { return }
        discardAllChanges(in: repositoryURL, successMessage: L10n("discardAll.success.current"))
    }

    func discardAllChanges(inWorktree worktree: WorktreeItem) {
        let targetURL = URL(fileURLWithPath: worktree.path)
        let displayName = worktreeDisplayName(worktree)
        discardAllChanges(in: targetURL, successMessage: L10n("discardAll.success.worktree", displayName))
    }

    func transferPendingChanges(toWorktree worktree: WorktreeItem, keepInCurrentWorktree: Bool) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        let sourceURL = repositoryURL
        let targetURL = URL(fileURLWithPath: worktree.path)
        let marker = "zion-transfer-\(UUID().uuidString)"

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            var stashRef: String?
            var sourceWasStashed = false
            var sourceRecoverySucceeded = false

            do {
                let status = try await worker.runAction(args: ["status", "--porcelain"], in: sourceURL)
                if status.clean.isEmpty {
                    clearError()
                    statusMessage = L10n("pending.transfer.noChanges")
                    isBusy = false
                    return
                }

                let _ = try await worker.runAction(
                    args: ["stash", "push", "--include-untracked", "-m", marker],
                    in: sourceURL
                )
                sourceWasStashed = true

                stashRef = try await transferStashReference(marker: marker, in: sourceURL)
                guard let stashRef else {
                    throw GitClientError.commandFailed(
                        command: "stash list",
                        message: L10n("pending.transfer.error.ref")
                    )
                }

                if keepInCurrentWorktree {
                    let _ = try await worker.runAction(args: ["stash", "apply", stashRef], in: sourceURL)
                    sourceWasStashed = false
                }

                let _ = try await worker.runAction(args: ["stash", "apply", stashRef], in: targetURL)
                let _ = try await worker.runAction(args: ["stash", "drop", stashRef], in: sourceURL)

                try Task.checkCancellation()
                clearError()
                let worktreeName = worktreeDisplayName(worktree)
                statusMessage = keepInCurrentWorktree
                    ? L10n("pending.transfer.copy.success", worktreeName)
                    : L10n("pending.transfer.move.success", worktreeName)
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                if sourceWasStashed, let stashRef {
                    if (try? await worker.runAction(args: ["stash", "apply", stashRef], in: sourceURL)) != nil {
                        sourceRecoverySucceeded = true
                    }
                }
                presentPendingTransferSupportAlert(
                    targetWorktree: worktree,
                    modeLabel: keepInCurrentWorktree ? L10n("pending.transfer.copy.short") : L10n("pending.transfer.move.short"),
                    stashReference: stashRef,
                    sourceRecovered: sourceRecoverySucceeded,
                    sourceWasStashed: sourceWasStashed,
                    errorDescription: error.localizedDescription
                )
                clearError()
                statusMessage = L10n("pending.transfer.support.handled")
                isBusy = false
                logger.log(.warn, "Pending transfer requires manual resolution: \(error.localizedDescription)", source: #function)
                refreshRepository(setBusy: false)
            }
        }
    }

    func discardAllChanges(in targetURL: URL, successMessage: String) {
        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runAction(args: ["reset", "--hard", "HEAD"], in: targetURL)
                let _ = try await worker.runAction(args: ["clean", "-fd"], in: targetURL)
                try Task.checkCancellation()
                clearError()
                statusMessage = successMessage
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func requestWorktreeRemoval(_ worktree: WorktreeItem) {
        let displayName = worktreeDisplayName(worktree)

        if worktree.uncommittedCount > 0 || worktree.hasConflicts {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n("worktree.remove.pending.title")
            alert.informativeText = L10n("worktree.remove.pending.message", displayName)
            alert.addButton(withTitle: L10n("worktree.remove.discardAndRemove"))
            alert.addButton(withTitle: L10n("worktree.remove.withoutDiscard"))
            alert.addButton(withTitle: L10n("Cancelar"))

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                discardAllChangesAndRemoveWorktree(worktree)
            case .alertSecondButtonReturn:
                removeWorktreeAndCloseTerminal(worktree, force: true)
            default:
                return
            }
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n("Remover worktree")
        alert.informativeText = L10n("Deseja remover o worktree %@?", worktree.path)
        alert.addButton(withTitle: L10n("Remover"))
        alert.addButton(withTitle: L10n("Cancelar"))
        if alert.runModal() == .alertFirstButtonReturn {
            removeWorktreeAndCloseTerminal(worktree)
        }
    }

    func removeWorktreeAndCloseTerminal(_ worktree: WorktreeItem, force: Bool = false) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(worktree.path)

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runAction(args: args, in: repositoryURL)
                try Task.checkCancellation()
                closeTerminalSession(forWorktree: worktree.id)
                clearError()
                statusMessage = force
                    ? L10n("worktree.remove.forced.success", worktreeDisplayName(worktree))
                    : L10n("worktree.remove.success", worktreeDisplayName(worktree))
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func discardAllChangesAndRemoveWorktree(_ worktree: WorktreeItem) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        let targetURL = URL(fileURLWithPath: worktree.path)
        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runAction(args: ["reset", "--hard", "HEAD"], in: targetURL)
                let _ = try await worker.runAction(args: ["clean", "-fd"], in: targetURL)
                let _ = try await worker.runAction(args: ["worktree", "remove", worktree.path], in: repositoryURL)
                try Task.checkCancellation()
                closeTerminalSession(forWorktree: worktree.id)
                clearError()
                statusMessage = L10n("worktree.remove.discarded.success", worktreeDisplayName(worktree))
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func worktreeDisplayName(_ worktree: WorktreeItem) -> String {
        if !worktree.branch.clean.isEmpty {
            return worktree.branch
        }
        return URL(fileURLWithPath: worktree.path).lastPathComponent
    }

    func transferStashReference(marker: String, in repositoryURL: URL) async throws -> String? {
        let output = try await worker.runAction(args: ["stash", "list", "--format=%gD%x09%s"], in: repositoryURL)
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let ref = String(parts[0])
            let subject = String(parts[1])
            if subject == marker {
                return ref
            }
        }
        return nil
    }

    func presentPendingTransferSupportAlert(
        targetWorktree: WorktreeItem,
        modeLabel: String,
        stashReference: String?,
        sourceRecovered: Bool,
        sourceWasStashed: Bool,
        errorDescription: String
    ) {
        let targetName = worktreeDisplayName(targetWorktree)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n("pending.transfer.support.title")

        var details: [String] = [
            L10n("pending.transfer.support.message", modeLabel, targetName),
            L10n("pending.transfer.support.error", errorDescription)
        ]

        if sourceWasStashed {
            if sourceRecovered {
                details.append(L10n("pending.transfer.support.sourceRecovered"))
            } else {
                details.append(L10n("pending.transfer.support.sourceNotRecovered"))
            }
        }

        if let stashReference, !stashReference.clean.isEmpty {
            details.append(L10n("pending.transfer.support.stash", stashReference))
            details.append(L10n("pending.transfer.support.keepStash"))
        }

        if aiTransferSupportHintsEnabled {
            details.append(
                isAIConfigured
                    ? L10n("pending.transfer.support.ai.available")
                    : L10n("pending.transfer.support.ai.optional")
            )
        }

        alert.informativeText = details.joined(separator: "\n\n")
        var actions: [() -> Void] = []

        alert.addButton(withTitle: L10n("pending.transfer.support.openTarget"))
        actions.append {
            self.openTransferSupportTarget(targetWorktree, stashReference: stashReference, openConflictResolver: false)
        }

        let canUseAIAction = aiTransferSupportHintsEnabled && isAIConfigured
        if canUseAIAction {
            alert.addButton(withTitle: L10n("pending.transfer.support.openTargetAI"))
            actions.append {
                self.openTransferSupportTarget(targetWorktree, stashReference: stashReference, openConflictResolver: true)
            }
        }

        if let stashReference, !stashReference.clean.isEmpty {
            alert.addButton(withTitle: L10n("pending.transfer.support.copyStash"))
            actions.append {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(stashReference, forType: .string)
                self.statusMessage = L10n("pending.transfer.support.copied")
            }
        }

        alert.addButton(withTitle: L10n("OK"))
        actions.append {}

        let response = alert.runModal()
        let index = Int(response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
        guard index >= 0 && index < actions.count else { return }
        actions[index]()
    }

    func openTransferSupportTarget(
        _ targetWorktree: WorktreeItem,
        stashReference: String?,
        openConflictResolver: Bool
    ) {
        openWorktreeInZion(targetWorktree, navigateToCode: false, sectionAfterOpen: .operations)
        guard openConflictResolver else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.Timing.transferSupportDelay)
            guard let repositoryURL else { return }

            var sourceStashApplyError: String?
            var safetyStashApplyError: String?
            var safetyRef: String?
            if let stashReference, !stashReference.clean.isEmpty {
                let safety = "zion-ai-support-\(UUID().uuidString.prefix(8))"
                _ = try? await worker.runAction(
                    args: ["stash", "push", "--include-untracked", "-m", safety],
                    in: repositoryURL
                )
                safetyRef = try? await latestStashReference(in: repositoryURL)

                // 1) Apply incoming/source stash.
                do {
                    let _ = try await worker.runAction(args: ["stash", "apply", stashReference], in: repositoryURL)
                } catch {
                    sourceStashApplyError = error.localizedDescription
                }

                // 2) Re-apply local/safety stash to preserve local work and surface real conflicts.
                if sourceStashApplyError == nil, let safetyRef {
                    do {
                        let _ = try await worker.runAction(args: ["stash", "apply", safetyRef], in: repositoryURL)
                    } catch {
                        safetyStashApplyError = error.localizedDescription
                    }
                }
            }

            do {
                let files = try await worker.listConflictedFiles(in: repositoryURL)
                conflictedFiles = files
                if let first = files.first(where: { !$0.isResolved }) {
                    selectConflictFile(first.path)
                } else {
                    selectedConflictFile = nil
                    conflictBlocks = []
                }

                if files.isEmpty {
                    isConflictViewVisible = false
                    let blockedByLocalChanges =
                        Self.isStashApplyBlockedByLocalChanges(sourceStashApplyError)
                        || Self.isStashApplyBlockedByLocalChanges(safetyStashApplyError)

                    // NOTE (release follow-up): when two worktrees edit the same file/line, Git can block stash apply
                    // without producing unmerged (-U) entries. In that case we do not get conflict files and must
                    // guide users through local-overwrite recovery. Revisit this flow with a deterministic same-file resolver.

                    if blockedByLocalChanges {
                        presentTransferLocalCollisionAlert(
                            targetWorktree: targetWorktree,
                            incomingStashRef: stashReference,
                            safetyStashRef: safetyRef,
                            sourceError: sourceStashApplyError,
                            safetyError: safetyStashApplyError
                        )
                        statusMessage = L10n("pending.transfer.support.localCollision.status")
                    } else if sourceStashApplyError != nil || safetyStashApplyError != nil {
                        statusMessage = L10n("pending.transfer.support.ai.result.failed")
                    } else {
                        statusMessage = L10n("pending.transfer.support.ai.result.clean")
                    }
                } else {
                    isConflictViewVisible = true
                    statusMessage = L10n("pending.transfer.support.ai.result.conflicts")
                }
                refreshRepository(setBusy: false)
            } catch {
                isConflictViewVisible = false
                handleError(error)
            }
        }
    }

    func presentTransferLocalCollisionAlert(
        targetWorktree: WorktreeItem,
        incomingStashRef: String?,
        safetyStashRef: String?,
        sourceError: String?,
        safetyError: String?
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n("pending.transfer.support.localCollision.title")

        var details: [String] = [
            L10n("pending.transfer.support.localCollision.message", worktreeDisplayName(targetWorktree))
        ]
        if let sourceError, !sourceError.clean.isEmpty {
            details.append(L10n("pending.transfer.support.localCollision.incomingError", sourceError))
        }
        if let safetyError, !safetyError.clean.isEmpty {
            details.append(L10n("pending.transfer.support.localCollision.localError", safetyError))
        }
        if let safetyStashRef, !safetyStashRef.clean.isEmpty {
            details.append(L10n("pending.transfer.support.localCollision.safetyRef", safetyStashRef))
        }
        if let incomingStashRef, !incomingStashRef.clean.isEmpty {
            details.append(L10n("pending.transfer.support.localCollision.incomingRef", incomingStashRef))
        }
        alert.informativeText = details.joined(separator: "\n\n")

        alert.addButton(withTitle: L10n("pending.transfer.support.localCollision.openOps"))
        if let safetyStashRef, !safetyStashRef.clean.isEmpty {
            alert.addButton(withTitle: L10n("pending.transfer.support.localCollision.copySafety"))
            alert.addButton(withTitle: L10n("OK"))
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(safetyStashRef, forType: .string)
                statusMessage = L10n("pending.transfer.support.localCollision.copiedSafety")
            }
            return
        }
        _ = alert.runModal()
    }

    static func isStashApplyBlockedByLocalChanges(_ description: String?) -> Bool {
        guard let description else { return false }
        let normalized = description.lowercased()
        return normalized.contains("would be overwritten by merge")
            || normalized.contains("please commit your changes or stash them before you merge")
            || normalized.contains("local changes")
    }

    func latestStashReference(in repositoryURL: URL) async throws -> String? {
        let output = try await worker.runAction(args: ["stash", "list", "-1", "--format=%gD"], in: repositoryURL)
        let ref = output.clean
        return ref.isEmpty ? nil : ref
    }

    // MARK: - Quick Worktree & Prune

    func quickCreateWorktree() {
        guard let repositoryURL else { return }
        let repoName = repositoryURL.lastPathComponent
        let parentDir = repositoryURL.deletingLastPathComponent()
        var n = 1
        while FileManager.default.fileExists(atPath: parentDir.appendingPathComponent("\(repoName)-wt-\(n)").path) {
            n += 1
        }
        let wtPath = parentDir.appendingPathComponent("\(repoName)-wt-\(n)").path
        let branchName = "wt-\(n)"

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runAction(args: ["worktree", "add", "-b", branchName, wtPath], in: repositoryURL)
                try Task.checkCancellation()
                clearError()
                let wtSession = TerminalSession(workingDirectory: URL(fileURLWithPath: wtPath), label: branchName, worktreeID: wtPath)
                splitFocusedWithSession(wtSession, direction: .vertical)
                statusMessage = "Worktree criado: \(repoName)-wt-\(n)"
                refreshRepository(setBusy: true)
            } catch is CancellationError { return }
            catch { isBusy = false; handleError(error) }
        }
    }

    func pruneWorktrees() {
        runGitAction(label: "Worktree prune", args: ["worktree", "prune"])
    }

    func pruneMergeBaseRef() -> String {
        let locals = Set(localBranchOptions)
        if locals.contains("main") { return "main" }
        if locals.contains("master") { return "master" }
        if locals.contains(currentBranch) { return currentBranch }
        return "HEAD"
    }

    func computeMergedBranchesToPrune(from output: String, baseRef: String) -> [String] {
        let protectedBranches = Set(["main", "master", "develop", "dev", baseRef, currentBranch])
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: "* ", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !protectedBranches.contains($0) }
    }

    func refreshMergedBranchesPreview() {
        guard let url = repositoryURL else {
            mergedBranchesPreview = []
            return
        }
        let baseRef = pruneMergeBaseRef()
        Task {
            let output = (try? await worker.runAction(args: ["branch", "--merged", baseRef], in: url)) ?? ""
            guard self.repositoryURL?.path == url.path else { return }
            self.mergedBranchesPreview = computeMergedBranchesToPrune(from: output, baseRef: baseRef)
        }
    }

    func slugifiedWorktreeName(from input: String) -> String {
        let folded = input
            .clean
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let mapped = folded.map { character -> Character in
            if character.isLetter || character.isNumber { return character }
            return "-"
        }

        var slug = String(mapped)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        while slug.hasPrefix(".") || slug.hasSuffix(".") {
            slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        return slug
    }

    func uniquePath(forBaseName baseName: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(baseName)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(index)")
            index += 1
        }
        return candidate
    }

    func pruneMergedBranches() {
        actionTask?.cancel()
        isBusy = true

        let url = repositoryURL
        actionTask = Task {
            do {
                guard let url else { return }
                let baseRef = pruneMergeBaseRef()
                let result = try await worker.runAction(args: ["branch", "--merged", baseRef], in: url)
                let branchesToDelete = computeMergedBranchesToPrune(from: result, baseRef: baseRef)

                if branchesToDelete.isEmpty {
                    statusMessage = L10n("Nenhuma branch mesclada encontrada.")
                    isBusy = false
                    return
                }

                let _ = try await worker.runAction(args: ["branch", "-d"] + branchesToDelete, in: url)
                clearError()
                let list = branchesToDelete.joined(separator: ", ")
                statusMessage = L10n("Branches removidas: %@", list)
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func createArchive(reference: String, outputPath: String) {
        let ref = reference.clean
        let path = outputPath.clean
        guard !ref.isEmpty, !path.isEmpty else { return }
        runGitAction(label: "Create archive", args: ["archive", "--format=zip", "--output", path, ref])
    }

    func deleteLocalBranch(_ branch: String, force: Bool) {
        let name = branch.clean
        guard !name.isEmpty else { return }
        runGitAction(
            label: "Delete local branch",
            args: ["branch", force ? "-D" : "-d", name]
        )
    }

    func branchInfo(named name: String) -> BranchInfo? {
        branchInfos.first(where: { $0.name == name })
    }
}
