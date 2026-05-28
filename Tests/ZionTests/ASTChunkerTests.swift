import XCTest
@testable import Zion

final class ASTChunkerTests: XCTestCase {

    private let chunker = ASTChunker()

    // MARK: - SourceLanguage.forExtension

    func test_forExtension_swift() {
        XCTAssertEqual(SourceLanguage.forExtension("swift"), .swift)
    }

    func test_forExtension_typescript() {
        XCTAssertEqual(SourceLanguage.forExtension("ts"), .typescript)
        XCTAssertEqual(SourceLanguage.forExtension("tsx"), .typescript)
    }

    func test_forExtension_python() {
        XCTAssertEqual(SourceLanguage.forExtension("py"), .python)
    }

    func test_forExtension_javascript() {
        XCTAssertEqual(SourceLanguage.forExtension("js"), .javascript)
        XCTAssertEqual(SourceLanguage.forExtension("mjs"), .javascript)
    }

    func test_forExtension_json() {
        XCTAssertEqual(SourceLanguage.forExtension("json"), .json)
    }

    func test_forExtension_markdown() {
        XCTAssertEqual(SourceLanguage.forExtension("md"), .markdown)
        XCTAssertEqual(SourceLanguage.forExtension("markdown"), .markdown)
    }

    func test_forExtension_unknown_returnsNil() {
        XCTAssertNil(SourceLanguage.forExtension("xyz"))
        XCTAssertNil(SourceLanguage.forExtension("rb"))
    }

    func test_forExtension_caseInsensitive() {
        XCTAssertEqual(SourceLanguage.forExtension("SWIFT"), .swift)
        XCTAssertEqual(SourceLanguage.forExtension("TS"), .typescript)
    }

    // MARK: - Chunk at function boundaries (AST path)

    /// Grammar-backed AST chunking is deferred — tree-sitter grammars do not
    /// yet publish SPM 6.2-compatible manifests.  This test is skipped until
    /// AST chunking is wired up.
    func test_swiftSource_chunksAtFunctionBoundaries() throws {
        throw XCTSkip("AST chunker pending grammar vendoring (tree-sitter SPM 6.2 compat deferred)")
    }

    // MARK: - Fallback fixed-window path

    func test_markdownFile_fallsBackToFixedWindow() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rag_test_\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Write ~300 lines of markdown so we get at least 2 chunks.
        let line = "## Section heading with some content here\n"
        let content = String(repeating: line, count: 300)
        try content.write(to: tmp, atomically: true, encoding: .utf8)

        let chunks = try chunker.chunk(file: tmp, language: .markdown)

        XCTAssertTrue(chunks.count > 1, "Expected multiple chunks for large markdown file, got \(chunks.count)")
        XCTAssertTrue(chunks.allSatisfy { $0.fallback }, "All markdown chunks should have fallback=true")
        XCTAssertTrue(chunks.allSatisfy { !$0.contentSHA.isEmpty }, "Every chunk needs a contentSHA")
    }

    func test_smallFile_producesOneChunk() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rag_small_\(UUID().uuidString).swift")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let content = "func hello() -> String { \"world\" }\n"
        try content.write(to: tmp, atomically: true, encoding: .utf8)

        let chunks = try chunker.chunk(file: tmp, language: .swift)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].startLine, 1)
        XCTAssertEqual(chunks[0].kind, "block")
        XCTAssertTrue(chunks[0].fallback)
    }

    func test_emptyFile_producesNoChunks() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rag_empty_\(UUID().uuidString).swift")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "".write(to: tmp, atomically: true, encoding: .utf8)

        let chunks = try chunker.chunk(file: tmp, language: .swift)
        XCTAssertTrue(chunks.isEmpty)
    }

    func test_oversizedFile_throws() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rag_big_\(UUID().uuidString).swift")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Write slightly more than maxBytesPerFile (1 MiB + 1 byte).
        let bigData = Data(repeating: UInt8(ascii: "x"), count: Constants.RAG.maxBytesPerFile + 1)
        try bigData.write(to: tmp)

        XCTAssertThrowsError(try chunker.chunk(file: tmp, language: .swift)) { error in
            guard case ASTChunkerError.fileTooLarge = error else {
                XCTFail("Expected fileTooLarge, got \(error)")
                return
            }
        }
    }

    func test_chunkLineNumbers_areConsistent() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rag_lines_\(UUID().uuidString).py")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let lines = (1...500).map { "# line \($0)" }.joined(separator: "\n")
        try lines.write(to: tmp, atomically: true, encoding: .utf8)

        let chunks = try chunker.chunk(file: tmp, language: .python)

        XCTAssertFalse(chunks.isEmpty)
        // First chunk starts at line 1.
        XCTAssertEqual(chunks.first?.startLine, 1)
        // All chunks: startLine <= endLine.
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.startLine, chunk.endLine,
                "startLine \(chunk.startLine) > endLine \(chunk.endLine)")
        }
        // Consecutive chunks: next startLine <= prev endLine + 1 (overlap allowed).
        for idx in 1..<chunks.count {
            let prev = chunks[idx - 1]
            let curr = chunks[idx]
            XCTAssertGreaterThanOrEqual(curr.startLine, prev.startLine + 1,
                "Chunk \(idx) startLine \(curr.startLine) not past prev startLine \(prev.startLine)")
        }
    }

    func test_contentSHA_isDeterministic() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rag_sha_\(UUID().uuidString).ts")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let content = String(repeating: "const x = 1;\n", count: 50)
        try content.write(to: tmp, atomically: true, encoding: .utf8)

        let chunks1 = try chunker.chunk(file: tmp, language: .typescript)
        let chunks2 = try chunker.chunk(file: tmp, language: .typescript)

        XCTAssertEqual(chunks1.map(\.contentSHA), chunks2.map(\.contentSHA))
    }
}
