// AgentRuntimeAnthropicTests.swift — ToolLoopRunner integration tests for Anthropic provider.
// Uses scripted stream factories and a mock MCPClient — no network required.

import XCTest
@testable import Zion

// MARK: - Helpers

private final class AnthropicMockMCPClient: @unchecked Sendable, MCPClientProtocol {
    var callCount = 0
    var fixedResult: [String: Any] = ["content": "mock result"]

    func callTool(_ name: String, args: [String: Any]) async throws -> [String: Any] {
        callCount += 1
        return fixedResult
    }
    func listTools() async throws -> [MCPToolDescriptor] { return [] }
}

/// Build a scripted AsyncThrowingStream that yields lines then finishes.
private func scriptedStream(_ lines: [String]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        for line in lines { continuation.yield(line) }
        continuation.finish()
    }
}

/// Actor-based counter for Swift 6 Sendable closure safety.
private actor CallCounter {
    private(set) var value: Int = 0
    func increment() -> Int {
        let current = value
        value += 1
        return current
    }
}

// MARK: - Tests

final class AgentRuntimeAnthropicTests: XCTestCase {

    // Two-round test: round 1 = tool_use → round 2 = end_turn.
    // The stream factory alternates between two scripted responses based on call count.
    @MainActor
    func test_anthropic_two_rounds_then_endTurn() async throws {
        let mockMCP = AnthropicMockMCPClient()
        let counter = CallCounter()

        // Round 1: model asks to use a tool
        let round1Lines = [
            // content_block_start with tool_use block
            #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"list_dir","input":{}}}"#,
            // message_delta with stop_reason=tool_use
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null}}"#,
            // message_stop
            #"{"type":"message_stop"}"#
        ]

        // Round 2: model replies with text + end_turn
        let round2Lines = [
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"5 files found"}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null}}"#,
            #"{"type":"message_stop"}"#
        ]

        let streamFactory: StreamFactory = { _, _, _, _ in
            let index = await counter.increment()
            if index == 0 {
                return scriptedStream(round1Lines)
            } else {
                return scriptedStream(round2Lines)
            }
        }

        let runner = ToolLoopRunner(streamFactory: streamFactory, mcpClient: mockMCP)
        let cancel = CancellationToken()
        // stepEvents collected on MainActor-isolated array via nonisolated closure capture trick
        var stepEvents: [AgentStepEvent] = []

        let result = try await runner.run(
            provider: .anthropic,
            model: "claude-3-5-sonnet-20241022",
            conversation: [["role": "user", "content": "list files"]],
            tools: [MCPToolDescriptor(name: "list_dir", description: "List directory", inputSchema: [:])],
            maxSteps: 10,
            budgetCap: 0,
            cancel: cancel,
            onStep: { event in stepEvents.append(event) }
        )

        XCTAssertEqual(result.stopReason, .endTurn, "Should end with .endTurn after second round")
        XCTAssertGreaterThanOrEqual(result.stepsUsed, 2, "Must have at least 2 steps (tool round + final)")
        XCTAssertFalse(result.cancelled)
        XCTAssertGreaterThanOrEqual(stepEvents.count, 2)
    }

    @MainActor
    func test_anthropic_endTurn_first_round() async throws {
        let mockMCP = AnthropicMockMCPClient()

        let lines = [
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello, world!"}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null}}"#,
            #"{"type":"message_stop"}"#
        ]

        let streamFactory: StreamFactory = { _, _, _, _ in
            return scriptedStream(lines)
        }

        let runner = ToolLoopRunner(streamFactory: streamFactory, mcpClient: mockMCP)
        let cancel = CancellationToken()

        let result = try await runner.run(
            provider: .anthropic,
            model: nil,
            conversation: [["role": "user", "content": "hi"]],
            tools: [],
            maxSteps: 10,
            budgetCap: 0,
            cancel: cancel,
            onStep: { _ in }
        )

        XCTAssertEqual(result.stopReason, .endTurn)
        XCTAssertEqual(result.stepsUsed, 1)
        XCTAssertEqual(result.finalText, "Hello, world!")
    }

    @MainActor
    func test_anthropic_capability_rejected_for_passthrough() async throws {
        let mockMCP = AnthropicMockMCPClient()
        let streamFactory: StreamFactory = { _, _, _, _ in scriptedStream([]) }
        let runner = ToolLoopRunner(streamFactory: streamFactory, mcpClient: mockMCP)
        let cancel = CancellationToken()

        do {
            _ = try await runner.run(
                provider: .claudeCLI,  // passthrough — should be rejected
                model: nil,
                conversation: [],
                tools: [],
                maxSteps: 5,
                budgetCap: 0,
                cancel: cancel,
                onStep: { _ in }
            )
            XCTFail("Expected LoopError.wrongCapability to be thrown")
        } catch let err as LoopError {
            if case .wrongCapability = err {
                // expected
            } else {
                XCTFail("Expected .wrongCapability, got \(err)")
            }
        }
    }
}
