import Foundation

extension RepositoryViewModel {

    // MARK: - Repo Context

    func buildRepoContext(
        fileHints: [String],
        recentMessages: [String] = [],
        extraNotes: [String] = []
    ) -> String {
        let uniqueFiles = Array(NSOrderedSet(array: fileHints.filter { !$0.isEmpty }).array as? [String] ?? [])
        if let snapshot = repoMemorySnapshot {
            let snapshotContext = repoMemoryService.promptContext(for: snapshot, focusFiles: uniqueFiles, mode: aiMode)
            if !snapshotContext.isEmpty {
                let notes = extraNotes.isEmpty ? "" : "\nnotes: \(extraNotes.joined(separator: " | "))"
                return snapshotContext + notes
            }
        }

        return buildTransientRepoContext(
            fileHints: uniqueFiles,
            recentMessages: recentMessages,
            extraNotes: extraNotes
        )
    }

    func ensurePRCatalogLoaded(
        provider: any GitHostingProvider,
        remote: HostedRemote
    ) async -> [HostedPRInfo] {
        if !pullRequests.isEmpty {
            return pullRequests
        }

        let prs = await provider.fetchPullRequests(remote: remote)
        if !prs.isEmpty {
            pullRequests = prs
        }
        return prs
    }

    // MARK: - Repo Memory

    func loadRepoMemorySnapshotIfAvailable() {
        guard let repositoryURL else { return }
        repoMemoryTask?.cancel()
        repoMemoryTask = Task {
            let snapshot = await repoMemoryService.loadSnapshot(for: repositoryURL)
            guard !Task.isCancelled else { return }
            repoMemorySnapshot = snapshot
            repoMemoryLastRefreshedAt = snapshot?.generatedAt
            updateRepoMemoryStatus(repositoryURL: repositoryURL, snapshot: snapshot)
            if hasRepoMemoryRefreshInputs,
               shouldRefreshRepoMemory(snapshot: snapshot, force: snapshot == nil) {
                await refreshRepoMemory(force: snapshot == nil)
            }
        }
    }

    func refreshRepoMemory(force: Bool = true) async {
        guard let repositoryURL, !isRepoMemoryRefreshing else { return }
        guard hasRepoMemoryRefreshInputs else { return }
        let snapshot = repoMemorySnapshot
        guard force || shouldRefreshRepoMemory(snapshot: snapshot, force: false) else { return }

        isRepoMemoryRefreshing = true
        defer { isRepoMemoryRefreshing = false }

        do {
            let refreshed = try await repoMemoryService.refreshSnapshot(
                for: repositoryURL,
                worker: worker,
                activeBranch: currentBranch,
                headShortHash: headShortHash
            )
            guard !Task.isCancelled else { return }
            repoMemorySnapshot = refreshed
            repoMemoryLastRefreshedAt = refreshed.generatedAt
            updateRepoMemoryStatus(repositoryURL: repositoryURL, snapshot: refreshed)
        } catch {
            repoMemoryStatusMessage = L10n("settings.ai.repoMemory.status.error")
            logger.log(.error, "Repo memory refresh failed: \(error.localizedDescription)", context: repositoryURL.lastPathComponent, source: #function)
        }
    }

    func clearRepoMemory() async {
        guard let repositoryURL else { return }
        do {
            try await repoMemoryService.clearSnapshot(for: repositoryURL)
            repoMemorySnapshot = nil
            repoMemoryLastRefreshedAt = nil
            updateRepoMemoryStatus(repositoryURL: repositoryURL, snapshot: nil)
        } catch {
            repoMemoryStatusMessage = L10n("settings.ai.repoMemory.status.error")
            logger.log(.error, "Repo memory clear failed: \(error.localizedDescription)", context: repositoryURL.lastPathComponent, source: #function)
        }
    }

    func scheduleRepoMemoryRefreshIfNeeded() {
        guard let repositoryURL, repositoryURL == self.repositoryURL else { return }
        guard hasRepoMemoryRefreshInputs else { return }
        let snapshot = repoMemorySnapshot
        guard shouldRefreshRepoMemory(snapshot: snapshot, force: false) else { return }
        repoMemoryTask?.cancel()
        repoMemoryTask = Task { [weak self] in
            await self?.refreshRepoMemory(force: true)
        }
    }

    // MARK: - Parsing Helpers

    static func parseCommitSubjects(fromLog log: String) -> [String] {
        log.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { return trimmed }
            return String(parts[1])
        }
    }

    static func parseFileHints(fromDiffStat diffStat: String) -> [String] {
        diffStat.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let filePart = trimmed.components(separatedBy: "|").first?.trimmingCharacters(in: .whitespacesAndNewlines),
               !filePart.isEmpty {
                return filePart
            }
            let tabParts = trimmed.split(separator: "\t")
            guard let last = tabParts.last else { return nil }
            return String(last).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func deriveModules(from fileHints: [String], limit: Int) -> [String] {
        RepoMemoryService.deriveModules(from: fileHints, limit: limit)
    }
}

// MARK: - Private Helpers

extension RepositoryViewModel {

    func reviewDiffPayload(
        for pr: HostedPRInfo,
        provider: any GitHostingProvider,
        remote: HostedRemote,
        repositoryURL: URL
    ) async -> (diff: String, diffStat: String) {
        if let diff = await provider.fetchPRDiff(remote: remote, prNumber: pr.number),
           !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (diff, "")
        }

        guard !pr.headBranch.isEmpty, !pr.baseBranch.isEmpty else {
            return ("", "")
        }

        let range = "\(pr.baseBranch)...\(pr.headBranch)"
        let diff = (try? await worker.runAction(args: ["diff", range], in: repositoryURL)) ?? ""
        let diffStat = (try? await worker.runAction(args: ["diff", "--stat", range], in: repositoryURL)) ?? ""
        return (diff, diffStat)
    }

    fileprivate func buildTransientRepoContext(
        fileHints: [String],
        recentMessages: [String],
        extraNotes: [String]
    ) -> String {
        let (messageBudget, fileBudget) = repoContextBudget
        let uniqueMessages = Array(NSOrderedSet(array: recentMessages.filter { !$0.isEmpty }).array as? [String] ?? [])
        let modules = RepoMemoryService.deriveModules(from: fileHints, limit: max(2, min(fileBudget, 6)))
        let testHints = fileHints.filter {
            $0.localizedCaseInsensitiveContains("test") || $0.contains("/Tests/")
        }

        var sections: [String] = []
        if let repoName = repositoryURL?.lastPathComponent, !repoName.isEmpty {
            sections.append("repository: \(repoName)")
        }
        if !currentBranch.isEmpty {
            sections.append("branch: \(currentBranch)")
        }
        if !modules.isEmpty {
            sections.append("modules: \(modules.joined(separator: ", "))")
        }
        if !fileHints.isEmpty {
            sections.append("focus files: \(fileHints.prefix(fileBudget).joined(separator: ", "))")
        }
        if !testHints.isEmpty {
            sections.append("test surface: \(testHints.prefix(max(1, fileBudget / 2)).joined(separator: ", "))")
        }
        if !uniqueMessages.isEmpty {
            sections.append("recent commit style: \(uniqueMessages.prefix(messageBudget).joined(separator: " | "))")
        }
        if !extraNotes.isEmpty {
            sections.append("notes: \(extraNotes.joined(separator: " | "))")
        }

        return sections.joined(separator: "\n")
    }

    fileprivate func shouldRefreshRepoMemory(snapshot: RepoMemorySnapshot?, force: Bool) -> Bool {
        if force || snapshot == nil {
            return true
        }
        guard let snapshot else { return true }
        if snapshot.activeBranch != currentBranch || snapshot.headShortHash != headShortHash {
            return true
        }
        let generatedAt = repoMemoryLastRefreshedAt ?? snapshot.generatedAt
        return Date().timeIntervalSince(generatedAt) > 3600
    }

    fileprivate func updateRepoMemoryStatus(repositoryURL: URL, snapshot: RepoMemorySnapshot?) {
        if let snapshot {
            repoMemoryStatusMessage = L10n("settings.ai.repoMemory.status.ready", repositoryURL.lastPathComponent)
            UserDefaults.standard.set(repositoryURL.lastPathComponent, forKey: "zion.repoMemory.activeRepoName")
            UserDefaults.standard.set(snapshot.generatedAt.timeIntervalSince1970, forKey: "zion.repoMemory.lastRefresh")
            UserDefaults.standard.set(true, forKey: "zion.repoMemory.ready")
        } else {
            repoMemoryStatusMessage = L10n("settings.ai.repoMemory.status.missing")
            UserDefaults.standard.set(repositoryURL.lastPathComponent, forKey: "zion.repoMemory.activeRepoName")
            UserDefaults.standard.removeObject(forKey: "zion.repoMemory.lastRefresh")
            UserDefaults.standard.set(false, forKey: "zion.repoMemory.ready")
        }
    }

    fileprivate var repoContextBudget: (messages: Int, files: Int) {
        switch aiMode {
        case .efficient: return (4, 4)
        case .smart: return (6, 6)
        case .bestQuality: return (8, 8)
        }
    }

    fileprivate var hasRepoMemoryRefreshInputs: Bool {
        repositoryURL != nil &&
        !currentBranch.isEmpty &&
        currentBranch != "-" &&
        !headShortHash.isEmpty &&
        headShortHash != "-"
    }
}
