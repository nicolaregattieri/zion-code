import XCTest
@testable import Zion

/// Phase 6 — auto-context injector unit tests. Focus on deterministic
/// pieces: skip heuristic, budget cap, mention-collision short-circuit,
/// system block rendering. Hybrid retrieval roundtrips live in
/// RAGStoreTests / HybridQueryTests.
final class ChatContextAutoInjectorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "chat.context.autoEnabled")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "chat.context.autoEnabled")
        super.tearDown()
    }

    // MARK: - Skip heuristic

    func test_skipReason_emptyMessage_isShort() {
        XCTAssertEqual(ChatContextAutoInjector.skipReason(for: ""), .shortMessage)
        XCTAssertEqual(ChatContextAutoInjector.skipReason(for: "   "), .shortMessage)
    }

    func test_skipReason_shortMessage_isShort() {
        // 7 chars / 4 = 1 token -> under the 8-token threshold.
        XCTAssertEqual(ChatContextAutoInjector.skipReason(for: "hi"), .metaPhrase) // matches regex
        XCTAssertEqual(ChatContextAutoInjector.skipReason(for: "abcdefg"), .shortMessage)
    }

    func test_skipReason_metaPhrase_isMeta() {
        XCTAssertEqual(ChatContextAutoInjector.skipReason(for: "why did you do that?"), .metaPhrase)
        XCTAssertEqual(ChatContextAutoInjector.skipReason(for: "thanks for the help"), .metaPhrase)
        XCTAssertEqual(ChatContextAutoInjector.skipReason(for: "Continue with the next step"), .metaPhrase)
        XCTAssertEqual(ChatContextAutoInjector.skipReason(for: "por que isso foi feito assim"), .metaPhrase)
    }

    func test_skipReason_longContentQuery_passes() {
        // Long, on-topic message should NOT be skipped.
        XCTAssertNil(ChatContextAutoInjector.skipReason(for: "where do we handle subprocess cancellation in the chat service?"))
        XCTAssertNil(ChatContextAutoInjector.skipReason(for: "como funciona a indexacao incremental do RAG quando um arquivo eh renomeado"))
    }

    // MARK: - Budget

    func test_budget_perTier_matchesConstants() {
        XCTAssertEqual(ChatContextAutoInjector.budget(for: .cheap), Constants.RAG.autoBudgetTokensCheap)
        XCTAssertEqual(ChatContextAutoInjector.budget(for: .expensive), Constants.RAG.autoBudgetTokensExpensive)
    }

    // MARK: - Path matching

    func test_pathMatches_exactAndSuffixAndDirectory() {
        XCTAssertTrue(ChatContextAutoInjector.pathMatches("Sources/Zion/Foo.swift", pinned: "Sources/Zion/Foo.swift"))
        XCTAssertTrue(ChatContextAutoInjector.pathMatches("/abs/Sources/Zion/Foo.swift", pinned: "Sources/Zion/Foo.swift"))
        XCTAssertTrue(ChatContextAutoInjector.pathMatches("Sources/Zion/Services/Foo.swift", pinned: "Sources/Zion/Services"))
        XCTAssertFalse(ChatContextAutoInjector.pathMatches("Sources/Zion/Bar.swift", pinned: "Sources/Zion/Foo.swift"))
    }

    // MARK: - System block rendering

    func test_renderSystemBlock_emptyPayload_returnsEmptyString() {
        let s = ChatContextAutoInjector.renderSystemBlock(.empty)
        XCTAssertTrue(s.isEmpty)
    }

    func test_renderSystemBlock_includesPathAndKind() {
        let chunk = RAGChunk(
            path: "Sources/Zion/Foo.swift", startLine: 10, endLine: 25,
            kind: "function", contentSHA: "abc", fallback: false
        )
        let hit = RAGHit(chunk: chunk, score: 0.9, source: .hybrid)
        let payload = ChatContextAutoInjector.Payload(
            hits: [hit], estimatedTokens: 250, truncated: false, skippedReason: nil
        )
        let s = ChatContextAutoInjector.renderSystemBlock(payload)
        XCTAssertTrue(s.contains("Sources/Zion/Foo.swift:10-25"))
        XCTAssertTrue(s.contains("function"))
        XCTAssertTrue(s.contains("(hybrid)"))
    }

    // MARK: - Resolve end-to-end (no real RAG service)

    func test_resolve_disabledFlag_returnsDisabledSkip() async {
        UserDefaults.standard.set(false, forKey: "chat.context.autoEnabled")
        let injector = ChatContextAutoInjector(service: { nil })
        let payload = await injector.resolve(
            message: "where do we handle subprocess cancellation in chat service today",
            tier: .cheap
        )
        XCTAssertEqual(payload.skippedReason, .disabled)
        XCTAssertTrue(payload.hits.isEmpty)
    }

    func test_resolve_noLocator_returnsUnavailableSkip() async {
        let injector = ChatContextAutoInjector(service: { nil })
        let payload = await injector.resolve(
            message: "long enough message about chat subprocess handling",
            tier: .cheap
        )
        XCTAssertEqual(payload.skippedReason, .unavailable)
    }
}
