// RepoMemorySearch.swift — zion_repo_memory_search tool

import Foundation

// MARK: - Local Codable replica (no link to main Zion target)

private struct RMSCommitStyleProfile: Codable {
    let usesConventionalCommits: Bool
    let commonTypes: [String]
    let commonScopes: [String]
    let preferredVerbStyle: String
    let averageTitleLength: Int
}

private struct RMSSnapshot: Codable {
    let schemaVersion: Int
    let repositoryID: String
    let generatedAt: Date
    let activeBranch: String
    let headShortHash: String
    let commitStyle: RMSCommitStyleProfile
    let moduleHints: [String]
    let branchPatterns: [String]
    let conventions: [String]
    let testMappings: [String: [String]]
    let sensitiveAreas: [String]
}

// MARK: - Search result entry

private struct SearchEntry {
    let path: String       // snapshot filename (storage location is not exposed)
    let kind: String       // "moduleHint" | "branchPattern" | "convention" | "testKey"
    let snippet: String    // the matching value
    let score: Int
    let date: Date
}

// MARK: - zion_repo_memory_search

struct RepoMemorySearchTool: Tool {
    let repoURL: URL

    /// Injected for tests; defaults to the real Application Support directory.
    let snapshotsDir: URL

    /// Default initialiser pointing at the real location.
    init(repoURL: URL) {
        self.repoURL = repoURL
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.snapshotsDir = appSupport
            .appendingPathComponent("Zion/RepoMemory", isDirectory: true)
    }

    /// Injected initialiser for tests.
    init(repoURL: URL, snapshotsDir: URL) {
        self.repoURL = repoURL
        self.snapshotsDir = snapshotsDir
    }

    var name: String { "zion_repo_memory_search" }
    var description: String {
        "Search repository memory snapshots for modules, branches, conventions and test mappings matching a query."
    }

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Search query — whitespace-split terms matched against snapshot fields.")
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximum results to return. Default 8.")
                ])
            ]),
            "required": .array([.string("query")])
        ]
    }

    func call(args: [String: JSONValue]) throws -> JSONValue {
        let query = try args.requireString("query")
        let limit: Int
        if let v = args["limit"], case .int(let n) = v {
            limit = max(1, min(n, 20))
        } else {
            limit = 8
        }

        let terms = query
            .components(separatedBy: .whitespaces)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }

        guard !terms.isEmpty else {
            return makeContent(["results": .array([])])
        }

        // Only the active repository's memory may enter this chat session.
        let snapshots = loadCurrentRepositorySnapshot()

        // Collect + score entries
        var entries: [SearchEntry] = []
        for (fileURL, snapshot) in snapshots {
            entries += scoredEntries(for: snapshot, fileURL: fileURL, terms: terms)
        }

        // Sort by score desc, then by date desc
        entries.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.date > $1.date
        }

        let top = Array(entries.prefix(limit))
        let resultsJSON: [JSONValue] = top.map { e in
            .object([
                "path":    .string(e.path),
                "kind":    .string(e.kind),
                "score":   .int(e.score),
                "snippet": .string(e.snippet)
            ])
        }

        return makeContent(["results": .array(resultsJSON)])
    }

    // MARK: - Private

    private func loadCurrentRepositorySnapshot() -> [(URL, RMSSnapshot)] {
        let fingerprint = RepoMapTool.computeRepoID(for: repoURL)
        let fileURL = snapshotsDir.appendingPathComponent("\(fingerprint).json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(RMSSnapshot.self, from: data),
              snapshot.repositoryID.hasPrefix(fingerprint + "-") else {
            return []
        }
        return [(fileURL, snapshot)]
    }

    private func scoredEntries(
        for snapshot: RMSSnapshot,
        fileURL: URL,
        terms: [String]
    ) -> [SearchEntry] {
        var entries: [SearchEntry] = []
        let date = snapshot.generatedAt
        let path = fileURL.lastPathComponent

        // moduleHints — weight 3 (treated like "name")
        for hint in snapshot.moduleHints {
            let score = termScore(text: hint.lowercased(), terms: terms, weight: 3)
            if score > 0 {
                entries.append(SearchEntry(path: path, kind: "moduleHint",
                                           snippet: hint, score: score, date: date))
            }
        }

        // branchPatterns — weight 2
        for pattern in snapshot.branchPatterns {
            let score = termScore(text: pattern.lowercased(), terms: terms, weight: 2)
            if score > 0 {
                entries.append(SearchEntry(path: path, kind: "branchPattern",
                                           snippet: pattern, score: score, date: date))
            }
        }

        // conventions — weight 2
        for convention in snapshot.conventions {
            let score = termScore(text: convention.lowercased(), terms: terms, weight: 2)
            if score > 0 {
                entries.append(SearchEntry(path: path, kind: "convention",
                                           snippet: convention, score: score, date: date))
            }
        }

        // testMappings keys — weight 2
        for (testKey, _) in snapshot.testMappings {
            let score = termScore(text: testKey.lowercased(), terms: terms, weight: 2)
            if score > 0 {
                entries.append(SearchEntry(path: path, kind: "testKey",
                                           snippet: testKey, score: score, date: date))
            }
        }

        // commitStyle scopes / types — weight 1
        for scope in snapshot.commitStyle.commonScopes {
            let score = termScore(text: scope.lowercased(), terms: terms, weight: 1)
            if score > 0 {
                entries.append(SearchEntry(path: path, kind: "commitScope",
                                           snippet: scope, score: score, date: date))
            }
        }

        return entries
    }

    /// Count occurrences of each term in `text`, multiply by `weight`.
    private func termScore(text: String, terms: [String], weight: Int) -> Int {
        var total = 0
        for term in terms {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: term, options: .caseInsensitive, range: searchRange) {
                total += weight
                searchRange = range.upperBound..<text.endIndex
            }
        }
        return total
    }
}
