import XCTest
@testable import Zion

final class ToolResultEvictorTests: XCTestCase {

    // MARK: - Helpers

    /// Build a tool_result block with the given content string.
    private func toolResult(id: String, content: String) -> [String: Any] {
        ["type": "tool_result", "tool_use_id": id, "content": content]
    }

    /// Build a user message that wraps one or more content blocks.
    private func userMsg(blocks: [[String: Any]]) -> [String: Any] {
        ["role": "user", "content": blocks]
    }

    /// Build a large string exceeding 4096 bytes.
    private func bigPayload(bytes: Int = 5000) -> String {
        String(repeating: "x", count: bytes)
    }

    // MARK: - Test 1: Latest tool_result intact

    func test_latest_tool_result_intact() {
        // 6 tool_result blocks, recentStepGuard=2 → last 2 survive
        var msgs: [[String: Any]] = []
        for i in 1...6 {
            msgs.append(userMsg(blocks: [toolResult(id: "r\(i)", content: bigPayload())]))
        }

        let result = ToolResultEvictor.evict(msgs, currentStep: 6)

        // Results 5 and 6 (last 2) must NOT be rewritten
        let block5 = (result[4]["content"] as? [[String: Any]])?.first
        let block6 = (result[5]["content"] as? [[String: Any]])?.first

        XCTAssertNil(block5?["zion_evicted"] as? Bool, "Result 5 should not be evicted")
        XCTAssertNil(block6?["zion_evicted"] as? Bool, "Result 6 should not be evicted")

        let content5 = block5?["content"] as? String ?? ""
        let content6 = block6?["content"] as? String ?? ""
        XCTAssertFalse(content5.contains("[elided"), "Result 5 content should not be elided")
        XCTAssertFalse(content6.contains("[elided"), "Result 6 content should not be elided")
    }

    // MARK: - Test 2: Older results rewritten with elide marker

    func test_older_results_rewritten_with_elide_marker() {
        // 6 tool_result blocks, results 1–4 should be rewritten
        let payloadSize = 5000
        var msgs: [[String: Any]] = []
        for i in 1...6 {
            msgs.append(userMsg(blocks: [toolResult(id: "r\(i)", content: bigPayload(bytes: payloadSize))]))
        }

        let result = ToolResultEvictor.evict(msgs, currentStep: 6)

        // Results 1–4 should be elided
        for i in 0..<4 {
            let block = (result[i]["content"] as? [[String: Any]])?.first
            let content = block?["content"] as? String ?? ""
            XCTAssertTrue(content.contains("[elided:"), "Result \(i+1) should be elided, got: \(content)")
            XCTAssertTrue(content.contains("\(payloadSize) bytes"), "Elide marker should contain byte count")
            XCTAssertTrue(content.contains("earlier round"), "Elide marker should mention 'earlier round'")
            XCTAssertEqual(block?["zion_evicted"] as? Bool, true)
        }
    }

    // MARK: - Test 3: Small tool_results not evicted

    func test_small_tool_results_not_evicted() {
        // A 1KB tool_result at result index 1 (below 4KB threshold) stays verbatim
        let smallPayload = String(repeating: "s", count: 1024)  // 1024 bytes < 4096
        let msg = userMsg(blocks: [toolResult(id: "r1", content: smallPayload)])
        // Add 5 more results to ensure r1 is in evict-eligible zone
        var msgs: [[String: Any]] = [msg]
        for i in 2...6 {
            msgs.append(userMsg(blocks: [toolResult(id: "r\(i)", content: bigPayload())]))
        }

        let result = ToolResultEvictor.evict(msgs, currentStep: 6)

        // r1 is eligible for eviction (seen=1 <= evictUpTo=4) but below size threshold
        let block1 = (result[0]["content"] as? [[String: Any]])?.first
        let content1 = block1?["content"] as? String ?? ""
        XCTAssertFalse(content1.contains("[elided"), "1KB result should NOT be elided, got: \(content1)")
        XCTAssertEqual(content1, smallPayload, "Small result content should be unchanged")
    }

    // MARK: - Test 4: currentStep < 3 (totalResults=2) → no eviction

    func test_currentStep_less_than_3_no_eviction() {
        // Only 2 tool_result blocks total; recentStepGuard=2 → evictUpTo=0 → nothing evicted
        let msgs: [[String: Any]] = [
            userMsg(blocks: [toolResult(id: "r1", content: bigPayload())]),
            userMsg(blocks: [toolResult(id: "r2", content: bigPayload())])
        ]

        let result = ToolResultEvictor.evict(msgs, currentStep: 2)

        for (i, msg) in result.enumerated() {
            let block = (msg["content"] as? [[String: Any]])?.first
            XCTAssertNil(block?["zion_evicted"] as? Bool, "Result \(i+1) should not be evicted when total=2")
            let content = block?["content"] as? String ?? ""
            XCTAssertFalse(content.contains("[elided"), "Result \(i+1) should not be elided")
        }
    }

    // MARK: - Test 5: Non-tool_result blocks untouched

    func test_non_tool_result_blocks_untouched() {
        let textBlock: [String: Any] = ["type": "text", "text": "This is plain text content."]
        let toolBlock = toolResult(id: "r1", content: bigPayload())
        // Mix: one message with both a text block and a tool_result block
        let mixedMsg: [String: Any] = ["role": "user", "content": [textBlock, toolBlock]]

        // Add enough tool results to push r1 into eviction zone
        var msgs: [[String: Any]] = [mixedMsg]
        for i in 2...5 {
            msgs.append(userMsg(blocks: [toolResult(id: "r\(i)", content: bigPayload())]))
        }

        let result = ToolResultEvictor.evict(msgs, currentStep: 5)

        let firstMsgBlocks = result[0]["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(firstMsgBlocks.count, 2, "Mixed message should still have 2 blocks")

        // Text block should be completely unchanged
        let resultTextBlock = firstMsgBlocks.first { ($0["type"] as? String) == "text" }
        XCTAssertEqual(resultTextBlock?["text"] as? String, "This is plain text content.",
                       "Text block content should be unchanged")

        // Non-tool_result blocks must not have zion_evicted
        XCTAssertNil(resultTextBlock?["zion_evicted"], "Text blocks should never have zion_evicted")
    }
}
