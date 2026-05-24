// TokenAwareHistoryTests.swift — verifies the token-budgeted history window replacing
// the legacy `suffix(10)` cap in ChatService.

import XCTest
@testable import Zion

@MainActor
final class TokenAwareHistoryTests: XCTestCase {

    private func msg(_ content: String, role: ChatRole = .user) -> ChatMessage {
        ChatMessage(role: role, content: content)
    }

    // MARK: - Acceptance criteria coverage

    func test_windowedHistory_returns_recent_messages_under_budget() {
        // 20 messages × ~100 tokens each (350 chars / 3.5 = 100). Budget 1000 tokens.
        let msgs = (0..<20).map { msg("m\($0) " + String(repeating: "x", count: 350)) }
        let kept = ChatService.windowedHistory(msgs, available: 1000)
        XCTAssertLessThanOrEqual(kept.count, 10)
        XCTAssertEqual(kept.last?.content, msgs.last?.content, "Last kept message must be the newest")
    }

    func test_windowedHistory_preserves_chronological_order() {
        let msgs = (0..<5).map { msg("m\($0) " + String(repeating: "x", count: 50)) }
        let kept = ChatService.windowedHistory(msgs, available: 10_000)
        XCTAssertEqual(kept.map { $0.content }, msgs.map { $0.content })
    }

    func test_windowedHistory_includes_all_when_under_budget() {
        let msgs = (0..<5).map { _ in msg("small") }
        let kept = ChatService.windowedHistory(msgs, available: 10_000)
        XCTAssertEqual(kept.count, 5)
    }

    func test_windowedHistory_empty_input() {
        let kept = ChatService.windowedHistory([], available: 1000)
        XCTAssertTrue(kept.isEmpty)
    }

    func test_windowedHistory_zero_budget_returns_empty() {
        let msgs = (0..<3).map { _ in msg("hi") }
        let kept = ChatService.windowedHistory(msgs, available: 0)
        XCTAssertTrue(kept.isEmpty)
    }

    func test_windowedHistory_trims_to_fit_with_large_messages() {
        // 30 messages × ~1000 tokens each. Budget 3000 → at most 3 fit.
        let msgs = (0..<30).map { msg("m\($0) " + String(repeating: "x", count: 3500)) }
        let kept = ChatService.windowedHistory(msgs, available: 3000)
        XCTAssertLessThanOrEqual(kept.count, 4, "Got \(kept.count) messages")
    }
}
