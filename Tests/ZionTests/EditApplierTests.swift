import XCTest
@testable import Zion

final class EditApplierTests: XCTestCase {

    let applier = EditApplier()

    // MARK: - Helpers

    private func makeBlock(path: String = "src/file.swift", search: String, replace: String = "REPLACED") -> EditBlock {
        EditBlock(path: path, search: search, replace: replace)
    }

    // MARK: - Tests

    func testExactMatchHits() async {
        let contents = "let x = 1\nlet y = 2\nlet z = 3"
        let block = makeBlock(search: "let y = 2", replace: "let y = 42")
        let result = await applier.apply(block, to: contents, reflection: nil, wholeFileRewrite: nil)
        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.finalContents, "let x = 1\nlet y = 42\nlet z = 3")
        XCTAssertEqual(result.attempts.first?.strategy, "exact")
        XCTAssertTrue(result.attempts.first?.ok == true)
    }

    func testWhitespaceNormalizedHits() async {
        // File uses spaces, search uses tabs — same content after normalization
        let contents = "func foo() {\n    let x = 1\n    return x\n}"
        // Search has tab-based indent — after normalizing both collapse to single spaces
        let block = makeBlock(search: "let\tx\t=\t1", replace: "let x = 99")
        let result = await applier.apply(block, to: contents, reflection: nil, wholeFileRewrite: nil)
        XCTAssertTrue(result.applied, "whitespace-normalized strategy should match tab vs space variant")
        XCTAssertNotNil(result.finalContents)
    }

    func testStripIndentHits() async {
        // File has 4-space indent; search has 8-space indent (extra 4 spaces)
        let contents = "func foo() {\n    let x = 1\n    return x\n}"
        let block = makeBlock(search: "        let x = 1\n        return x", replace: "    let x = 99\n    return x")
        let result = await applier.apply(block, to: contents, reflection: nil, wholeFileRewrite: nil)
        XCTAssertTrue(result.applied, "strip-indent strategy should handle extra leading indent in search")
        XCTAssertNotNil(result.finalContents)
    }

    func testFuzzyMatchHits() async {
        // Search differs by one character (typo) — ratio should be >= 0.92
        // contents: "let result = computeX(a, b)" (27 chars)
        // search:   "let result = computeY(a, b)" (27 chars) — 1 char diff, ratio = 1 - 1/27 ≈ 0.963
        let contents = "let result = computeX(a, b)"
        let block = makeBlock(search: "let result = computeY(a, b)", replace: "let result = REPLACED(a, b)")
        let result = await applier.apply(block, to: contents, reflection: nil, wholeFileRewrite: nil)
        XCTAssertTrue(result.applied, "fuzzy strategy should match near-identical string with ratio >= 0.92")
        XCTAssertNotNil(result.finalContents)
        // Confirm fuzzy strategy was reached
        let strategies = result.attempts.map { $0.strategy }
        XCTAssertTrue(strategies.contains("fuzzy"))
    }

    func testReflectionFallbackHits() async {
        let contents = "let value = originalFunction()"
        // Block that will not match by exact/ws/indent/fuzzy
        let block = makeBlock(search: "completely_different_text_xyz_123", replace: "let value = newFunction()")

        let reflection: ReflectionCallback = { fileContents, _ in
            // Return a corrected block whose search actually matches the file
            EditBlock(path: "src/file.swift", search: "let value = originalFunction()", replace: "let value = newFunction()")
        }

        let result = await applier.apply(block, to: contents, reflection: reflection, wholeFileRewrite: nil)
        XCTAssertTrue(result.applied, "reflection fallback should succeed with corrected block")
        XCTAssertEqual(result.finalContents, "let value = newFunction()")
        let strategies = result.attempts.map { $0.strategy }
        XCTAssertTrue(strategies.contains("reflection"))
        XCTAssertTrue(result.attempts.last?.ok == true)
    }

    func testWholeFileRewriteFallback() async {
        let contents = "let a = 1\nlet b = 2\nlet c = 3"
        let block = makeBlock(search: "NOMATCH_XYZ_999", replace: "irrelevant")

        let newFile = "let a = 1\nlet b = 2\nlet c = 100\n// added comment\nlet d = 4"

        let rewrite: WholeFileCallback = { _, _ in newFile }

        let result = await applier.apply(block, to: contents, reflection: nil, wholeFileRewrite: rewrite)
        XCTAssertTrue(result.applied, "whole-file rewrite fallback should succeed with valid new contents")
        XCTAssertEqual(result.finalContents, newFile)
        let strategies = result.attempts.map { $0.strategy }
        XCTAssertTrue(strategies.contains("wholeFileRewrite"))
    }

    func testWholeFileRewriteRejectsLazy() async {
        let contents = "let a = 1\nlet b = 2\nlet c = 3\nlet d = 4\nlet e = 5"
        let block = makeBlock(search: "NOMATCH_XYZ_999", replace: "irrelevant")

        let lazyRewrite: WholeFileCallback = { _, _ in
            "let a = 1\n// rest of code"
        }

        let result = await applier.apply(block, to: contents, reflection: nil, wholeFileRewrite: lazyRewrite)
        XCTAssertFalse(result.applied, "whole-file rewrite should reject lazy placeholder '// rest of code'")
        XCTAssertNil(result.finalContents)
        let wholeFileAttempt = result.attempts.first(where: { $0.strategy == "wholeFileRewrite" })
        XCTAssertEqual(wholeFileAttempt?.ok, false)
    }

    func testPathRejected() async {
        let block = makeBlock(path: "/etc/passwd", search: "root", replace: "hacked")
        let result = await applier.apply(block, to: "root:x:0:0", reflection: nil, wholeFileRewrite: nil)
        XCTAssertFalse(result.applied)
        XCTAssertNil(result.finalContents)
        XCTAssertEqual(result.failureReason, "invalid_path")
        XCTAssertEqual(result.attempts.count, 1)
        XCTAssertEqual(result.attempts.first?.strategy, "pathRejected")
    }

    func testPathRejectedTraversal() async {
        let block = makeBlock(path: "../../secret", search: "data", replace: "hacked")
        let result = await applier.apply(block, to: "data", reflection: nil, wholeFileRewrite: nil)
        XCTAssertFalse(result.applied)
        XCTAssertNil(result.finalContents)
        XCTAssertEqual(result.failureReason, "invalid_path")
        XCTAssertEqual(result.attempts.count, 1)
    }

    func testAllStrategiesFail() async {
        let contents = "let x = 1"
        let block = makeBlock(search: "COMPLETELY_UNRELATED_STRING_THAT_NEVER_MATCHES_ABCDEF", replace: "noop")
        let result = await applier.apply(block, to: contents, reflection: nil, wholeFileRewrite: nil)
        XCTAssertFalse(result.applied)
        XCTAssertNil(result.finalContents)
        let strategies = result.attempts.map { $0.strategy }
        XCTAssertTrue(strategies.contains("exact"), "should attempt exact")
        XCTAssertTrue(strategies.contains("whitespaceNormalized"), "should attempt whitespaceNormalized")
        XCTAssertTrue(strategies.contains("stripIndent"), "should attempt stripIndent")
        XCTAssertTrue(strategies.contains("fuzzy"), "should attempt fuzzy")
        XCTAssertTrue(result.attempts.allSatisfy { !$0.ok })
    }
}
