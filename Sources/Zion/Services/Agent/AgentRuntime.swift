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

    // MARK: - Private

    @ObservationIgnored private var cancelToken: CancellationToken?
    @ObservationIgnored private let toolLoopRunner: any ToolLoopRunnerProtocol
    @ObservationIgnored private let reactRunner: any ReActRunnerProtocol
    @ObservationIgnored private let cliRunner: any CLIRunnerProtocol

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

        let capability = AgenticCapability.resolve(provider: provider, modelName: model)

        // Activate
        isLoopActive = true
        currentStepIndex = 0
        currentProviderResolved = provider
        lastError = nil
        let token = CancellationToken()
        cancelToken = token

        defer {
            isLoopActive = false
            cancelToken = nil
        }

        do {
            let result: LoopResult
            let selfRef = self // capture for step index updates
            switch capability {
            case .nativeToolUse:
                result = try await toolLoopRunner.run(
                    provider: provider,
                    model: model,
                    conversation: conversation,
                    tools: tools,
                    maxSteps: maxSteps,
                    budgetCap: 0,
                    cancel: token,
                    onStep: { @MainActor @Sendable event in
                        selfRef.currentStepIndex = event.stepIndex
                        onStep(event)
                    }
                )

            case .reactTextFallback:
                result = try await reactRunner.run(
                    provider: provider,
                    model: model,
                    conversation: conversation,
                    tools: tools,
                    maxSteps: maxSteps,
                    budgetCap: 0,
                    cancel: token,
                    onStep: { @MainActor @Sendable event in
                        selfRef.currentStepIndex = event.stepIndex
                        onStep(event)
                    }
                )

            case .passthrough:
                result = try await cliRunner.run(
                    provider: provider,
                    model: model,
                    userPrompt: userPrompt,
                    maxSteps: maxSteps,
                    cancel: token,
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
            return result
        } catch {
            lastError = (error as? AIError) ?? AIError.apiError(String(describing: error))
            throw error
        }
    }

    // MARK: - Cancel

    /// Signals the active loop to abort. No-op when no loop is running.
    func cancel() async {
        await cancelToken?.cancel()
    }
}
