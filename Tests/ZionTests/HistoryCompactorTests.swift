import XCTest
@testable import Zion

final class HistoryCompactorTests: XCTestCase {

    // MARK: - Helpers

    /// Build a synthetic user/assistant exchange with ~N characters per message.
    private func makeTurns(_ count: Int, charsPerMsg: Int = 500) -> [[String: Any]] {
        var msgs: [[String: Any]] = []
        for i in 0..<count {
            msgs.append(["role": "user",      "content": String(repeating: "u", count: charsPerMsg) + " turn\(i)"])
            msgs.append(["role": "assistant", "content": String(repeating: "a", count: charsPerMsg) + " turn\(i)"])
        }
        return msgs
    }

    // MARK: - Test 1: Under budget → unchanged

    func test_under_budget_returns_unchanged() async {
        let compactor = HistoryCompactor()
        let conversation: [[String: Any]] = [
            ["role": "system",    "content": "You are helpful."],
            ["role": "user",      "content": "Hello"],
            ["role": "assistant", "content": "Hi there!"]
        ]
        // Budget well above the tiny conversation (~10 tokens).
        let result = await compactor.compactIfNeeded(conversation, tokenBudget: 200)
        XCTAssertEqual(result.count, conversation.count)
        XCTAssertEqual(result[0]["content"] as? String, "You are helpful.")
        XCTAssertEqual(result[1]["content"] as? String, "Hello")
        XCTAssertEqual(result[2]["content"] as? String, "Hi there!")
    }

    // MARK: - Test 2: Over budget → summary inserted, tail preserved

    func test_over_budget_inserts_summary_and_preserves_tail() async {
        // 50 turns × 2 messages × 500 chars ≈ 50000 / 3.5 ≈ ~14286 tokens — over 10k budget
        let body = makeTurns(50, charsPerMsg: 500)
        let systemMsg: [String: Any] = ["role": "system", "content": "System prompt."]
        let conversation = [systemMsg] + body

        let compactor = HistoryCompactor(summarizer: { _ in "S" })
        let result = await compactor.compactIfNeeded(conversation, tokenBudget: 10_000)

        // Head: 1 system msg
        // Summary: 1 msg containing "S"
        // Tail: last 8 msgs (4 turns × 2 roles)
        XCTAssertEqual(result.count, 1 + 1 + 8, "Expected head(1) + summary(1) + tail(8) = 10 messages, got \(result.count)")

        // First message is the original system prompt
        XCTAssertEqual(result[0]["content"] as? String, "System prompt.")

        // Second message is the summary
        let summaryMsg = result[1]
        XCTAssertEqual(summaryMsg["role"] as? String, "system")
        let summaryContent = summaryMsg["content"] as? String ?? ""
        XCTAssertTrue(summaryContent.contains("S"), "Summary content should contain 'S', got: \(summaryContent)")
        XCTAssertTrue(summaryContent.hasPrefix(HistoryCompactor.summaryMarkerPrefix))
        XCTAssertEqual(summaryMsg["compactor_replacement"] as? Bool, true)

        // Last 8 messages match the tail of the original body
        let expectedTail = Array(body.suffix(8))
        for (i, msg) in result.suffix(8).enumerated() {
            XCTAssertEqual(msg["content"] as? String, expectedTail[i]["content"] as? String,
                           "Tail message \(i) content mismatch")
        }
    }

    // MARK: - Test 3: Pinned messages survive compaction

    func test_pinned_messages_survive() async {
        let body = makeTurns(50, charsPerMsg: 500)
        // A pinned message in the "middle" — it should be lifted into head by split()
        let pinnedMsg: [String: Any] = [
            "role": "user",
            "content": "@file:important.swift — pinned context",
            "pinned": true
        ]
        // Insert pinned message somewhere before the tail
        var conversation: [[String: Any]] = [["role": "system", "content": "Sys"]]
        conversation += Array(body.prefix(10))
        conversation.append(pinnedMsg)
        conversation += Array(body.suffix(40))

        let compactor = HistoryCompactor(summarizer: { _ in "Summary text" })
        let result = await compactor.compactIfNeeded(conversation, tokenBudget: 5_000)

        // Check that the pinned message is present in the result
        let pinnedFound = result.contains { msg in
            (msg["content"] as? String)?.contains("pinned context") == true
        }
        XCTAssertTrue(pinnedFound, "Pinned message should survive compaction")

        // Pinned message should be in the head section (before the summary)
        let summaryIndex = result.firstIndex { ($0["compactor_replacement"] as? Bool) == true }
        let pinnedIndex = result.firstIndex { (($0["content"] as? String)?.contains("pinned context")) == true }
        if let si = summaryIndex, let pi = pinnedIndex {
            XCTAssertLessThan(pi, si, "Pinned message should appear before the summary block")
        }
    }

    // MARK: - Test 4: Summarizer failure → truncation marker

    func test_summarizer_failure_falls_back_to_truncation_marker() async {
        let body = makeTurns(50, charsPerMsg: 500)
        let conversation: [[String: Any]] = [["role": "system", "content": "S"]] + body

        // Summarizer returns nil → triggers fallback
        let compactor = HistoryCompactor(summarizer: { _ in nil })
        let result = await compactor.compactIfNeeded(conversation, tokenBudget: 5_000)

        let summaryMsg = result.first { ($0["compactor_replacement"] as? Bool) == true }
        XCTAssertNotNil(summaryMsg, "A compactor_replacement message should be present")

        let content = summaryMsg?["content"] as? String ?? ""
        XCTAssertTrue(content.contains("[truncated"), "Fallback should contain '[truncated', got: \(content)")
        XCTAssertTrue(content.contains("older turns"), "Fallback should mention 'older turns', got: \(content)")
    }

    // MARK: - Test 5: Split correctly separates head, middle, tail

    func test_split_separates_correctly() {
        let sys: [String: Any] = ["role": "system", "content": "Sys"]
        let u1: [String: Any]  = ["role": "user",      "content": "U1"]
        let a1: [String: Any]  = ["role": "assistant",  "content": "A1"]
        let u2: [String: Any]  = ["role": "user",      "content": "U2"]
        let a2: [String: Any]  = ["role": "assistant",  "content": "A2"]
        let u3: [String: Any]  = ["role": "user",      "content": "U3"]
        let a3: [String: Any]  = ["role": "assistant",  "content": "A3"]

        let conv = [sys, u1, a1, u2, a2, u3, a3]
        // preservedTurns=2 → tail = last 4 messages
        let (head, middle, tail) = HistoryCompactor.split(conv, preservedTurns: 2)

        XCTAssertEqual(head.count, 1, "Head should contain only system message")
        XCTAssertEqual(head[0]["content"] as? String, "Sys")

        XCTAssertEqual(tail.count, 4, "Tail should contain last 4 messages (2 turns × 2)")
        XCTAssertEqual(tail[0]["content"] as? String, "U2")

        XCTAssertEqual(middle.count, 2, "Middle should contain remaining non-head, non-tail messages")
        XCTAssertEqual(middle[0]["content"] as? String, "U1")
    }
}
