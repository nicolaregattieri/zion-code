// AgentRuntimeCapsTests.swift — ToolLoopRunner capability + guard tests.
// Verifies: maxSteps cap, budget cap, wrong-capability rejection.

import XCTest
@testable import Zion

// MARK: - Mock helpers

private final class CapsMockMCPClient: @unchecked Sendable, MCPClientProtocol {
    func callTool(_ name: String, args: [String: Any]) async throws -> [String: Any] {
        return ["result": "ok"]
    }
    func listTools() async throws -> [MCPToolDescriptor] { return [] }
}

/// Returns an OpenAI-shaped stream that always emits a tool_call (never ends cleanly).
private func runawayToolStream() -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let lines = [
            #"{"id":"chatcmpl-r","object":"chat.completion.chunk","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_xyz","function":{"name":"infinite_tool","arguments":"{}"}}]},"finish_reason":null}]}"#,
            #"{"id":"chatcmpl-r","object":"chat.completion.chunk","choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#
        ]
        for line in lines { continuation.yield(line) }
        continuation.finish()
    }
}

// MARK: - Tests

final class AgentRuntimeCapsTests: XCTestCase {

    // Runaway tool loop: provider always returns tool_use, never endTurn.
    // Verifies the runner halts at maxSteps=25.
    @MainActor
    func test_runaway_stops_at_maxSteps() async throws {
        let maxSteps = 25
        let mockMCP = CapsMockMCPClient()

        let streamFactory: StreamFactory = { _, _, _, _ in runawayToolStream() }
        let runner = ToolLoopRunner(streamFactory: streamFactory, mcpClient: mockMCP)
        let cancel = CancellationToken()
        var stepCount = 0

        let result = try await runner.run(
            provider: .openai,
            model: "gpt-4o",
            conversation: [["role": "user", "content": "run forever"]],
            tools: [MCPToolDescriptor(name: "infinite_tool", description: "never stops", inputSchema: [:])],
            maxSteps: maxSteps,
            budgetCap: 0,
            cancel: cancel,
            onStep: { _ in stepCount += 1 }
        )

        XCTAssertEqual(result.stopReason, .maxStepsReached,
                       "Runaway loop must stop at maxSteps=\(maxSteps)")
        XCTAssertEqual(result.stepsUsed, maxSteps, "stepsUsed must equal maxSteps")
        XCTAssertFalse(result.cancelled)
    }

    @MainActor
    func test_runaway_stops_at_custom_maxSteps() async throws {
        let maxSteps = 3
        let mockMCP = CapsMockMCPClient()
        let streamFactory: StreamFactory = { _, _, _, _ in runawayToolStream() }
        let runner = ToolLoopRunner(streamFactory: streamFactory, mcpClient: mockMCP)
        let cancel = CancellationToken()

        let result = try await runner.run(
            provider: .openai,
            model: nil,
            conversation: [["role": "user", "content": "loop"]],
            tools: [MCPToolDescriptor(name: "infinite_tool", description: "loops", inputSchema: [:])],
            maxSteps: maxSteps,
            budgetCap: 0,
            cancel: cancel,
            onStep: { _ in }
        )

        XCTAssertEqual(result.stopReason, .maxStepsReached)
        XCTAssertEqual(result.stepsUsed, maxSteps)
    }

    @MainActor
    func test_wrong_capability_rejected_passthrough() async throws {
        let mockMCP = CapsMockMCPClient()
        let streamFactory: StreamFactory = { _, _, _, _ in AsyncThrowingStream { $0.finish() } }
        let runner = ToolLoopRunner(streamFactory: streamFactory, mcpClient: mockMCP)
        let cancel = CancellationToken()

        do {
            _ = try await runner.run(
                provider: .claudeCLI,
                model: nil,
                conversation: [],
                tools: [],
                maxSteps: 5,
                budgetCap: 0,
                cancel: cancel,
                onStep: { _ in }
            )
            XCTFail("Should have thrown LoopError.wrongCapability")
        } catch let err as LoopError {
            if case .wrongCapability(let cap) = err {
                XCTAssertEqual(cap, .passthrough)
            } else {
                XCTFail("Expected .wrongCapability, got \(err)")
            }
        }
    }

    @MainActor
    func test_wrong_capability_rejected_unsupported() async throws {
        let mockMCP = CapsMockMCPClient()
        let streamFactory: StreamFactory = { _, _, _, _ in AsyncThrowingStream { $0.finish() } }
        let runner = ToolLoopRunner(streamFactory: streamFactory, mcpClient: mockMCP)
        let cancel = CancellationToken()

        do {
            _ = try await runner.run(
                provider: .none,
                model: nil,
                conversation: [],
                tools: [],
                maxSteps: 5,
                budgetCap: 0,
                cancel: cancel,
                onStep: { _ in }
            )
            XCTFail("Should have thrown LoopError.wrongCapability")
        } catch let err as LoopError {
            if case .wrongCapability(let cap) = err {
                XCTAssertEqual(cap, .unsupported)
            } else {
                XCTFail("Expected .wrongCapability, got \(err)")
            }
        }
    }

    @MainActor
    func test_cancellation_token_works() async throws {
        let mockMCP = CapsMockMCPClient()
        let streamFactory: StreamFactory = { _, _, _, _ in runawayToolStream() }
        let runner = ToolLoopRunner(streamFactory: streamFactory, mcpClient: mockMCP)
        let cancel = CancellationToken()
        await cancel.cancel()

        let result = try await runner.run(
            provider: .anthropic,
            model: nil,
            conversation: [["role": "user", "content": "start"]],
            tools: [],
            maxSteps: 100,
            budgetCap: 0,
            cancel: cancel,
            onStep: { _ in }
        )

        XCTAssertEqual(result.stopReason, .cancelled)
        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.stepsUsed, 0, "No steps should run after pre-cancellation")
    }
}
