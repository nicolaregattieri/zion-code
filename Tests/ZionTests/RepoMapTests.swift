import XCTest
import GRDB
@testable import Zion

// MARK: - RepoMapTests

final class RepoMapTests: XCTestCase {

    // MARK: - Helpers

    private func makeDB() throws -> (SymbolDB, URL) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        let db = try SymbolDB(path: path)
        return (db, path)
    }

    private func tearDownDB(_ db: inout SymbolDB?, path: URL) {
        db = nil
        try? FileManager.default.removeItem(at: path)
    }

    // MARK: - PageRanker Tests

    /// 1. Uniform distribution: 5 nodes, no edges, no personalization → all ranks ≈ 1/5.
    func test_pageRank_uniform_no_edges() {
        let nodes = ["A", "B", "C", "D", "E"]
        let scores = PageRanker.rank(nodes: nodes, edges: [:])
        let expected = 1.0 / Double(nodes.count)
        for node in nodes {
            let score = scores[node] ?? 0
            XCTAssertEqual(score, expected, accuracy: 0.01, "Node \(node) should be near uniform rank")
        }
        let total = scores.values.reduce(0, +)
        XCTAssertEqual(total, 1.0, accuracy: 0.01, "Scores should sum to ~1.0")
    }

    /// 2. Convergence on 10-node graph: result sums to ~1.0; highest in-degree node wins.
    func test_pageRank_converges_on_10node_graph() {
        // Nodes 0-9. Node "hub" is pointed to by many others.
        let nodes = (0..<10).map { "node\($0)" }
        // hub = node0; many nodes point to it
        var edges: [String: Set<String>] = [:]
        for i in 1..<8 {
            edges["node\(i)"] = ["node0"]
        }
        // Add a cycle to prevent trivial convergence in 1 step
        edges["node8"] = ["node9"]
        edges["node9"] = ["node8"]

        let scores = PageRanker.rank(nodes: nodes, edges: edges)

        let total = scores.values.reduce(0, +)
        XCTAssertEqual(total, 1.0, accuracy: 0.05, "Scores should sum to ~1.0")

        // node0 has 7 in-links; should have highest rank
        let hub = scores["node0"] ?? 0
        for i in 1..<10 {
            let other = scores["node\(i)"] ?? 0
            XCTAssertGreaterThan(hub, other, "hub node0 should outrank node\(i)")
        }
    }

    /// 3. Personalization: node A gets 100× weight → A has highest rank even with no edges.
    func test_pageRank_respects_personalization() {
        let nodes = ["A", "B", "C", "D", "E"]
        let personalization: [String: Double] = [
            "A": 100,
            "B": 1,
            "C": 1,
            "D": 1,
            "E": 1
        ]
        let scores = PageRanker.rank(nodes: nodes, edges: [:], personalization: personalization)
        let aScore = scores["A"] ?? 0
        for node in ["B", "C", "D", "E"] {
            XCTAssertGreaterThan(aScore, scores[node] ?? 0, "A should outrank \(node)")
        }
    }

    /// 4. Hard limit: maxIters=3 on a large ring prevents infinite loop.
    func test_pageRank_terminates_at_maxIters() {
        // 50-node ring — slow to converge
        let n = 50
        let nodes = (0..<n).map { "ring\($0)" }
        var edges: [String: Set<String>] = [:]
        for i in 0..<n {
            edges["ring\(i)"] = ["ring\((i + 1) % n)"]
        }
        // Should return without hanging even with maxIters=3 and epsilon=1e-10 (won't converge)
        let start = Date()
        let scores = PageRanker.rank(
            nodes: nodes,
            edges: edges,
            maxIters: 3,
            epsilon: 1e-10
        )
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 5.0, "Should terminate well within 5 seconds")
        XCTAssertEqual(scores.count, n, "Should return scores for all nodes")
    }

    // MARK: - RepoMapBuilder Tests

    /// 5. focusFiles ranks first in output.
    func test_builder_focusFiles_ranks_first() async throws {
        var dbOpt: SymbolDB? = nil
        let (db, path) = try makeDB()
        dbOpt = db
        defer { tearDownDB(&dbOpt, path: path) }

        // Insert 3 files with symbols
        try await db.insertFile(path: "A.swift", contentHash: "aaa")
        try await db.insertFile(path: "B.swift", contentHash: "bbb")
        try await db.insertFile(path: "C.swift", contentHash: "ccc")

        try await db.upsertSymbols([
            SymbolRow(file: "A.swift", kind: "class", name: "Alpha", line: 1, col: 0),
        ], file: "A.swift")
        try await db.upsertSymbols([
            SymbolRow(file: "B.swift", kind: "struct", name: "Beta", line: 1, col: 0),
        ], file: "B.swift")
        try await db.upsertSymbols([
            SymbolRow(file: "C.swift", kind: "func", name: "gamma", line: 1, col: 0),
        ], file: "C.swift")

        let builder = RepoMapBuilder(db: db)
        let output = try await builder.markdown(focusFiles: ["A.swift"], tokenBudget: 1000)

        // A.swift section must appear before B.swift and C.swift
        let aRange = output.range(of: "## A.swift")
        let bRange = output.range(of: "## B.swift")
        let cRange = output.range(of: "## C.swift")

        XCTAssertNotNil(aRange, "A.swift section should appear in output")
        if let a = aRange, let b = bRange {
            XCTAssertLessThan(a.lowerBound, b.lowerBound, "A.swift should appear before B.swift")
        }
        if let a = aRange, let c = cRange {
            XCTAssertLessThan(a.lowerBound, c.lowerBound, "A.swift should appear before C.swift")
        }
    }

    /// 6. Token budget respected: output char count ≤ tokenBudget*4.
    func test_builder_respects_token_budget() async throws {
        var dbOpt: SymbolDB? = nil
        let (db, path) = try makeDB()
        dbOpt = db
        defer { tearDownDB(&dbOpt, path: path) }

        // Insert 20 files with several symbols each
        for i in 0..<20 {
            let filePath = "File\(i).swift"
            try await db.insertFile(path: filePath, contentHash: "hash\(i)")
            let symbols = (0..<10).map { j in
                SymbolRow(file: filePath, kind: "func", name: "method\(j)", line: j + 1, col: 0)
            }
            try await db.upsertSymbols(symbols, file: filePath)
        }

        let tokenBudget = 200
        let charBudget = tokenBudget * 4

        let builder = RepoMapBuilder(db: db)
        let output = try await builder.markdown(tokenBudget: tokenBudget)

        XCTAssertLessThanOrEqual(
            output.utf8.count,
            charBudget,
            "Output (\(output.utf8.count) chars) must fit within charBudget (\(charBudget))"
        )
    }

    /// 7. Output includes kind and name strings for inserted symbols.
    func test_builder_includes_kind_and_name() async throws {
        var dbOpt: SymbolDB? = nil
        let (db, path) = try makeDB()
        dbOpt = db
        defer { tearDownDB(&dbOpt, path: path) }

        try await db.insertFile(path: "Widget.swift", contentHash: "w1")
        try await db.upsertSymbols([
            SymbolRow(file: "Widget.swift", kind: "struct", name: "Widget", line: 1, col: 0),
            SymbolRow(file: "Widget.swift", kind: "func", name: "render", line: 10, col: 4),
        ], file: "Widget.swift")

        let builder = RepoMapBuilder(db: db)
        let output = try await builder.markdown(tokenBudget: 4000)

        XCTAssertTrue(output.contains("struct"), "Output should contain 'struct'")
        XCTAssertTrue(output.contains("func"), "Output should contain 'func'")
        XCTAssertTrue(output.contains("Widget"), "Output should contain 'Widget'")
        XCTAssertTrue(output.contains("render"), "Output should contain 'render'")
    }

    /// 8. Empty DB → header-only output (no crash).
    func test_builder_empty_db() async throws {
        var dbOpt: SymbolDB? = nil
        let (db, path) = try makeDB()
        dbOpt = db
        defer { tearDownDB(&dbOpt, path: path) }

        let builder = RepoMapBuilder(db: db)
        let output = try await builder.markdown(tokenBudget: 4000)

        XCTAssertTrue(output.contains("# Repo Map"), "Output should contain header")
        // Should not crash and should be short
        XCTAssertLessThan(output.count, 200, "Empty DB output should be minimal")
    }
}
