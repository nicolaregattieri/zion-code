// ChatServiceBudgetGateTests.swift — verifies the pre-send budget gate + 75% compact threshold.

import XCTest
@testable import Zion

@MainActor
final class ChatServiceBudgetGateTests: XCTestCase {

    func test_budgetOverflowState_struct_equatable() {
        let id = UUID()
        let a = ChatService.BudgetOverflowState(estimatedTokens: 100, availableTokens: 50, messageID: id)
        let b = ChatService.BudgetOverflowState(estimatedTokens: 100, availableTokens: 50, messageID: id)
        let c = ChatService.BudgetOverflowState(estimatedTokens: 101, availableTokens: 50, messageID: id)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func test_estimate_alignment_with_TokenEstimator() {
        let text = String(repeating: "x", count: 350)
        XCTAssertEqual(TokenEstimator.estimate(text, kind: .code), 100)
    }

    func test_shouldCompact_above_75_percent_returns_true() {
        XCTAssertTrue(ChatService.shouldCompact(estimated: 800, budget: 1000))
        XCTAssertTrue(ChatService.shouldCompact(estimated: 751, budget: 1000))
    }

    func test_shouldCompact_at_or_below_75_percent_returns_false() {
        XCTAssertFalse(ChatService.shouldCompact(estimated: 750, budget: 1000))
        XCTAssertFalse(ChatService.shouldCompact(estimated: 100, budget: 1000))
    }

    func test_shouldCompact_zero_budget_returns_false() {
        XCTAssertFalse(ChatService.shouldCompact(estimated: 1000, budget: 0))
    }

    func test_shouldCompact_zero_estimated_returns_false() {
        XCTAssertFalse(ChatService.shouldCompact(estimated: 0, budget: 1000))
    }
}
