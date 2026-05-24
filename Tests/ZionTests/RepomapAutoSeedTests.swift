// RepomapAutoSeedTests.swift — Tests for RepoMapBuilder.autoSeed.

import XCTest
@testable import Zion

final class RepomapAutoSeedTests: XCTestCase {

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

    /// Populate the DB with N files, each having a small set of symbols.
    private func populateDB(_ db: SymbolDB, fileCount: Int) async throws {
        for i in 0..<fileCount {
            let filePath = "AutoSeedFile\(i).swift"
            try await db.insertFile(path: filePath, contentHash: "hash\(i)")
            let symbols = [
                SymbolRow(file: filePath, kind: "struct", name: "Type\(i)", line: 1, col: 0),
                SymbolRow(file: filePath, kind: "func", name: "method\(i)", line: 5, col: 4),
            ]
            try await db.upsertSymbols(symbols, file: filePath)
        }
    }

    // MARK: - Tests

    /// 1. autoSeed output is under tokenBudget (1500 tokens default).
    func test_autoSeed_under_budget() async throws {
        var dbOpt: SymbolDB? = nil
        let (db, path) = try makeDB()
        dbOpt = db
        defer { tearDownDB(&dbOpt, path: path) }

        try await populateDB(db, fileCount: 20)

        let builder = RepoMapBuilder(db: db)
        let output = try await builder.autoSeed(tokenBudget: 1500)

        let estimatedTokens = TokenEstimator.estimate(output, kind: .code)
        XCTAssertLessThanOrEqual(
            estimatedTokens, 1500,
            "autoSeed output (\(estimatedTokens) tokens) must be under 1500 token budget"
        )
    }

    /// 2. autoSeed output starts with the "# Repo Map" header.
    func test_autoSeed_includes_header() async throws {
        var dbOpt: SymbolDB? = nil
        let (db, path) = try makeDB()
        dbOpt = db
        defer { tearDownDB(&dbOpt, path: path) }

        try await populateDB(db, fileCount: 5)

        let builder = RepoMapBuilder(db: db)
        let output = try await builder.autoSeed()

        XCTAssertTrue(output.hasPrefix("# Repo Map"),
                      "autoSeed output must start with '# Repo Map' header, got: \(output.prefix(50))")
    }

    /// 3. autoSeed on empty DB returns minimal header-only output (no crash).
    func test_autoSeed_empty_db_returns_header_only() async throws {
        var dbOpt: SymbolDB? = nil
        let (db, path) = try makeDB()
        dbOpt = db
        defer { tearDownDB(&dbOpt, path: path) }

        let builder = RepoMapBuilder(db: db)
        let output = try await builder.autoSeed()

        XCTAssertTrue(output.contains("# Repo Map"),
                      "Empty DB autoSeed must contain repo map header")
        XCTAssertLessThan(output.utf8.count, 300,
                          "Empty DB autoSeed output should be minimal")
    }

    /// 4. autoSeed default budget matches markdown(focusFiles:[], tokenBudget:1500) in length.
    func test_autoSeed_default_budget_is_1500() async throws {
        var dbOpt: SymbolDB? = nil
        let (db, path) = try makeDB()
        dbOpt = db
        defer { tearDownDB(&dbOpt, path: path) }

        try await populateDB(db, fileCount: 10)

        let builder = RepoMapBuilder(db: db)
        let autoSeedOutput = try await builder.autoSeed()
        let markdownOutput = try await builder.markdown(
            focusFiles: [],
            historyFiles: [],
            mentionedIdentifiers: [],
            tokenBudget: 1500
        )

        XCTAssertEqual(autoSeedOutput.utf8.count, markdownOutput.utf8.count,
                       "autoSeed() with default budget must produce same output as markdown(tokenBudget:1500)")
    }
}
