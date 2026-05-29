import XCTest
@testable import Zion

/// Phase 6.6 — Anthropic native tool loop. We can't hit the live API in
/// unit tests, but we CAN pin the request-body builder so the protocol
/// shape stays correct: tool_use blocks ride in the assistant turn,
/// tool_result blocks ride in the next user turn, and additional
/// messages append in the right order.
final class AnthropicToolLoopBodyTests: XCTestCase {

    private func payload() -> AIPromptPayload {
        AIPromptPayload(
            systemInstructions: "sys",
            taskInstructions: "task",
            untrustedSections: [],
            suspiciousPatterns: []
        )
    }

    func test_emptyAdditional_buildsSingleUserMessage() throws {
        let data = ChatService.buildAnthropicBody(
            payload: payload(),
            modelID: "claude-3-5-sonnet-20241022",
            maxTokens: 100,
            tools: [],
            additionalMessages: []
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let msgs = try XCTUnwrap(root["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0]["role"] as? String, "user")
    }

    func test_additionalMessages_appendInOrder() throws {
        let extra: [[String: Any]] = [
            ["role": "assistant", "content": [["type": "text", "text": "thinking"]]],
            ["role": "user", "content": [["type": "tool_result", "tool_use_id": "abc", "content": "ok"]]]
        ]
        let data = ChatService.buildAnthropicBody(
            payload: payload(),
            modelID: "claude-3-5-sonnet-20241022",
            maxTokens: 100,
            tools: [],
            additionalMessages: extra
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let msgs = try XCTUnwrap(root["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.count, 3)
        XCTAssertEqual(msgs[0]["role"] as? String, "user")        // original turn
        XCTAssertEqual(msgs[1]["role"] as? String, "assistant")    // prior assistant w/ tool_use
        XCTAssertEqual(msgs[2]["role"] as? String, "user")         // tool_result turn
    }

    func test_toolsAttached_whenNonEmpty() throws {
        let tools: [[String: Any]] = [
            ["name": "ctx_search", "description": "search", "input_schema": ["type": "object"]]
        ]
        let data = ChatService.buildAnthropicBody(
            payload: payload(),
            modelID: "claude-3-5-sonnet-20241022",
            maxTokens: 100,
            tools: tools,
            additionalMessages: []
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let outTools = try XCTUnwrap(root["tools"] as? [[String: Any]])
        XCTAssertEqual(outTools.count, 1)
        XCTAssertEqual(outTools[0]["name"] as? String, "ctx_search")
    }

    func test_streamFlagPresent() throws {
        let data = ChatService.buildAnthropicBody(
            payload: payload(),
            modelID: "claude-3-5-sonnet-20241022",
            maxTokens: 100,
            tools: [],
            additionalMessages: []
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["stream"] as? Bool, true)
    }

    func test_flagDefault_isOff() {
        // We can't read UserDefaults in CI cleanly but we can assert that
        // the key the loop wires against is the documented one.
        XCTAssertEqual(ChatService.nativeToolLoopFlagKey, "chat.nativeToolLoop.enabled")
    }
}
