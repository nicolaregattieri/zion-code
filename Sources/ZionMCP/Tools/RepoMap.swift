// RepoMap.swift — zion_repo_map tool
// Reads the snapshot JSON written by RepoMapService and returns ranked entries.
// Cannot import Zion target — types duplicated here.

import CryptoKit
import Foundation

// MARK: - Local snapshot types (must match RepoMapService serialised schema)

private struct RMEntry: Codable {
    let path: String
    let kind: String
    let name: String
    let score: Double
    let snippet: String?
}

private struct RMSnapshot: Codable {
    let repoID: String
    let indexedAt: Double   // epoch seconds (JSONEncoder default for Date)
    let entries: [RMEntry]
    let references: [String: [String]]
}

// MARK: - zion_repo_map

struct RepoMapTool: Tool {
    /// Repo root — used to derive repoID and as injected path in tests.
    let repoURL: URL

    /// Override snapshot directory for tests.
    let snapshotDir: URL?

    // MARK: - Initialisers

    init(repoURL: URL) {
        self.repoURL = repoURL
        self.snapshotDir = nil
    }

    /// Test-only: inject custom snapshot directory.
    init(repoURL: URL, snapshotDir: URL) {
        self.repoURL = repoURL
        self.snapshotDir = snapshotDir
    }

    // MARK: - Tool protocol

    var name: String { "zion_repo_map" }
    var description: String {
        "Search the repository symbol map for entries matching a query. " +
        "Returns ranked entries (name × 3, path × 1, snippet × 0.5)."
    }

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Search query against symbol names, paths, and snippets.")
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximum results to return. Default 30.")
                ])
            ]),
            "required": .array([.string("query")])
        ]
    }

    func call(args: [String: JSONValue]) throws -> JSONValue {
        let query = try args.requireString("query")
        let limit: Int
        if let v = args["limit"], case .int(let n) = v {
            limit = max(1, min(n, 50))
        } else {
            limit = 30
        }

        let repoID = Self.computeRepoID(for: repoURL)
        let snapshotURL = resolvedSnapshotDir()
            .appendingPathComponent("\(repoID).json")

        // Load snapshot
        guard let data = try? Data(contentsOf: snapshotURL) else {
            return makeContent([
                "available": .bool(false),
                "reason": .string("no_snapshot"),
                "entries": .array([])
            ])
        }

        let decoder = JSONDecoder()
        // The snapshot uses epoch-seconds for indexedAt written by JSONEncoder with .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(RMSnapshot.self, from: data) else {
            return makeContent([
                "available": .bool(false),
                "reason": .string("malformed_snapshot"),
                "entries": .array([])
            ])
        }

        // Score and rank
        let lq = query.lowercased()
        var scored: [(entry: RMEntry, score: Double)] = snapshot.entries.compactMap { entry in
            var s = 0.0
            if entry.name.lowercased().contains(lq)              { s += 3.0 }
            if entry.path.lowercased().contains(lq)              { s += 1.0 }
            if let snip = entry.snippet, snip.lowercased().contains(lq) { s += 0.5 }
            guard s > 0 else { return nil }
            // Break ties using stored PageRank score
            return (entry, s + entry.score * 0.001)
        }

        scored.sort { $0.score > $1.score }
        let top = Array(scored.prefix(limit))

        let entriesJSON: [JSONValue] = top.map { item in
            var obj: [String: JSONValue] = [
                "path":  .string(item.entry.path),
                "kind":  .string(item.entry.kind),
                "name":  .string(item.entry.name),
                "score": .double(item.entry.score)
            ]
            if let snip = item.entry.snippet {
                obj["snippet"] = .string(snip)
            }
            return .object(obj)
        }

        return makeContent([
            "available": .bool(true),
            "entries": .array(entriesJSON)
        ])
    }

    // MARK: - Helpers

    /// Replicates RepoMapService.repoID(for:) exactly.
    static func computeRepoID(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let data = Data(path.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func resolvedSnapshotDir() -> URL {
        if let dir = snapshotDir { return dir }
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Zion")
            .appendingPathComponent("repo-map")
    }
}
