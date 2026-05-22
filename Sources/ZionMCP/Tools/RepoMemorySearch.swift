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
    let path: String       // snapshot file path
    let kind: String       // "moduleHint" | "branchPattern" | "convention" | "testKey"
    let snippet: String    // the matching value
    let score: Int
    let date: Date
}

// MARK: - zion_repo_memory_search

struct RepoMemorySearchTool: Tool {
    /// Injected for tests; defaults to the real Application Support directory.
    let snapshotsDir: URL

    /// Default initialiser pointing at the real location.
    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.snapshotsDir = appSupport
            .appendingPathComponent("Zion")
            .appendingPathComponent("repo-memory")
    }

    /// Injected initialiser for tests.
    init(snapshotsDir: URL) {
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
            limit = max(1, n)
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

        // Load all snapshot files
        let snapshots = loadSnapshots()

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

    private func loadSnapshots() -> [(URL, RMSSnapshot)] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: snapshotsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var result: [(URL, RMSSnapshot)] = []
        for fileURL in contents where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let snapshot = try? decoder.decode(RMSSnapshot.self, from: data) else {
                continue // skip malformed files
            }
            result.append((fileURL, snapshot))
        }
        return result
    }

    private func scoredEntries(
        for snapshot: RMSSnapshot,
        fileURL: URL,
        terms: [String]
    ) -> [SearchEntry] {
        var entries: [SearchEntry] = []
        let date = snapshot.generatedAt
        let path = fileURL.path

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
