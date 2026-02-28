import Foundation
import SwiftUI
import CryptoKit

extension RepositoryViewModel {

    // MARK: - Refresh

    func refreshRepository() {
        refreshRepository(setBusy: true, origin: .userInitiated)
    }

    func selectCommit(_ commitID: String?) {
        if selectedCommitID != commitID {
            selectedCommitFile = nil
            currentCommitFileDiff = ""
            currentCommitFileDiffHunks = []
            clearCommitReviewSelectionStateOnCommitChange()
        }
        selectedCommitID = commitID
        loadCommitDetails(for: commitID, policy: .interactive)
    }

    func selectChangeFile(_ file: String?) {
        selectedChangeFile = file
        if let file {
            loadDiff(for: file)
        } else {
            currentFileDiff = ""
        }
    }

    // MARK: - Fetch / Pull / Push

    func fetch() { runGitAction(label: "Fetch", args: ["fetch", "--all", "--prune"]) }
    func pull() { runGitAction(label: "Pull", args: ["pull", "--ff-only"]) }
    func pullRebase() { runGitAction(label: "Pull (rebase)", args: ["pull", "--rebase"]) }
    func requestPush() {
        guard let repositoryURL else {
            push()
            return
        }

        pushPreflightTask?.cancel()
        isBusy = true
        pushPreflightTask = Task {
            do {
                try await refreshPushDivergence(in: repositoryURL)
                try Task.checkCancellation()
                isBusy = false

                let behind = behindRemoteCount
                let ahead = aheadRemoteCount
                if behind > 0 && ahead > 0 {
                    pushDivergenceState = .diverged(ahead: ahead, behind: behind)
                    showPushDivergenceWarning = true
                } else if behind > 0 {
                    pushDivergenceState = .behind(behind)
                    showPushDivergenceWarning = true
                } else {
                    pushDivergenceState = .clear
                    push()
                }
            } catch is CancellationError {
                isBusy = false
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func push() {
        let branch = currentBranch
        let hasUpstream = branchInfos.first(where: { !$0.isRemote && $0.name == branch })?.upstream.isEmpty == false
        if hasUpstream {
            runGitAction(label: "Push", args: ["push"])
        } else if !branch.isEmpty {
            let remote = remotes.first?.name ?? "origin"
            runGitAction(label: "Push", args: ["push", "--set-upstream", remote, branch])
        } else {
            runGitAction(label: "Push", args: ["push"])
        }
    }

    func forceWithLeasePush() {
        let branch = currentBranch
        let hasUpstream = branchInfos.first(where: { !$0.isRemote && $0.name == branch })?.upstream.isEmpty == false
        if hasUpstream {
            runGitAction(label: "Push", args: ["push", "--force-with-lease"])
        } else if !branch.isEmpty {
            let remote = remotes.first?.name ?? "origin"
            runGitAction(label: "Push", args: ["push", "--force-with-lease", "--set-upstream", remote, branch])
        } else {
            runGitAction(label: "Push", args: ["push", "--force-with-lease"])
        }
    }

    // MARK: - Branch Focus & Commits

    func setBranchFocus(_ branch: String?) {
        let normalized = branch?.clean
        focusedBranch = normalized?.isEmpty == true ? nil : normalized
        commitLimit = defaultCommitLimit(for: focusedBranch)
        refreshCommitsOnly()
    }

    func loadMoreCommits() {
        guard repositoryURL != nil, hasMoreCommits else { return }
        let nextLimit = min(maxCommitLimit, commitLimit + commitPageSize)
        guard nextLimit != commitLimit else { return }
        commitLimit = nextLimit
        refreshCommitsOnly()
    }

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

    // MARK: - Rebase / Cherry-pick / Revert / Reset

    func rebaseOntoTarget() {
        let target = rebaseTargetInput.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Rebase", args: ["rebase", target])
    }

    func rebaseCurrentBranch(onto reference: String) {
        let target = reference.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Rebase", args: ["rebase", target])
    }

    func cherryPick() {
        let target = cherryPickInput.clean
        guard !target.isEmpty else { return }
        cherryPick(commitHash: target)
    }

    func cherryPick(commitHash: String) {
        let target = commitHash.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Cherry-pick", args: ["cherry-pick", target])
    }

    func revert(commitHash: String) {
        let target = commitHash.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Revert", args: ["revert", "--no-edit", target])
    }

    func hardReset() {
        let target = resetTargetInput.clean
        guard !target.isEmpty else { return }
        hardReset(to: target)
    }

    func hardReset(to target: String) {
        let cleanedTarget = target.clean
        guard !cleanedTarget.isEmpty else { return }
        runGitAction(label: "Reset --hard", args: ["reset", "--hard", cleanedTarget])
    }

    func resetToCommit(_ commitID: String, hard: Bool) {
        let args = hard ? ["reset", "--hard", commitID] : ["reset", "--soft", commitID]
        runGitAction(label: hard ? "Reset --hard" : "Reset --soft", args: args)
    }

    func discardChanges(in path: String) {
        let file = path.trimmingCharacters(in: .whitespaces)
        runGitAction(label: "Discard", args: ["checkout", "--", file])
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

    // MARK: - Stash

    func createStash() {
        let message = stashMessageInput.clean
        createStash(message: message.isEmpty ? nil : message)
    }

    func createStash(message: String?) {
        let cleanedMessage = message?.clean ?? ""
        if cleanedMessage.isEmpty {
            runGitAction(label: "Stash", args: ["stash", "push"])
        } else {
            runGitAction(label: "Stash", args: ["stash", "push", "-m", cleanedMessage])
        }
    }

    func applySelectedStash() {
        Task {
            let ref = await resolveStashReference(selectedStash)
            guard let ref else { return }
            runStashRestoreAction(reference: ref, pop: false)
        }
    }

    func popSelectedStash() {
        Task {
            let ref = await resolveStashReference(selectedStash)
            guard let ref else { return }
            runStashRestoreAction(reference: ref, pop: true)
        }
    }

    func dropSelectedStash() {
        Task {
            let ref = await resolveStashReference(selectedStash)
            guard let ref else { return }
            runGitAction(label: "Drop stash", args: ["stash", "drop", ref])
        }
    }

    // MARK: - Recovery Snapshots

    func refreshRecoverySnapshots(includeDangling: Bool = true) {
        guard let repositoryURL else {
            recoverySnapshots = []
            recoverySnapshotsStatus = ""
            return
        }

        recoverySnapshotsTask?.cancel()
        isRecoverySnapshotsLoading = true
        recoverySnapshotsTask = Task {
            do {
                let active = try await loadActiveRecoverySnapshots(in: repositoryURL)
                let dangling = includeDangling ? (try await loadDanglingRecoverySnapshots(in: repositoryURL)) : []

                var byHash: [String: RecoverySnapshot] = [:]
                for item in active { byHash[item.hash] = item }
                for item in dangling where byHash[item.hash] == nil { byHash[item.hash] = item }

                let merged = byHash.values.sorted { $0.date > $1.date }
                recoverySnapshots = merged
                recoverySnapshotsRepositoryPath = repositoryURL.path
                recoverySnapshotsStatus = merged.isEmpty
                    ? L10n("recovery.status.empty")
                    : L10n("recovery.status.loaded", "\(merged.count)")
                isRecoverySnapshotsLoading = false
            } catch is CancellationError {
                return
            } catch {
                isRecoverySnapshotsLoading = false
                recoverySnapshotsStatus = L10n("recovery.status.failed")
                logger.log(.warn, "Recovery snapshot scan failed: \(error.localizedDescription)", source: #function)
            }
        }
    }

    func copyRecoverySnapshotReference(_ snapshot: RecoverySnapshot) {
        let value = snapshot.reference ?? snapshot.hash
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        statusMessage = L10n("recovery.copy.success", value)
    }

    func restoreRecoverySnapshot(_ snapshot: RecoverySnapshot) {
        if let reference = snapshot.reference, !reference.clean.isEmpty {
            selectedStash = reference
            applySelectedStash()
            return
        }
        runGitAction(label: "Restore snapshot", args: ["checkout", snapshot.hash, "--", "."])
    }

    func loadActiveRecoverySnapshots(in repositoryURL: URL) async throws -> [RecoverySnapshot] {
        let output = try await worker.runAction(
            args: ["stash", "list", "--format=%gD%x1F%H%x1F%ct%x1F%gs"],
            in: repositoryURL
        )

        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.split(separator: Character(UnicodeScalar(0x1F)!), omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { return nil }
            let ref = fields[0].clean
            let hash = fields[1].clean
            let timestamp = TimeInterval(fields[2].clean) ?? 0
            let subject = fields[3].clean
            guard !ref.isEmpty, !hash.isEmpty else { return nil }
            return RecoverySnapshot(
                hash: hash,
                shortHash: String(hash.prefix(8)),
                reference: ref,
                subject: subject,
                date: Date(timeIntervalSince1970: timestamp),
                source: .activeStash
            )
        }
    }

    func loadDanglingRecoverySnapshots(in repositoryURL: URL) async throws -> [RecoverySnapshot] {
        let fsck = try await worker.runActionAllowingFailure(
            args: ["fsck", "--no-reflogs", "--full", "--unreachable", "--no-progress"],
            in: repositoryURL
        )
        let hashes = fsck.output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> String? in
                let text = String(line)
                guard text.hasPrefix("unreachable commit ") else { return nil }
                return String(text.dropFirst("unreachable commit ".count)).clean
            }
            .filter { !$0.isEmpty }

        guard !hashes.isEmpty else { return [] }
        let limited = Array(hashes.prefix(180))
        let showOutput = try await worker.runAction(
            args: ["show", "-s", "--format=%H%x1F%h%x1F%ct%x1F%s"] + limited,
            in: repositoryURL
        )

        return showOutput.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.split(separator: Character(UnicodeScalar(0x1F)!), omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { return nil }
            let hash = fields[0].clean
            let shortHash = fields[1].clean
            let timestamp = TimeInterval(fields[2].clean) ?? 0
            let subject = fields[3].clean
            guard subject.contains("zion-safety-") || subject.contains("zion-transfer-") else { return nil }
            return RecoverySnapshot(
                hash: hash,
                shortHash: shortHash.isEmpty ? String(hash.prefix(8)) : shortHash,
                reference: nil,
                subject: subject,
                date: Date(timeIntervalSince1970: timestamp),
                source: .danglingSnapshot
            )
        }
    }

    func runStashRestoreAction(reference: String, pop: Bool) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        actionTask?.cancel()
        isBusy = true
        let verb = pop ? "pop" : "apply"

        actionTask = Task {
            do {
                let _ = try await worker.runAction(args: ["stash", verb, reference], in: repositoryURL)
                try Task.checkCancellation()
                clearError()
                statusMessage = pop ? L10n("stash.pop.success") : L10n("stash.apply.success")
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                if handleStashRestoreFailure(error, reference: reference, pop: pop) {
                    return
                }
                if let friendly = friendlyStashRestoreErrorMessage(error, reference: reference, pop: pop) {
                    clearError()
                    lastError = friendly
                    statusMessage = friendly
                    logger.log(.error, friendly, source: #function)
                    return
                }
                handleError(error)
            }
        }
    }

    @discardableResult
    func handleStashRestoreFailure(_ error: Error, reference: String, pop: Bool) -> Bool {
        let raw = error.localizedDescription.lowercased()
        let overwriteBlocked = raw.contains("would be overwritten by merge")
            || raw.contains("please commit your changes or stash them before you merge")

        guard overwriteBlocked else { return false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n("stash.restore.blocked.title")
        alert.informativeText = L10n("stash.restore.blocked.message", reference)
        alert.addButton(withTitle: L10n("stash.restore.blocked.autoStashRetry"))
        alert.addButton(withTitle: L10n("Cancelar"))

        if alert.runModal() == .alertFirstButtonReturn {
            runAutoStashAndRetry(reference: reference, pop: pop)
        } else {
            clearError()
            statusMessage = L10n("stash.restore.blocked.cancelled")
        }
        return true
    }

    func runAutoStashAndRetry(reference: String, pop: Bool) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        actionTask?.cancel()
        isBusy = true
        let safetyMessage = "zion-safety-\(UUID().uuidString.prefix(8))"
        let verb = pop ? "pop" : "apply"

        actionTask = Task {
            do {
                let isTransferFlow = await isTransferStash(reference: reference, in: repositoryURL)
                let stableReference = await stableStashReferenceForRetry(reference, in: repositoryURL)
                let _ = try await worker.runAction(
                    args: ["stash", "push", "--include-untracked", "-m", safetyMessage],
                    in: repositoryURL
                )
                let safetyRef = try? await latestStashReference(in: repositoryURL)
                let _ = try await worker.runAction(args: ["stash", verb, stableReference], in: repositoryURL)

                if isTransferFlow, let safetyRef, !safetyRef.clean.isEmpty {
                    do {
                        let _ = try await worker.runAction(args: ["stash", "apply", safetyRef], in: repositoryURL)
                        statusMessage = L10n("stash.restore.blocked.transferRestored", safetyMessage)
                    } catch {
                        let files = (try? await worker.listConflictedFiles(in: repositoryURL)) ?? []
                        if let first = files.first {
                            conflictedFiles = files
                            isConflictViewVisible = true
                            selectConflictFile(first.path)
                            statusMessage = L10n("stash.restore.blocked.transferConflicts")
                        } else {
                            statusMessage = L10n("stash.restore.blocked.transferPartial", safetyMessage)
                        }
                    }
                } else {
                    statusMessage = L10n("stash.restore.blocked.retried", safetyMessage)
                }

                try Task.checkCancellation()
                clearError()
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func isTransferStash(reference: String, in repositoryURL: URL) async -> Bool {
        let normalized = reference.clean
        guard !normalized.isEmpty else { return false }
        let resolved = (await resolveStashReference(normalized)) ?? normalized

        let output = (try? await worker.runAction(args: ["stash", "list", "--format=%H%x09%gD%x09%s"], in: repositoryURL)) ?? ""
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let hash = String(parts[0])
            let ref = String(parts[1])
            let subject = String(parts[2])
            guard subject.contains("zion-transfer-") else { continue }

            if normalized == ref || normalized == hash || hash.hasPrefix(normalized) || resolved == ref || resolved == hash {
                return true
            }
        }
        return false
    }

    func stableStashReferenceForRetry(_ reference: String, in repositoryURL: URL) async -> String {
        let cleaned = reference.clean
        let isOrdinal = cleaned.range(of: "^stash@\\{\\d+\\}$", options: .regularExpression) != nil
        guard isOrdinal else { return cleaned }

        let hash = (try? await worker.runAction(args: ["rev-parse", cleaned], in: repositoryURL).clean) ?? ""
        return hash.isEmpty ? cleaned : hash
    }

    func friendlyStashRestoreErrorMessage(_ error: Error, reference: String, pop: Bool) -> String? {
        guard case let GitClientError.commandFailed(_, message) = error else {
            return nil
        }

        let normalized = message.lowercased()
        if normalized.contains("no stash entries found") || normalized.contains("stash not found") {
            return L10n("stash.restore.error.noEntries")
        }
        if normalized.contains("not a valid reference")
            || normalized.contains("unknown revision")
            || normalized.contains("bad revision") {
            return L10n("stash.restore.error.invalidReference", reference)
        }
        if normalized.contains("conflict")
            || normalized.contains("merge conflict")
            || normalized.contains("could not apply") {
            return pop
                ? L10n("stash.restore.error.popConflict")
                : L10n("stash.restore.error.applyConflict")
        }

        return pop
            ? L10n("stash.restore.error.popGeneric")
            : L10n("stash.restore.error.applyGeneric")
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
            try? await Task.sleep(nanoseconds: 600_000_000)
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

    // MARK: - Init / Remote

    func initRepository() {
        runGitAction(label: "Git Init", args: ["init"])
    }

    func addRemote() {
        let name = remoteNameInput.clean
        let url = remoteURLInput.clean
        guard !name.isEmpty, !url.isEmpty else { return }
        runGitAction(label: "Add Remote", args: ["remote", "add", name, url])
    }

    func removeRemote(named name: String) {
        runGitAction(label: "Remove Remote", args: ["remote", "remove", name])
    }

    func testRemote(named name: String) {
        runGitAction(label: "Test Remote", args: ["ls-remote", "--exit-code", name])
    }

    // MARK: - Commit & Stage

    func commit(message: String) {
        let msg = message.clean
        guard !msg.isEmpty else { return }

        actionTask?.cancel()
        isBusy = true

        let url = repositoryURL
        let shouldAmend = amendLastCommit

        actionTask = Task {
            do {
                guard let url else { return }

                // 1. Always stage everything first for a guaranteed "Quick Commit"
                // This handles both modified and untracked files.
                let _ = try await worker.runAction(args: ["add", "-A"], in: url)

                // 2. Prepare commit arguments
                var commitArgs = ["commit", "-m", msg]
                if shouldAmend {
                    commitArgs.append("--amend")
                }

                // 3. Execute commit
                let _ = try await worker.runAction(args: commitArgs, in: url)

                if let newHeadCommitID = try? await worker.runAction(args: ["rev-parse", "HEAD"], in: url).clean,
                   !newHeadCommitID.isEmpty {
                    selectCommit(newHeadCommitID)
                }

                clearError()
                statusMessage = shouldAmend ? L10n("Commit corrigido com sucesso.") : L10n("Commit realizado com sucesso.")
                commitMessageInput = ""
                amendLastCommit = false
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func stageFile(_ path: String) {
        runGitAction(label: "Stage", args: ["add", path])
    }

    func unstageFile(_ path: String) {
        runGitAction(label: "Unstage", args: ["reset", "HEAD", "--", path])
    }

    func stageAllFiles() {
        runGitAction(label: "Stage All", args: ["add", "-A"])
    }

    func unstageAllFiles() {
        runGitAction(label: "Unstage All", args: ["reset", "HEAD", "--", "."])
    }

    func addToGitIgnore(path: String) {
        guard let url = repositoryURL else { return }
        let gitIgnoreURL = url.appendingPathComponent(".gitignore")

        actionTask?.cancel()
        isBusy = true

        actionTask = Task {
            do {
                var content = ""
                if FileManager.default.fileExists(atPath: gitIgnoreURL.path) {
                    content = try String(contentsOf: gitIgnoreURL, encoding: .utf8)
                }

                if !content.contains(path) {
                    if !content.isEmpty && !content.hasSuffix("\n") {
                        content += "\n"
                    }
                    content += "\(path)\n"
                    try content.write(to: gitIgnoreURL, atomically: true, encoding: .utf8)
                }

                // After adding to gitignore, we should unstage it if it was staged
                let _ = try await worker.runAction(args: ["rm", "--cached", path], in: url)

                clearError()
                statusMessage = L10n("Adicionado ao .gitignore: %@", path)
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func renameRemote(oldName: String, newName: String) {
        runGitAction(label: "Rename Remote", args: ["remote", "rename", oldName, newName])
    }

    func abortMerge() { runGitAction(label: "Abort Merge", args: ["merge", "--abort"]) }
    func abortRebase() { runGitAction(label: "Abort Rebase", args: ["rebase", "--abort"]) }
    func abortCherryPick() { runGitAction(label: "Abort Cherry-pick", args: ["cherry-pick", "--abort"]) }

    // MARK: - Conflict Resolution

    func loadConflictedFiles() {
        guard let repositoryURL else { return }
        conflictTask?.cancel()
        conflictTask = Task {
            do {
                let files = try await worker.listConflictedFiles(in: repositoryURL)
                try Task.checkCancellation()
                conflictedFiles = files
                if let first = files.first(where: { !$0.isResolved }) {
                    selectConflictFile(first.path)
                }
            } catch is CancellationError {
                return
            } catch {
                handleError(error)
            }
        }
    }

    func selectConflictFile(_ path: String) {
        guard let repositoryURL else { return }
        selectedConflictFile = path
        conflictTask?.cancel()
        conflictTask = Task {
            do {
                let content = try await worker.readConflictFileContent(path: path, in: repositoryURL)
                try Task.checkCancellation()
                conflictBlocks = Self.parseConflictBlocks(content)
            } catch is CancellationError {
                return
            } catch {
                handleError(error)
            }
        }
    }

    func resolveRegion(_ regionID: UUID, choice: ConflictChoice) {
        for i in conflictBlocks.indices {
            if case .conflict(var region) = conflictBlocks[i], region.id == regionID {
                region.choice = choice
                conflictBlocks[i] = .conflict(region)
                break
            }
        }
    }

    func saveAndMarkResolved(_ path: String) {
        guard let repositoryURL else { return }
        let merged = buildMergedContent()
        conflictTask?.cancel()
        conflictTask = Task {
            do {
                try await worker.writeResolvedFile(path: path, content: merged, in: repositoryURL)
                try await worker.markFileResolved(path: path, in: repositoryURL)
                try Task.checkCancellation()
                if let idx = conflictedFiles.firstIndex(where: { $0.path == path }) {
                    conflictedFiles[idx].isResolved = true
                }
                statusMessage = "\(path) " + L10n("Marcar como Resolvido")
                // Select next unresolved file
                if let next = conflictedFiles.first(where: { !$0.isResolved }) {
                    selectConflictFile(next.path)
                } else {
                    selectedConflictFile = nil
                    conflictBlocks = []
                }
            } catch is CancellationError {
                return
            } catch {
                handleError(error)
            }
        }
    }

    func continueAfterResolution() {
        guard let repositoryURL else { return }
        isBusy = true
        conflictTask?.cancel()
        conflictTask = Task {
            do {
                let output = try await worker.continueOperation(in: repositoryURL)
                try Task.checkCancellation()
                isConflictViewVisible = false
                statusMessage = output.isEmpty ? L10n("Todos os conflitos resolvidos!") : String(output.prefix(240))
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    var allConflictsResolved: Bool {
        !conflictedFiles.isEmpty && conflictedFiles.allSatisfy(\.isResolved)
    }

    var unresolvedConflictCount: Int {
        conflictedFiles.filter { !$0.isResolved }.count
    }

    var currentFileAllRegionsChosen: Bool {
        conflictBlocks.allSatisfy { block in
            if case .conflict(let region) = block { return region.choice != .undecided }
            return true
        }
    }

    var activeOperationLabel: String {
        if isMerging { return "Merge" }
        if isRebasing { return "Rebase" }
        if isCherryPicking { return "Cherry-pick" }
        return ""
    }

    func buildMergedContent() -> String {
        var lines: [String] = []
        for block in conflictBlocks {
            switch block {
            case .context(let contextLines):
                lines.append(contentsOf: contextLines)
            case .conflict(let region):
                switch region.choice {
                case .undecided:
                    // Keep original markers if undecided
                    lines.append("<<<<<<< \(region.oursLabel)")
                    lines.append(contentsOf: region.oursLines)
                    lines.append("=======")
                    lines.append(contentsOf: region.theirsLines)
                    lines.append(">>>>>>> \(region.theirsLabel)")
                case .ours:
                    lines.append(contentsOf: region.oursLines)
                case .theirs:
                    lines.append(contentsOf: region.theirsLines)
                case .both:
                    lines.append(contentsOf: region.oursLines)
                    lines.append(contentsOf: region.theirsLines)
                case .bothReverse:
                    lines.append(contentsOf: region.theirsLines)
                    lines.append(contentsOf: region.oursLines)
                case .custom(let text):
                    lines.append(contentsOf: text.components(separatedBy: "\n"))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func parseConflictBlocks(_ content: String) -> [ConflictBlock] {
        let lines = content.components(separatedBy: "\n")
        var blocks: [ConflictBlock] = []
        var contextBuffer: [String] = []
        var oursBuffer: [String] = []
        var theirsBuffer: [String] = []
        var oursLabel = ""
        var theirsLabel = ""
        var inOurs = false
        var inTheirs = false

        for line in lines {
            if line.hasPrefix("<<<<<<< ") {
                if !contextBuffer.isEmpty {
                    blocks.append(.context(contextBuffer))
                    contextBuffer = []
                }
                oursLabel = String(line.dropFirst(8))
                oursBuffer = []
                inOurs = true
                inTheirs = false
            } else if line == "=======" && inOurs {
                inOurs = false
                inTheirs = true
                theirsBuffer = []
            } else if line.hasPrefix(">>>>>>> ") && inTheirs {
                theirsLabel = String(line.dropFirst(8))
                let region = ConflictRegion(
                    oursLines: oursBuffer,
                    theirsLines: theirsBuffer,
                    oursLabel: oursLabel,
                    theirsLabel: theirsLabel
                )
                blocks.append(.conflict(region))
                inTheirs = false
                oursBuffer = []
                theirsBuffer = []
            } else if inOurs {
                oursBuffer.append(line)
            } else if inTheirs {
                theirsBuffer.append(line)
            } else {
                contextBuffer.append(line)
            }
        }
        if !contextBuffer.isEmpty {
            blocks.append(.context(contextBuffer))
        }
        return blocks
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

    func localBranchExists(named name: String) -> Bool {
        branchInfos.contains(where: { !$0.isRemote && $0.name == name })
    }

    func isRemoteRefName(_ value: String) -> Bool {
        branchInfos.contains(where: { $0.isRemote && $0.name == value })
    }

    // MARK: - Stash Reference Resolution

    func resolveStashReference(_ input: String) async -> String? {
        let value = input.clean
        guard !value.isEmpty else { return nil }

        // 1. If it's already a stash@{n} format, try to extract just that part
        if value.hasPrefix("stash@{") || value.contains("stash@{") {
            if let range = value.range(of: "stash@{[0-9]+}", options: .regularExpression) {
                return String(value[range])
            }
        }

        // 2. If it's a hash, we need to find which stash@{n} corresponds to it
        let isHex = value.range(of: "^[0-9a-fA-F]{7,40}$", options: .regularExpression) != nil
        if isHex {
            guard let url = repositoryURL else { return value }
            // Run git stash list with hashes to find the match
            do {
                let output = try await worker.runAction(args: ["stash", "list", "--format=%H %gD"], in: url)
                for line in output.split(separator: "\n") {
                    let parts = line.split(separator: " ")
                    if parts.count >= 2 {
                        let hash = String(parts[0])
                        let stashRef = String(parts[1])
                        if hash.hasPrefix(value) || value.hasPrefix(hash) {
                            return stashRef // Found stash@{n}
                        }
                    }
                }
            } catch {
                logger.log(.warn, "Failed to resolve stash ref: \(error.localizedDescription)", context: value, source: #function)
                return value // Fallback to hash if it fails
            }
        }

        return value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? value
    }

    // MARK: - Repository Refresh (Internal)

    func refreshCommitsOnly() {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            hasMoreCommits = false
            return
        }

        refreshTask?.cancel()
        let requestID = UUID()
        refreshRequestID = requestID
        isBusy = true

        let focusedBranchSnapshot = focusedBranch
        let selectedCommitSnapshot = selectedCommitID
        let commitLimitSnapshot = commitLimit

        refreshTask = Task {
            do {
                let payload = try await worker.loadCommits(
                    in: repositoryURL,
                    reference: focusedBranchSnapshot,
                    selectedCommitID: selectedCommitSnapshot,
                    limit: commitLimitSnapshot
                )
                try Task.checkCancellation()
                guard refreshRequestID == requestID else { return }

                clearError()
                commits = payload.commits
                hasMoreCommits = payload.hasMore
                let didSelectedCommitChange = payload.selectedCommitID != selectedCommitSnapshot
                if didSelectedCommitChange {
                    selectedCommitFile = nil
                    currentCommitFileDiff = ""
                    currentCommitFileDiffHunks = []
                    clearCommitReviewSelectionStateOnCommitChange()
                }
                selectedCommitID = payload.selectedCommitID
                let refreshedStatusMessage: String
                if let focusedBranchSnapshot {
                    refreshedStatusMessage = L10n("Filtro de branch ativo: %@ · %@ commits", focusedBranchSnapshot, "\(payload.commits.count)")
                } else {
                    refreshedStatusMessage = L10n("Visualizando todas as branches · %@ commits", "\(payload.commits.count)")
                }
                if statusMessage != refreshedStatusMessage {
                    statusMessage = refreshedStatusMessage
                }
                isBusy = false
                if didSelectedCommitChange {
                    let commitToken = payload.selectedCommitID.map { String($0.prefix(8)) } ?? "nil"
                    logger.log(.info, "details.reload interactive", context: "origin=refreshCommitsOnly commit=\(commitToken)", source: #function)
                    loadCommitDetails(for: payload.selectedCommitID, policy: .interactive)
                } else {
                    logger.log(.info, "details.reload skipped (same commit)", context: "origin=refreshCommitsOnly", source: #function)
                }
                loadCommitStats()
            } catch is CancellationError {
                guard refreshRequestID == requestID else { return }
                isBusy = false
                logger.log(.info, "refreshCommitsOnly cancelled", context: "request=\(requestID.uuidString.prefix(8))", source: #function)
                return
            } catch {
                guard refreshRequestID == requestID else { return }
                isBusy = false
                handleError(error)
            }
        }
    }

    func refreshRepository(
        setBusy: Bool,
        options: RepositoryLoadOptions = .full,
        origin: RefreshOrigin = .userInitiated,
        clearRepositorySwitchStateOnBusyCompletion: Bool = true,
        onFinish: (() -> Void)? = nil
    ) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            hasMoreCommits = false
            return
        }

        refreshTask?.cancel()
        let requestID = UUID()
        refreshRequestID = requestID
        if setBusy {
            isBusy = true
        }

        let focusedBranchSnapshot = focusedBranch
        let selectedCommitSnapshot = selectedCommitID
        let selectedStashSnapshot = selectedStash
        let effectiveOptions = RepositoryLoadOptions(
            includeWorktreeStatus: options.includeWorktreeStatus,
            includeBranchTree: options.includeBranchTree,
            includeTagsAndStashes: options.includeTagsAndStashes,
            inferOrigins: options.inferOrigins && inferBranchOrigins
        )
        let commitLimitSnapshot = commitLimit

        refreshTask = Task {
            do {
                let payload = try await worker.loadRepository(
                    in: repositoryURL,
                    focusedBranch: focusedBranchSnapshot,
                    selectedCommitID: selectedCommitSnapshot,
                    selectedStash: selectedStashSnapshot,
                    options: effectiveOptions,
                    limit: commitLimitSnapshot
                )
                try Task.checkCancellation()
                guard refreshRequestID == requestID else { return }

                clearError()
                currentBranch = payload.currentBranch
                headShortHash = payload.headShortHash
                branchInfos = payload.branchInfos
                branches = payload.branches
                focusedBranch = payload.focusedBranch
                branchTree = payload.branchTree
                tags = payload.tags
                stashes = payload.stashes
                selectedStash = payload.selectedStash
                let resolvedWorktrees = mergeWorktreeStatusIfNeeded(
                    payload.worktrees,
                    includeWorktreeStatus: effectiveOptions.includeWorktreeStatus
                )
                if worktrees != resolvedWorktrees {
                    worktrees = resolvedWorktrees
                }
                if let root = recentRepositoryRoot(for: repositoryURL) {
                    recentWorktreeCounts[root] = max(resolvedWorktrees.count - 1, 0)
                }
                remotes = payload.remotes
                commits = payload.commits
                hasMoreCommits = payload.hasMoreCommits
                let didSelectedCommitChange = payload.selectedCommitID != selectedCommitSnapshot
                if didSelectedCommitChange {
                    selectedCommitFile = nil
                    currentCommitFileDiff = ""
                    currentCommitFileDiffHunks = []
                    clearCommitReviewSelectionStateOnCommitChange()
                }
                selectedCommitID = payload.selectedCommitID
                hasConflicts = payload.hasConflicts
                isMerging = payload.isMerging
                isRebasing = payload.isRebasing
                isCherryPicking = payload.isCherryPicking
                isGitRepository = payload.isGitRepository
                // Guard against transient empty results from `git status`
                // (e.g. lock-file conflicts during concurrent git operations).
                // Only accept an empty list from user-initiated or repo-switch refreshes.
                let isBackgroundRefresh = origin == .autoTimer || origin == .fileWatcher
                let payloadChanges = (isBackgroundRefresh && payload.uncommittedChanges.isEmpty && !uncommittedChanges.isEmpty && payload.uncommittedCount > 0)
                    ? uncommittedChanges // keep current list
                    : payload.uncommittedChanges
                let didUncommittedChangesChange = uncommittedChanges != payloadChanges
                if didUncommittedChangesChange {
                    uncommittedChanges = payloadChanges
                }
                if uncommittedCount != payload.uncommittedCount {
                    uncommittedCount = payload.uncommittedCount
                }
                syncSelectedChangeFileWithPendingChanges(
                    origin: origin,
                    didUncommittedChangesChange: didUncommittedChangesChange
                )
                if !aiPendingChangesSummary.isEmpty {
                    aiPendingChangesSummary = "" // Clear cached summary on refresh
                }
                ensureBranchReviewSelections()
                refreshMergedBranchesPreview()
                if recoverySnapshotsRepositoryPath == repositoryURL.path {
                    refreshRecoverySnapshots(includeDangling: false)
                }
                let refreshedStatusMessage = L10n("Repositorio carregado: %@ · %@ commits", repositoryURL.lastPathComponent, "\(payload.commits.count)")
                if statusMessage != refreshedStatusMessage {
                    statusMessage = refreshedStatusMessage
                }
                if setBusy {
                    isBusy = false
                    if clearRepositorySwitchStateOnBusyCompletion, isSwitchingRepository {
                        isSwitchingRepository = false
                    }
                }
                if didSelectedCommitChange {
                    let detailsPolicy: CommitDetailsLoadPolicy = origin.usesSilentCommitDetails ? .silent : .interactive
                    let mode = origin.usesSilentCommitDetails ? "silent" : "interactive"
                    let commitToken = payload.selectedCommitID.map { String($0.prefix(8)) } ?? "nil"
                    logger.log(.info, "details.reload \(mode)", context: "origin=\(origin.rawValue) commit=\(commitToken)", source: #function)
                    loadCommitDetails(for: payload.selectedCommitID, policy: detailsPolicy)
                } else {
                    switch origin {
                    case .autoTimer, .fileWatcher:
                        break
                    case .userInitiated, .repositorySwitch:
                        logger.log(.info, "details.reload skipped (same commit)", context: "origin=\(origin.rawValue)", source: #function)
                    }
                }
                loadCommitStats()
                onFinish?()
            } catch is CancellationError {
                guard refreshRequestID == requestID else { return }
                if setBusy {
                    isBusy = false
                    if clearRepositorySwitchStateOnBusyCompletion, isSwitchingRepository {
                        isSwitchingRepository = false
                    }
                }
                logger.log(.info, "refreshRepository cancelled", context: "request=\(requestID.uuidString.prefix(8)) busy=\(setBusy)", source: #function)
                onFinish?()
                return
            } catch {
                guard refreshRequestID == requestID else { return }
                if setBusy {
                    isBusy = false
                    if clearRepositorySwitchStateOnBusyCompletion, isSwitchingRepository {
                        isSwitchingRepository = false
                    }
                }
                handleError(error)
                onFinish?()
            }
        }
    }

    // MARK: - Git Action Runner

    func runGitAction(label: String, args: [String]) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        actionTask?.cancel()
        isBusy = true

        let commandSummary = redactedGitCommandSummary(args: args)
        logger.log(.git, commandSummary, context: label)

        actionTask = Task {
            do {
                let output = try await runActionWithCredentialRetry(
                    label: label,
                    args: args,
                    in: repositoryURL,
                    commandSummary: commandSummary
                )
                try Task.checkCancellation()

                clearError()
                if output.isEmpty {
                    statusMessage = "\(label) executado com sucesso."
                } else {
                    statusMessage = "\(label): \(output.prefix(240))"
                }
                logger.log(.git, "\(label) OK", context: commandSummary)
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                logger.log(.error, error.localizedDescription, context: commandSummary)
                handleError(error)
            }
        }
    }

    // MARK: - Credential Retry

    func runActionWithCredentialRetry(
        label: String,
        args: [String],
        in repositoryURL: URL,
        commandSummary: String
    ) async throws -> String {
        do {
            return try await worker.runAction(args: args, in: repositoryURL)
        } catch {
            guard shouldHandleCredentialPrompt(for: args),
                  isCredentialFailure(error),
                  let context = buildGitAuthContext(
                    label: label,
                    args: args,
                    commandSummary: commandSummary,
                    error: error
                  ) else {
                throw error
            }

            if let stored = gitCredentialStore.load(host: context.host, usernameHint: context.usernameHint) {
                do {
                    return try await worker.runAction(
                        args: args,
                        in: repositoryURL,
                        mode: .withCredential(GitCredentialInput(username: stored.username, secret: stored.secret))
                    )
                } catch {
                    if isCredentialFailure(error) {
                        try? gitCredentialStore.delete(host: context.host, username: stored.username)
                    } else {
                        throw error
                    }
                }
            }

            let promptResult = await requestGitCredentials(context: context)
            switch promptResult {
            case .cancelled:
                throw GitClientError.commandFailed(command: commandSummary, message: L10n("git.auth.cancelled"))
            case .provided(let usernameRaw, let secretRaw):
                let secret = secretRaw.clean
                guard !secret.isEmpty else {
                    throw GitClientError.commandFailed(command: commandSummary, message: L10n("git.auth.secretRequired"))
                }

                let normalizedUsername = usernameRaw.clean
                let effectiveUsername = normalizedUsername.isEmpty ? context.usernameHint : normalizedUsername
                let credential = GitCredentialInput(username: effectiveUsername, secret: secret)
                let output = try await worker.runAction(args: args, in: repositoryURL, mode: .withCredential(credential))

                if let effectiveUsername, !effectiveUsername.isEmpty {
                    try? gitCredentialStore.save(host: context.host, username: effectiveUsername, secret: secret)
                }
                return output
            }
        }
    }

    func shouldHandleCredentialPrompt(for args: [String]) -> Bool {
        guard let subcommand = args.first?.lowercased() else { return false }
        return subcommand == "fetch"
            || subcommand == "pull"
            || subcommand == "push"
            || subcommand == "ls-remote"
    }

    func buildGitAuthContext(
        label: String,
        args: [String],
        commandSummary: String,
        error: Error
    ) -> GitAuthContext? {
        guard let remoteURL = resolveRemoteURL(for: args),
              let remote = parseHTTPSRemote(remoteURL) else {
            return nil
        }

        let message: String
        if case let GitClientError.commandFailed(_, m) = error {
            message = m
        } else {
            message = error.localizedDescription
        }

        return GitAuthContext(
            operationLabel: label,
            commandSummary: commandSummary,
            remoteURL: remoteURL,
            host: remote.host,
            usernameHint: remote.usernameHint,
            errorMessage: message,
            isAzureDevOps: remote.host.contains("dev.azure.com")
        )
    }

    func resolveRemoteURL(for args: [String]) -> String? {
        guard !remotes.isEmpty else { return nil }
        let remoteMap = Dictionary(uniqueKeysWithValues: remotes.map { ($0.name, $0.url) })

        let nonOptionTokens = args.filter { !$0.hasPrefix("-") }
        for token in nonOptionTokens.reversed() {
            if let url = remoteMap[token] {
                return url
            }
        }
        return remotes.first?.url
    }

    func parseHTTPSRemote(_ remoteURL: String) -> (host: String, usernameHint: String?)? {
        guard let components = URLComponents(string: remoteURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              let host = components.host?.lowercased() else {
            return nil
        }

        let user = components.user?.clean
        return (host, user?.isEmpty == true ? nil : user)
    }

    func requestGitCredentials(context: GitAuthContext) async -> GitAuthPromptResult {
        if let existing = gitAuthPromptContinuation {
            gitAuthPromptContinuation = nil
            existing.resume(returning: .cancelled)
        }
        gitAuthContext = context
        isGitAuthPromptVisible = true
        return await withCheckedContinuation { continuation in
            gitAuthPromptContinuation = continuation
        }
    }

    func submitGitAuthPrompt(username: String, secret: String) {
        guard let continuation = gitAuthPromptContinuation else { return }
        gitAuthPromptContinuation = nil
        isGitAuthPromptVisible = false
        gitAuthContext = nil
        continuation.resume(returning: .provided(username: username, secret: secret))
    }

    func cancelGitAuthPrompt() {
        guard let continuation = gitAuthPromptContinuation else { return }
        gitAuthPromptContinuation = nil
        isGitAuthPromptVisible = false
        gitAuthContext = nil
        continuation.resume(returning: .cancelled)
    }

    func redactedGitCommandSummary(args: [String]) -> String {
        let subcommand = args.first ?? "command"
        let fingerprint = gitArgsFingerprint(args)
        return "git \(subcommand) [args=\(args.count), id=\(fingerprint)]"
    }

    func gitArgsFingerprint(_ args: [String]) -> String {
        let payload = args.joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(10))
    }

    // MARK: - Commit Details

    func loadCommitDetails(for commitID: String?, policy: CommitDetailsLoadPolicy = .interactive) {
        guard let repositoryURL else {
            commitDetails = L10n("Selecione um repositorio Git.")
            return
        }

        guard let commitID else {
            commitDetails = L10n("Selecione um commit para ver os detalhes.")
            return
        }

        detailsTask?.cancel()
        let requestID = UUID()
        detailsRequestID = requestID
        switch policy {
        case .interactive:
            commitDetails = L10n("Carregando detalhes do commit...")
        case .silent:
            break
        }

        detailsTask = Task {
            do {
                let details = try await worker.loadCommitDetails(in: repositoryURL, commitID: commitID)
                try Task.checkCancellation()
                guard detailsRequestID == requestID else { return }
                if commitDetails != details {
                    commitDetails = details
                }
            } catch is CancellationError {
                return
            } catch {
                guard detailsRequestID == requestID else { return }
                logger.log(.warn, "Failed to load commit details: \(error.localizedDescription)", context: commitID, source: #function)
                let message = error.localizedDescription
                if commitDetails != message {
                    commitDetails = message
                }
            }
        }
    }

    // MARK: - Diff Loading

    func statusForFile(_ file: String) -> String? {
        uncommittedChanges.first { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 4 else { return false }
            let start = trimmed.index(trimmed.startIndex, offsetBy: 3)
            var path = String(trimmed[start...]).trimmingCharacters(in: .whitespaces)
            if let arrowRange = path.range(of: " -> ") {
                path = String(path[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            return path == file
        }.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(2))
        }
    }

    static func buildSyntheticNewFileDiff(file: String, lines: [String]) -> String {
        let count = lines.count
        var result = "diff --git a/\(file) b/\(file)\n"
        result += "new file mode 100644\n"
        result += "--- /dev/null\n"
        result += "+++ b/\(file)\n"
        result += "@@ -0,0 +1,\(count) @@\n"
        for line in lines {
            result += "+\(line)\n"
        }
        return result
    }

    func loadDiff(for file: String) {
        guard let url = repositoryURL else { return }

        Task {
            do {
                // Get diff including staged changes
                let diff = try await worker.runAction(args: ["diff", "HEAD", "--", file], in: url)
                let newDiff: String
                let newHunks: [DiffHunk]
                if diff.isEmpty {
                    let status = statusForFile(file)
                    let resolvedDiff: String? = await resolveMissingDiff(for: file, status: status, in: url)
                    if let resolvedDiff, !resolvedDiff.isEmpty {
                        newDiff = resolvedDiff
                        newHunks = Self.parseDiffHunks(resolvedDiff)
                    } else {
                        newDiff = L10n("Nenhuma mudanca detectada (ou arquivo novo nao rastreado).")
                        newHunks = []
                    }
                } else {
                    newDiff = diff
                    newHunks = Self.parseDiffHunks(diff)
                }
                // Only update UI when the diff content actually changed,
                // preventing flicker and preserving hunk selection on auto-refresh.
                if newDiff != currentFileDiff {
                    currentFileDiff = newDiff
                    currentFileDiffHunks = newHunks
                    selectedHunkLines = []
                }
            } catch {
                logger.log(.warn, "Failed to load diff: \(error.localizedDescription)", context: file, source: #function)
                currentFileDiff = L10n("error.loadDiff", error.localizedDescription)
                currentFileDiffHunks = []
            }
        }
    }

    func resolveMissingDiff(for file: String, status: String?, in url: URL) async -> String? {
        if status == "??" {
            return await resolveUntrackedDiff(for: file, in: url)
        } else if status?.hasPrefix("A") == true {
            return await resolveStagedNewFileDiff(for: file, in: url)
        }
        return nil
    }

    func resolveUntrackedDiff(for file: String, in url: URL) async -> String? {
        let fullPath = url.appendingPathComponent(file).path
        let fm = FileManager.default
        var isDir: ObjCBool = false

        // Directory: list contents as synthetic diff
        if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
            if let entries = try? fm.contentsOfDirectory(atPath: fullPath) {
                let lines = entries.sorted().map { "  \($0)" }
                return Self.buildSyntheticNewFileDiff(file: file, lines: ["[\(file)]"] + lines)
            }
            return nil
        }

        // Try git diff --no-index (exits 1 on success for new files)
        if let result = try? await worker.runActionAllowingFailure(
            args: ["diff", "--no-index", "--", "/dev/null", file],
            in: url
        ), result.status == 1, !result.output.isEmpty {
            return result.output
        }

        // Fallback: read file directly
        return readFileAsSyntheticDiff(file: file, fullPath: fullPath)
    }

    func resolveStagedNewFileDiff(for file: String, in url: URL) async -> String? {
        // Try git diff --cached for staged new files
        if let diff = try? await worker.runAction(args: ["diff", "--cached", "--", file], in: url),
           !diff.isEmpty {
            return diff
        }

        // Fallback: git show :<file> (index version)
        if let content = try? await worker.runAction(args: ["show", ":\(file)"], in: url),
           !content.isEmpty {
            let lines = content.components(separatedBy: "\n")
            return Self.buildSyntheticNewFileDiff(file: file, lines: lines)
        }

        return nil
    }

    func readFileAsSyntheticDiff(file: String, fullPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: fullPath) else { return nil }
        // Check for binary content
        if data.contains(0) {
            return L10n("Arquivo binario ou nao legivel.")
        }
        guard let content = String(data: data, encoding: .utf8), !content.isEmpty else { return nil }
        let lines = content.components(separatedBy: "\n")
        return Self.buildSyntheticNewFileDiff(file: file, lines: lines)
    }

    // MARK: - Commit Stats

    func loadCommitStats() {
        guard let url = repositoryURL, !commits.isEmpty else { return }
        commitStatsTask?.cancel()
        let hashes = commits.map(\.id)
        commitStatsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stats = try await worker.fetchCommitStats(in: url, hashes: hashes)
                try Task.checkCancellation()
                for i in commits.indices {
                    if let stat = stats[commits[i].id] {
                        commits[i].insertions = stat.0
                        commits[i].deletions = stat.1
                    }
                }
            } catch {
                // Silently fail — stats are optional enhancement
            }
        }
    }

    // MARK: - Diff Parsing

    static func parseDiffHunks(_ rawDiff: String) -> [DiffHunk] {
        let lines = rawDiff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var hunks: [DiffHunk] = []
        var i = 0

        // Skip file header lines (diff --git, index, ---, +++)
        while i < lines.count && !lines[i].hasPrefix("@@") {
            i += 1
        }

        while i < lines.count {
            let line = lines[i]
            guard line.hasPrefix("@@") else { i += 1; continue }

            // Parse hunk header: @@ -oldStart,oldCount +newStart,newCount @@
            let header = line
            var oldStart = 0, oldCount = 0, newStart = 0, newCount = 0
            if let rangeMatch = line.range(of: "@@ -(\\d+)(?:,(\\d+))? \\+(\\d+)(?:,(\\d+))? @@",
                                           options: .regularExpression) {
                let headerStr = String(line[rangeMatch])
                let nums = headerStr.matches(of: /(\d+)/)
                if nums.count >= 3 {
                    oldStart = Int(nums[0].output.1) ?? 0
                    if nums.count == 4 {
                        oldCount = Int(nums[1].output.1) ?? 0
                        newStart = Int(nums[2].output.1) ?? 0
                        newCount = Int(nums[3].output.1) ?? 0
                    } else {
                        oldCount = 0
                        newStart = Int(nums[1].output.1) ?? 0
                        newCount = Int(nums[2].output.1) ?? 0
                    }
                }
            }

            i += 1
            var diffLines: [DiffLine] = []
            var currentOld = oldStart
            var currentNew = newStart

            while i < lines.count && !lines[i].hasPrefix("@@") {
                let diffLineText = lines[i]
                if diffLineText.hasPrefix("+") {
                    diffLines.append(DiffLine(type: .addition, content: String(diffLineText.dropFirst()),
                                              oldLineNumber: nil, newLineNumber: currentNew))
                    currentNew += 1
                } else if diffLineText.hasPrefix("-") {
                    diffLines.append(DiffLine(type: .deletion, content: String(diffLineText.dropFirst()),
                                              oldLineNumber: currentOld, newLineNumber: nil))
                    currentOld += 1
                } else if diffLineText.hasPrefix("\\") {
                    // "\ No newline at end of file" — skip
                    i += 1
                    continue
                } else {
                    // Context line (starts with space or is empty)
                    let content = diffLineText.isEmpty ? "" : String(diffLineText.dropFirst())
                    diffLines.append(DiffLine(type: .context, content: content,
                                              oldLineNumber: currentOld, newLineNumber: currentNew))
                    currentOld += 1
                    currentNew += 1
                }
                i += 1
            }

            hunks.append(DiffHunk(header: header, oldStart: oldStart, oldCount: oldCount,
                                  newStart: newStart, newCount: newCount, lines: diffLines))
        }

        return hunks
    }

    // MARK: - Hunk & Line Staging

    func stageHunk(_ hunk: DiffHunk, file: String) {
        guard let url = repositoryURL else { return }

        // Hunk-level staging doesn't work for untracked files — fall back to full stage
        if statusForFile(file) == "??" {
            stageFile(file)
            return
        }

        let patch = buildPatch(file: file, hunks: [hunk])

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runActionWithStdin(
                    args: ["apply", "--cached", "--unidiff-zero"],
                    stdin: patch,
                    in: url
                )
                clearError()
                statusMessage = L10n("Hunk staged com sucesso.")
                refreshRepository(setBusy: true)
                if let file = selectedChangeFile { loadDiff(for: file) }
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func unstageHunk(_ hunk: DiffHunk, file: String) {
        guard let url = repositoryURL else { return }
        let patch = buildPatch(file: file, hunks: [hunk])

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runActionWithStdin(
                    args: ["apply", "--cached", "--reverse", "--unidiff-zero"],
                    stdin: patch,
                    in: url
                )
                clearError()
                statusMessage = L10n("Hunk unstaged com sucesso.")
                refreshRepository(setBusy: true)
                if let file = selectedChangeFile { loadDiff(for: file) }
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func stageSelectedLines(from hunk: DiffHunk, selectedLineIDs: Set<UUID>, file: String) {
        guard let url = repositoryURL else { return }
        let patch = buildPartialPatch(file: file, hunk: hunk, selectedLineIDs: selectedLineIDs)
        guard !patch.isEmpty else { return }

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runActionWithStdin(
                    args: ["apply", "--cached", "--unidiff-zero"],
                    stdin: patch,
                    in: url
                )
                clearError()
                statusMessage = L10n("Linhas staged com sucesso.")
                refreshRepository(setBusy: true)
                if let file = selectedChangeFile { loadDiff(for: file) }
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func buildPatch(file: String, hunks: [DiffHunk]) -> String {
        var parts: [String] = ["--- a/\(file)", "+++ b/\(file)"]
        for hunk in hunks {
            parts.append(hunk.header)
            for line in hunk.lines {
                switch line.type {
                case .context: parts.append(" \(line.content)")
                case .addition: parts.append("+\(line.content)")
                case .deletion: parts.append("-\(line.content)")
                }
            }
        }
        return parts.joined(separator: "\n") + "\n"
    }

    func buildPartialPatch(file: String, hunk: DiffHunk, selectedLineIDs: Set<UUID>) -> String {
        // Build a hunk with only the selected changed lines; unselected changes become context
        var newLines: [DiffLine] = []
        var oldLineCount = 0
        var newLineCount = 0

        for line in hunk.lines {
            let isSelected = selectedLineIDs.contains(line.id)
            switch line.type {
            case .context:
                newLines.append(line)
                oldLineCount += 1
                newLineCount += 1
            case .addition:
                if isSelected {
                    newLines.append(line)
                    newLineCount += 1
                }
                // If not selected, skip the addition entirely
            case .deletion:
                if isSelected {
                    newLines.append(line)
                    oldLineCount += 1
                } else {
                    // Unselected deletion becomes context
                    newLines.append(DiffLine(type: .context, content: line.content,
                                             oldLineNumber: line.oldLineNumber, newLineNumber: nil))
                    oldLineCount += 1
                    newLineCount += 1
                }
            }
        }

        guard newLines.contains(where: { $0.type != .context }) else { return "" }

        let header = "@@ -\(hunk.oldStart),\(oldLineCount) +\(hunk.newStart),\(newLineCount) @@"
        var parts: [String] = ["--- a/\(file)", "+++ b/\(file)", header]
        for line in newLines {
            switch line.type {
            case .context: parts.append(" \(line.content)")
            case .addition: parts.append("+\(line.content)")
            case .deletion: parts.append("-\(line.content)")
            }
        }
        return parts.joined(separator: "\n") + "\n"
    }

    // MARK: - Commit Diff for File

    func loadDiffForCommitFile(commitID: String, file: String) {
        guard let url = repositoryURL else { return }
        selectedCommitFile = file
        Task {
            do {
                let diff = try await worker.runAction(
                    args: ["diff", "\(commitID)~1", commitID, "--", file],
                    in: url
                )
                currentCommitFileDiff = diff.isEmpty ? L10n("Nenhuma mudanca.") : diff
                currentCommitFileDiffHunks = Self.parseDiffHunks(diff)
            } catch {
                logger.log(.warn, "Failed to load commit file diff: \(error.localizedDescription)", context: "\(commitID):\(file)", source: #function)
                currentCommitFileDiff = L10n("error.generic", error.localizedDescription)
                currentCommitFileDiffHunks = []
            }
        }
    }

    // MARK: - Git Blame

    func loadBlame(for file: FileItem) {
        guard let url = repositoryURL else { return }
        let filePath: String
        if let repoURL = repositoryURL {
            filePath = file.url.path.replacingOccurrences(of: repoURL.path + "/", with: "")
        } else {
            filePath = file.name
        }

        blameTask?.cancel()
        blameEntries = []

        blameTask = Task {
            do {
                let output = try await worker.runAction(
                    args: ["blame", "--porcelain", filePath],
                    in: url
                )
                let entries = Self.parseBlameOutput(output)
                blameEntries = entries
            } catch {
                logger.log(.warn, "Failed to load blame: \(error.localizedDescription)", context: filePath, source: #function)
                blameEntries = []
                statusMessage = "Blame: \(error.localizedDescription)"
            }
        }
    }

    func toggleBlame() {
        isBlameVisible.toggle()
        if isBlameVisible, let file = selectedCodeFile {
            loadBlame(for: file)
        } else {
            blameEntries = []
        }
    }

    static func parseBlameOutput(_ raw: String) -> [BlameEntry] {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var entries: [BlameEntry] = []
        var i = 0
        var authorMap: [String: String] = [:]
        var dateMap: [String: Date] = [:]

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        while i < lines.count {
            let line = lines[i]
            // Header line: <hash> <orig-line> <final-line> [<num-lines>]
            let parts = line.split(separator: " ")
            guard parts.count >= 3,
                  let hash = parts.first, hash.count >= 7,
                  hash.allSatisfy({ $0.isHexDigit }),
                  let lineNum = Int(parts[2]) else {
                i += 1
                continue
            }

            let commitHash = String(hash)
            i += 1

            // Read metadata lines until we hit the tab-prefixed content line
            var author = authorMap[commitHash] ?? ""
            var date = dateMap[commitHash] ?? Date.distantPast

            while i < lines.count && !lines[i].hasPrefix("\t") {
                let metaLine = lines[i]
                if metaLine.hasPrefix("author ") {
                    author = String(metaLine.dropFirst(7))
                    authorMap[commitHash] = author
                } else if metaLine.hasPrefix("author-time ") {
                    if let ts = TimeInterval(metaLine.dropFirst(12)) {
                        date = Date(timeIntervalSince1970: ts)
                        dateMap[commitHash] = date
                    }
                }
                i += 1
            }

            // Content line (starts with tab)
            var content = ""
            if i < lines.count && lines[i].hasPrefix("\t") {
                content = String(lines[i].dropFirst(1))
            }
            i += 1

            entries.append(BlameEntry(
                commitHash: commitHash,
                shortHash: String(commitHash.prefix(8)),
                author: author,
                date: date,
                lineNumber: lineNum,
                content: content
            ))
        }

        return entries
    }

    // MARK: - Reflog

    func loadReflog() {
        guard let url = repositoryURL else { return }

        reflogTask?.cancel()
        reflogEntries = []

        reflogTask = Task {
            do {
                let output = try await worker.runAction(
                    args: ["reflog", "--format=%H|%h|%gD|%gs|%ci|%cr", "-n", "50"],
                    in: url
                )
                let entries = Self.parseReflogOutput(output)
                reflogEntries = entries
            } catch {
                logger.log(.warn, "Failed to load reflog: \(error.localizedDescription)", source: #function)
                reflogEntries = []
            }
        }
    }

    func undoLastAction() {
        guard !reflogEntries.isEmpty else { return }
        // Find the previous state (reflog entry at index 1)
        guard reflogEntries.count > 1 else { return }
        let target = reflogEntries[1]
        runGitAction(label: "Undo", args: ["reset", "--soft", target.hash])
    }

    static func parseReflogOutput(_ raw: String) -> [ReflogEntry] {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        // First pass: parse raw entries
        struct RawEntry {
            let hash, shortHash, refName, action, message, relDate: String
            let date: Date
        }
        var rawEntries: [RawEntry] = []
        for line in lines {
            let parts = line.split(separator: "|", maxSplits: 5).map(String.init)
            guard parts.count >= 6 else { continue }
            let action = parts[3].split(separator: ":", maxSplits: 1).first.map(String.init) ?? parts[3]
            rawEntries.append(RawEntry(
                hash: parts[0], shortHash: parts[1], refName: parts[2],
                action: action, message: parts[3],
                relDate: parts[5],
                date: dateFormatter.date(from: parts[4]) ?? .distantPast
            ))
        }

        // Second pass: walk entries (newest->oldest) tracking which branch HEAD was on.
        // When we see "checkout: moving from X to Y", entries above were on Y, entries below on X.
        var branchStack = ""
        // Find the first checkout to seed the current branch
        for entry in rawEntries where entry.action.lowercased() == "checkout" {
            if let branches = ReflogEntry.parseCheckoutBranches(from: entry.message) {
                branchStack = branches.to
                break
            }
        }

        var results: [ReflogEntry] = []
        for entry in rawEntries {
            if entry.action.lowercased() == "checkout",
               let branches = ReflogEntry.parseCheckoutBranches(from: entry.message) {
                let detail = ReflogEntry.humanDetail(from: entry.message, action: entry.action)
                results.append(ReflogEntry(
                    hash: entry.hash, shortHash: entry.shortHash, refName: entry.refName,
                    action: entry.action, message: entry.message, detail: detail,
                    branch: branches.to, date: entry.date, relativeDate: entry.relDate
                ))
                branchStack = branches.from
            } else {
                let detail = ReflogEntry.humanDetail(from: entry.message, action: entry.action)
                results.append(ReflogEntry(
                    hash: entry.hash, shortHash: entry.shortHash, refName: entry.refName,
                    action: entry.action, message: entry.message, detail: detail,
                    branch: branchStack, date: entry.date, relativeDate: entry.relDate
                ))
            }
        }
        return results
    }

    // MARK: - Interactive Rebase

    func prepareInteractiveRebase(from baseRef: String) {
        guard let url = repositoryURL else { return }
        rebaseBaseRef = baseRef

        Task {
            do {
                let output = try await worker.runAction(
                    args: ["log", "--oneline", "--reverse", "\(baseRef)..HEAD"],
                    in: url
                )
                let items = output.split(separator: "\n", omittingEmptySubsequences: true).map { line -> RebaseItem in
                    let parts = line.split(separator: " ", maxSplits: 1)
                    let hash = parts.count > 0 ? String(parts[0]) : ""
                    let subject = parts.count > 1 ? String(parts[1]) : ""
                    return RebaseItem(hash: hash, shortHash: String(hash.prefix(8)), subject: subject)
                }
                rebaseItems = items
                isRebaseSheetVisible = true
            } catch {
                handleError(error)
            }
        }
    }

    func executeInteractiveRebase() {
        guard let url = repositoryURL, !rebaseItems.isEmpty else { return }

        // Build the rebase todo list
        let todoList = rebaseItems.map { item in
            "\(item.action.rawValue) \(item.hash) \(item.subject)"
        }.joined(separator: "\n")

        actionTask?.cancel()
        isBusy = true
        isRebaseSheetVisible = false

        actionTask = Task {
            do {
                // Use GIT_SEQUENCE_EDITOR to pass the todo list
                // We write the todo to a temp file and use a script that replaces the editor
                let tempDir = ZionTemp.directory
                let todoFile = tempDir.appendingPathComponent("zion-rebase-todo-\(UUID().uuidString)")
                try todoList.write(to: todoFile, atomically: true, encoding: .utf8)

                let scriptContent = "#!/bin/sh\ncp \"\(todoFile.path)\" \"$1\""
                let scriptFile = tempDir.appendingPathComponent("zion-rebase-editor-\(UUID().uuidString).sh")
                try scriptContent.write(to: scriptFile, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)

                // Run rebase with our custom sequence editor
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git", "rebase", "-i", rebaseBaseRef]
                process.currentDirectoryURL = url
                var env = ProcessInfo.processInfo.environment
                env["GIT_SEQUENCE_EDITOR"] = scriptFile.path
                env["LC_ALL"] = "C"
                env["LANG"] = "C"
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                try process.run()
                process.waitUntilExit()

                // Cleanup temp files
                try? FileManager.default.removeItem(at: todoFile)
                try? FileManager.default.removeItem(at: scriptFile)

                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    handleError(GitClientError.commandFailed(
                        command: "git rebase -i \(rebaseBaseRef)",
                        message: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                    isBusy = false
                } else {
                    clearError()
                    statusMessage = L10n("Rebase interativo concluido com sucesso.")
                    refreshRepository(setBusy: true)
                }
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    // MARK: - Submodules

    func loadSubmodules() {
        guard let url = repositoryURL else { return }

        Task {
            do {
                let output = try await worker.runAction(args: ["submodule", "status"], in: url)
                submodules = Self.parseSubmoduleStatus(output, repoURL: url)
            } catch {
                logger.log(.warn, "Failed to load submodules: \(error.localizedDescription)", source: #function)
                submodules = []
            }
        }
    }

    func submoduleInit() {
        runGitAction(label: "Submodule init", args: ["submodule", "init"])
    }

    func submoduleUpdate(recursive: Bool) {
        var args = ["submodule", "update", "--init"]
        if recursive { args.append("--recursive") }
        runGitAction(label: "Submodule update", args: args)
    }

    func submoduleSync() {
        runGitAction(label: "Submodule sync", args: ["submodule", "sync"])
    }

    static func parseSubmoduleStatus(_ raw: String, repoURL: URL) -> [SubmoduleInfo] {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            let statusChar = trimmed.first
            let rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            let parts = rest.split(separator: " ", maxSplits: 1)
            guard parts.count >= 1 else { return nil }

            let hash = String(parts[0])
            let path = parts.count > 1 ? String(parts[1]).split(separator: " ").first.map(String.init) ?? "" : ""

            let status: SubmoduleInfo.SubmoduleStatus
            switch statusChar {
            case "-": status = .uninitialized
            case "+": status = .modified
            default: status = .upToDate
            }

            return SubmoduleInfo(name: URL(fileURLWithPath: path).lastPathComponent,
                               path: path, url: "", hash: hash, status: status)
        }
    }

    // MARK: - Auth Error Detection

    func detectAuthError(from errorMessage: String) -> String? {
        let patterns = [
            "Permission denied",
            "Could not read from remote",
            "Authentication failed",
            "fatal: repository.*not found",
            "ERROR: Repository not found",
            "Host key verification failed"
        ]
        for pattern in patterns {
            if errorMessage.range(of: pattern, options: .regularExpression) != nil {
                return errorMessage
            }
        }
        return nil
    }

    // MARK: - Commit Signing Visualization

    func loadSignatureStatuses() {
        guard let url = repositoryURL else { return }

        Task {
            do {
                let output = try await worker.runAction(
                    args: ["log", "--format=%H %G?", "-n", "100"],
                    in: url
                )
                var statuses: [String: String] = [:]
                for line in output.split(separator: "\n") {
                    let parts = line.split(separator: " ", maxSplits: 1)
                    if parts.count == 2 {
                        statuses[String(parts[0])] = String(parts[1])
                    }
                }
                commitSignatureStatus = statuses
            } catch {
                logger.log(.warn, "Failed to load signature statuses: \(error.localizedDescription)", source: #function)
                commitSignatureStatus = [:]
            }
        }
    }

    func signatureStatusFor(_ commitHash: String) -> String? {
        commitSignatureStatus[commitHash]
    }

    // MARK: - File History

    func loadFileHistory(for relativePath: String) {
        guard let url = repositoryURL else { return }

        fileHistoryTask?.cancel()
        isFileHistoryLoading = true
        fileHistoryEntries = []

        fileHistoryTask = Task {
            defer { isFileHistoryLoading = false }

            do {
                let output = try await worker.runAction(
                    args: ["log", "--follow", "--format=%H|%h|%an|%ar|%s", "-50", "--", relativePath],
                    in: url
                )

                let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
                var entries: [FileHistoryEntry] = []
                for line in lines {
                    let parts = line.components(separatedBy: "|")
                    guard parts.count >= 5 else { continue }
                    entries.append(FileHistoryEntry(
                        hash: parts[0],
                        shortHash: parts[1],
                        author: parts[2],
                        date: parts[3],
                        message: parts[4...].joined(separator: "|")
                    ))
                }
                fileHistoryEntries = entries
                isFileHistoryVisible = true
            } catch {
                logger.log(.error, "File history failed: \(error.localizedDescription)", source: #function)
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    func defaultCommitLimit(for reference: String?) -> Int {
        if let reference, !reference.clean.isEmpty {
            return defaultCommitLimitFocused
        }
        return defaultCommitLimitAll
    }

    func ensureBranchReviewSelections() {
        let available = Set(branches)
        guard !available.isEmpty else {
            branchReviewSource = ""
            branchReviewTarget = ""
            return
        }

        if branchReviewTarget.isEmpty || !available.contains(branchReviewTarget) {
            if available.contains(currentBranch) {
                branchReviewTarget = currentBranch
            } else if let preferred = localBranchOptions.first ?? branches.first {
                branchReviewTarget = preferred
            }
        }

        if branchReviewSource.isEmpty || !available.contains(branchReviewSource) || branchReviewSource == branchReviewTarget {
            // Prefer common base branches as the comparison source
            let baseBranches = ["master", "main", "develop"]
            let preferredSource = baseBranches.first(where: { available.contains($0) && $0 != branchReviewTarget })
                ?? localBranchOptions.first(where: { $0 != branchReviewTarget })
                ?? remoteBranchOptions.first(where: { $0 != branchReviewTarget })
                ?? branches.first(where: { $0 != branchReviewTarget })
            branchReviewSource = preferredSource ?? ""
        }
    }

    func syncSelectedChangeFileWithPendingChanges(
        origin: RefreshOrigin,
        didUncommittedChangesChange: Bool
    ) {
        // When the uncommitted-changes list hasn't changed, the file list and
        // diff content are identical — skip entirely to prevent diff flicker.
        guard didUncommittedChangesChange || origin == .userInitiated || origin == .repositorySwitch else {
            return
        }

        let files = uncommittedChanges.compactMap(Self.filePathFromStatusLine)
        guard !files.isEmpty else {
            selectedChangeFile = nil
            currentFileDiff = ""
            currentFileDiffHunks = []
            selectedHunkLines = []
            return
        }

        if let selectedChangeFile, files.contains(selectedChangeFile) {
            loadDiff(for: selectedChangeFile)
            return
        }

        selectedChangeFile = nil
        currentFileDiff = ""
        currentFileDiffHunks = []
        selectedHunkLines = []
    }

    static func filePathFromStatusLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count >= 4 else { return trimmed }

        let start = trimmed.index(trimmed.startIndex, offsetBy: 3)
        var path = String(trimmed[start...]).trimmingCharacters(in: .whitespaces)
        if let arrowRange = path.range(of: " -> ") {
            path = String(path[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return path.isEmpty ? nil : path
    }

}
