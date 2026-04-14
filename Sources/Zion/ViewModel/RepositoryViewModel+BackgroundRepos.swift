import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - Background Repo Persistence

    func startBackgroundMonitor(for url: URL) {
        guard var state = backgroundRepoStates[url] else { return }

        state.fileWatcher.onChange = { [weak self] event in
            guard event.hasTreeImpact || event.hasGitMetadataImpact || event.requiresRescan else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.updateChangedFileCount(for: url)
            }
        }
        state.fileWatcher.watch(directory: url)
        state.monitorTask?.cancel()
        state.monitorTask = nil

        backgroundRepoStates[url] = state
    }

    func updateChangedFileCount(for url: URL) async {
        do {
            let output = try await worker.runAction(
                args: ["status", "--porcelain"],
                in: url
            )
            let count = output.split(separator: "\n").count
            let canonical = canonicalRecentRepositoryURL(for: url)
            backgroundRepoChangedFiles[canonical] = count
        } catch {
            // Silently fail — repo may be unavailable
        }
    }

    func pauseBackgroundWatchers() {
        for (_, state) in backgroundRepoStates {
            state.fileWatcher.stop()
        }
    }

    func resumeBackgroundWatchers() {
        for (url, state) in backgroundRepoStates {
            state.fileWatcher.watch(directory: url)
        }
    }

    func cleanupAllBackgroundStates() {
        for (_, state) in backgroundRepoStates {
            state.monitorTask?.cancel()
            state.fileWatcher.stop()
            for tab in state.terminalTabs {
                for session in tab.allSessions() {
                    session.killCachedProcess()
                }
            }
        }
        backgroundRepoStates.removeAll()
        backgroundRepoChangedFiles.removeAll()
    }

    /// Evict background repo states beyond the allowed limit, preferring to keep
    /// repos that appear in the recent list. Evicted repos get their terminals killed
    /// and file watchers stopped to free memory (PERF-015).
    func evictExcessBackgroundRepoStates(keeping maxCount: Int) {
        guard backgroundRepoStates.count > maxCount else { return }
        let recentSet = Set(recentRepositories)
        // Sort: repos NOT in recents are evicted first
        let sorted = backgroundRepoStates.keys.sorted { a, b in
            let aRecent = recentSet.contains(canonicalRecentRepositoryURL(for: a))
            let bRecent = recentSet.contains(canonicalRecentRepositoryURL(for: b))
            if aRecent != bRecent { return bRecent } // non-recent first for eviction
            return false
        }
        let toEvict = sorted.prefix(backgroundRepoStates.count - maxCount)
        for url in toEvict {
            guard let state = backgroundRepoStates.removeValue(forKey: url) else { continue }
            state.monitorTask?.cancel()
            state.fileWatcher.stop()
            for tab in state.terminalTabs {
                for session in tab.allSessions() {
                    session.killCachedProcess()
                }
            }
            backgroundRepoChangedFiles.removeValue(forKey: canonicalRecentRepositoryURL(for: url))
            logger.log(.info, "EVICT background repo", context: url.lastPathComponent, source: #function)
        }
    }

    // MARK: - Repository Statistics

    func loadRepositoryStats() {
        guard let url = repositoryURL else { return }

        Task {
            do {
                // Total commits
                let countOutput = try await worker.runAction(args: ["rev-list", "--count", "HEAD"], in: url)
                let totalCommits = Int(countOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

                // Contributors
                let shortlog = try await worker.runAction(args: ["shortlog", "-sne", "HEAD"], in: url)
                let contributors = shortlog.split(separator: "\n").compactMap { line -> ContributorStat? in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let parts = trimmed.split(separator: "\t", maxSplits: 1)
                    guard parts.count == 2 else { return nil }
                    let count = Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0
                    let nameEmail = String(parts[1])
                    // Parse "Name <email>"
                    var name = nameEmail
                    var email = ""
                    if let emailRange = nameEmail.range(of: "<(.+?)>", options: .regularExpression) {
                        email = String(nameEmail[emailRange]).replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
                        name = String(nameEmail[..<emailRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    }
                    return ContributorStat(name: name, email: email, commitCount: count)
                }

                // Language breakdown by file extension
                let files = try await worker.runAction(args: ["ls-files"], in: url)
                var extCount: [String: Int] = [:]
                for file in files.split(separator: "\n") {
                    let ext = URL(fileURLWithPath: String(file)).pathExtension.lowercased()
                    if !ext.isEmpty {
                        extCount[ext, default: 0] += 1
                    }
                }
                let totalFiles = max(1, extCount.values.reduce(0, +))
                let languages = extCount.sorted { $0.value > $1.value }.prefix(10).map { ext, count in
                    LanguageStat(language: Self.languageName(for: ext), fileCount: count,
                                percentage: Double(count) / Double(totalFiles) * 100)
                }

                // Date range
                let firstDate = try? await worker.runAction(args: ["log", "--reverse", "--format=%ci", "-1"], in: url)
                let lastDate = try? await worker.runAction(args: ["log", "--format=%ci", "-1"], in: url)

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

                repoStats = RepositoryStats(
                    totalCommits: totalCommits,
                    totalBranches: branches.count,
                    totalTags: tags.count,
                    contributors: contributors,
                    languageBreakdown: languages,
                    firstCommitDate: firstDate.flatMap { dateFormatter.date(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) },
                    lastCommitDate: lastDate.flatMap { dateFormatter.date(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                )
            } catch {
                logger.log(.warn, "Failed to load repo stats: \(error.localizedDescription)", source: #function)
                repoStats = nil
            }
        }
    }

    static func languageName(for ext: String) -> String {
        let map: [String: String] = [
            "swift": "Swift", "ts": "TypeScript", "tsx": "TypeScript", "js": "JavaScript",
            "jsx": "JavaScript", "py": "Python", "rb": "Ruby", "go": "Go", "rs": "Rust",
            "java": "Java", "kt": "Kotlin", "c": "C", "cpp": "C++", "h": "C/C++ Header",
            "cs": "C#", "php": "PHP", "html": "HTML", "css": "CSS", "scss": "SCSS",
            "json": "JSON", "yaml": "YAML", "yml": "YAML", "md": "Markdown",
            "sql": "SQL", "sh": "Shell", "bash": "Shell", "zsh": "Shell",
            "xml": "XML", "toml": "TOML", "lock": "Lock", "liquid": "Liquid"
        ]
        return map[ext] ?? ext.uppercased()
    }

    // MARK: - Submodules

    func loadSubmodules() {
        guard let url = repositoryURL else { return }
        guard isGitRepository else {
            submoduleTask?.cancel()
            submodules = []
            return
        }

        submoduleTask?.cancel()
        let requestToken = UUID()
        submoduleLoadToken = requestToken
        submoduleTask = Task { [weak self] in
            guard let self else { return }
            do {
                let output = try await self.worker.runAction(args: ["submodule", "status"], in: url)
                guard !Task.isCancelled else { return }
                guard self.submoduleLoadToken == requestToken, self.repositoryURL == url else { return }
                self.submodules = Self.parseSubmoduleStatus(output, repoURL: url)
            } catch {
                guard !Task.isCancelled else { return }
                guard self.submoduleLoadToken == requestToken, self.repositoryURL == url else { return }
                self.logger.log(.warn, "Failed to load submodules: \(error.localizedDescription)", source: #function)
                self.submodules = []
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


    // MARK: - Full History Search

    func searchFullHistory(query: String) {
        gitSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = repositoryURL else {
            clearGitSearch()
            return
        }

        gitSearchQuery = trimmed
        isGitSearching = true
        let loadedHashes = Set(commits.map(\.id))

        gitSearchTask = Task {
            defer { if !Task.isCancelled { isGitSearching = false } }
            do {
                let results = try await worker.searchFullHistory(
                    query: trimmed,
                    in: url,
                    excludeHashes: loadedHashes
                )
                guard !Task.isCancelled else { return }
                gitSearchResults = results
            } catch {
                guard !Task.isCancelled else { return }
                gitSearchResults = []
            }
        }
    }

    func clearGitSearch() {
        gitSearchTask?.cancel()
        gitSearchResults = []
        isGitSearching = false
        gitSearchQuery = ""
    }

}
