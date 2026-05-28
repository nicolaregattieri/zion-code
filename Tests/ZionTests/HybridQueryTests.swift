import XCTest
@testable import Zion

/// Phase 5b query service tests. Focus on the deterministic pieces:
/// RRF merge math and FTS5 query sanitization. Live embedder roundtrip
/// is exercised inside RAGStoreTests; here we keep the surface tight.
final class HybridQueryTests: XCTestCase {

    private func makeChunk(_ id: String) -> RAGChunk {
        RAGChunk(
            path: "\(id).swift", startLine: 1, endLine: 10,
            kind: "function", contentSHA: id, fallback: false
        )
    }

    func test_rrfMerge_combinesVectorAndKeyword() {
        let a = makeChunk("a")
        let b = makeChunk("b")
        let c = makeChunk("c")

        let vector = [
            RAGHit(chunk: a, score: 0.9, source: .vector),
            RAGHit(chunk: b, score: 0.7, source: .vector),
        ]
        let keyword = [
            RAGHit(chunk: c, score: 0.95, source: .keyword),
            RAGHit(chunk: a, score: 0.6, source: .keyword),
        ]

        let merged = RAGQueryService.reciprocalRankFusion(
            vector: vector,
            keyword: keyword,
            limit: 5,
            k: 60
        )

        // `a` is in both lists — must outrank either single-source hit.
        XCTAssertEqual(merged.first?.chunk.contentSHA, "a")
        XCTAssertEqual(merged.allSatisfy { $0.source == .hybrid }, true)
    }

    func test_sanitizeFTSQuery_handlesNaturalLanguage() {
        let q = "where is L10n loaded?"
        let safe = RAGQueryService.sanitizeFTSQuery(q)
        XCTAssertEqual(safe, "\"where\" \"is\" \"L10n\" \"loaded\"")
    }

    func test_sanitizeFTSQuery_emptyInput() {
        let q = "?? ()"
        let safe = RAGQueryService.sanitizeFTSQuery(q)
        XCTAssertEqual(safe, "\"\"")
    }
}
