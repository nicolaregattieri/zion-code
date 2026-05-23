// AgentRuntimeOpenAITests.swift — ToolLoopRunner integration tests for OpenAI provider.
// Uses scripted stream factories and a mock MCPClient — no network required.

import XCTest
@testable import Zion

// MARK: - Helpers (local to this file)

private final class OpenAIMockMCPClient: @unchecked Sendable, MCPClientProtocol {
    var callCount = 0
    var fixedResult: [String: Any] = ["output": "tool output"]

    func callTool(_ name: String, args: [String: Any]) async throws -> [String: Any] {
        callCount += 1
        return fixedResult
    }
    func listTools() async throws -> [MCPToolDescriptor] { return [] }
}

private func openAIStream(_ lines: [String]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        for line in lines { continuation.yield(line) }
        continuation.finish()
    }
}

/// Actor-based counter for Swift 6 Sendable closure safety.
private actor OpenAICallCounter {
    private(set) var value: Int = 0
    func increment() -> Int {
        let current = value
        value += 1
        return current
    }
}

// MARK: - Tests

final class AgentRuntimeOpenAITests: XCTestCase {

    // Two-round test: round 1 = tool_calls finish_reason → round 2 = stop finish_reason.
    @MainActor
    func test_openai_two_rounds_then_stop() async throws {
        let mockMCP = OpenAIMockMCPClient()
        let counter = OpenAICallCounter()

        // Round 1: model emits tool_calls
        let round1Lines = [
            #"{"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc","function":{"name":"list_dir","arguments":"{\"path\":\".\"}"},"type":"function"}]},"finish_reason":null}]}"#,
            #"{"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#
        ]

        // Round 2: model emits text + stop
        let round2Lines = [
            #"{"id":"chatcmpl-2","object":"chat.completion.chunk","choices":[{"delta":{"content":"Found 3 items."},"finish_reason":null}]}"#,
            #"{"id":"chatcmpl-2","object":"chat.completion.chunk","choices":[{"delta":{},"finish_reason":"stop"}]}"#
        ]

        let streamFactory: StreamFactory = { _, _, _, _ in
            let index = await counter.increment()
            return index == 0 ? openAIStream(round1Lines) : openAIStream(round2Lines)
        }

        let runner = ToolLoopRunner(streamFactory: streamFactory, mcpClient: mockMCP)
        let cancel = CancellationToken()
        var steps: [AgentStepEvent] = []

        let result = try await runner.run(
            provider: .openai,
            model: "gpt-4o",
            conversation: [["role": "user", "content": "list directory"]],
            tools: [MCPToolDescriptor(name: "list_dir", description: "List directory", inputSchema: [:])],
            maxSteps: 10,
            budgetCap: 0,
            cancel: cancel,
            onStep: { event in steps.append(event) }
        )

        XCTAssertEqual(result.stopReason, .endTurn,
                       "OpenAI 'stop' finish_reason should map to .endTurn")
        XCTAssertGreaterThanOrEqual(result.stepsUsed, 2, "Must complete at least 2 steps")
        XCTAssertFalse(result.cancelled)
        XCTAssertGreaterThanOrEqual(steps.count, 2)
    }

    @MainActor
    func test_openai_single_round_stop() async throws {
        let mockMCP = OpenAIMockMCPClient()

        let lines = [
            #"{"id":"chatcmpl-x","object":"chat.completion.chunk","choices":[{"delta":{"content":"Direct answer."},"finish_reason":null}]}"#,
            #"{"id":"chatcmpl-x","object":"chat.completion.chunk","choices":[{"delta":{},"finish_reason":"stop"}]}"#
        ]

        let streamFactory: StreamFactory = { _, _, _, _ in openAIStream(lines) }
        let runner = ToolLoopRunner(streamFactory: streamFactory, mcpClient: mockMCP)
        let cancel = CancellationToken()

        let result = try await runner.run(
            provider: .openai,
            model: "gpt-4o-mini",
            conversation: [["role": "user", "content": "what is 2+2"]],
            tools: [],
            maxSteps: 5,
            budgetCap: 0,
            cancel: cancel,
            onStep: { _ in }
        )

        XCTAssertEqual(result.stopReason, .endTurn)
        XCTAssertEqual(result.stepsUsed, 1)
        XCTAssertEqual(result.finalText, "Direct answer.")
    }

    @MainActor
    func test_openai_cancellation_before_start() async throws {
        let mockMCP = OpenAIMockMCPClient()
        let lines = [
            #"{"id":"chatcmpl-y","object":"chat.completion.chunk","choices":[{"delta":{},"finish_reason":"stop"}]}"#
        ]
        let streamFactory: StreamFactory = { _, _, _, _ in openAIStream(lines) }
        let runner = ToolLoopRunner(streamFactory: streamFactory, mcpClient: mockMCP)

        let cancel = CancellationToken()
        await cancel.cancel()  // cancel before run

        let result = try await runner.run(
            provider: .openai,
            model: nil,
            conversation: [["role": "user", "content": "hi"]],
            tools: [],
            maxSteps: 5,
            budgetCap: 0,
            cancel: cancel,
            onStep: { _ in }
        )

        XCTAssertEqual(result.stopReason, .cancelled)
        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.stepsUsed, 0)
    }
}
