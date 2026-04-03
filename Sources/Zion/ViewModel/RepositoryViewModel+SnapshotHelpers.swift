import Foundation
import SwiftUI

// MARK: - Repository Switch Snapshot Helpers

extension RepositoryViewModel {

    func hasFreshRepositorySnapshot(for url: URL) -> Bool {
        guard let snapshot = repositorySwitchSnapshots[url] else { return false }
        return Date().timeIntervalSince(snapshot.capturedAt) <= repositorySwitchSnapshotTTL
    }

    func hasRepositorySnapshot(for url: URL) -> Bool {
        repositorySwitchSnapshots[url] != nil
    }

    func prepareBlockingRepositorySwitch(for url: URL) {
        guard !hasRepositorySnapshot(for: url) else { return }
        isSwitchingRepository = true
        isBlockingRepositorySwitch = true
    }

    func applyRepositorySnapshotIfFresh(for url: URL) -> Bool {
        guard let snapshot = repositorySwitchSnapshots[url],
              Date().timeIntervalSince(snapshot.capturedAt) <= repositorySwitchSnapshotTTL else {
            return false
        }

        applyRepositorySnapshot(snapshot)
        return true
    }

    func applyRepositorySnapshotIfAvailable(for url: URL) -> Bool {
        guard let snapshot = repositorySwitchSnapshots[url] else {
            return false
        }

        applyRepositorySnapshot(snapshot)
        return true
    }

    private func applyRepositorySnapshot(_ snapshot: RepositorySwitchSnapshot) {
        commitLimit = snapshot.commitLimit
        focusedBranch = snapshot.focusedBranch
        currentBranch = snapshot.currentBranch
        headShortHash = snapshot.headShortHash
        branchInfos = snapshot.branchInfos
        branches = snapshot.branches
        branchTree = snapshot.branchTree
        tags = snapshot.tags
        stashes = snapshot.stashes
        selectedStash = snapshot.selectedStash
        worktrees = snapshot.worktrees
        remotes = snapshot.remotes
        commits = snapshot.commits
        recalculateMaxLaneCount()
        hasMoreCommits = snapshot.hasMoreCommits
        selectedCommitID = snapshot.selectedCommitID
        hasConflicts = snapshot.hasConflicts
        isMerging = snapshot.isMerging
        isRebasing = snapshot.isRebasing
        isCherryPicking = snapshot.isCherryPicking
        isGitRepository = snapshot.isGitRepository
        uncommittedChanges = snapshot.uncommittedChanges
        uncommittedCount = snapshot.uncommittedCount
        repositoryFiles = snapshot.repositoryFiles
        expandedPaths = snapshot.expandedPaths
    }

    func clearRepositorySwitchState() {
        isBlockingRepositorySwitch = false
        isSwitchingRepository = false
    }

    /// Clears branch/commit/worktree data from the previous repo so the UI
    /// does not display stale trees, pills, or commit lists while the new
    /// repo's `refreshRepository` loads in the background.
    /// Uses `RepositorySwitchSnapshot.empty` so any new snapshot field is
    /// automatically covered without a second place to maintain.
    func clearStaleRepositoryData() {
        let preservedCommitLimit = commitLimit
        applyRepositorySnapshot(.empty)
        commitLimit = preservedCommitLimit
        aheadRemoteCount = 0
        behindRemoteCount = 0
        statusMessage = L10n("switch.loading.status", repositoryURL?.lastPathComponent ?? "")
    }

    /// Safety net: force-clears isSwitchingRepository after a timeout if finalization never fires.
    func armSwitchWatchdog(for url: URL, switchToken: UUID) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.repositorySwitchWatchdogTimeout)
            guard let self, self.repositorySwitchToken == switchToken else { return }
            if self.isSwitchingRepository {
                self.logger.log(.warn, "switch.watchdog: force-clearing stale isSwitchingRepository",
                                context: "repo=\(url.lastPathComponent)", source: #function)
                self.clearRepositorySwitchState()
            }
        }
    }

    func captureRepositorySnapshot(for url: URL) {
        repositorySwitchSnapshots[url] = RepositorySwitchSnapshot(
            capturedAt: Date(),
            commitLimit: commitLimit,
            focusedBranch: focusedBranch,
            currentBranch: currentBranch,
            headShortHash: headShortHash,
            branchInfos: branchInfos,
            branches: branches,
            branchTree: branchTree,
            tags: tags,
            stashes: stashes,
            selectedStash: selectedStash,
            worktrees: worktrees,
            remotes: remotes,
            commits: commits,
            hasMoreCommits: hasMoreCommits,
            selectedCommitID: selectedCommitID,
            hasConflicts: hasConflicts,
            isMerging: isMerging,
            isRebasing: isRebasing,
            isCherryPicking: isCherryPicking,
            isGitRepository: isGitRepository,
            uncommittedChanges: uncommittedChanges,
            uncommittedCount: uncommittedCount,
            repositoryFiles: repositoryFiles,
            expandedPaths: expandedPaths
        )
    }

    // MARK: - recalculateMaxLaneCount

    func recalculateMaxLaneCount() {
        var maxLane = 0
        for commit in commits {
            maxLane = max(maxLane, commit.lane)
            for lane in commit.incomingLanes { maxLane = max(maxLane, lane) }
            for lane in commit.outgoingLanes { maxLane = max(maxLane, lane) }
            for edge in commit.outgoingEdges { maxLane = max(maxLane, edge.to) }
        }
        maxLaneCount = maxLane + 1
    }
}

// MARK: - Open Repository & Switch Lifecycle

extension RepositoryViewModel {

    func openRepository(_ url: URL, silent: Bool = false) {
        let previousURL = repositoryURL

        // Same repo already open — just refresh metadata, don't touch terminals
        if previousURL == url {
            logger.log(.info, "openRepository SKIP (same repo)", context: "\(url.lastPathComponent) tabs=\(terminalTabs.count) sessions=\(terminalTabs.flatMap { $0.allSessions() }.count)", source: #function)
            if !silent { saveRecentRepository(url) }
            loadRepoMemorySnapshotIfAvailable()
            refreshRepository()
            refreshFileTree()
            loadPullRequests()
            refreshPRReviewQueue()
            loadSubmodules()
            loadBridgeState()
            return
        }

        let switchToken = UUID()
        repositorySwitchToken = switchToken
        isBlockingRepositorySwitch = !hasRepositorySnapshot(for: url)
        isSwitchingRepository = true
        logger.log(.info, "switch.start", context: "target=\(url.lastPathComponent) token=\(switchToken.uuidString.prefix(8))", source: #function)
        cancelRepositoryBackgroundActivityForSwitch()
        replaceUndoStack.removeAll()
        replaceRedoStack.removeAll()
        dismissPendingChangesSummary()
        lastNotifiedBehindCount = 0
        observedOpenPRIDs = nil
        pullRequests = []
        prReviewQueue = []
        if let previousURL {
            expandedPathsByRepository[previousURL] = expandedPaths
            captureRepositorySnapshot(for: previousURL)
        }

        repositoryURL = url
        pendingRepositoryURL = nil
        repoMemorySnapshot = nil
        repoMemoryLastRefreshedAt = nil
        repoMemoryStatusMessage = L10n("settings.ai.repoMemory.status.loading")
        repoEditorConfig = EditorConfig.load(from: url)
        loadRepoMemorySnapshotIfAvailable()
        if !silent { saveRecentRepository(url) }
        commitLimit = defaultCommitLimit(for: nil)
        focusedBranch = nil
        expandedPaths = expandedPathsByRepository[url] ?? []
        cachedIgnoredPaths = ignoredPathsCacheByRepository[url]?.paths
        worktreeNameInput = ""
        worktreePathInput = ""
        worktreeBranchInput = ""
        isWorktreeAdvancedExpanded = false

        let stashedKeys = backgroundRepoStates.keys.map { $0.lastPathComponent }
        logger.log(.info, "openRepository ENTER", context: "prev=\(previousURL?.lastPathComponent ?? "nil") target=\(url.lastPathComponent) tabs=\(terminalTabs.count) sessions=\(terminalTabs.flatMap { $0.allSessions() }.count) stashed=\(stashedKeys)", source: #function)

        // Stash current repo's terminals (save WITHOUT clearing terminalTabs yet to avoid
        // intermediate empty state that could cause SwiftUI to dismantle NSViews prematurely)
        if let previousURL, !terminalTabs.isEmpty {
            let sessions = terminalTabs.flatMap { $0.allSessions() }
            logger.log(.info, "STASH", context: "\(previousURL.lastPathComponent): \(terminalTabs.count) tabs, \(sessions.map { "\($0.label)(\($0.id.uuidString.prefix(4))) alive=\($0.isAlive) preserve=\($0._shouldPreserve) pid=\($0._shellPid)" })", source: #function)
            let watcher = FileWatcher()
            backgroundRepoStates[previousURL] = BackgroundRepoState(
                terminalTabs: terminalTabs,
                activeTabID: activeTabID,
                focusedSessionID: focusedSessionID,
                fileWatcher: watcher,
                monitorTask: nil,
                burstUntil: nil
            )
            let canonicalPreviousURL = canonicalRecentRepositoryURL(for: previousURL)
            backgroundRepoChangedFiles[canonicalPreviousURL] = uncommittedCount
            startBackgroundMonitor(for: previousURL)
            // DON'T set terminalTabs = [] here — let the restore/create below do a direct swap
        } else if previousURL == nil {
            // First open — no previous repo, kill any leftover terminals
            logger.log(.info, "KILL (first open)", context: "tabs=\(terminalTabs.count)", source: #function)
            for tab in terminalTabs {
                for session in tab.allSessions() {
                    session.killCachedProcess()
                }
            }
        }

        // Restore stashed terminals or create fresh (direct swap, no empty intermediate)
        if let restored = backgroundRepoStates.removeValue(forKey: url) {
            restored.fileWatcher.stop()
            restored.monitorTask?.cancel()
            let sessions = restored.terminalTabs.flatMap { $0.allSessions() }
            logger.log(.info, "RESTORE", context: "\(url.lastPathComponent): \(restored.terminalTabs.count) tabs, \(sessions.map { "\($0.label)(\($0.id.uuidString.prefix(4))) alive=\($0.isAlive) preserve=\($0._shouldPreserve) pid=\($0._shellPid)" })", source: #function)
            terminalTabs = restored.terminalTabs
            activeTabID = restored.activeTabID
            focusedSessionID = restored.focusedSessionID
            backgroundRepoChangedFiles.removeValue(forKey: canonicalRecentRepositoryURL(for: url))
            // Reset isAlive for sessions that died while stashed — lets updateNSView restart them
            for tab in terminalTabs {
                for session in tab.allSessions() {
                    session._needsProjectSwitchDisplayResync = true
                    if !session.isAlive {
                        session.isAlive = true
                    }
                }
            }
        } else {
            let stashedKeysNow = backgroundRepoStates.keys.map { $0.lastPathComponent }
            logger.log(.info, "FRESH (no stash found)", context: "\(url.lastPathComponent) stashedKeys=\(stashedKeysNow)", source: #function)
            terminalTabs = []
            activeTabID = nil
            focusedSessionID = nil
            createDefaultTerminalSession(repositoryURL: url, branchName: currentBranch.isEmpty ? url.lastPathComponent : currentBranch)
        }

        let finalStashedKeys = backgroundRepoStates.keys.map { $0.lastPathComponent }
        logger.log(.info, "openRepository EXIT", context: "tabs=\(terminalTabs.count) sessions=\(terminalTabs.flatMap { $0.allSessions() }.count) stashed=\(finalStashedKeys)", source: #function)

        openedFiles.removeAll()
        missingOpenFileIDs.removeAll()
        activeFileID = nil
        selectedCodeFile = nil
        selectedChangeFile = nil
        currentFileDiff = ""
        currentFileDiffHunks = []
        selectedCommitFile = nil
        currentCommitFileDiff = ""
        currentCommitFileDiffHunks = []
        selectedHunkLines = []
        commitDetailsCache.clear()
        commitFileDiffCache.clear()
        startFileWatcher(for: url)

        if applyRepositorySnapshotIfAvailable(for: url) {
            let snapshotAgeSeconds = repositorySwitchSnapshots[url].map {
                Int(Date().timeIntervalSince($0.capturedAt))
            } ?? 0
            logger.log(
                .info,
                "switch.snapshot.restore",
                context: "repo=\(url.lastPathComponent) token=\(switchToken.uuidString.prefix(8)) age=\(snapshotAgeSeconds)s blocking=\(isRepositorySwitchBlocking)",
                source: #function
            )
            loadCommitDetails(for: selectedCommitID, policy: .silent)
            refreshFileTree()
            scheduleDeferredRepositoryLoads(
                for: url,
                switchToken: switchToken,
                refreshRepositoryFirst: true
            )
        } else {
            // FRESH open: clear stale data from previous repo so the UI
            // shows a loading/empty state instead of the old repo's tree.
            clearStaleRepositoryData()

            refreshRepository(
                setBusy: true,
                options: .full,
                origin: .repositorySwitch,
                clearRepositorySwitchStateOnBusyCompletion: false,
                onFinish: { [weak self] in
                    self?.finalizeRepositorySwitch(for: url, switchToken: switchToken)
                }
            )
            refreshFileTree()
            armSwitchWatchdog(for: url, switchToken: switchToken)
        }

        if !pendingExternalFiles.isEmpty {
            let pending = pendingExternalFiles
            pendingExternalFiles = []
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                openFilesAsTabs(pending)
            }
        }
    }

    func cancelRepositoryBackgroundActivityForSwitch() {
        deferredRepositoryLoadTask?.cancel()
        refreshTask?.cancel()
        fileTreeRefreshTask?.cancel()
        fileTreeRefreshTask = nil
        isRefreshingFileTree = false
        pendingFileTreeRefreshRepositoryURL = nil
        pendingFileTreeRefreshForceReload = false
        prTask?.cancel()
        submoduleTask?.cancel()
        signatureStatusTask?.cancel()
        prPollingTask?.cancel()
        prPollingTimer?.cancel()
        backgroundFetchTask?.cancel()
        autoRefreshTask?.cancel()

        // Cancel any in-flight git action (e.g. fetch) so isBusy doesn't stay stuck
        // on the new repo after a switch.
        actionTask?.cancel()
        actionTask = nil
        activeGitActionToken = nil
        if isBusy {
            isBusy = false
            disarmBusyWatchdog()
        }
    }

    func scheduleDeferredRepositoryLoads(
        for url: URL,
        switchToken: UUID,
        refreshRepositoryFirst: Bool
    ) {
        deferredRepositoryLoadTask?.cancel()
        deferredRepositoryLoadTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: Constants.Timing.repositorySwitchDeferral)
            guard !Task.isCancelled else { return }
            guard self.repositorySwitchToken == switchToken, self.repositoryURL == url else { return }

            for _ in 0..<Constants.Timing.maxRepositorySwitchAttempts {
                if Task.isCancelled { return }
                if !self.isBusy { break }
                try? await Task.sleep(nanoseconds: Constants.Timing.repositorySwitchPollInterval)
                guard self.repositorySwitchToken == switchToken, self.repositoryURL == url else { return }
            }

            guard !Task.isCancelled else { return }
            guard self.repositorySwitchToken == switchToken, self.repositoryURL == url else { return }

            // Force-clear stale busy state after polling timeout
            if self.isBusy {
                self.logger.log(.warn, "switch.deferred: force-clearing stale isBusy after poll timeout", context: "repo=\(url.lastPathComponent)", source: #function)
                self.isBusy = false
                self.disarmBusyWatchdog()
            }

            if refreshRepositoryFirst {
                self.logger.log(.info, "switch.deferred.begin", context: "repo=\(url.lastPathComponent) token=\(switchToken.uuidString.prefix(8))", source: #function)
                self.refreshRepository(
                    setBusy: false,
                    options: .full,
                    origin: .repositorySwitch,
                    onFinish: { [weak self] in
                        self?.finalizeRepositorySwitch(for: url, switchToken: switchToken)
                    }
                )
            } else {
                self.finalizeRepositorySwitch(for: url, switchToken: switchToken)
            }

            self.armSwitchWatchdog(for: url, switchToken: switchToken)
        }
    }

    func finalizeRepositorySwitch(for url: URL, switchToken: UUID) {
        guard repositorySwitchToken == switchToken, repositoryURL == url else { return }
        loadPullRequests()
        refreshPRReviewQueue()
        startPRPollingTimer()
        loadSubmodules()
        loadSignatureStatuses()
        startBackgroundFetch()
        startAutoRefreshTimer()
        loadBridgeState()
        captureRepositorySnapshot(for: url)
        clearRepositorySwitchState()
    }

    func mergeWorktreeStatusIfNeeded(_ incoming: [WorktreeItem], includeWorktreeStatus: Bool) -> [WorktreeItem] {
        if includeWorktreeStatus {
            for worktree in incoming {
                cachedWorktreeStatusByPath[worktree.path] = (
                    uncommittedCount: worktree.uncommittedCount,
                    hasConflicts: worktree.hasConflicts
                )
            }
            return incoming
        }

        return incoming.map { item in
            guard let cached = cachedWorktreeStatusByPath[item.path] else { return item }
            return WorktreeItem(
                path: item.path,
                head: item.head,
                branch: item.branch,
                isMainWorktree: item.isMainWorktree,
                isDetached: item.isDetached,
                isLocked: item.isLocked,
                lockReason: item.lockReason,
                isPrunable: item.isPrunable,
                pruneReason: item.pruneReason,
                isCurrent: item.isCurrent,
                uncommittedCount: cached.uncommittedCount,
                hasConflicts: cached.hasConflicts
            )
        }
    }
}

// MARK: - Pending Changes Summary

extension RepositoryViewModel {

    var hasVisiblePendingChangesSummary: Bool {
        !aiPendingChangesSummary.clean.isEmpty
    }

    func beginPendingChangesSummaryRequest() {
        pendingSummaryTask?.cancel()
        isLoadingPendingChangesSummary = true
    }

    func applyPendingChangesSummary(_ summary: String) {
        aiPendingChangesSummary = summary.clean
        isLoadingPendingChangesSummary = false
    }

    func handlePendingChangesSummaryFailure(_ error: Error) {
        isLoadingPendingChangesSummary = false
        lastError = error.localizedDescription
    }

    func dismissPendingChangesSummary() {
        pendingSummaryTask?.cancel()
        pendingSummaryTask = nil
        isLoadingPendingChangesSummary = false
        aiPendingChangesSummary = ""
    }

    func syncPendingChangesSummaryAfterRefresh(hasPendingChanges: Bool) {
        guard !hasPendingChanges else { return }
        dismissPendingChangesSummary()
    }
}

// MARK: - Error Handling

extension RepositoryViewModel {

    func clearError() {
        lastError = nil
    }

    func friendlyErrorMessage(for error: Error) -> String? {
        guard case let GitClientError.commandFailed(command, message) = error else {
            return nil
        }

        guard command.contains("git checkout") else { return nil }

        let pattern = "'([^']+)' is already used by worktree at '([^']+)'"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let branchRange = Range(match.range(at: 1), in: message),
              let pathRange = Range(match.range(at: 2), in: message) else {
            return nil
        }

        let branch = String(message[branchRange])
        let path = String(message[pathRange])
        return L10n("gitError.checkout.usedByWorktree", branch, path)
    }

    func handleError(_ error: Error, source: String = #function) {
        let rawMessage = error.localizedDescription
        let message = friendlyErrorMessage(for: error)
            ?? ErrorClassifier.classify(rawMessage)
            ?? rawMessage
        lastError = message
        statusMessage = message
        logger.log(.error, rawMessage, source: source)
    }
}

// MARK: - File Watcher

extension RepositoryViewModel {

    func startFileWatcher(for url: URL) {
        fileWatcher.onChange = { [weak self] event in
            guard let self else { return }
            self.enqueueFileWatcherEvent(event)
        }
        pendingFileWatcherEvent = nil
        isApplyingFileWatcherRefresh = false
        fileWatcherGateTask?.cancel()
        fileWatcherGateTask = nil
        fileWatcher.watch(directory: url)
    }

    func enqueueFileWatcherEvent(_ event: FileWatcher.ChangeEvent) {
        guard !isSwitchingRepository else { return }
        pendingFileWatcherEvent = pendingFileWatcherEvent?.merged(with: event) ?? event
        guard !isZenModePaused else { return }
        processPendingFileWatcherEventIfNeeded()
    }

    func processPendingFileWatcherEventIfNeeded() {
        guard !isApplyingFileWatcherRefresh else { return }
        guard let event = pendingFileWatcherEvent else { return }
        pendingFileWatcherEvent = nil
        isApplyingFileWatcherRefresh = true

        if isBusy {
            pendingFileWatcherEvent = (pendingFileWatcherEvent?.merged(with: event)) ?? event
        } else {
            if event.hasStructuralImpact || event.requiresRescan {
                refreshFileTree(forceReloadExpandedDirectories: true)
            }

            if event.hasTreeImpact {
                reloadSelectedCodeFileFromDiskIfNeeded(event: event)
            }

            if event.hasWorktreeStatusImpact {
                if Date() < suppressFileWatcherGitMetadataUntil && !event.hasTreeImpact {
                    // Skip watcher-only git metadata noise while an explicit git action
                    // is already expected to refresh worktree state.
                } else {
                    refreshRepository(setBusy: false, options: .worktreeStatus, origin: .fileWatcher)
                }
            }
        }

        fileWatcherGateTask?.cancel()
        fileWatcherGateTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self.isApplyingFileWatcherRefresh = false
            self.processPendingFileWatcherEventIfNeeded()
        }
    }

    func reloadSelectedCodeFileFromDiskIfNeeded(event: FileWatcher.ChangeEvent) {
        guard let file = selectedCodeFile else { return }
        let selectedPath = FileWatcher.normalizePath(file.url.standardizedFileURL.path)
        let shouldReload = event.requiresRescan || event.changedPaths.contains(selectedPath)
        guard shouldReload else { return }

        if !FileManager.default.fileExists(atPath: file.url.path) {
            missingOpenFileIDs.insert(file.id)
            codeFileContent = L10n("editor.file.missingContent")
            statusMessage = L10n("editor.file.missingStatus", file.name)
            unsavedFiles.remove(file.id)
            return
        }

        missingOpenFileIDs.remove(file.id)
        if let content = try? String(contentsOf: file.url, encoding: .utf8),
           content != codeFileContent {
            codeFileContent = content
            originalFileContents[file.id] = content
            unsavedFiles.remove(file.id)
        }
    }

    func extendFileWatcherGitMetadataSuppression(by seconds: TimeInterval) {
        let candidate = Date().addingTimeInterval(seconds)
        if candidate > suppressFileWatcherGitMetadataUntil {
            suppressFileWatcherGitMetadataUntil = candidate
        }
    }
}
