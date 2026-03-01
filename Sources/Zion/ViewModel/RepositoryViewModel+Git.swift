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
        runDestructiveGitAction(label: "Rebase", args: ["rebase", target], operationTag: "rebase", targetHint: target)
    }

    func rebaseCurrentBranch(onto reference: String) {
        let target = reference.clean
        guard !target.isEmpty else { return }
        runDestructiveGitAction(label: "Rebase", args: ["rebase", target], operationTag: "rebase", targetHint: target)
    }

    func cherryPick() {
        let target = cherryPickInput.clean
        guard !target.isEmpty else { return }
        cherryPick(commitHash: target)
    }

    func cherryPick(commitHash: String) {
        let target = commitHash.clean
        guard !target.isEmpty else { return }
        runDestructiveGitAction(label: "Cherry-pick", args: ["cherry-pick", target], operationTag: "cherry-pick", targetHint: String(target.prefix(8)))
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
        runDestructiveGitAction(label: "Reset --hard", args: ["reset", "--hard", cleanedTarget], operationTag: "reset-hard", targetHint: String(cleanedTarget.prefix(8)))
    }

    func resetToCommit(_ commitID: String, shouldHardReset: Bool) {
        if shouldHardReset {
            runDestructiveGitAction(label: "Reset --hard", args: ["reset", "--hard", commitID], operationTag: "reset-hard", targetHint: String(commitID.prefix(8)))
        } else {
            runGitAction(label: "Reset --soft", args: ["reset", "--soft", commitID])
        }
    }

    func discardChanges(in path: String) {
        let file = path.trimmingCharacters(in: .whitespaces)
        runDestructiveGitAction(label: "Discard", args: ["checkout", "--", file], operationTag: "discard")
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
            runStashRestoreAction(reference: ref, shouldPop: false)
        }
    }

    func popSelectedStash() {
        Task {
            let ref = await resolveStashReference(selectedStash)
            guard let ref else { return }
            runStashRestoreAction(reference: ref, shouldPop: true)
        }
    }

    func dropSelectedStash() {
        Task {
            let ref = await resolveStashReference(selectedStash)
            guard let ref else { return }
            runGitAction(label: "Drop stash", args: ["stash", "drop", ref])
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
                // Fetch remote refs on user-initiated refresh so origin/* branches update
                if origin == .userInitiated {
                    _ = try? await worker.runAction(args: ["fetch", "--all", "--prune"], in: repositoryURL)
                    try Task.checkCancellation()
                }

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

    // MARK: - Destructive Git Action Runner

    func runDestructiveGitAction(label: String, args: [String], operationTag: String, targetHint: String = "") {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        guard uncommittedCount > 0 else {
            runGitAction(label: label, args: args)
            return
        }

        actionTask?.cancel()
        isBusy = true

        let commandSummary = redactedGitCommandSummary(args: args)
        logger.log(.git, commandSummary, context: label)

        let snapshotTag = targetHint.isEmpty ? "zion-pre-\(operationTag)" : "zion-pre-\(operationTag)-\(targetHint)"

        actionTask = Task {
            do {
                // 1. Create stash commit without modifying working tree
                let stashHash = try await worker.runAction(args: ["stash", "create"], in: repositoryURL)
                let trimmedHash = stashHash.clean

                // 2. Store the stash commit in the stash reflog
                if !trimmedHash.isEmpty {
                    let _ = try await worker.runAction(
                        args: ["stash", "store", "-m", snapshotTag, trimmedHash],
                        in: repositoryURL
                    )
                    logger.log(.info, "Pre-snapshot created: \(snapshotTag)", context: trimmedHash, source: #function)
                }

                // 3. Run the destructive command
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
