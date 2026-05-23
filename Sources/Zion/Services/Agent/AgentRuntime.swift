// AgentRuntime.swift — Top-level agentic kernel. Resolves AgenticCapability for a
// provider+model and dispatches to the appropriate runner:
//   .nativeToolUse   → ToolLoopRunner
//   .reactTextFallback → ReActTextRunner
//   .passthrough     → CLIRelayRunner
//   .unsupported     → throws AIError.noProviderAvailable
//
// Owns:
//   - isLoopActive flag (read by ProviderOrchestrator to enforce sticky lock)
//   - CancellationToken (fed by chat stop button)
//   - currentStepIndex (incremented per onStep callback)
//   - AgentStepEvent stream via onStep closure
//
// Concurrency: @Observable @MainActor final class — all mutations on MainActor,
// runners execute on background tasks but update state via Task { @MainActor in }.

import Foundation

// MARK: - Runner Protocols (for test injection)

/// Abstraction over ToolLoopRunner for injection.
protocol ToolLoopRunnerProtocol: Sendable {
    func run(
        provider: AIProvider,
        model: String?,
        conversation: [[String: Any]],
        tools: [MCPToolDescriptor],
        maxSteps: Int,
        budgetCap: Double,
        cancel: CancellationToken,
        onStep: @escaping @MainActor @Sendable (AgentStepEvent) -> Void
    ) async throws -> LoopResult
}

/// Abstraction over ReActTextRunner for injection.
protocol ReActRunnerProtocol: Sendable {
    func run(
        provider: AIProvider,
        model: String?,
        conversation: [[String: Any]],
        tools: [MCPToolDescriptor],
        maxSteps: Int,
        budgetCap: Double,
        cancel: CancellationToken,
        onStep: @escaping @MainActor @Sendable (AgentStepEvent) -> Void
    ) async throws -> LoopResult
}

/// Abstraction over CLIRelayRunner for injection.
protocol CLIRunnerProtocol: Sendable {
    func run(
        provider: AIProvider,
        model: String?,
        userPrompt: String,
        maxSteps: Int,
        cancel: CancellationToken,
        onStep: @escaping @Sendable (AgentStepEvent) -> Void
    ) async throws -> LoopResult
}

// MARK: - Conformances on real runners

extension ToolLoopRunner: ToolLoopRunnerProtocol {}
extension ReActTextRunner: ReActRunnerProtocol {}
extension CLIRelayRunner: CLIRunnerProtocol {}

// MARK: - Null runners (used by default AgentRuntime() init — throw noProviderAvailable)

/// Null ToolLoopRunner — always throws .noProviderAvailable. Used when no real runner is injected.
final class NullToolLoopRunner: ToolLoopRunnerProtocol, @unchecked Sendable {
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
        throw AIError.noProviderAvailable
    }
}

/// Null ReActTextRunner — always throws .noProviderAvailable.
final class NullReActRunner: ReActRunnerProtocol, @unchecked Sendable {
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
        throw AIError.noProviderAvailable
    }
}

/// Null CLIRelayRunner — always throws .noProviderAvailable.
final class NullCLIRunner: CLIRunnerProtocol, @unchecked Sendable {
    func run(
        provider: AIProvider,
        model: String?,
        userPrompt: String,
        maxSteps: Int,
        cancel: CancellationToken,
        onStep: @escaping @Sendable (AgentStepEvent) -> Void
    ) async throws -> LoopResult {
        throw AIError.noProviderAvailable
    }
}

// MARK: - AgentRuntime

@Observable
@MainActor
final class AgentRuntime {

    // MARK: - Observable State

    private(set) var isLoopActive: Bool = false
    private(set) var currentStepIndex: Int = 0
    private(set) var currentProviderResolved: AIProvider?
    private(set) var lastError: AIError?

    // MARK: - Plan Mode State

    /// True while the runtime is suspended waiting for the user to approve or reject the plan.
    private(set) var awaitingPlanApproval: Bool = false

    // MARK: - Private

    @ObservationIgnored private var cancelToken: CancellationToken?
    @ObservationIgnored private let toolLoopRunner: any ToolLoopRunnerProtocol
    @ObservationIgnored private let reactRunner: any ReActRunnerProtocol
    @ObservationIgnored private let cliRunner: any CLIRunnerProtocol
    @ObservationIgnored private var planModeGate: PlanModeGate?

    // MARK: - Init

    /// Convenience init with null runners. Use in tests by passing mock runners,
    /// or in production by using the designated init with real runners.
    init(
        toolLoopRunner: any ToolLoopRunnerProtocol = NullToolLoopRunner(),
        reactRunner: any ReActRunnerProtocol = NullReActRunner(),
        cliRunner: any CLIRunnerProtocol = NullCLIRunner()
    ) {
        self.toolLoopRunner = toolLoopRunner
        self.reactRunner = reactRunner
        self.cliRunner = cliRunner
    }

    // MARK: - Run

    /// Executes the agentic loop. Resolves the capability for `provider`+`model`,
    /// then dispatches to the appropriate runner. Fires `onStep` for each step.
    ///
    /// When `PlanModeState.current() == .planFirst` the loop runs phase 1 with
    /// `.readOnly` tools (max 1 step), then pauses with `awaitingPlanApproval = true`
    /// until the user calls `approvePlan(withTier:)` or `rejectPlan()`.
    ///
    /// - Throws: `AIError.loopAlreadyActive` if a loop is already running.
    ///           `AIError.noProviderAvailable` if the provider/model combination is unsupported.
    func run(
        provider: AIProvider,
        model: String?,
        conversation: sending [[String: Any]],
        userPrompt: String,
        tools: [MCPToolDescriptor],
        maxSteps: Int = 25,
        onStep: @escaping @Sendable (AgentStepEvent) -> Void
    ) async throws -> LoopResult {
        guard !isLoopActive else { throw AIError.loopAlreadyActive }

        // Activate
        isLoopActive = true
        currentStepIndex = 0
        currentProviderResolved = provider
        lastError = nil
        let token = CancellationToken()
        cancelToken = token

        // Set up plan mode gate
        let gate = PlanModeGate(initialState: PlanModeState.current())
        planModeGate = gate

        defer {
            isLoopActive = false
            awaitingPlanApproval = false
            cancelToken = nil
            planModeGate = nil
        }

        do {
            let gateStatus = await gate.status
            if gateStatus == .beforeFirstStep {
                // ── Phase 1: single step, readOnly ──────────────────────────────
                let phase1Result = try await AgentApprovalTier.$overrideTier.withValue(.readOnly) {
                    try await innerRun(
                        provider: provider,
                        model: model,
                        conversation: conversation,
                        userPrompt: userPrompt,
                        tools: tools,
                        maxSteps: 1,
                        cancel: token,
                        onStep: onStep
                    )
                }

                // Emit planProposed synthetic event so UI can render PlanCard
                let syntheticEvent = AgentStepEvent(
                    kind: .planProposed,
                    toolEvent: ChatToolEvent(
                        id: UUID().uuidString,
                        name: "plan_proposed",
                        status: .completed,
                        argsPreview: phase1Result.finalText.prefix(120).description
                    ),
                    stepIndex: phase1Result.stepsUsed,
                    cumulativeTokens: phase1Result.cumulativeTokens,
                    cumulativeCostUSD: phase1Result.cumulativeCostUSD
                )
                onStep(syntheticEvent)

                // Pause — wait for user approval/rejection
                awaitingPlanApproval = true
                let approvedTier = await gate.waitForApprovalIfNeeded(currentStep: 1)
                awaitingPlanApproval = false

                guard let tier = approvedTier else {
                    // Rejected — return phase 1 result marked as cancelled
                    return LoopResult(
                        finalText: phase1Result.finalText,
                        stepsUsed: phase1Result.stepsUsed,
                        stopReason: .cancelled,
                        cumulativeTokens: phase1Result.cumulativeTokens,
                        cumulativeCostUSD: phase1Result.cumulativeCostUSD,
                        cancelled: true,
                        conversation: phase1Result.conversation
                    )
                }

                // ── Phase 2: remaining steps, user's approved tier ──────────────
                let remainingSteps = max(1, maxSteps - phase1Result.stepsUsed)
                let phase2Result = try await AgentApprovalTier.$overrideTier.withValue(tier) {
                    try await innerRun(
                        provider: provider,
                        model: model,
                        conversation: phase1Result.conversation,
                        userPrompt: userPrompt,
                        tools: tools,
                        maxSteps: remainingSteps,
                        cancel: token,
                        onStep: onStep
                    )
                }

                return LoopResult(
                    finalText: phase2Result.finalText.isEmpty ? phase1Result.finalText : phase2Result.finalText,
                    stepsUsed: phase1Result.stepsUsed + phase2Result.stepsUsed,
                    stopReason: phase2Result.stopReason,
                    cumulativeTokens: phase1Result.cumulativeTokens + phase2Result.cumulativeTokens,
                    cumulativeCostUSD: phase1Result.cumulativeCostUSD + phase2Result.cumulativeCostUSD,
                    cancelled: phase2Result.cancelled,
                    conversation: phase2Result.conversation
                )
            } else {
                // ── Normal path (autoApply or non-planFirst) ────────────────────
                let userTier = AgentApprovalTier.current
                return try await AgentApprovalTier.$overrideTier.withValue(userTier) {
                    try await innerRun(
                        provider: provider,
                        model: model,
                        conversation: conversation,
                        userPrompt: userPrompt,
                        tools: tools,
                        maxSteps: maxSteps,
                        cancel: token,
                        onStep: onStep
                    )
                }
            }
        } catch {
            lastError = (error as? AIError) ?? AIError.apiError(String(describing: error))
            throw error
        }
    }

    // MARK: - Plan Approval / Rejection

    /// Approves the plan and resumes the loop with the given tier.
    func approvePlan(withTier tier: AgentApprovalTier) async {
        await planModeGate?.approve(withTier: tier)
        awaitingPlanApproval = false
    }

    /// Rejects the plan, cancelling the loop.
    func rejectPlan() async {
        await planModeGate?.reject()
        awaitingPlanApproval = false
    }

    // MARK: - Cancel

    /// Signals the active loop to abort. No-op when no loop is running.
    func cancel() async {
        await cancelToken?.cancel()
    }

    // MARK: - Inner Run (capability dispatch)

    /// Dispatches to the appropriate runner based on resolved AgenticCapability.
    private func innerRun(
        provider: AIProvider,
        model: String?,
        conversation: sending [[String: Any]],
        userPrompt: String,
        tools: [MCPToolDescriptor],
        maxSteps: Int,
        cancel: CancellationToken,
        onStep: @escaping @Sendable (AgentStepEvent) -> Void
    ) async throws -> LoopResult {
        let capability = AgenticCapability.resolve(provider: provider, modelName: model)
        let selfRef = self

        switch capability {
        case .nativeToolUse:
            return try await toolLoopRunner.run(
                provider: provider,
                model: model,
                conversation: conversation,
                tools: tools,
                maxSteps: maxSteps,
                budgetCap: 0,
                cancel: cancel,
                onStep: { @MainActor @Sendable event in
                    selfRef.currentStepIndex = event.stepIndex
                    onStep(event)
                }
            )

        case .reactTextFallback:
            return try await reactRunner.run(
                provider: provider,
                model: model,
                conversation: conversation,
                tools: tools,
                maxSteps: maxSteps,
                budgetCap: 0,
                cancel: cancel,
                onStep: { @MainActor @Sendable event in
                    selfRef.currentStepIndex = event.stepIndex
                    onStep(event)
                }
            )

        case .passthrough:
            return try await cliRunner.run(
                provider: provider,
                model: model,
                userPrompt: userPrompt,
                maxSteps: maxSteps,
                cancel: cancel,
                onStep: { @Sendable event in
                    Task { @MainActor in
                        selfRef.currentStepIndex = event.stepIndex
                    }
                    onStep(event)
                }
            )

        case .unsupported:
            throw AIError.noProviderAvailable
        }
    }
}
