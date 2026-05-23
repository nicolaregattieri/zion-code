import XCTest
@testable import Zion

final class EditBlockParserTests: XCTestCase {

    // MARK: - Helpers

    private func block(path: String, search: String, replace: String) -> String {
        "<<<<<<< SEARCH: \(path)\n\(search)\n=======\n\(replace)\n>>>>>>> REPLACE\n"
    }

    // MARK: - Tests

    func testSingleBlockInOneDelta() {
        var parser = EditBlockParser()
        let input = block(path: "Sources/Foo/Bar.swift", search: "let oldVal = 1", replace: "let oldVal = 2")
        let result = parser.feed(input)
        XCTAssertEqual(result.count, 1)
        let b = result[0]
        XCTAssertEqual(b.path, "Sources/Foo/Bar.swift")
        XCTAssertEqual(b.search, "let oldVal = 1")
        XCTAssertEqual(b.replace, "let oldVal = 2")
    }

    func testBlockSplitAcrossThreeDeltas() {
        var parser = EditBlockParser()
        let full = block(path: "Sources/A.swift", search: "old", replace: "new")
        // Split roughly into thirds
        let idx1 = full.index(full.startIndex, offsetBy: full.count / 3)
        let idx2 = full.index(full.startIndex, offsetBy: 2 * full.count / 3)
        let part1 = String(full[..<idx1])
        let part2 = String(full[idx1..<idx2])
        let part3 = String(full[idx2...])

        let r1 = parser.feed(part1)
        let r2 = parser.feed(part2)
        let r3 = parser.feed(part3)

        XCTAssertEqual(r1, [])
        XCTAssertEqual(r2, [])
        XCTAssertEqual(r3.count, 1)
        XCTAssertEqual(r3[0].path, "Sources/A.swift")
        XCTAssertEqual(r3[0].search, "old")
        XCTAssertEqual(r3[0].replace, "new")
    }

    func testMultipleBackToBackBlocks() {
        var parser = EditBlockParser()
        let b1 = block(path: "Sources/A.swift", search: "alpha", replace: "ALPHA")
        let b2 = block(path: "Sources/B.swift", search: "beta",  replace: "BETA")
        let result = parser.feed(b1 + b2)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].path, "Sources/A.swift")
        XCTAssertEqual(result[0].search, "alpha")
        XCTAssertEqual(result[0].replace, "ALPHA")
        XCTAssertEqual(result[1].path, "Sources/B.swift")
        XCTAssertEqual(result[1].search, "beta")
        XCTAssertEqual(result[1].replace, "BETA")
    }

    func testMissingCloseFenceReturnsEmpty() {
        var parser = EditBlockParser()
        let incomplete = "<<<<<<< SEARCH: Sources/X.swift\nold content\n=======\nnew content\n"
        let result = parser.feed(incomplete)
        XCTAssertEqual(result, [])
    }

    func testMalformedFenceIgnored() {
        var parser = EditBlockParser()
        // "<<<<<<< OOPS" has no "SEARCH:" prefix so it won't match openPrefix
        let malformed = "<<<<<<< OOPS: some garbage\nstuff here\n>>>>>>> REPLACE\n"
        let result = parser.feed(malformed)
        XCTAssertEqual(result, [])
    }

    func testOversizedBufferResets() {
        var parser = EditBlockParser()
        // Feed 70 KB of garbage — no close fence
        let garbage = String(repeating: "x", count: 70 * 1024)
        let afterGarbage = parser.feed(garbage)
        XCTAssertEqual(afterGarbage, [], "Overflow should produce no blocks")

        // Parser should have reset; a valid block fed now must still parse
        let valid = block(path: "Sources/Reset.swift", search: "a", replace: "b")
        let result = parser.feed(valid)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].path, "Sources/Reset.swift")
    }

    func testPathTrimming() {
        var parser = EditBlockParser()
        // Extra spaces around path
        let input = "<<<<<<< SEARCH:   Sources/Spaces.swift   \nold\n=======\nnew\n>>>>>>> REPLACE\n"
        let result = parser.feed(input)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].path, "Sources/Spaces.swift")
    }
}
