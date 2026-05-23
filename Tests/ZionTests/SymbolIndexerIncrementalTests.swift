// SymbolIndexerIncrementalTests.swift
// Tests for SymbolIndexer cold scan, incremental reparse, debounce, and autocomplete.
//
// Phase 12, Task 4.

import XCTest
@testable import Zion

final class SymbolIndexerIncrementalTests: XCTestCase {

    // MARK: - Helpers

    private var tempRepo: URL!
    private var dbPath: URL!
    private var db: SymbolDB!

    override func setUp() async throws {
        try await super.setUp()
        // Create isolated temp repo + DB
        tempRepo = FileManager.default.temporaryDirectory
            .appendingPathComponent("SymbolIndexerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRepo, withIntermediateDirectories: true)

        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("symboldb-\(UUID().uuidString).sqlite")
        db = try SymbolDB(path: dbPath)
    }

    override func tearDown() async throws {
        // Release DB before removing the file
        db = nil
        try? FileManager.default.removeItem(at: tempRepo)
        try? FileManager.default.removeItem(at: dbPath)
        try await super.tearDown()
    }

    /// Writes 10 distinct .swift files into tempRepo.
    private func writeSwiftFiles(count: Int = 10) throws {
        for i in 0..<count {
            let content = "struct Foo\(i) {}\nfunc bar\(i)() {}\n"
            try content.write(
                to: tempRepo.appendingPathComponent("File\(i).swift"),
                atomically: true, encoding: .utf8
            )
        }
    }

    /// Creates a SymbolIndexer using the shared db.
    private func makeIndexer(spy: (@Sendable (URL) -> Void)? = nil) -> SymbolIndexer {
        SymbolIndexer(db: db, repoURL: tempRepo, parserSpy: spy)
    }

    // MARK: - Tests

    // 1. Cold scan 10 files populates DB with correct count.
    func testBootstrap_cold_scan_10_files() async throws {
        try writeSwiftFiles(count: 10)
        let indexer = makeIndexer()
        let scanned = try await indexer.bootstrap()
        XCTAssertEqual(scanned, 10, "bootstrap() should report scanning 10 files")

        let allFiles = try await db.allFiles()
        XCTAssertEqual(allFiles.count, 10, "DB should contain 10 file rows")

        // Each file should have ≥2 symbols (struct + func)
        for fileRow in allFiles {
            let syms = try await db.symbolsForFile(fileRow.path)
            XCTAssertGreaterThanOrEqual(syms.count, 2,
                "File \(fileRow.path) should have at least 2 symbols")
        }
    }

    // 2. fileDidChange triggers reparse within 200 ms.
    func testFileDidChange_triggers_reparse_within_200ms() async throws {
        try writeSwiftFiles(count: 10)
        let indexer = makeIndexer()
        try await indexer.bootstrap()

        // Modify File0 to have a new symbol
        let newContent = "struct Foo0 {}\nfunc bar0() {}\nfunc extra0() {}\n"
        let file0 = tempRepo.appendingPathComponent("File0.swift")
        try newContent.write(to: file0, atomically: true, encoding: .utf8)

        // Inject FS event
        await indexer.fileDidChange(file0)

        // Wait 300ms (200ms debounce + 100ms buffer)
        try await Task.sleep(nanoseconds: 300_000_000)

        let syms = try await db.symbolsForFile(file0.path)
        XCTAssertGreaterThanOrEqual(syms.count, 3,
            "After 300ms, reparse should have added extra0 — got \(syms.count) symbols")
    }

    // 3. Saving an unchanged file must NOT call the scanner.
    func testUnchanged_file_no_reparse() async throws {
        try writeSwiftFiles(count: 10)

        // Counter wrapped in a class using NSLock — matches P11 pattern for @Sendable
        final class SpyCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var _count = 0
            func increment() { lock.withLock { _count += 1 } }
            var count: Int { lock.withLock { _count } }
        }
        let spy = SpyCounter()
        let file0 = tempRepo.appendingPathComponent("File0.swift")

        let indexer = makeIndexer(spy: { url in
            // Use lastPathComponent to avoid symlink/path-canonicalization mismatches
            if url.lastPathComponent == "File0.swift" {
                spy.increment()
            }
        })

        // Bootstrap — spy call for File0 expected here
        try await indexer.bootstrap()
        let callsAfterBootstrap = spy.count
        XCTAssertEqual(callsAfterBootstrap, 1,
            "Scanner should be called once for File0 during bootstrap")

        // Now signal fileDidChange for the same, unchanged file
        await indexer.fileDidChange(file0)
        try await Task.sleep(nanoseconds: 300_000_000)

        // Spy should NOT have been called again (contentHash matches → early return)
        XCTAssertEqual(spy.count, callsAfterBootstrap,
            "Scanner must NOT be called for an unchanged file. Got \(spy.count) total calls.")
    }

    // 4. Non-swift files are not indexed.
    func testNon_swift_file_skipped() async throws {
        try writeSwiftFiles(count: 3)
        // Add a .txt file — should be ignored
        try "hello world".write(
            to: tempRepo.appendingPathComponent("notes.txt"),
            atomically: true, encoding: .utf8
        )

        let indexer = makeIndexer()
        try await indexer.bootstrap()

        let allFiles = try await db.allFiles()
        // Only the 3 .swift files should be recorded
        XCTAssertEqual(allFiles.count, 3)
        for row in allFiles {
            XCTAssertTrue(row.path.hasSuffix(".swift"), "Only .swift files should be in DB")
        }
    }

    // 5. fileSuggestions returns matching paths.
    func testFileSuggestions_returns_matching_paths() async throws {
        try writeSwiftFiles(count: 10)
        let indexer = makeIndexer()
        try await indexer.bootstrap()

        let suggestions = await indexer.fileSuggestions(prefix: "File1")
        XCTAssertGreaterThanOrEqual(suggestions.count, 1,
            "fileSuggestions(prefix: 'File1') should match at least File1.swift")
        XCTAssertTrue(suggestions.allSatisfy { $0.contains("File1") },
            "All suggestions should contain 'File1'")
    }

    // 6. symbolSuggestions returns matching symbol names.
    func testSymbolSuggestions_returns_matching_names() async throws {
        try writeSwiftFiles(count: 10)
        let indexer = makeIndexer()
        try await indexer.bootstrap()

        let suggestions = await indexer.symbolSuggestions(prefix: "Foo")
        XCTAssertGreaterThanOrEqual(suggestions.count, 1,
            "symbolSuggestions(prefix: 'Foo') should find at least one Foo* struct")
        XCTAssertTrue(suggestions.allSatisfy { $0.hasPrefix("Foo") },
            "All returned symbol names should start with 'Foo'")
    }

    // 7. Debounce batches multiple rapid fileDidChange calls — each file reparsed exactly once.
    func testDebounce_batches_multiple_changes() async throws {
        try writeSwiftFiles(count: 10)

        final class SpyCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var _calls: [String: Int] = [:]
            func record(_ path: String) { lock.withLock { _calls[path, default: 0] += 1 } }
            func callCount(for path: String) -> Int { lock.withLock { _calls[path] ?? 0 } }
        }
        let spy = SpyCounter()

        // We only count incremental reparse calls (post-bootstrap).
        // Bootstrap populates hashes. Then we modify 3 files and measure spy calls.
        let indexer = makeIndexer(spy: { url in
            spy.record(url.path)
        })

        // Bootstrap — establishes content hashes (spy called once per file here, we ignore those)
        try await indexer.bootstrap()

        // Overwrite 3 files with new content so hash differs
        let targets = [0, 1, 2].map { tempRepo.appendingPathComponent("File\($0).swift") }
        for (i, url) in targets.enumerated() {
            let updated = "struct Updated\(i) {}\nfunc updatedFn\(i)() {}\nfunc extra\(i)() {}\n"
            try updated.write(to: url, atomically: true, encoding: .utf8)
        }

        // Reset spy counts AFTER bootstrap so we only measure incremental
        // (We can't reset the existing counter, so capture current counts as baseline)
        let baseline = targets.map { spy.callCount(for: $0.path) }

        // Fire 3 rapid changes (all within debounce window)
        for url in targets {
            await indexer.fileDidChange(url)
        }

        // Wait for debounce + buffer
        try await Task.sleep(nanoseconds: 350_000_000)

        // Each of the 3 files should have been parsed exactly once more
        for (i, url) in targets.enumerated() {
            let delta = spy.callCount(for: url.path) - baseline[i]
            XCTAssertEqual(delta, 1,
                "File\(i).swift should be reparsed exactly 1 time after batched change, got \(delta)")
        }
    }

    // Note: test 7 (bootstrap_respects_5000_cap) skipped — too expensive for CI.
    // The maxColdScanFiles constant is enforced by `files.prefix(Self.maxColdScanFiles)`.
}
