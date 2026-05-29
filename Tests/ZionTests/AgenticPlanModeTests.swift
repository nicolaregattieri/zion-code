// AgenticPlanModeTests.swift — Plan mode gate + AgentRuntime two-phase flow tests.
//
// Tests:
//   1. PlanModeGate: beforeFirstStep enforces readOnly
//   2. PlanModeGate: approve transitions correctly
//   3. PlanModeGate: reject returns nil
//   4. AgentRuntime: planFirst emits planProposed + resumes with approved tier
//   5. AgentRuntime: planFirst rejection cancels loop

import XCTest
@testable import Zion

// MARK: - Mock ToolLoopRunner

/// Configurable mock: returns a single-step LoopResult with preset finalText.
private final class PlanMockToolLoopRunner: ToolLoopRunnerProtocol, @unchecked Sendable {

    /// Tier captured at last call time (via TaskLocal AgentApprovalTier.current).
    var capturedTier: AgentApprovalTier = .readOnly
    /// Call counter.
    var callCount: Int = 0
    /// Text to return as finalText.
    var responseText: String

    init(responseText: String = "Here is my plan.") {
        self.responseText = responseText
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
        callCount += 1
        capturedTier = AgentApprovalTier.current
        // Emit one synthetic step
        let event = AgentStepEvent(
            toolEvent: ChatToolEvent(
                id: "mock-step-\(callCount)",
                name: "mock_tool",
                status: .completed,
                argsPreview: "args"
            ),
            stepIndex: callCount - 1
        )
        await onStep(event)
        return LoopResult(
            finalText: responseText,
            stepsUsed: 1,
            stopReason: .endTurn,
            cumulativeTokens: 10,
            cumulativeCostUSD: 0.001,
            cancelled: false,
            conversation: conversation + [["role": "assistant", "content": responseText]]
        )
    }
}

// MARK: - EventCollector

/// Thread-safe collector for AgentStepEvent emitted via onStep callbacks during tests.
private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentStepEvent] = []

    func append(_ event: AgentStepEvent) {
        lock.lock(); defer { lock.unlock() }
        items.append(event)
    }

    func contains(where predicate: (AgentStepEvent) -> Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return items.contains(where: predicate)
    }

    func filter(_ predicate: (AgentStepEvent) -> Bool) -> [AgentStepEvent] {
        lock.lock(); defer { lock.unlock() }
        return items.filter(predicate)
    }
}

// MARK: - Tests

@MainActor
final class AgenticPlanModeTests: XCTestCase {

    // MARK: - Helpers

    private func setPlanMode(_ state: PlanModeState) {
        PlanModeState.set(state)
    }

    override func tearDown() {
        super.tearDown()
        // Reset to autoApply so other tests are unaffected
        PlanModeState.set(.autoApply)
        UserDefaults.standard.removeObject(forKey: "chat.plan.mode")
    }

    // MARK: - Test 1: beforeFirstStep enforces readOnly

    func test_gate_beforeFirstStep_enforcesReadOnly() {
        let gate = PlanModeGate(initialState: .planFirst)
        let effective = Task {
            await gate.effectiveTier(userTier: .fullAccess)
        }
        let expectation = expectation(description: "gate tier")
        Task {
            let tier = await effective.value
            XCTAssertEqual(tier, .readOnly)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    // MARK: - Test 2: approve transitions correctly

    func test_gate_approve_resumesTier() async throws {
        let gate = PlanModeGate(initialState: .planFirst)

        // Start waiting in a background task
        let waitTask = Task {
            await gate.waitForApprovalIfNeeded(currentStep: 1)
        }

        // Give the task time to enter the continuation
        try await Task.sleep(nanoseconds: 50_000_000)

        // Approve
        await gate.approve(withTier: .workspaceWrite)

        let result = await waitTask.value
        XCTAssertEqual(result, .workspaceWrite)

        let status = await gate.status
        if case .resumedWithTier(let tier) = status {
            XCTAssertEqual(tier, .workspaceWrite)
        } else {
            XCTFail("Expected .resumedWithTier, got \(status)")
        }
    }

    // MARK: - Test 3: reject returns nil

    func test_gate_reject_returnsNil() async throws {
        let gate = PlanModeGate(initialState: .planFirst)

        let waitTask = Task {
            await gate.waitForApprovalIfNeeded(currentStep: 1)
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        await gate.reject()

        let result = await waitTask.value
        XCTAssertNil(result)

        let status = await gate.status
        XCTAssertEqual(status, .rejected)
    }

    // MARK: - Test 4: planFirst path runs two phases, emits planProposed, resumes with approved tier

    func test_runtime_planFirst_twoPhases() async throws {
        setPlanMode(.planFirst)

        let mockRunner = PlanMockToolLoopRunner(responseText: "Step 1 plan.")
        let runtime = AgentRuntime(
            toolLoopRunner: mockRunner,
            reactRunner: NullReActRunner(),
            cliRunner: NullCLIRunner()
        )

        let events = EventCollector()

        let runTask = Task { @MainActor in
            try await runtime.run(
                provider: .anthropic,
                model: "claude-opus-4-5",
                conversation: [["role": "user", "content": "plan something"]],
                userPrompt: "plan something",
                tools: [],
                maxSteps: 5,
                onStep: { event in
                    events.append(event)
                }
            )
        }

        // Wait for runtime to enter awaitingPlanApproval
        let deadline = Date().addingTimeInterval(3)
        while !runtime.awaitingPlanApproval && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let awaiting1 = runtime.awaitingPlanApproval
        XCTAssertTrue(awaiting1, "Should be awaiting approval")

        // Approve with workspaceWrite tier
        await runtime.approvePlan(withTier: .workspaceWrite)

        let result = try await runTask.value

        // Phase 1 used readOnly, phase 2 used workspaceWrite
        XCTAssertEqual(mockRunner.callCount, 2, "Runner should have been called twice (phase1 + phase2)")
        XCTAssertEqual(result.stopReason, .endTurn)
        XCTAssertFalse(result.cancelled)

        // planProposed event should have been emitted
        let deadline2 = Date().addingTimeInterval(1)
        while events.filter({ $0.kind == .planProposed }).isEmpty && Date() < deadline2 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(events.contains(where: { $0.kind == .planProposed }), "planProposed event must be emitted")
    }

    // MARK: - Test 5: planFirst rejection cancels loop

    func test_runtime_planFirst_rejection_cancels() async throws {
        setPlanMode(.planFirst)

        let mockRunner = PlanMockToolLoopRunner(responseText: "Step 1 plan.")
        let runtime = AgentRuntime(
            toolLoopRunner: mockRunner,
            reactRunner: NullReActRunner(),
            cliRunner: NullCLIRunner()
        )

        let runTask = Task { @MainActor in
            try await runtime.run(
                provider: .anthropic,
                model: "claude-opus-4-5",
                conversation: [["role": "user", "content": "plan something"]],
                userPrompt: "plan something",
                tools: [],
                maxSteps: 5,
                onStep: { _ in }
            )
        }

        // Wait for awaitingPlanApproval
        let deadline = Date().addingTimeInterval(3)
        while !runtime.awaitingPlanApproval && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let awaiting2 = runtime.awaitingPlanApproval
        XCTAssertTrue(awaiting2, "Should be awaiting approval before rejection")

        // Reject
        await runtime.rejectPlan()

        let result = try await runTask.value
        XCTAssertEqual(result.stopReason, .cancelled)
        XCTAssertTrue(result.cancelled)
        // Phase 2 must NOT have run — runner called only once
        XCTAssertEqual(mockRunner.callCount, 1, "Phase 2 must not run after rejection")
    }
}
