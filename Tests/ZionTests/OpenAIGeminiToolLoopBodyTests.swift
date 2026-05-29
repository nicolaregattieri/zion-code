import XCTest
@testable import Zion

/// Phase 6.7 — body builders for OpenAI / Gemini native tool loops.
/// Live API not exercised in CI; we pin the request-body shape so the
/// protocol stays correct.
final class OpenAIGeminiToolLoopBodyTests: XCTestCase {

    private func payload() -> AIPromptPayload {
        AIPromptPayload(
            systemInstructions: "sys",
            taskInstructions: "task",
            untrustedSections: [],
            suspiciousPatterns: []
        )
    }

    // MARK: - OpenAI

    func test_openai_emptyAdditional_buildsSystemThenUser() throws {
        let data = ChatService.buildOpenAIBody(
            payload: payload(),
            modelID: "gpt-4o",
            maxTokens: 100,
            tools: [],
            additionalMessages: []
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let msgs = try XCTUnwrap(root["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.count, 2)
        XCTAssertEqual(msgs[0]["role"] as? String, "system")
        XCTAssertEqual(msgs[1]["role"] as? String, "user")
        XCTAssertEqual(root["stream"] as? Bool, true)
    }

    func test_openai_additionalMessages_appendInOrder() throws {
        let extra: [[String: Any]] = [
            [
                "role": "assistant",
                "tool_calls": [["id": "abc", "type": "function", "function": ["name": "ctx_search", "arguments": "{}"]]]
            ],
            ["role": "tool", "tool_call_id": "abc", "content": "matches=3"]
        ]
        let data = ChatService.buildOpenAIBody(
            payload: payload(),
            modelID: "gpt-4o",
            maxTokens: 100,
            tools: [],
            additionalMessages: extra
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let msgs = try XCTUnwrap(root["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.count, 4)
        XCTAssertEqual(msgs[2]["role"] as? String, "assistant")
        XCTAssertEqual(msgs[3]["role"] as? String, "tool")
    }

    func test_openai_toolsAttached_whenNonEmpty() throws {
        let tools: [[String: Any]] = [
            ["type": "function", "function": ["name": "use_skill", "description": "x", "parameters": ["type": "object"]]]
        ]
        let data = ChatService.buildOpenAIBody(
            payload: payload(),
            modelID: "gpt-4o",
            maxTokens: 100,
            tools: tools,
            additionalMessages: []
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let outTools = try XCTUnwrap(root["tools"] as? [[String: Any]])
        XCTAssertEqual(outTools.count, 1)
    }

    // MARK: - Gemini

    func test_gemini_buildsContents_andTools() throws {
        let data = ChatService.buildGeminiBody(
            contents: [["role": "user", "parts": [["text": "hi"]]]],
            tools: [["name": "ctx_search", "description": "search", "parameters": ["type": "object"]]]
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let contents = try XCTUnwrap(root["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.count, 1)
        let toolsArr = try XCTUnwrap(root["tools"] as? [[String: Any]])
        XCTAssertEqual(toolsArr.count, 1)
        let fdecls = try XCTUnwrap(toolsArr[0]["functionDeclarations"] as? [[String: Any]])
        XCTAssertEqual(fdecls[0]["name"] as? String, "ctx_search")
    }

    func test_gemini_emptyTools_omitsToolsField() throws {
        let data = ChatService.buildGeminiBody(
            contents: [["role": "user", "parts": [["text": "hi"]]]],
            tools: []
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(root["tools"])
    }
}
