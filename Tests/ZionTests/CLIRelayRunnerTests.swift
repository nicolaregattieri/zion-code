// CLIRelayRunnerTests.swift — Unit tests for CLIRelayRunner (T7, Phase 11).
//
// Tests inject a scripted CLIStreamFactory instead of spawning a real CLI binary.
// Five test cases cover: tool events, cost, cancel, non-zero exit, text accumulation.
//
// Note: CLIRelayRunner is an actor; all `await runner.run(...)` calls are safe from async test context.

import XCTest
@testable import Zion

// MARK: - Helpers

/// Thread-safe collector for AgentStepEvents, usable in @Sendable closures (NSLock-backed).
private final class StepCollector: @unchecked Sendable {
    private var _steps: [AgentStepEvent] = []
    private let lock = NSLock()

    func append(_ step: AgentStepEvent) {
        lock.withLock { _steps.append(step) }
    }

    var steps: [AgentStepEvent] {
        lock.withLock { _steps }
    }
}

/// Builds a CLIStreamFactory that yields a scripted sequence of CLIStreamEvents, then finishes.
private func mockFactory(events: [CLIStreamEvent]) -> CLIStreamFactory {
    return { _, _ in
        AsyncThrowingStream<CLIStreamEvent, Error> { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

/// Builds a CLIStreamFactory that throws an AIError.cliError on finish (simulates non-zero exit).
private func mockFailingFactory(stderr: String, exitCode: Int32 = 1) -> CLIStreamFactory {
    return { _, _ in
        AsyncThrowingStream<CLIStreamEvent, Error> { continuation in
            continuation.finish(throwing: AIError.cliError(stderr: stderr, exitCode: exitCode))
        }
    }
}

/// Builds a CLIStreamFactory that emits events from an actor-controlled bridge,
/// allowing mid-stream cancellation from outside.
private actor StreamBridge {
    private var continuation: AsyncThrowingStream<CLIStreamEvent, Error>.Continuation?

    func stream() -> AsyncThrowingStream<CLIStreamEvent, Error> {
        AsyncThrowingStream { cont in
            self.continuation = cont
        }
    }

    func yield(_ event: CLIStreamEvent) {
        continuation?.yield(event)
    }

    func finish() {
        continuation?.finish()
    }
}

// MARK: - CLIRelayRunnerTests

final class CLIRelayRunnerTests: XCTestCase {

    // MARK: 1. Tool events surface on onStep callback

    func testToolEventSurfacesOnStep() async throws {
        let toolUseEvents: [CLIStreamEvent] = [
            .toolStart(id: "tool-1", name: "Bash", description: "ls -la"),
            .done
        ]

        let runner = CLIRelayRunner(cliStreamFactory: mockFactory(events: toolUseEvents))
        let cancel = CancellationToken()

        let collector = StepCollector()
        let result = try await runner.run(
            provider: .claudeCLI,
            model: nil,
            userPrompt: "list files",
            maxSteps: 25,
            cancel: cancel,
            onStep: { step in
                collector.append(step)
            }
        )

        let receivedSteps = collector.steps
        XCTAssertFalse(receivedSteps.isEmpty, "Expected at least one step event")
        XCTAssertEqual(receivedSteps.first?.toolEvent.name, "Bash")
        XCTAssertEqual(receivedSteps.first?.toolEvent.argsPreview, "ls -la")
        XCTAssertEqual(result.stopReason, .endTurn)
        XCTAssertFalse(result.cancelled)
    }

    // MARK: 2. Final turnCost event sets cumulativeCostUSD

    func testFinalResultEventSetsCost() async throws {
        let events: [CLIStreamEvent] = [
            .textDelta("Hello!"),
            .turnCost(usd: 0.024),
            .done
        ]

        let runner = CLIRelayRunner(cliStreamFactory: mockFactory(events: events))
        let cancel = CancellationToken()

        let result = try await runner.run(
            provider: .claudeCLI,
            model: nil,
            userPrompt: "say hello",
            maxSteps: 25,
            cancel: cancel,
            onStep: { _ in }
        )

        XCTAssertEqual(result.cumulativeCostUSD, 0.024, accuracy: 0.0001)
        XCTAssertEqual(result.finalText, "Hello!")
        XCTAssertEqual(result.stopReason, .endTurn)
    }

    // MARK: 3. Cancel before CLI completes resolves as .cancelled

    func testCancelBeforeCLICompletes() async throws {
        let bridge = StreamBridge()

        let factory: CLIStreamFactory = { _, _ in
            await bridge.stream()
        }

        let runner = CLIRelayRunner(cliStreamFactory: factory)
        let cancel = CancellationToken()

        // Yield one event to confirm the stream started, then cancel before done.
        let runTask = Task {
            try await runner.run(
                provider: .claudeCLI,
                model: nil,
                userPrompt: "long task",
                maxSteps: 25,
                cancel: cancel,
                onStep: { _ in }
            )
        }

        // Yield first event, then cancel.
        await bridge.yield(.textDelta("partial..."))
        await cancel.cancel()

        // Let the runner see the cancellation: yield a second event to pump the loop.
        await bridge.yield(.textDelta("more text"))

        let result = try await runTask.value

        XCTAssertTrue(result.cancelled, "Expected result.cancelled == true after token cancel")
        XCTAssertEqual(result.stopReason, .cancelled)
    }

    // MARK: 4. Non-zero exit becomes providerError

    func testNonZeroExitBecomesProviderError() async throws {
        let stderrMsg = "claude: authentication required"
        let runner = CLIRelayRunner(cliStreamFactory: mockFailingFactory(stderr: stderrMsg, exitCode: 1))
        let cancel = CancellationToken()

        let result = try await runner.run(
            provider: .claudeCLI,
            model: nil,
            userPrompt: "hello",
            maxSteps: 25,
            cancel: cancel,
            onStep: { _ in }
        )

        if case .providerError(let msg) = result.stopReason {
            XCTAssertTrue(msg.contains("authentication"), "Expected stderr in providerError, got: \(msg)")
        } else {
            XCTFail("Expected .providerError, got \(result.stopReason)")
        }
        XCTAssertFalse(result.cancelled)
    }

    // MARK: 5. Text accumulation: multiple textDelta events concatenate in order

    func testTextAccumulation() async throws {
        let events: [CLIStreamEvent] = [
            .textDelta("Hello"),
            .textDelta(", "),
            .textDelta("world"),
            .textDelta("!"),
            .done
        ]

        let runner = CLIRelayRunner(cliStreamFactory: mockFactory(events: events))
        let cancel = CancellationToken()

        let result = try await runner.run(
            provider: .codexCLI,
            model: nil,
            userPrompt: "greet",
            maxSteps: 25,
            cancel: cancel,
            onStep: { _ in }
        )

        XCTAssertEqual(result.finalText, "Hello, world!")
        XCTAssertEqual(result.stopReason, .endTurn)
    }
}
