import XCTest
import GRDB
@testable import Zion

final class SymbolDBTests: XCTestCase {
    var dbPath: URL!
    var db: SymbolDB!

    override func setUp() async throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        db = try SymbolDB(path: dbPath)
    }

    override func tearDown() async throws {
        db = nil
        try? FileManager.default.removeItem(at: dbPath)
    }

    // 1. Migration creates both tables
    func test_migration_v1_succeeds() async throws {
        // Open a raw DatabaseQueue to inspect sqlite_master
        let raw = try DatabaseQueue(path: dbPath.path)
        let tables = try await raw.read { db -> [String] in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
        }
        XCTAssertTrue(tables.contains("files"), "files table missing")
        XCTAssertTrue(tables.contains("symbols"), "symbols table missing")
    }

    // 2. insertFile round-trips contentHash
    func test_insert_file_and_read_hash() async throws {
        try await db.insertFile(path: "/src/main.swift", contentHash: "abc123")
        let hash = try await db.contentHashFor("/src/main.swift")
        XCTAssertEqual(hash, "abc123")
    }

    // 3. upsertSymbols round-trip
    func test_upsert_symbols_roundtrip() async throws {
        let symbols = [
            SymbolRow(file: "/src/a.swift", kind: "func", name: "foo", line: 1, col: 0),
            SymbolRow(file: "/src/a.swift", kind: "struct", name: "Bar", line: 10, col: 0),
            SymbolRow(file: "/src/a.swift", kind: "var", name: "baz", line: 20, col: 4),
        ]
        try await db.upsertSymbols(symbols, file: "/src/a.swift")
        let fetched = try await db.symbolsForFile("/src/a.swift")
        XCTAssertEqual(fetched.count, 3)
        XCTAssertTrue(fetched.contains(where: { $0.name == "foo" }))
        XCTAssertTrue(fetched.contains(where: { $0.name == "Bar" }))
        XCTAssertTrue(fetched.contains(where: { $0.name == "baz" }))
    }

    // 4. upsert replaces per-file
    func test_upsert_replaces_per_file() async throws {
        let initial = [
            SymbolRow(file: "/src/a.swift", kind: "func", name: "alpha", line: 1, col: 0),
            SymbolRow(file: "/src/a.swift", kind: "func", name: "beta", line: 5, col: 0),
            SymbolRow(file: "/src/a.swift", kind: "func", name: "gamma", line: 9, col: 0),
        ]
        try await db.upsertSymbols(initial, file: "/src/a.swift")

        let replacement = [
            SymbolRow(file: "/src/a.swift", kind: "func", name: "only", line: 1, col: 0),
        ]
        try await db.upsertSymbols(replacement, file: "/src/a.swift")

        let fetched = try await db.symbolsForFile("/src/a.swift")
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "only")
    }

    // 5. symbolsByName cross-file lookup
    func test_symbols_by_name_lookup() async throws {
        let fileA = [SymbolRow(file: "/src/a.swift", kind: "func", name: "sharedName", line: 1, col: 0)]
        let fileB = [SymbolRow(file: "/src/b.swift", kind: "func", name: "sharedName", line: 2, col: 0)]
        try await db.upsertSymbols(fileA, file: "/src/a.swift")
        try await db.upsertSymbols(fileB, file: "/src/b.swift")

        let results = try await db.symbolsByName("sharedName")
        XCTAssertEqual(results.count, 2)
        let files = Set(results.map(\.file))
        XCTAssertTrue(files.contains("/src/a.swift"))
        XCTAssertTrue(files.contains("/src/b.swift"))
    }

    // 6. symbolsByName with kind filter
    func test_symbols_by_name_with_kind_filter() async throws {
        let symbols = [
            SymbolRow(file: "/src/a.swift", kind: "func", name: "target", line: 1, col: 0),
            SymbolRow(file: "/src/a.swift", kind: "var", name: "target", line: 5, col: 0),
        ]
        try await db.upsertSymbols(symbols, file: "/src/a.swift")

        let funcResults = try await db.symbolsByName("target", kind: "func")
        XCTAssertEqual(funcResults.count, 1)
        XCTAssertEqual(funcResults.first?.kind, "func")

        let varResults = try await db.symbolsByName("target", kind: "var")
        XCTAssertEqual(varResults.count, 1)
        XCTAssertEqual(varResults.first?.kind, "var")
    }
}
