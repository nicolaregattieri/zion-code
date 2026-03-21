import Foundation

extension RepositoryWorker {

    func loadCommitDetails(in repositoryURL: URL, commitID: String) throws -> String {
        guard commitID.allSatisfy({ $0.isHexDigit }) else {
            throw GitClientError.commandFailed(command: "show", message: "Invalid commit ID: \(commitID)")
        }
        return try git.run(
            args: ["show", "--no-color", "--name-status", "--pretty=fuller", "--first-parent", commitID],
            in: repositoryURL
        ).stdout
    }

    func commitList(in repositoryURL: URL, reference: String?, limit: Int) throws -> ([Commit], Bool) {
        let effectiveLimit = max(150, limit)
        let format = "%H%x1F%P%x1F%an%x1F%ae%x1F%ad%x1F%s%x1F%D%x1E"
        var args = ["log"]
        if let reference, !reference.clean.isEmpty {
            args.append("--")
            args.append(reference.clean)
        } else {
            args.append("--all")
        }
        args.append("--topo-order")
        args.append("--max-count=\(effectiveLimit + 1)")
        args.append(contentsOf: ["--date=iso-strict", "--pretty=format:\(format)"])

        let output = try git.run(args: args, in: repositoryURL).stdout

        let rawParsed = parseCommits(from: output)
        let hasMore = rawParsed.count > effectiveLimit
        let parsed = collapseStashHelperCommits(in: hasMore ? Array(rawParsed.prefix(effectiveLimit)) : rawParsed)
        let visibleParsed = parsed

        // When showing all branches, compute main-chain to pin main line to lane 0
        let mainChain: Set<String>
        if reference == nil {
            mainChain = GitGraphLaneCalculator.mainFirstParentChain(from: visibleParsed)
        } else {
            mainChain = []
        }
        let layout = laneCalculator.layout(for: visibleParsed, mainChain: mainChain)
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
                email: entry.email,
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

    // MARK: - Commit Stats (insertions/deletions)

    func fetchCommitStats(in repositoryURL: URL, hashes: [String]) throws -> [String: (Int, Int)] {
        guard !hashes.isEmpty else { return [:] }
        // Use --shortstat to get compact "+N -M" per commit
        let limit = min(hashes.count, 500)
        let args = ["log", "--all", "--shortstat", "--format=%H", "--max-count=\(limit)"]
        let output = try git.run(args: args, in: repositoryURL).stdout

        var stats: [String: (Int, Int)] = [:]
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var currentHash: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Full SHA hash line (40 hex chars)
            if trimmed.count == 40, trimmed.allSatisfy({ $0.isHexDigit }) {
                currentHash = trimmed
                continue
            }

            // Shortstat line: "N files changed, N insertions(+), N deletions(-)"
            if let hash = currentHash, trimmed.contains("changed") {
                var ins = 0, del = 0
                let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                for part in parts {
                    if part.contains("insertion") {
                        ins = Int(part.split(separator: " ").first ?? "0") ?? 0
                    } else if part.contains("deletion") {
                        del = Int(part.split(separator: " ").first ?? "0") ?? 0
                    }
                }
                stats[hash] = (ins, del)
                currentHash = nil
            }
        }
        return stats
    }

    func parseCommits(from output: String) -> [ParsedCommit] {
        let recordSeparator = Constants.gitRecordSeparator
        let fieldSeparator = Constants.gitFieldSeparator

        return output
            .split(separator: recordSeparator, omittingEmptySubsequences: true)
            .compactMap { rawRecord in
                let fields = rawRecord.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 7 else { return nil }

                let hash = fields[0].clean
                guard !hash.isEmpty else { return nil }

                let parents = fields[1]
                    .split(separator: " ", omittingEmptySubsequences: true)
                    .map(String.init)

                let author = fields[2].clean
                let email = fields[3].clean
                let dateValue = parseISODate(fields[4].clean)
                let subject = fields[5].clean
                let decorations = fields[6]
                    .split(separator: ",", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

                return ParsedCommit(
                    hash: hash,
                    parents: parents,
                    author: author,
                    email: email,
                    date: dateValue,
                    subject: subject,
                    decorations: decorations
                )
            }
    }

    func collapseStashHelperCommits(in commits: [ParsedCommit]) -> [ParsedCommit] {
        guard !commits.isEmpty else { return commits }

        let hiddenHelperHashes = Set(
            commits
                .filter { commit in
                    commit.decorations.contains { $0.contains("refs/stash") }
                }
                .flatMap { Array($0.parents.dropFirst()) }
        )

        guard !hiddenHelperHashes.isEmpty else { return commits }

        return commits.compactMap { commit in
            guard !hiddenHelperHashes.contains(commit.hash) else { return nil }

            if commit.decorations.contains(where: { $0.contains("refs/stash") }) {
                return ParsedCommit(
                    hash: commit.hash,
                    parents: commit.parents.first.map { [$0] } ?? [],
                    author: commit.author,
                    email: commit.email,
                    date: commit.date,
                    subject: commit.subject,
                    decorations: commit.decorations
                )
            }

            return commit
        }
    }
}
