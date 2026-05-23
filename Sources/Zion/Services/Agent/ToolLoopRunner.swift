// ToolLoopRunner.swift — Outer while-loop orchestrator for nativeToolUse providers.
// Drives multi-step agentic execution: stream → parse → execute tools → repeat.
//
// Supported providers: anthropic, openai, gemini (all resolve to .nativeToolUse).
// Rejects .reactTextFallback / .passthrough / .unsupported with LoopError.wrongCapability.
//
// Implemented as a `final class` (not an `actor`) to avoid the actor-isolation boundary
// that prevents passing non-Sendable `[[String: Any]]` conversation data across isolation
// domains. Internal state (streamFactory, mcpClient) is set once at init and never mutated,
// so the @unchecked Sendable contract is safe.

import Foundation

// MARK: - LoopStopReason

enum LoopStopReason: Sendable, Equatable {
    case endTurn
    case maxStepsReached
    case budgetExceeded
    case cancelled
    case toolError(String)
    case providerError(String)

    static func == (lhs: LoopStopReason, rhs: LoopStopReason) -> Bool {
        switch (lhs, rhs) {
        case (.endTurn, .endTurn): return true
        case (.maxStepsReached, .maxStepsReached): return true
        case (.budgetExceeded, .budgetExceeded): return true
        case (.cancelled, .cancelled): return true
        case (.toolError(let a), .toolError(let b)): return a == b
        case (.providerError(let a), .providerError(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - LoopResult

// [String: Any] cannot satisfy Sendable without @unchecked; the conversation array
// is immutable JSON-decoded data passed through without mutation.
struct LoopResult: @unchecked Sendable {
    let finalText: String
    let stepsUsed: Int
    let stopReason: LoopStopReason
    let cumulativeTokens: Int
    let cumulativeCostUSD: Double
    let cancelled: Bool
    let conversation: [[String: Any]]
}

// MARK: - CancellationToken

actor CancellationToken {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}

// MARK: - LoopError

enum LoopError: Error, LocalizedError {
    case wrongCapability(AgenticCapability)
    case emptyToolUseResponse

    var errorDescription: String? {
        switch self {
        case .wrongCapability(let cap):
            return "ToolLoopRunner requires .nativeToolUse capability, got \(cap)"
        case .emptyToolUseResponse:
            return "Provider indicated tool_use but returned no tool calls (infinite loop guard)"
        }
    }
}

// MARK: - StreamFactory

/// Injectable stream factory for test isolation.
/// Receives the raw conversation and returns a line-stream (same format as ToolLoopExecutor expects).
typealias StreamFactory = @Sendable (
    AIProvider,
    String?,
    [[String: Any]],
    [MCPToolDescriptor]
) async throws -> AsyncThrowingStream<String, Error>

// MARK: - ToolLoopRunner

final class ToolLoopRunner: @unchecked Sendable {

    // MARK: Dependencies

    private let streamFactory: StreamFactory
    private let mcpClient: any MCPClientProtocol

    // MARK: Init

    /// Production initializer — caller supplies real network stream factories and an MCP client.
    init(streamFactory: @escaping StreamFactory, mcpClient: any MCPClientProtocol) {
        self.streamFactory = streamFactory
        self.mcpClient = mcpClient
    }

    // MARK: Run

    /// Executes the outer agentic while-loop until endTurn, maxSteps, budget exceeded, or cancelled.
    ///
    /// - Parameters:
    ///   - provider:       The AI provider to use.
    ///   - model:          Optional model identifier string.
    ///   - conversation:   Initial conversation as raw message dictionaries.
    ///   - tools:          Tool descriptors to offer to the model.
    ///   - maxSteps:       Hard ceiling on loop iterations (default 25, matches spec).
    ///   - budgetCap:      Maximum cumulative cost in USD (0 = unlimited).
    ///   - cancel:         CancellationToken polled at the top of each loop iteration.
    ///   - onStep:         Callback fired on the MainActor after each completed step.
    /// - Returns: `LoopResult` summarising the run.
    func run(
        provider: AIProvider,
        model: String?,
        conversation initialConversation: [[String: Any]],
        tools: [MCPToolDescriptor],
        maxSteps: Int = 25,
        budgetCap: Double = 0,
        cancel: CancellationToken,
        onStep: @escaping @MainActor @Sendable (AgentStepEvent) -> Void
    ) async throws -> LoopResult {

        // Validate capability
        let capability = AgenticCapability.resolve(provider: provider, modelName: model)
        guard capability == .nativeToolUse else {
            throw LoopError.wrongCapability(capability)
        }

        let family = providerFamily(provider)
        let executor = ToolLoopExecutor(family: family, mcpClient: mcpClient)

        var conversation = initialConversation
        var stepCount = 0
        let cumulativeTokens = 0
        let cumulativeCostUSD: Double = 0
        var loopStop: LoopStopReason = .endTurn
        var finalText = ""

        while true {
            // --- Guard conditions ---
            if await cancel.isCancelled { loopStop = .cancelled; break }
            if stepCount >= maxSteps    { loopStop = .maxStepsReached; break }
            if budgetCap > 0 && cumulativeCostUSD >= budgetCap { loopStop = .budgetExceeded; break }

            // --- Stream + parse one step ---
            let outcome: StepOutcome
            do {
                let stream = try await streamFactory(provider, model, conversation, tools)
                outcome = try await executor.runOneStep(streamLines: stream, conversation: conversation)
            } catch {
                loopStop = .providerError(error.localizedDescription)
                break
            }

            stepCount += 1
            finalText = outcome.text

            // --- Fire step callback ---
            let stepEvent = buildStepEvent(
                outcome: outcome,
                stepIndex: stepCount,
                cumulativeTokens: cumulativeTokens,
                cumulativeCostUSD: cumulativeCostUSD
            )
            await onStep(stepEvent)

            // --- Update conversation from outcome ---
            conversation = outcome.updatedConversation

            // --- Route on stop reason ---
            switch outcome.stopReason {
            case .endTurn:
                loopStop = .endTurn
                return LoopResult(
                    finalText: finalText,
                    stepsUsed: stepCount,
                    stopReason: .endTurn,
                    cumulativeTokens: cumulativeTokens,
                    cumulativeCostUSD: cumulativeCostUSD,
                    cancelled: false,
                    conversation: conversation
                )

            case .toolUse:
                // Guard against empty-tool-calls infinite loop
                if outcome.toolCalls.isEmpty {
                    loopStop = .providerError("empty tool_use response")
                    break
                }
                // Tool results already in outcome.updatedConversation — just continue.
                continue

            case .maxTokens:
                loopStop = .providerError("max_tokens — consider raising budget")
                break

            case .other(let reason):
                loopStop = .providerError(reason)
                break
            }

            // Reached here only from non-endTurn breaks inside switch
            break
        }

        return LoopResult(
            finalText: finalText,
            stepsUsed: stepCount,
            stopReason: loopStop,
            cumulativeTokens: cumulativeTokens,
            cumulativeCostUSD: cumulativeCostUSD,
            cancelled: loopStop == .cancelled,
            conversation: conversation
        )
    }

    // MARK: - Private helpers

    /// Map AIProvider to ProviderFamily for ToolLoopExecutor.
    private func providerFamily(_ provider: AIProvider) -> ProviderFamily {
        switch provider {
        case .anthropic:           return .anthropic
        case .openai, .auto:       return .openai
        case .gemini:              return .gemini
        case .local:               return .localOpenAICompatible
        default:                   return .openai
        }
    }

    /// Build an AgentStepEvent from a StepOutcome.
    private func buildStepEvent(
        outcome: StepOutcome,
        stepIndex: Int,
        cumulativeTokens: Int,
        cumulativeCostUSD: Double
    ) -> AgentStepEvent {
        let toolEvent: ChatToolEvent
        if let firstCall = outcome.toolCalls.first {
            toolEvent = ChatToolEvent(
                id: firstCall.id,
                name: firstCall.name,
                status: .completed,
                argsPreview: "\(firstCall.args)"
            )
        } else {
            toolEvent = ChatToolEvent(
                id: UUID().uuidString,
                name: "step",
                status: .completed,
                argsPreview: String(outcome.text.prefix(60))
            )
        }
        return AgentStepEvent(
            toolEvent: toolEvent,
            stepIndex: stepIndex,
            cumulativeTokens: cumulativeTokens,
            cumulativeCostUSD: cumulativeCostUSD
        )
    }
}
