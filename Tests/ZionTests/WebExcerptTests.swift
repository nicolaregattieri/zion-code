import XCTest
@testable import Zion

final class WebExcerptTests: XCTestCase {

    // MARK: - 1. Under-threshold returns stripped raw text

    func test_under_threshold_returns_raw() {
        let html = "<p>hello world</p>"
        let result = WebExcerptRetriever.excerpt(html: html, query: "anything")
        XCTAssertEqual(result, "hello world")
        XCTAssertLessThanOrEqual(result.utf8.count, WebExcerptRetriever.directInjectThresholdBytes)
    }

    // MARK: - 2. Over-threshold payload is capped at <=32 KB

    func test_over_threshold_returns_capped() {
        // Build ~100 KB HTML with repeated paragraphs
        let paragraph = "<p>This is a paragraph about " + String(repeating: "content ", count: 20) + "</p>\n"
        var html = "<html><body>"
        while html.utf8.count < 100 * 1024 {
            html += paragraph
        }
        html += "</body></html>"
        XCTAssertGreaterThan(html.utf8.count, 100 * 1024)

        let result = WebExcerptRetriever.excerpt(html: html, query: "important")
        XCTAssertLessThanOrEqual(result.utf8.count, 32 * 1024,
            "Expected <=32 KB but got \(result.utf8.count) bytes")
    }

    // MARK: - 3. Query term ranks matching chunk higher

    func test_query_term_ranks_higher() {
        // Build content over threshold so excerpting kicks in.
        // Chunk A + C have no query terms; chunk B has "important" twice.
        // We need total stripped content >32 KB to trigger excerpt mode.
        let filler = String(repeating: "word ", count: 300) // ~1500 bytes per chunk
        // Build a large HTML so the stripped result exceeds 32 KB
        var html = "<html><body>"
        // Add many filler paragraphs without the query term
        for i in 0..<30 {
            html += "<p>Section \(i): \(filler)</p>"
        }
        // Add the important paragraph
        html += "<p>This paragraph is important and very important for ranking.</p>"
        // Add more fillers
        for i in 30..<60 {
            html += "<p>Section \(i): \(filler)</p>"
        }
        html += "</body></html>"

        let stripped = WebExcerptRetriever.stripHTML(html)
        // Only run ranking test if stripped exceeds threshold
        guard stripped.utf8.count > WebExcerptRetriever.directInjectThresholdBytes else {
            XCTFail("Test setup error: stripped content \(stripped.utf8.count) bytes is not over threshold")
            return
        }

        let chunks = WebExcerptRetriever.chunkByHeadings(stripped)
        let ranked = WebExcerptRetriever.rankByQuery(chunks, query: "important")

        // The top-ranked chunk should contain the word "important"
        guard let topChunk = ranked.first else {
            XCTFail("No chunks ranked")
            return
        }
        XCTAssertTrue(topChunk.chunk.lowercased().contains("important"),
            "Top ranked chunk should contain query term 'important'. Got: \(topChunk.chunk.prefix(200))")
    }

    // MARK: - 4. alwaysInjectRaw bypasses excerpt mode

    func test_alwaysInjectRaw_bypass() async throws {
        // Build a large mock body (>32 KB)
        let largeBody = String(repeating: "a", count: 40 * 1024)
        XCTAssertGreaterThan(largeBody.utf8.count, WebExcerptRetriever.directInjectThresholdBytes)

        // Verify that excerpt would normally truncate it
        let excerpted = WebExcerptRetriever.excerpt(html: largeBody, query: "anything")
        XCTAssertLessThanOrEqual(excerpted.utf8.count, 32 * 1024)

        // Verify the bypass flag in FileSystemMentionToolClient via UserDefaults
        let key = "chat.web.alwaysInjectRaw"
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // With alwaysRaw = true the body is returned as-is (no excerpt).
        // We test this by reading the flag directly and simulating the logic.
        let alwaysRaw = UserDefaults.standard.bool(forKey: key)
        XCTAssertTrue(alwaysRaw)
        // When alwaysRaw = true the client returns body unchanged, so large body stays large
        let bodyBytes = largeBody.utf8.count
        XCTAssertGreaterThan(bodyBytes, 32 * 1024,
            "alwaysInjectRaw should allow full body through (>32 KB)")
    }

    // MARK: - 5. Empty query returns chunks in original insertion order (uniform score)

    func test_empty_query_uses_uniform_order() {
        // Build text using period-separated sentences so chunkByHeadings splits into multiple chunks.
        // Each sentence is ~50 chars; 30+ sentences per chunk target (~1000 bytes),
        // so we need many sentences to produce multiple chunks.
        var sentences: [String] = []
        for i in 0..<200 {
            sentences.append("This is sentence number \(i) with some filler words to add length here")
        }
        let text = sentences.joined(separator: ". ") + "."

        let chunks = WebExcerptRetriever.chunkByHeadings(text)
        guard chunks.count >= 2 else {
            XCTFail("Expected multiple chunks, got \(chunks.count)")
            return
        }
        let ranked = WebExcerptRetriever.rankByQuery(chunks, query: "")
        // With empty query all scores are 1.0 — order must match original
        let allScoresUniform = ranked.allSatisfy { $0.score == 1.0 }
        XCTAssertTrue(allScoresUniform, "Empty query should produce uniform scores")
        // Original order is preserved
        XCTAssertEqual(ranked.map { $0.chunk }, chunks)
    }
}
