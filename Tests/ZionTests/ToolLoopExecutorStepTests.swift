// ToolLoopExecutorStepTests.swift — Unit tests for ToolLoopExecutor.runOneStep.
// Covers the four StopReason branches: endTurn, toolUse, maxTokens, other.

import XCTest
@testable import Zion

// MARK: - MockMCPClient

/// Stub MCP client that returns a fixed result for any callTool invocation.
final class MockMCPClient: @unchecked Sendable, MCPClientProtocol {

    var callToolResult: [String: Any] = ["output": "stub"]
    private(set) var callCount = 0

    func callTool(_ name: String, args: [String: Any]) async throws -> [String: Any] {
        callCount += 1
        return callToolResult
    }

    func listTools() async throws -> [MCPToolDescriptor] {
        return []
    }
}

// MARK: - Stream helpers

private func makeStream(lines: [String]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        for line in lines {
            continuation.yield(line)
        }
        continuation.finish()
    }
}

// MARK: - ToolLoopExecutorStepTests

final class ToolLoopExecutorStepTests: XCTestCase {

    private var mockMCP: MockMCPClient!
    private var executor: ToolLoopExecutor!

    override func setUp() {
        super.setUp()
        mockMCP = MockMCPClient()
        executor = ToolLoopExecutor(family: .openai, mcpClient: mockMCP)
    }

    // MARK: 1. endTurn — text-only stream

    func testEndTurnStopReason() async throws {
        // OpenAI-style: one text delta chunk, then finish_reason = "stop"
        let textDelta = """
        {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"delta":{"content":"Hello world"},"finish_reason":null}]}
        """
        let finishChunk = """
        {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"delta":{},"finish_reason":"stop"}]}
        """

        let stream = makeStream(lines: [textDelta, finishChunk, "[DONE]"])
        let outcome = try await executor.runOneStep(streamLines: stream, conversation: [])

        XCTAssertEqual(outcome.stopReason, .endTurn)
        XCTAssertTrue(outcome.toolCalls.isEmpty)
        XCTAssertEqual(outcome.text, "Hello world")
        XCTAssertEqual(mockMCP.callCount, 0)
    }

    // MARK: 2. toolUse — one tool call chunk

    func testToolUseStopReason() async throws {
        // OpenAI-style: one tool call chunk
        let toolChunk = """
        {"id":"chatcmpl-2","object":"chat.completion.chunk","choices":[{"delta":{"tool_calls":[{"id":"call_abc","function":{"name":"read_file","arguments":"{\\"path\\":\\"/tmp/x\\"}"}}]},"finish_reason":null}]}
        """
        let finishChunk = """
        {"id":"chatcmpl-2","object":"chat.completion.chunk","choices":[{"delta":{},"finish_reason":"tool_calls"}]}
        """

        let stream = makeStream(lines: [toolChunk, finishChunk])
        let outcome = try await executor.runOneStep(streamLines: stream, conversation: [])

        XCTAssertEqual(outcome.stopReason, .toolUse)
        XCTAssertEqual(outcome.toolCalls.count, 1)
        XCTAssertEqual(outcome.toolCalls[0].name, "read_file")
        XCTAssertEqual(outcome.toolCalls[0].id, "call_abc")
        // Mock was called once
        XCTAssertEqual(mockMCP.callCount, 1)
        // updatedConversation has the tool_result message appended
        let last = outcome.updatedConversation.last
        XCTAssertEqual(last?["role"] as? String, "user")
        XCTAssertEqual(last?["zion_tool_results"] as? Bool, true)
    }

    // MARK: 3. maxTokens — finish_reason "length"

    func testMaxTokensStopReason() async throws {
        // OpenAI finish_reason = "length" → .maxTokens
        let textDelta = """
        {"id":"chatcmpl-3","object":"chat.completion.chunk","choices":[{"delta":{"content":"truncated..."},"finish_reason":null}]}
        """
        let finishChunk = """
        {"id":"chatcmpl-3","object":"chat.completion.chunk","choices":[{"delta":{},"finish_reason":"length"}]}
        """

        let stream = makeStream(lines: [textDelta, finishChunk])
        let outcome = try await executor.runOneStep(streamLines: stream, conversation: [])

        XCTAssertEqual(outcome.stopReason, .maxTokens)
        XCTAssertTrue(outcome.toolCalls.isEmpty)
    }

    // MARK: 3b. maxTokens — Anthropic "max_tokens"

    func testMaxTokensStopReasonAnthropic() async throws {
        let executorAnthropic = ToolLoopExecutor(family: .anthropic, mcpClient: mockMCP)

        // Anthropic emits message_delta with stop_reason = "max_tokens"
        let deltaLine = """
        {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}
        """
        let stopLine = """
        {"type":"message_stop"}
        """

        let stream = makeStream(lines: [deltaLine, stopLine])
        let outcome = try await executorAnthropic.runOneStep(streamLines: stream, conversation: [])

        XCTAssertEqual(outcome.stopReason, .maxTokens)
        XCTAssertTrue(outcome.toolCalls.isEmpty)
    }

    // MARK: 4. other — unknown finish reason

    func testOtherStopReason() async throws {
        // OpenAI finish_reason = "unknown_reason" → .other("unknown_reason")
        let finishChunk = """
        {"id":"chatcmpl-4","object":"chat.completion.chunk","choices":[{"delta":{},"finish_reason":"unknown_reason"}]}
        """

        let stream = makeStream(lines: [finishChunk])
        let outcome = try await executor.runOneStep(streamLines: stream, conversation: [])

        XCTAssertEqual(outcome.stopReason, .other("unknown_reason"))
        XCTAssertTrue(outcome.toolCalls.isEmpty)
    }

    // MARK: Compatibility: run() wrapper returns same data

    func testRunWrapperReturnsLegacyTuple() async throws {
        let textDelta = """
        {"id":"chatcmpl-5","object":"chat.completion.chunk","choices":[{"delta":{"content":"Hi"},"finish_reason":null}]}
        """
        let finishChunk = """
        {"id":"chatcmpl-5","object":"chat.completion.chunk","choices":[{"delta":{},"finish_reason":"stop"}]}
        """

        let stream = makeStream(lines: [textDelta, finishChunk])
        let (text, _) = try await executor.run(streamLines: stream, conversation: [])

        XCTAssertEqual(text, "Hi")
    }

    // MARK: StepOutcome.fromGemini adapter

    func testFromGeminiAdapter() {
        let geminiTC = GeminiToolCall(id: "g1", name: "search", args: ["q": "test"])
        let geminiOutcome = GeminiStepOutcome(
            text: "found it",
            toolCalls: [geminiTC],
            stopReason: .maxTokens,
            updatedConversation: []
        )
        let unified = StepOutcome.fromGemini(geminiOutcome)

        XCTAssertEqual(unified.text, "found it")
        XCTAssertEqual(unified.stopReason, .maxTokens)
        XCTAssertEqual(unified.toolCalls.count, 1)
        XCTAssertEqual(unified.toolCalls[0].name, "search")
        XCTAssertEqual(unified.toolCalls[0].id, "g1")
    }
}
