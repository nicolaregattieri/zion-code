import Foundation

actor RepositoryWorker {
    let git = GitClient()
    let laneCalculator = GitGraphLaneCalculator()
    let isoDateWithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    let isoDateWithoutFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func runGitCommand(
        in repositoryURL: URL,
        args: [String],
        mode: GitExecutionMode = .normal
    ) throws -> String {
        try git.run(args: args, in: repositoryURL, mode: mode).stdout
    }

    func isGitRepository(at url: URL) -> Bool {
        do {
            let result = try git.runAllowingFailure(args: ["rev-parse", "--is-inside-work-tree"], in: url)
            return result.status == 0
        } catch {
            return false
        }
    }

    func loadCommits(
        in repositoryURL: URL,
        reference: String?,
        selectedCommitID: String?,
        limit: Int
    ) throws -> CommitLoadPayload {
        let (loadedCommits, hasMore) = try commitList(in: repositoryURL, reference: reference, limit: limit)
        let selected = loadedCommits.contains(where: { $0.id == selectedCommitID })
            ? selectedCommitID
            : loadedCommits.first?.id
        return CommitLoadPayload(commits: loadedCommits, hasMore: hasMore, selectedCommitID: selected)
    }

    func loadRepository(
        in repositoryURL: URL,
        focusedBranch: String?,
        selectedCommitID: String?,
        selectedStash: String,
        options: RepositoryLoadOptions = .full,
        limit: Int
    ) throws -> RepositoryLoadPayload {
        guard isGitRepository(at: repositoryURL) else {
            return RepositoryLoadPayload(
                currentBranch: "-",
                headShortHash: "-",
                branchInfos: [],
                branches: [],
                focusedBranch: nil,
                tags: [],
                stashes: [],
                selectedStash: "",
                worktrees: [],
                remotes: [],
                commits: [],
                hasMoreCommits: false,
                selectedCommitID: nil,
                hasConflicts: false,
                isMerging: false,
                isRebasing: false,
                isCherryPicking: false,
                isGitRepository: false,
                uncommittedChanges: [],
                uncommittedCount: 0,
                isBisecting: false,
                bisectCurrentHash: ""
            )
        }

        let branch = try currentBranchName(in: repositoryURL)
        let head = (try? currentHeadHash(in: repositoryURL)) ?? "-"
        let infos = try branchInfoList(in: repositoryURL)
        let names = infos.map(\.name)
        let resolvedFocused = focusedBranch.flatMap { names.contains($0) ? $0 : nil }
        let loadedTags = options.includeTagsAndStashes ? try tagList(in: repositoryURL) : []
        let loadedStashes = options.includeTagsAndStashes ? try stashList(in: repositoryURL) : []
        let stashSelection = loadedStashes.contains(selectedStash) ? selectedStash : (loadedStashes.first ?? "")
        let loadedWorktrees = try worktreeList(in: repositoryURL, includeStatus: options.includeWorktreeStatus)
        let loadedRemotes = try remoteList(in: repositoryURL)
        let (loadedCommits, hasMore) = (try? commitList(in: repositoryURL, reference: resolvedFocused, limit: limit)) ?? ([], false)
        let selected = loadedCommits.contains(where: { $0.id == selectedCommitID })
            ? selectedCommitID
            : loadedCommits.first?.id

        let conflictResult = try? git.runAllowingFailure(args: ["ls-files", "--unmerged"], in: repositoryURL)
        let hasConflicts = !(conflictResult?.stdout.clean.isEmpty ?? true)

        let gitDir = repositoryURL.appendingPathComponent(".git")
        let isMerging = FileManager.default.fileExists(atPath: gitDir.appendingPathComponent("MERGE_HEAD").path)
        let isRebasing = FileManager.default.fileExists(atPath: gitDir.appendingPathComponent("rebase-apply").path) ||
                         FileManager.default.fileExists(atPath: gitDir.appendingPathComponent("rebase-merge").path)
        let isCherryPicking = FileManager.default.fileExists(atPath: gitDir.appendingPathComponent("CHERRY_PICK_HEAD").path)
        let isBisecting = FileManager.default.fileExists(atPath: gitDir.appendingPathComponent("BISECT_START").path)
        let bisectCurrentHash: String
        if isBisecting {
            let headResult = try? git.runAllowingFailure(args: ["rev-parse", "HEAD"], in: repositoryURL)
            bisectCurrentHash = headResult?.stdout.clean ?? ""
        } else {
            bisectCurrentHash = ""
        }

        let statusResult = try? git.runAllowingFailure(args: ["status", "--porcelain"], in: repositoryURL)
        let uncommittedLines = statusResult?.stdout.split(separator: "\n").map { String($0) } ?? []

        return RepositoryLoadPayload(
            currentBranch: branch,
            headShortHash: head,
            branchInfos: infos,
            branches: names,
            focusedBranch: resolvedFocused,
            tags: loadedTags,
            stashes: loadedStashes,
            selectedStash: stashSelection,
            worktrees: loadedWorktrees,
            remotes: loadedRemotes,
            commits: loadedCommits,
            hasMoreCommits: hasMore,
            selectedCommitID: selected,
            hasConflicts: hasConflicts,
            isMerging: isMerging,
            isRebasing: isRebasing,
            isCherryPicking: isCherryPicking,
            isGitRepository: true,
            uncommittedChanges: uncommittedLines,
            uncommittedCount: uncommittedLines.count,
            isBisecting: isBisecting,
            bisectCurrentHash: bisectCurrentHash
        )
    }

    // MARK: - Conflict Resolution

    func listConflictedFiles(in repositoryURL: URL) throws -> [ConflictFile] {
        let result = try git.runAllowingFailure(args: ["diff", "--name-only", "--diff-filter=U"], in: repositoryURL)
        guard result.status == 0 else { return [] }
        return result.stdout.clean
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map { ConflictFile(path: $0) }
    }

    func readConflictFileContent(path: String, in repositoryURL: URL) throws -> String {
        let fileURL = repositoryURL.appendingPathComponent(path).standardizedFileURL
        guard fileURL.path.hasPrefix(repositoryURL.standardizedFileURL.path + "/") else {
            throw GitClientError.commandFailed(command: "read", message: "Invalid path: \(path)")
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    func writeResolvedFile(path: String, content: String, in repositoryURL: URL) throws {
        let fileURL = repositoryURL.appendingPathComponent(path).standardizedFileURL
        guard fileURL.path.hasPrefix(repositoryURL.standardizedFileURL.path + "/") else {
            throw GitClientError.commandFailed(command: "write", message: "Invalid path: \(path)")
        }
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func markFileResolved(path: String, in repositoryURL: URL) throws {
        _ = try git.run(args: ["add", "--", path], in: repositoryURL)
    }

    func detectActiveOperation(in repositoryURL: URL) -> String? {
        let gitDir = repositoryURL.appendingPathComponent(".git")
        let fm = FileManager.default
        if fm.fileExists(atPath: gitDir.appendingPathComponent("MERGE_HEAD").path) { return "merge" }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-merge").path) ||
           fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-apply").path) { return "rebase" }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("CHERRY_PICK_HEAD").path) { return "cherry-pick" }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("BISECT_START").path) { return "bisect" }
        return nil
    }

    func continueOperation(in repositoryURL: URL) throws -> String {
        guard let op = detectActiveOperation(in: repositoryURL) else {
            return "No active operation to continue."
        }
        let args: [String]
        switch op {
        case "merge": args = ["merge", "--continue"]
        case "rebase": args = ["rebase", "--continue"]
        case "cherry-pick": args = ["cherry-pick", "--continue"]
        default: return "Unknown operation: \(op)"
        }
        let result = try git.run(args: args, in: repositoryURL)
        return result.stdout.clean.isEmpty ? result.stderr.clean : result.stdout.clean
    }

    // MARK: - Full History Search

    func searchFullHistory(
        query: String,
        in repositoryURL: URL,
        excludeHashes: Set<String>
    ) throws -> [GitSearchResult] {
        let sep = Constants.gitFieldSeparator
        let format = ["%H", "%h", "%an", "%ad", "%s", "%D"].joined(separator: String(sep))
        var allResults: [GitSearchResult] = []
        var seenHashes: Set<String> = []

        func addResults(from output: String, source: GitSearchResult.Source) {
            let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
            for line in lines {
                let fields = line.split(separator: sep, omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 5 else { continue }
                let fullHash = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !fullHash.isEmpty,
                      !excludeHashes.contains(fullHash),
                      !seenHashes.contains(fullHash) else { continue }
                seenHashes.insert(fullHash)

                let shortHash = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let author = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
                let dateStr = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
                let subject = fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
                let decorations: [String] = fields.count > 5
                    ? fields[5].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    : []
                let date = parseISODate(dateStr)

                allResults.append(GitSearchResult(
                    id: fullHash,
                    shortHash: shortHash,
                    author: author,
                    date: date,
                    subject: subject,
                    decorations: decorations,
                    source: source
                ))
            }
        }

        // Search commit messages (--fixed-strings prevents ReDoS via user-crafted regex)
        let messageOutput = try runActionAllowingFailure(
            args: ["log", "--all", "--fixed-strings", "--grep=\(query)", "-i",
                   "--format=\(format)", "--date=iso-strict", "-n", "50"],
            in: repositoryURL
        )
        if messageOutput.status == 0 { addResults(from: messageOutput.output, source: .message) }

        // Search by author
        let authorOutput = try runActionAllowingFailure(
            args: ["log", "--all", "--fixed-strings", "--author=\(query)", "-i",
                   "--format=\(format)", "--date=iso-strict", "-n", "50"],
            in: repositoryURL
        )
        if authorOutput.status == 0 { addResults(from: authorOutput.output, source: .author) }

        // Search by hash prefix (only if 4+ hex chars)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        if query.count >= 4 && query.unicodeScalars.allSatisfy({ hexChars.contains($0) }) {
            let hashOutput = try runActionAllowingFailure(
                args: ["log", "-1", "--format=\(format)", "--date=iso-strict", query],
                in: repositoryURL
            )
            if hashOutput.status == 0 { addResults(from: hashOutput.output, source: .hash) }
        }

        // Search branches (always include -- ref name is unique info even if commit was already found)
        var seenBranches: Set<String> = []
        let branchOutput = try runActionAllowingFailure(
            args: ["branch", "--all", "--list", "*\(query)*",
                   "--format=%(refname:short) %(objectname)"],
            in: repositoryURL
        )
        if branchOutput.status == 0 {
            for line in branchOutput.output.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let branchName = parts[0]
                let fullHash = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !seenBranches.contains(branchName) else { continue }
                seenBranches.insert(branchName)
                let info = try runActionAllowingFailure(
                    args: ["log", "-1", "--format=\(format)", "--date=iso-strict", fullHash],
                    in: repositoryURL
                )
                if info.status == 0 {
                    addResults(from: info.output, source: .branch(branchName))
                }
            }
        }

        // Search tags (always include -- ref name is unique info even if commit was already found)
        var seenTags: Set<String> = []
        let tagOutput = try runActionAllowingFailure(
            args: ["tag", "--list", "*\(query)*",
                   "--format=%(refname:short) %(objectname)"],
            in: repositoryURL
        )
        if tagOutput.status == 0 {
            for line in tagOutput.output.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let tagName = parts[0]
                let fullHash = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !seenTags.contains(tagName) else { continue }
                seenTags.insert(tagName)
                let info = try runActionAllowingFailure(
                    args: ["log", "-1", "--format=\(format)", "--date=iso-strict", fullHash],
                    in: repositoryURL
                )
                if info.status == 0 {
                    addResults(from: info.output, source: .tag(tagName))
                }
            }
        }

        return Array(allResults.prefix(50))
    }

    func parseISODate(_ value: String) -> Date {
        if let parsed = isoDateWithFractions.date(from: value) {
            return parsed
        }
        if let parsed = isoDateWithoutFractions.date(from: value) {
            return parsed
        }
        return Date(timeIntervalSince1970: 0)
    }

    func previousReleaseTag(in repositoryURL: URL) -> String? {
        // Try git describe first (finds most recent tag reachable from HEAD~1)
        if let result = try? runActionAllowingFailure(
            args: ["describe", "--tags", "--abbrev=0", "HEAD~1"],
            in: repositoryURL
        ), result.status == 0, !result.output.isEmpty {
            return result.output
        }
        // Fallback: use the first tag from sorted list (latest version)
        if let tags = try? tagList(in: repositoryURL), let first = tags.first {
            return first
        }
        return nil
    }

    func sortTagsDescending(_ tags: [String]) -> [String] {
        tags.sorted { lhs, rhs in
            let lhsVersion = versionComponents(from: lhs)
            let rhsVersion = versionComponents(from: rhs)

            if !lhsVersion.isEmpty && !rhsVersion.isEmpty {
                let comparison = compareVersionComponents(lhsVersion, rhsVersion)
                if comparison != .orderedSame {
                    return comparison == .orderedDescending
                }
            } else if !lhsVersion.isEmpty {
                return true
            } else if !rhsVersion.isEmpty {
                return false
            }

            return lhs.localizedStandardCompare(rhs) == .orderedDescending
        }
    }

    private func compareVersionComponents(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let leftValue = index < lhs.count ? lhs[index] : 0
            let rightValue = index < rhs.count ? rhs[index] : 0
            if leftValue != rightValue {
                return leftValue < rightValue ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    func versionComponents(from tag: String) -> [Int] {
        let normalized = tag.hasPrefix("v") || tag.hasPrefix("V")
            ? String(tag.dropFirst())
            : tag

        var numbers: [Int] = []
        var current = ""

        for character in normalized {
            if character.isNumber {
                current.append(character)
                continue
            }

            if !current.isEmpty {
                numbers.append(Int(current) ?? 0)
                current = ""
            }
        }

        if !current.isEmpty {
            numbers.append(Int(current) ?? 0)
        }

        return numbers
    }
}

extension String {
    var clean: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Array where Element: Hashable {
    func mostFrequent() -> Element? {
        var counts: [Element: Int] = [:]
        for element in self { counts[element, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
