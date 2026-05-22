// ToolLoopExecutorTests.swift

import XCTest
@testable import Zion

// MARK: - StubMCPClient

/// Thread-safe stub MCP client for testing.
final class StubMCPClient: MCPClientProtocol, @unchecked Sendable {

    var callCount = 0
    var stubbedResult: [String: Any] = ["output": "stub result"]
    var stubbedTools: [MCPToolDescriptor] = []

    func callTool(_ name: String, args: [String: Any]) async throws -> [String: Any] {
        callCount += 1
        return stubbedResult
    }

    func listTools() async throws -> [MCPToolDescriptor] {
        return stubbedTools
    }
}

// MARK: - ToolLoopExecutorTests

final class ToolLoopExecutorTests: XCTestCase {

    // MARK: - Helpers

    private func makeStream(_ lines: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }

    private func openAIToolCallLine(id: String = "call_abc", name: String, argsJSON: String) -> String {
        let json: [String: Any] = [
            "choices": [[
                "delta": [
                    "tool_calls": [[
                        "id": id,
                        "type": "function",
                        "function": [
                            "name": name,
                            "arguments": argsJSON
                        ]
                    ]]
                ],
                "finish_reason": NSNull()
            ]]
        ]
        return (try? JSONSerialization.data(withJSONObject: json))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private func openAIDoneLine() -> String {
        let json: [String: Any] = [
            "choices": [[
                "delta": [:] as [String: Any],
                "finish_reason": "stop"
            ]]
        ]
        return (try? JSONSerialization.data(withJSONObject: json))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private func openAITextLine(_ text: String) -> String {
        let json: [String: Any] = [
            "choices": [[
                "delta": ["content": text],
                "finish_reason": NSNull()
            ]]
        ]
        return (try? JSONSerialization.data(withJSONObject: json))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    // MARK: - Tests: Single tool call

    func test_singleToolCall_executesAndAppendResult() async throws {
        let stub = StubMCPClient()
        stub.stubbedResult = ["content": "file contents here"]

        let executor = ToolLoopExecutor(family: .openai, mcpClient: stub)

        let lines = [
            openAIToolCallLine(name: "read_file", argsJSON: #"{"path":"/tmp/test.txt"}"#),
            openAIDoneLine()
        ]

        let initialConversation: [[String: Any]] = [
            ["role": "user", "content": "Read /tmp/test.txt"]
        ]

        let (_, updatedConversation) = try await executor.run(
            streamLines: makeStream(lines),
            conversation: initialConversation
        )

        // Executor should have called the tool
        XCTAssertEqual(stub.callCount, 1)

        // A tool-result message should be appended
        XCTAssertGreaterThan(updatedConversation.count, initialConversation.count)
        let lastMessage = updatedConversation.last
        XCTAssertEqual(lastMessage?["role"] as? String, "user")
        XCTAssertEqual(lastMessage?["zion_tool_results"] as? Bool, true)
    }

    // MARK: - Tests: Text only (no tool calls)

    func test_textOnlyStream_noToolExecution() async throws {
        let stub = StubMCPClient()
        let executor = ToolLoopExecutor(family: .openai, mcpClient: stub)

        let lines = [
            openAITextLine("Hello "),
            openAITextLine("world"),
            openAIDoneLine()
        ]

        let initialConversation: [[String: Any]] = [["role": "user", "content": "Hi"]]
        let (text, updatedConversation) = try await executor.run(
            streamLines: makeStream(lines),
            conversation: initialConversation
        )

        XCTAssertEqual(stub.callCount, 0)
        XCTAssertEqual(text, "Hello world")
        // No extra messages appended
        XCTAssertEqual(updatedConversation.count, initialConversation.count)
    }

    // MARK: - Tests: Multiple tool calls in one turn

    func test_multipleToolCalls_allExecuted() async throws {
        let stub = StubMCPClient()
        stub.stubbedResult = ["ok": true]

        let executor = ToolLoopExecutor(family: .openai, mcpClient: stub)

        let lines = [
            openAIToolCallLine(id: "call_1", name: "tool_a", argsJSON: "{}"),
            openAIToolCallLine(id: "call_2", name: "tool_b", argsJSON: "{}"),
            openAIDoneLine()
        ]

        let (_, _) = try await executor.run(
            streamLines: makeStream(lines),
            conversation: [["role": "user", "content": "Use two tools"]]
        )

        XCTAssertEqual(stub.callCount, 2)
    }

    // MARK: - Tests: Anthropic stream parsing

    func test_anthropicTextDelta_parsed() {
        let line = """
        {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}
        """
        let chunks = ChunkParser.parseAnthropic(line: line)
        XCTAssertEqual(chunks.count, 1)
        if case .textDelta(let text) = chunks[0] {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected textDelta")
        }
    }

    func test_anthropicToolUse_parsed() {
        let line = """
        {"type":"content_block_start","content_block":{"type":"tool_use","id":"toolu_01","name":"read_file"}}
        """
        let chunks = ChunkParser.parseAnthropic(line: line)
        XCTAssertEqual(chunks.count, 1)
        if case .toolCall(let id, let name, _) = chunks[0] {
            XCTAssertEqual(id, "toolu_01")
            XCTAssertEqual(name, "read_file")
        } else {
            XCTFail("Expected toolCall")
        }
    }

    func test_anthropicMessageStop_done() {
        let line = """
        {"type":"message_stop"}
        """
        let chunks = ChunkParser.parseAnthropic(line: line)
        XCTAssertEqual(chunks.count, 1)
        if case .done = chunks[0] { } else {
            XCTFail("Expected done")
        }
    }

    // MARK: - Tests: OpenAI stream parsing

    func test_openAIDone_parsed() {
        let chunks = ChunkParser.parseOpenAI(line: "[DONE]")
        XCTAssertEqual(chunks.count, 1)
        if case .done = chunks[0] { } else {
            XCTFail("Expected done")
        }
    }

    func test_openAITextDelta_parsed() {
        let line = openAITextLine("Test text")
        let chunks = ChunkParser.parseOpenAI(line: line)
        XCTAssertEqual(chunks.count, 1)
        if case .textDelta(let text) = chunks[0] {
            XCTAssertEqual(text, "Test text")
        } else {
            XCTFail("Expected textDelta")
        }
    }

    func test_openAIToolCall_parsed() {
        let line = openAIToolCallLine(id: "call_xyz", name: "my_tool", argsJSON: #"{"key":"value"}"#)
        let chunks = ChunkParser.parseOpenAI(line: line)

        let toolCalls = chunks.compactMap { chunk -> (String, String, [String: Any])? in
            if case .toolCall(let id, let name, let args) = chunk {
                return (id, name, args)
            }
            return nil
        }
        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertEqual(toolCalls[0].0, "call_xyz")
        XCTAssertEqual(toolCalls[0].1, "my_tool")
        XCTAssertEqual(toolCalls[0].2["key"] as? String, "value")
    }

    // MARK: - Integration: synthetic openai tool_call resolves end-to-end

    func test_integration_syntheticOpenAIStream_toolCallResolvesEndToEnd() async throws {
        let stub = StubMCPClient()
        stub.stubbedResult = ["result": "integration_result"]

        let executor = ToolLoopExecutor(family: .openai, mcpClient: stub)

        let lines: [String] = [
            openAITextLine("I'll help with that. "),
            openAIToolCallLine(id: "call_int_1", name: "read_file", argsJSON: #"{"path":"/repo/README.md"}"#),
            openAIDoneLine()
        ]

        let conversation: [[String: Any]] = [
            ["role": "system", "content": "You are a helpful assistant."],
            ["role": "user",   "content": "Summarize the README."]
        ]

        let (text, updatedConversation) = try await executor.run(
            streamLines: makeStream(lines),
            conversation: conversation
        )

        // Text was accumulated
        XCTAssertEqual(text, "I'll help with that. ")

        // Tool was called once
        XCTAssertEqual(stub.callCount, 1)

        // Tool result appended as extra message
        XCTAssertEqual(updatedConversation.count, 3)
        let toolResultMsg = updatedConversation[2]
        XCTAssertEqual(toolResultMsg["role"] as? String, "user")
        XCTAssertEqual(toolResultMsg["zion_tool_results"] as? Bool, true)

        // Check the tool result content
        let content = toolResultMsg["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["tool_call_id"] as? String, "call_int_1")
        XCTAssertEqual(content?.first?["name"] as? String, "read_file")
    }
}
