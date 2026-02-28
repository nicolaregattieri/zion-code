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
