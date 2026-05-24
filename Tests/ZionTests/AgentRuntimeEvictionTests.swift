// AgentRuntimeEvictionTests.swift — Integration tests for ToolResultEvictor wiring
// in ToolLoopRunner. Tests verify that stale tool_result blocks are elided on
// rounds beyond the first and that the latest result is never touched.

import XCTest
@testable import Zion

// MARK: - AgentRuntimeEvictionTests

final class AgentRuntimeEvictionTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a fake multi-round conversation where every round has:
    ///   - an assistant message with a tool_use block
    ///   - a user message with a tool_result block containing `payloadSize` bytes
    private func makeConversation(rounds: Int, payloadSize: Int) -> [[String: Any]] {
        let payload = String(repeating: "X", count: payloadSize)
        var convo: [[String: Any]] = []
        for i in 0..<rounds {
            // assistant turn
            let toolUse: [String: Any] = [
                "type": "tool_use",
                "id": "tu\(i)",
                "name": "test_tool",
                "input": [String: Any]()
            ]
            let assistantMsg: [String: Any] = [
                "role": "assistant",
                "content": [toolUse]
            ]
            // user turn (tool result)
            let toolResult: [String: Any] = [
                "type": "tool_result",
                "tool_use_id": "tu\(i)",
                "content": payload
            ]
            let userMsg: [String: Any] = [
                "role": "user",
                "content": [toolResult]
            ]
            convo.append(assistantMsg)
            convo.append(userMsg)
        }
        return convo
    }

    /// Returns all tool_result content strings from a conversation in order.
    private func toolResultContents(_ conversation: [[String: Any]]) -> [String] {
        var results: [String] = []
        for msg in conversation {
            if let blocks = msg["content"] as? [[String: Any]] {
                for block in blocks where (block["type"] as? String) == "tool_result" {
                    results.append(block["content"] as? String ?? "")
                }
            }
        }
        return results
    }

    // MARK: - Test 1: round 6 elides rounds 1 through 4

    func test_round6_elides_rounds1_through4() {
        // Build a 6-round conversation with 10 KB payloads (above the 4096-byte threshold).
        let rounds = 6
        let payloadSize = 10_240
        let convo = makeConversation(rounds: rounds, payloadSize: payloadSize)

        // Simulate what ToolLoopRunner does before step 6 (stepCount = 5, currentStep = 6).
        let evicted = ToolResultEvictor.evict(convo, currentStep: 6)

        let contents = toolResultContents(evicted)
        XCTAssertEqual(contents.count, rounds, "Should have \(rounds) tool_result blocks total")

        // recentStepGuard = 2 → preserve rounds 5 and 6 (indices 4 and 5).
        // Rounds 1-4 (indices 0-3) should be elided.
        for i in 0..<4 {
            XCTAssertTrue(
                contents[i].hasPrefix("[elided:"),
                "Round \(i + 1) tool_result should be elided; got: \(contents[i].prefix(80))"
            )
            XCTAssertTrue(
                contents[i].contains("earlier round"),
                "Elide marker for round \(i + 1) should contain 'earlier round'"
            )
        }

        // Rounds 5 and 6 should be intact.
        for i in 4..<6 {
            XCTAssertFalse(
                contents[i].hasPrefix("[elided:"),
                "Round \(i + 1) tool_result must NOT be elided"
            )
            XCTAssertEqual(
                contents[i].utf8.count, payloadSize,
                "Round \(i + 1) should retain full \(payloadSize)-byte payload"
            )
        }
    }

    // MARK: - Test 2: latest tool_result never evicted

    func test_latest_tool_result_never_evicted() {
        let payloadSize = 10_240
        let convo = makeConversation(rounds: 6, payloadSize: payloadSize)

        // Apply eviction as if we're at step 6.
        let evicted = ToolResultEvictor.evict(convo, currentStep: 6)
        let contents = toolResultContents(evicted)

        let last = contents.last ?? ""
        XCTAssertFalse(
            last.hasPrefix("[elided:"),
            "The final tool_result must never be elicted; got: \(last.prefix(80))"
        )
        XCTAssertEqual(
            last.utf8.count, payloadSize,
            "Last tool_result must retain full payload"
        )
    }

    // MARK: - Test 3: small tool_results below threshold are not evicted

    func test_small_tool_results_not_evicted() {
        // 1 KB payloads — below the 4096-byte minByteLengthToEvict threshold.
        let payloadSize = 1_024
        let convo = makeConversation(rounds: 6, payloadSize: payloadSize)

        // Even at step 6, small results should survive untouched.
        let evicted = ToolResultEvictor.evict(convo, currentStep: 6)
        let contents = toolResultContents(evicted)

        for (i, content) in contents.enumerated() {
            XCTAssertFalse(
                content.hasPrefix("[elided:"),
                "Round \(i + 1) with small payload should NOT be elided"
            )
            XCTAssertEqual(
                content.utf8.count, payloadSize,
                "Round \(i + 1) small payload must be intact"
            )
        }
    }

    // MARK: - Test 4: first round (stepCount = 0) — evictor not called, conversation unchanged

    func test_first_round_not_evicted() {
        // At stepCount = 0, ToolLoopRunner skips eviction entirely.
        // Simulate this by calling evict with currentStep = 1 on a 1-round conversation.
        let payloadSize = 10_240
        let convo = makeConversation(rounds: 1, payloadSize: payloadSize)

        // currentStep = 1 → evictUpTo = max(0, 1 - 2) = 0 → nothing evicted.
        let result = ToolResultEvictor.evict(convo, currentStep: 1)
        let contents = toolResultContents(result)

        XCTAssertEqual(contents.count, 1)
        XCTAssertFalse(
            contents[0].hasPrefix("[elided:"),
            "Round 1 at currentStep=1 must never be evicted"
        )
        XCTAssertEqual(contents[0].utf8.count, payloadSize)
    }

    // MARK: - Test 5: elided marker format matches spec

    func test_elide_marker_format() {
        let payloadSize = 10_240
        let convo = makeConversation(rounds: 4, payloadSize: payloadSize)

        // currentStep = 4 → evictUpTo = max(0, 4 - 2) = 2 → elide rounds 1 and 2.
        let evicted = ToolResultEvictor.evict(convo, currentStep: 4)
        let contents = toolResultContents(evicted)

        // First two should be elided.
        XCTAssertEqual(
            contents[0],
            "[elided: \(payloadSize) bytes \u{2014} earlier round]",
            "Elide marker must match exact format"
        )
        XCTAssertEqual(
            contents[1],
            "[elided: \(payloadSize) bytes \u{2014} earlier round]",
            "Elide marker must match exact format"
        )

        // Rounds 3 and 4 intact.
        XCTAssertFalse(contents[2].hasPrefix("[elided:"))
        XCTAssertFalse(contents[3].hasPrefix("[elided:"))
    }
}
