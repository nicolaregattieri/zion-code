import Foundation

struct CommitLoadPayload: Sendable {
    let commits: [Commit]
    let hasMore: Bool
    let selectedCommitID: String?
}

struct RepositoryLoadPayload: Sendable {
    let currentBranch: String
    let headShortHash: String
    let branchInfos: [BranchInfo]
    let branches: [String]
    let focusedBranch: String?
    let branchTree: [BranchTreeNode]
    let tags: [String]
    let stashes: [String]
    let selectedStash: String
    let worktrees: [WorktreeItem]
    let remotes: [RemoteInfo]
    let commits: [Commit]
    let hasMoreCommits: Bool
    let selectedCommitID: String?
    let hasConflicts: Bool
    let isMerging: Bool
    let isRebasing: Bool
    let isCherryPicking: Bool
    let isGitRepository: Bool
    let uncommittedChanges: [String]
    let uncommittedCount: Int
}

actor RepositoryWorker {
    private let git = GitClient()
    private let laneCalculator = GitGraphLaneCalculator()
    private let isoDateWithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let isoDateWithoutFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

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
        inferOrigins: Bool,
        limit: Int
    ) throws -> RepositoryLoadPayload {
        guard isGitRepository(at: repositoryURL) else {
            return RepositoryLoadPayload(
                currentBranch: "-",
                headShortHash: "-",
                branchInfos: [],
                branches: [],
                focusedBranch: nil,
                branchTree: [],
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
                uncommittedCount: 0
            )
        }

        let branch = try currentBranchName(in: repositoryURL)
        let head = (try? currentHeadHash(in: repositoryURL)) ?? "-"
        let infos = try branchInfoList(in: repositoryURL)
        let names = infos.map(\.name)
        let resolvedFocused = focusedBranch.flatMap { names.contains($0) ? $0 : nil }
        let tree = try buildBranchTree(in: repositoryURL, using: infos, inferOrigins: inferOrigins)
        let loadedTags = try tagList(in: repositoryURL)
        let loadedStashes = try stashList(in: repositoryURL)
        let stashSelection = loadedStashes.contains(selectedStash) ? selectedStash : (loadedStashes.first ?? "")
        let loadedWorktrees = try worktreeList(in: repositoryURL)
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

        let statusResult = try? git.runAllowingFailure(args: ["status", "--porcelain"], in: repositoryURL)
        let uncommittedLines = statusResult?.stdout.split(separator: "\n").map { String($0) } ?? []

        return RepositoryLoadPayload(
            currentBranch: branch,
            headShortHash: head,
            branchInfos: infos,
            branches: names,
            focusedBranch: resolvedFocused,
            branchTree: tree,
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
            uncommittedCount: uncommittedLines.count
        )
    }

    func runAction(args: [String], in repositoryURL: URL) throws -> String {
        let result = try git.run(args: args, in: repositoryURL)
        return result.stdout.clean.isEmpty ? result.stderr.clean : result.stdout.clean
    }

    nonisolated func runShellStream(command: String, in repositoryURL: URL, onOutput: @escaping @Sendable (String) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "export PATH=\"/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH\"; \(command)"]
        process.currentDirectoryURL = repositoryURL
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                onOutput(str)
            }
        }
        
        try process.run()
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
    }

    func loadCommitDetails(in repositoryURL: URL, commitID: String) throws -> String {
        try git.run(
            args: ["show", "--no-color", "--name-status", "--pretty=fuller", commitID],
            in: repositoryURL
        ).stdout
    }

    private func currentBranchName(in repositoryURL: URL) throws -> String {
        let branch = try git.runAllowingFailure(args: ["branch", "--show-current"], in: repositoryURL).stdout.clean
        if !branch.isEmpty { return branch }
        
        // If empty, we are likely in detached HEAD. Try to find if we are at a tag or remote branch.
        let describe = try? git.runAllowingFailure(args: ["describe", "--tags", "--exact-match"], in: repositoryURL).stdout.clean
        if let tag = describe, !tag.isEmpty {
            return "detached (tag: \(tag))"
        }
        
        let hash = try? currentHeadHash(in: repositoryURL)
        return "detached (\(hash ?? "unknown"))"
    }

    private func currentHeadHash(in repositoryURL: URL) throws -> String {
        try git.run(args: ["rev-parse", "--short", "HEAD"], in: repositoryURL).stdout.clean
    }

    private func remoteList(in repositoryURL: URL) throws -> [RemoteInfo] {
        let output = try git.run(args: ["remote", "-v"], in: repositoryURL).stdout
        var remotesMap: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            if parts.count >= 2 {
                let name = String(parts[0])
                let urlAndType = String(parts[1])
                let url = urlAndType.split(separator: " ").first.map(String.init) ?? ""
                remotesMap[name] = url
            }
        }
        return remotesMap.map { RemoteInfo(name: $0.key, url: $0.value) }.sorted { $0.name < $1.name }
    }

    private func branchInfoList(in repositoryURL: URL) throws -> [BranchInfo] {
        let recordSeparator = Character(UnicodeScalar(0x1e)!)
        let fieldSeparator = Character(UnicodeScalar(0x1f)!)
        let output = try git.run(
            args: [
                "for-each-ref",
                "--sort=-committerdate",
                "--format=%(refname)%x1F%(refname:short)%x1F%(objectname)%x1F%(upstream:short)%x1F%(committerdate:iso-strict)%x1E",
                "refs/heads",
                "refs/remotes"
            ],
            in: repositoryURL
        ).stdout

        return output
            .split(separator: recordSeparator, omittingEmptySubsequences: true)
            .compactMap { rawRecord in
                let fields = rawRecord.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 5 else { return nil }

                let fullRef = fields[0].clean
                let name = fields[1].clean
                let head = fields[2].clean
                let upstream = fields[3].clean
                let date = parseISODate(fields[4].clean)
                let isRemote = fullRef.hasPrefix("refs/remotes/")

                if isRemote, name.hasSuffix("/HEAD") {
                    return nil
                }

                return BranchInfo(
                    name: name,
                    fullRef: fullRef,
                    head: head,
                    upstream: upstream,
                    committerDate: date,
                    isRemote: isRemote
                )
            }
    }

    private func tagList(in repositoryURL: URL) throws -> [String] {
        let output = try git.run(args: ["tag", "--list", "--sort=-creatordate"], in: repositoryURL).stdout
        let tags = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        return sortTagsDescending(tags)
    }

    private func stashList(in repositoryURL: URL) throws -> [String] {
        let output = try git.run(args: ["stash", "list"], in: repositoryURL).stdout
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func worktreeList(in repositoryURL: URL) throws -> [WorktreeItem] {
        let output = try git.run(args: ["worktree", "list", "--porcelain"], in: repositoryURL).stdout
        let currentPath = repositoryURL.path
        return parseWorktrees(from: output, currentPath: currentPath)
    }

    private func commitList(in repositoryURL: URL, reference: String?, limit: Int) throws -> ([Commit], Bool) {
        let effectiveLimit = max(150, limit)
        let format = "%H%x1F%P%x1F%an%x1F%ad%x1F%s%x1F%D%x1E"
        var args = ["log"]
        if let reference, !reference.clean.isEmpty {
            args.append(reference.clean)
        } else {
            args.append("--all")
        }
        args.append("--topo-order")
        args.append("--max-count=\(effectiveLimit + 1)")
        args.append(contentsOf: ["--date=iso-strict", "--pretty=format:\(format)"])

        let output = try git.run(args: args, in: repositoryURL).stdout

        let parsed = parseCommits(from: output)
        let hasMore = parsed.count > effectiveLimit
        let visibleParsed = hasMore ? Array(parsed.prefix(effectiveLimit)) : parsed
        let layout = laneCalculator.layout(for: visibleParsed)
        let layoutByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })

        let commits = visibleParsed.map { entry in
            let laneData = layoutByID[entry.hash] ?? CommitGraphLayout(
                id: entry.hash,
                lane: 0,
                nodeColorKey: 0,
                incomingLanes: [0],
                outgoingLanes: [0],
                laneColors: [LaneColor(lane: 0, colorKey: 0)],
                outgoingEdges: [LaneEdge(from: 0, to: 0, colorKey: 0)]
            )
            return Commit(
                id: entry.hash,
                shortHash: String(entry.hash.prefix(8)),
                parents: entry.parents,
                author: entry.author,
                date: entry.date,
                subject: entry.subject,
                decorations: entry.decorations,
                lane: laneData.lane,
                nodeColorKey: laneData.nodeColorKey,
                incomingLanes: laneData.incomingLanes,
                outgoingLanes: laneData.outgoingLanes,
                laneColors: laneData.laneColors,
                outgoingEdges: laneData.outgoingEdges
            )
        }
        return (commits, hasMore)
    }

    private func buildBranchTree(
        in repositoryURL: URL,
        using infos: [BranchInfo],
        inferOrigins: Bool
    ) throws -> [BranchTreeNode] {
        let locals = infos
            .filter { !$0.isRemote }
            .sorted { $0.committerDate > $1.committerDate }
        let remotes = infos
            .filter(\.isRemote)
            .sorted { $0.name < $1.name }

        let localNames = Set(locals.map(\.name))
        let preferredRoots = ["main", "master", "develop", "dev", "trunk", "production"]
            .filter(localNames.contains)
        var parentByChild: [String: String] = [:]
        var forkByChild: [String: String] = [:]

        let shouldComputeForkMergeBase = inferOrigins && locals.count <= 48

        for branch in locals {
            if preferredRoots.contains(branch.name) {
                continue
            }

            var parentRef: String?
            if !branch.upstream.isEmpty {
                parentRef = branch.upstream
            } else if inferOrigins {
                parentRef = guessBestParent(for: branch.name, preferredRoots: preferredRoots)
            }

            guard let parentRef, parentRef != branch.name else { continue }
            parentByChild[branch.name] = parentRef

            if shouldComputeForkMergeBase,
               localNames.contains(parentRef),
               let mergeBase = mergeBase(branch.name, parentRef, in: repositoryURL) {
                forkByChild[branch.name] = String(mergeBase.prefix(8))
            }
        }

        let childrenByParent = Dictionary(grouping: locals) { branch -> String? in
            guard let parent = parentByChild[branch.name], localNames.contains(parent) else {
                return nil
            }
            return parent
        }

        func subtitle(for branch: BranchInfo) -> String {
            var parts: [String] = []
            if let parent = parentByChild[branch.name] {
                parts.append("from: \(parent)")
            }
            if let fork = forkByChild[branch.name] {
                parts.append("fork: \(fork)")
            }
            if !branch.upstream.isEmpty {
                parts.append("upstream: \(branch.upstream)")
            } else {
                parts.append("HEAD \(branch.shortHead)")
            }
            return parts.joined(separator: " | ")
        }

        func makeLocalNode(_ branch: BranchInfo) -> BranchTreeNode {
            let children = (childrenByParent[branch.name] ?? [])
                .sorted { $0.committerDate > $1.committerDate }
                .map(makeLocalNode)

            return BranchTreeNode(
                id: "local:\(branch.name)",
                title: branch.name,
                subtitle: subtitle(for: branch),
                branchName: branch.name,
                children: children
            )
        }

        let localRootsInfos = locals
            .filter { branch in
                guard let parent = parentByChild[branch.name] else { return true }
                return !localNames.contains(parent)
            }
            .sorted { $0.committerDate > $1.committerDate }

        let localRoots: [BranchTreeNode]
        if localRootsInfos.count > 20 {
            localRoots = groupedLocalRootNodes(localRootsInfos, subtitleProvider: subtitle)
        } else {
            localRoots = localRootsInfos.map(makeLocalNode)
        }

        let localGroup = BranchTreeNode(
            id: "group:locals",
            title: "Local branches",
            subtitle: shouldComputeForkMergeBase ? "\(locals.count)" : "\(locals.count) · inferencia rapida",
            branchName: nil,
            children: localRoots
        )

        let remoteChildrenByRemote = Dictionary(grouping: remotes) { info -> String in
            info.name.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? "remote"
        }

        let remoteGroups = remoteChildrenByRemote
            .sorted { $0.key < $1.key }
            .map { remoteName, remoteBranches in
                let children = remoteBranches
                    .sorted { $0.name < $1.name }
                    .map { branch -> BranchTreeNode in
                        let shortName = branch.name.hasPrefix("\(remoteName)/")
                            ? String(branch.name.dropFirst(remoteName.count + 1))
                            : branch.name
                        return BranchTreeNode(
                            id: "remote:\(branch.name)",
                            title: shortName,
                            subtitle: "HEAD \(branch.shortHead)",
                            branchName: branch.name,
                            children: []
                        )
                    }
                return BranchTreeNode(
                    id: "group:remote:\(remoteName)",
                    title: remoteName,
                    subtitle: "\(remoteBranches.count)",
                    branchName: nil,
                    children: children
                )
            }

        let remoteGroup = BranchTreeNode(
            id: "group:remotes",
            title: "Remote branches",
            subtitle: "\(remotes.count)",
            branchName: nil,
            children: remoteGroups
        )

        return [localGroup, remoteGroup]
    }

    private func groupedLocalRootNodes(
        _ roots: [BranchInfo],
        subtitleProvider: (BranchInfo) -> String
    ) -> [BranchTreeNode] {
        let grouped = Dictionary(grouping: roots) { branch -> String in
            let parts = branch.name.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                return String(parts[0])
            }
            return "misc"
        }

        return grouped
            .sorted { $0.key < $1.key }
            .map { namespace, branches in
                let children = branches
                    .sorted { $0.committerDate > $1.committerDate }
                    .map { branch in
                        let title: String
                        if namespace == "misc" {
                            title = branch.name
                        } else if branch.name.hasPrefix("\(namespace)/") {
                            title = String(branch.name.dropFirst(namespace.count + 1))
                        } else {
                            title = branch.name
                        }

                        return BranchTreeNode(
                            id: "local-grouped:\(branch.name)",
                            title: title,
                            subtitle: subtitleProvider(branch),
                            branchName: branch.name,
                            children: []
                        )
                    }

                return BranchTreeNode(
                    id: "local-namespace:\(namespace)",
                    title: namespace,
                    subtitle: "\(branches.count)",
                    branchName: nil,
                    children: children
                )
            }
    }

    private func mergeBase(_ lhs: String, _ rhs: String, in repositoryURL: URL) -> String? {
        guard !lhs.clean.isEmpty, !rhs.clean.isEmpty else { return nil }
        do {
            let result = try git.runAllowingFailure(args: ["merge-base", lhs, rhs], in: repositoryURL)
            guard result.status == 0 else { return nil }
            let value = result.stdout.clean
            return value.isEmpty ? nil : value
        } catch {
            return nil
        }
    }

    private func guessBestParent(for branch: String, preferredRoots: [String]) -> String? {
        guard !branch.clean.isEmpty else { return nil }

        if branch.hasPrefix("hotfix/") || branch.hasPrefix("release/") {
            return preferredRoots.first(where: { $0 == "main" || $0 == "master" }) ?? preferredRoots.first
        }
        if branch.hasPrefix("feature/") || branch.hasPrefix("bugfix/") || branch.hasPrefix("chore/") || branch.hasPrefix("test/") {
            return preferredRoots.first(where: { $0 == "develop" || $0 == "dev" })
                ?? preferredRoots.first(where: { $0 == "main" || $0 == "master" })
                ?? preferredRoots.first
        }

        return preferredRoots.first(where: { $0 == "main" || $0 == "master" })
            ?? preferredRoots.first
    }

    private func parseCommits(from output: String) -> [ParsedCommit] {
        let recordSeparator = Character(UnicodeScalar(0x1e)!)
        let fieldSeparator = Character(UnicodeScalar(0x1f)!)

        return output
            .split(separator: recordSeparator, omittingEmptySubsequences: true)
            .compactMap { rawRecord in
                let fields = rawRecord.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 6 else { return nil }

                let hash = fields[0].clean
                guard !hash.isEmpty else { return nil }

                let parents = fields[1]
                    .split(separator: " ", omittingEmptySubsequences: true)
                    .map(String.init)

                let author = fields[2].clean
                let dateValue = parseISODate(fields[3].clean)
                let subject = fields[4].clean
                let decorations = fields[5]
                    .split(separator: ",", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

                return ParsedCommit(
                    hash: hash,
                    parents: parents,
                    author: author,
                    date: dateValue,
                    subject: subject,
                    decorations: decorations
                )
            }
    }

    private func parseWorktrees(from output: String, currentPath: String) -> [WorktreeItem] {
        var items: [WorktreeItem] = []
        var path = ""
        var head = ""
        var branch = ""
        var isDetached = false
        var isLocked = false
        var lockReason = ""
        var isPrunable = false
        var pruneReason = ""

        func flush() {
            guard !path.isEmpty else { return }
            let normalizedBranch = branch
                .replacingOccurrences(of: "refs/heads/", with: "")
                .replacingOccurrences(of: "refs/remotes/", with: "")
            let isCurrent = URL(fileURLWithPath: path).standardized.path == URL(fileURLWithPath: currentPath).standardized.path
            items.append(
                WorktreeItem(
                    path: path,
                    head: String(head.prefix(8)),
                    branch: normalizedBranch.isEmpty ? "detached" : normalizedBranch,
                    isDetached: isDetached,
                    isLocked: isLocked,
                    lockReason: lockReason,
                    isPrunable: isPrunable,
                    pruneReason: pruneReason,
                    isCurrent: isCurrent
                )
            )
            path = ""
            head = ""
            branch = ""
            isDetached = false
            isLocked = false
            lockReason = ""
            isPrunable = false
            pruneReason = ""
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) + [""] {
            if line.isEmpty {
                flush()
                continue
            }

            if line.hasPrefix("worktree ") {
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                branch = String(line.dropFirst("branch ".count))
            } else if line.hasPrefix("locked") {
                isLocked = true
                lockReason = String(line.dropFirst("locked".count)).clean
            } else if line.hasPrefix("prunable") {
                isPrunable = true
                pruneReason = String(line.dropFirst("prunable".count)).clean
            } else if line == "detached" {
                isDetached = true
            }
        }

        return items
    }

    private func parseISODate(_ value: String) -> Date {
        if let parsed = isoDateWithFractions.date(from: value) {
            return parsed
        }
        if let parsed = isoDateWithoutFractions.date(from: value) {
            return parsed
        }
        return Date(timeIntervalSince1970: 0)
    }

    private func sortTagsDescending(_ tags: [String]) -> [String] {
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
            let l = index < lhs.count ? lhs[index] : 0
            let r = index < rhs.count ? rhs[index] : 0
            if l != r {
                return l < r ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    private func versionComponents(from tag: String) -> [Int] {
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
