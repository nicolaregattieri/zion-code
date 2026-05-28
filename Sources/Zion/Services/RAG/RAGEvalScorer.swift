import Foundation

/// Phase 5d — Recall@K scorer for the hand-labeled golden fixture.
/// Given a query and an expected-files list, considers the query "hit"
/// when at least one expected file appears in the top-K results.
///
/// Recall@K = hits / total_queries.
///
/// Path matching is permissive: a result hit's `path` matches an
/// expected entry when the result path ENDS WITH the expected one OR
/// the expected one is a prefix-directory of the result. Real Zion
/// paths are repo-relative (`Sources/Zion/...`); the indexer also
/// stores them repo-relative so the match is straightforward.
enum RAGEvalScorer {

    struct GoldenEntry: Codable, Equatable {
        let query: String
        let expectedFiles: [String]
    }

    struct Result: Equatable {
        let totalQueries: Int
        let hits: Int
        var recallAtK: Double {
            guard totalQueries > 0 else { return 0 }
            return Double(hits) / Double(totalQueries)
        }
    }

    /// Treat a result `path` as a match for an `expected` entry when:
    /// 1. `path` is exactly `expected`, OR
    /// 2. `path` ends with `expected` (handles absolute → relative mismatch), OR
    /// 3. `path` starts with `expected + "/"` (expected is a directory hit).
    static func matches(path: String, expected: String) -> Bool {
        if path == expected { return true }
        if path.hasSuffix(expected) { return true }
        if path.hasPrefix(expected + "/") { return true }
        return false
    }

    /// Score a golden-set run. `runQuery` is invoked once per entry
    /// and returns the top-K result paths in order.
    static func score(
        entries: [GoldenEntry],
        runQuery: (String) async throws -> [String]
    ) async throws -> Result {
        var hits = 0
        for entry in entries {
            let paths = try await runQuery(entry.query)
            let matched = paths.contains { resultPath in
                entry.expectedFiles.contains { expected in
                    matches(path: resultPath, expected: expected)
                }
            }
            if matched { hits += 1 }
        }
        return Result(totalQueries: entries.count, hits: hits)
    }
}
