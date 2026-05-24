// FindSymbolTests.swift — verifies the find_symbol MCP tool dispatch.

import XCTest
@testable import Zion

@MainActor
final class FindSymbolTests: XCTestCase {

    private var tempDB: URL!
    private var db: SymbolDB!
    private var indexer: SymbolIndexer!
    private var tempRepo: URL!

    override func setUp() async throws {
        let tmp = FileManager.default.temporaryDirectory
        tempDB = tmp.appendingPathComponent("\(UUID().uuidString).sqlite")
        db = try SymbolDB(path: tempDB)
        tempRepo = tmp.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRepo, withIntermediateDirectories: true)

        // Seed: insert 3 known symbols across 2 files
        try await db.insertFile(path: "/repo/UserAPI.swift", contentHash: "abc")
        try await db.upsertSymbols(
            [
                SymbolRow(file: "/repo/UserAPI.swift", kind: "struct", name: "Foo", line: 10, col: 1, refsJSON: "[]"),
                SymbolRow(file: "/repo/UserAPI.swift", kind: "function", name: "fetchFoo", line: 20, col: 1, refsJSON: "[]")
            ],
            file: "/repo/UserAPI.swift"
        )
        try await db.insertFile(path: "/repo/Helper.swift", contentHash: "def")
        try await db.upsertSymbols(
            [
                SymbolRow(file: "/repo/Helper.swift", kind: "struct", name: "Foo", line: 5, col: 1, refsJSON: "[]")
            ],
            file: "/repo/Helper.swift"
        )

        indexer = SymbolIndexer(db: db, repoURL: tempRepo)
        SymbolIndexer.shared = indexer
    }

    override func tearDown() async throws {
        SymbolIndexer.shared = nil
        try? FileManager.default.removeItem(at: tempDB)
        try? FileManager.default.removeItem(at: tempRepo)
    }

    // MARK: - Dispatch tests

    func test_find_symbol_returns_matching_rows() async throws {
        let result = try await MCPConfigBuilder.dispatch(name: "find_symbol", args: ["name": "Foo"])
        XCTAssertTrue(result.contains("UserAPI.swift:10"), "Should include UserAPI.swift hit. Got: \(result)")
        XCTAssertTrue(result.contains("Helper.swift:5"), "Should include Helper.swift hit. Got: \(result)")
    }

    func test_find_symbol_with_kind_filter() async throws {
        let result = try await MCPConfigBuilder.dispatch(name: "find_symbol", args: ["name": "Foo", "kind": "struct"])
        XCTAssertTrue(result.contains("struct Foo"))
    }

    func test_find_symbol_empty_result() async throws {
        let result = try await MCPConfigBuilder.dispatch(name: "find_symbol", args: ["name": "NonExistent"])
        XCTAssertTrue(result.lowercased().contains("no symbols"), "Got: \(result)")
    }

    func test_find_symbol_missing_indexer_returns_error() async throws {
        SymbolIndexer.shared = nil
        let result = try await MCPConfigBuilder.dispatch(name: "find_symbol", args: ["name": "Foo"])
        XCTAssertTrue(result.lowercased().contains("not initialized") || result.lowercased().contains("error"))
    }
}
