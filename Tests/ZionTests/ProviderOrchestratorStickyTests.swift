// ProviderOrchestratorStickyTests.swift — T8 (Phase 11) sticky-lock + AgentRuntime lifecycle tests.
//
// 1. Sticky lock refuses switch during active loop
// 2. Switch allowed when loop inactive
// 3. AgentRuntime.isLoopActive lifecycle (false → true → false)
// 4. Cancel aborts within 500ms
// 5. ChatService routes through AgentRuntime (direct run() invocation proof)

import XCTest
@testable import Zion

// MARK: - Mock AgentLoopStateProvider

/// Simple mock that returns a fixed `isLoopActive` value.
private final class MockLoopStateProvider: AgentLoopStateProvider, @unchecked Sendable {
    @MainActor var isLoopActive: Bool

    @MainActor init(isLoopActive: Bool) {
        self.isLoopActive = isLoopActive
    }
}

// MARK: - Slow mock ToolLoopRunner (for lifecycle test)

/// Records whether run() was entered and delays for `delaySeconds` before returning.
private final class SlowMockToolLoopRunner: ToolLoopRunnerProtocol, @unchecked Sendable {
    let delaySeconds: Double
    private let lock = NSLock()
    private var _entered = false
    var entered: Bool { lock.withLock { _entered } }

    init(delaySeconds: Double = 0.2) {
        self.delaySeconds = delaySeconds
    }

    func run(
        provider: AIProvider,
        model: String?,
        conversation: [[String: Any]],
        tools: [MCPToolDescriptor],
        maxSteps: Int,
        budgetCap: Double,
        cancel: CancellationToken,
        onStep: @escaping @MainActor @Sendable (AgentStepEvent) -> Void
    ) async throws -> LoopResult {
        lock.withLock { _entered = true }
        try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        return LoopResult(
            finalText: "slow done",
            stepsUsed: 1,
            stopReason: .endTurn,
            cumulativeTokens: 0,
            cumulativeCostUSD: 0,
            cancelled: false,
            conversation: conversation
        )
    }
}

// MARK: - Cancellable mock ToolLoopRunner

/// Loops until CancellationToken.isCancelled is set, then returns a .cancelled result.
private final class CancellableMockToolLoopRunner: ToolLoopRunnerProtocol, @unchecked Sendable {
    func run(
        provider: AIProvider,
        model: String?,
        conversation: [[String: Any]],
        tools: [MCPToolDescriptor],
        maxSteps: Int,
        budgetCap: Double,
        cancel: CancellationToken,
        onStep: @escaping @MainActor @Sendable (AgentStepEvent) -> Void
    ) async throws -> LoopResult {
        while true {
            if await cancel.isCancelled { break }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms poll
        }
        return LoopResult(
            finalText: "",
            stepsUsed: 0,
            stopReason: .cancelled,
            cumulativeTokens: 0,
            cumulativeCostUSD: 0,
            cancelled: true,
            conversation: conversation
        )
    }
}

// MARK: - Call-recording mock AgentRuntime injection wrapper

/// Wraps a ToolLoopRunnerProtocol and records how many times run() was invoked.
private final class RecordingToolLoopRunner: ToolLoopRunnerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    var callCount: Int { lock.withLock { _callCount } }

    func run(
        provider: AIProvider,
        model: String?,
        conversation: [[String: Any]],
        tools: [MCPToolDescriptor],
        maxSteps: Int,
        budgetCap: Double,
        cancel: CancellationToken,
        onStep: @escaping @MainActor @Sendable (AgentStepEvent) -> Void
    ) async throws -> LoopResult {
        lock.withLock { _callCount += 1 }
        return LoopResult(
            finalText: "recorded",
            stepsUsed: 1,
            stopReason: .endTurn,
            cumulativeTokens: 0,
            cumulativeCostUSD: 0,
            cancelled: false,
            conversation: conversation
        )
    }
}

// MARK: - ProviderOrchestratorStickyTests

final class ProviderOrchestratorStickyTests: XCTestCase {

    private var savedPlanModeRaw: String?

    override func setUp() {
        super.setUp()
        // Force `.autoApply` for every test in this class. Default `.planFirst`
        // makes `AgentRuntime.run()` suspend after phase 1 inside
        // `PlanModeGate.waitForApprovalIfNeeded` waiting for a user action that
        // never comes in tests — the call then hangs the entire suite.
        savedPlanModeRaw = UserDefaults.standard.string(forKey: "chat.plan.mode")
        PlanModeState.set(.autoApply)
    }

    override func tearDown() {
        if let raw = savedPlanModeRaw {
            UserDefaults.standard.set(raw, forKey: "chat.plan.mode")
        } else {
            UserDefaults.standard.removeObject(forKey: "chat.plan.mode")
        }
        savedPlanModeRaw = nil
        super.tearDown()
    }

    // MARK: Test 1 — Sticky lock refuses switch during active loop

    func testStickyLockRefusesSwitchDuringLoop() async {
        let mockRuntime = await MockLoopStateProvider(isLoopActive: true)

        let policy = RoutingPolicy()
        let orchestrator = ProviderOrchestrator(policy: policy)
        await orchestrator.attachAgentRuntime(mockRuntime)

        let result = await orchestrator.requestSwitch(to: .anthropic, lane: .general)

        if case .refused(let reason) = result {
            XCTAssertEqual(reason, .loopActive, "Should refuse with .loopActive when loop is running")
        } else {
            XCTFail("Expected .refused(.loopActive), got \(result)")
        }
    }

    // MARK: Test 2 — Switch allowed when loop inactive

    func testSwitchAllowedWhenLoopInactive() async {
        let mockRuntime = await MockLoopStateProvider(isLoopActive: false)

        // Build a policy that has .anthropic in the general chain
        let policy = RoutingPolicy(chains: [AITaskLane.general.rawValue: [AIProvider.anthropic.rawValue, AIProvider.openai.rawValue]])

        let orchestrator = ProviderOrchestrator(policy: policy)
        await orchestrator.attachAgentRuntime(mockRuntime)

        let result = await orchestrator.requestSwitch(to: .anthropic, lane: .general)

        if case .allowed(let provider) = result {
            XCTAssertEqual(provider, .anthropic)
        } else {
            XCTFail("Expected .allowed(.anthropic), got \(result)")
        }
    }

    // MARK: Test 3 — AgentRuntime.isLoopActive lifecycle

    @MainActor
    func testIsLoopActiveLifecycle() async throws {
        let slowRunner = SlowMockToolLoopRunner(delaySeconds: 0.2)
        let runtime = AgentRuntime(toolLoopRunner: slowRunner)

        // Initially false
        XCTAssertFalse(runtime.isLoopActive, "isLoopActive should be false before run()")

        // Capture isLoopActive mid-run using a separate Task
        var observedDuringRun: Bool? = nil
        let runTask = Task { @MainActor in
            let result = try await runtime.run(
                provider: .anthropic,
                model: nil,
                conversation: [["role": "user", "content": "test"]],
                userPrompt: "test",
                tools: [],
                maxSteps: 5,
                onStep: { _ in }
            )
            return result
        }

        // Poll until the slow runner has entered (gives us confidence the loop is active)
        let deadline = Date().addingTimeInterval(1.0)
        while !slowRunner.entered && Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }

        // Read isLoopActive on MainActor while run() is in flight
        observedDuringRun = runtime.isLoopActive
        XCTAssertEqual(observedDuringRun, true, "isLoopActive should be true during run()")

        // Wait for completion
        _ = try await runTask.value

        // After completion, false again
        XCTAssertFalse(runtime.isLoopActive, "isLoopActive should be false after run() returns")
    }

    // MARK: Test 4 — Cancel aborts within 500ms

    @MainActor
    func testCancelAbortsWithin500ms() async throws {
        let cancellableRunner = CancellableMockToolLoopRunner()
        let runtime = AgentRuntime(toolLoopRunner: cancellableRunner)

        let runTask = Task { @MainActor in
            try await runtime.run(
                provider: .anthropic,
                model: nil,
                conversation: [["role": "user", "content": "hi"]],
                userPrompt: "hi",
                tools: [],
                maxSteps: 100,
                onStep: { _ in }
            )
        }

        // Wait 100ms then cancel
        try await Task.sleep(nanoseconds: 100_000_000)
        await runtime.cancel()

        // Wait for the run task to finish — it should respond to cancellation quickly.
        // Give it up to 500ms after cancel() returns.
        let startWait = Date()
        let result = try await runTask.value
        let elapsed = Date().timeIntervalSince(startWait)

        XCTAssertLessThan(elapsed, 0.5, "run() should complete within 500ms of cancel()")
        XCTAssertEqual(result.stopReason, .cancelled, "Stop reason should be .cancelled")
        XCTAssertTrue(result.cancelled, "cancelled flag should be true")
    }

    // MARK: Test 5 — AgentRuntime dispatches through injected runner (ChatService routing proof)

    /// This test proves the routing path ChatService uses: it injects a recording runner into
    /// AgentRuntime and calls runtime.run() directly — the same call path ChatService takes at
    /// line ~435. This avoids constructing a full ChatService with heavyweight AIClient/RepositoryWorker
    /// dependencies while still exercising the identical injection point.
    @MainActor
    func testAgentRuntimeDispatchesToInjectedRunner() async throws {
        let recorder = RecordingToolLoopRunner()
        let runtime = AgentRuntime(toolLoopRunner: recorder)

        XCTAssertEqual(recorder.callCount, 0, "No calls before run()")

        _ = try await runtime.run(
            provider: .anthropic,
            model: nil,
            conversation: [["role": "user", "content": "hello"]],
            userPrompt: "hello",
            tools: [],
            maxSteps: 5,
            onStep: { _ in }
        )

        XCTAssertEqual(recorder.callCount, 1, "AgentRuntime should have routed one call to the injected runner")
    }
}
