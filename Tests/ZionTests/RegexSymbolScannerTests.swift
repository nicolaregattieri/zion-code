import XCTest
@testable import Zion

/// Phase 5h — regex scanner for TS / JS / Python.
final class RegexSymbolScannerTests: XCTestCase {

    func test_typescript_emitsFunctionAndClass() {
        let src = """
        export function foo() { return 1 }

        export class Bar {
            constructor() {}
        }
        """
        let hits = RegexSymbolScanner().scan(source: src, language: .typescript)
        let kinds = Set(hits.map { $0.kind })
        XCTAssertTrue(kinds.contains("function"))
        XCTAssertTrue(kinds.contains("class"))
    }

    func test_python_emitsDefAndClass() {
        let src = """
        class Foo:
            def bar(self):
                return 1

        async def baz():
            return 2
        """
        let hits = RegexSymbolScanner().scan(source: src, language: .python)
        let kinds = Set(hits.map { $0.kind })
        XCTAssertTrue(kinds.contains("class"))
        XCTAssertTrue(kinds.contains("function"))
        XCTAssertEqual(hits.count, 3, "expected class + 2 functions, got \(hits)")
    }

    func test_javascript_emitsFunction() {
        let src = """
        async function compute() {
            return 42
        }
        """
        let hits = RegexSymbolScanner().scan(source: src, language: .javascript)
        XCTAssertEqual(hits.first?.kind, "function")
    }

    func test_chunker_typescriptFile_producesSemanticChunks() throws {
        let chunker = ASTChunker()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rag_ts_\(UUID().uuidString).ts")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let source = """
        export function alpha() { return 1 }

        export class Beta {
            run() { return 2 }
        }
        """
        try source.write(to: tmp, atomically: true, encoding: .utf8)
        let chunks = try chunker.chunk(file: tmp, language: .typescript)
        XCTAssertGreaterThan(chunks.count, 0)
        XCTAssertTrue(chunks.contains { !$0.fallback }, "expected semantic chunks for TS, got \(chunks.map { $0.fallback })")
    }
}
