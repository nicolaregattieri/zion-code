import Foundation

// MARK: - AgentStepEventKind

/// Distinguishes the semantic kind of an agent step event.
enum AgentStepEventKind: String, Sendable, Equatable, Codable {
    /// A normal tool-call step in the agentic loop.
    case toolCall
    /// Emitted after step 1 in planFirst mode — contains the plan proposal for user review.
    case planProposed
}

// MARK: - AgentStepEvent

/// Carries per-step metadata for agentic loop progress reporting.
/// Extends the existing `ChatToolEvent` flow with step index and cumulative cost tracking.
struct AgentStepEvent: Equatable, Codable {
    /// Semantic kind of this step event. Defaults to `.toolCall` for backwards compatibility.
    var kind: AgentStepEventKind
    /// The underlying tool event this step wraps.
    var toolEvent: ChatToolEvent
    /// Zero-based index of this step within the current agentic loop run.
    let stepIndex: Int
    /// Total tokens consumed across all steps up to and including this one.
    var cumulativeTokens: Int
    /// Total cost in USD accumulated across all steps up to and including this one.
    var cumulativeCostUSD: Double

    init(
        kind: AgentStepEventKind = .toolCall,
        toolEvent: ChatToolEvent,
        stepIndex: Int,
        cumulativeTokens: Int = 0,
        cumulativeCostUSD: Double = 0.0
    ) {
        self.kind = kind
        self.toolEvent = toolEvent
        self.stepIndex = stepIndex
        self.cumulativeTokens = cumulativeTokens
        self.cumulativeCostUSD = cumulativeCostUSD
    }
}

// MARK: - ChatToolEvent step annotation

extension ChatToolEvent {
    /// Wraps this event into an `AgentStepEvent` for agentic loop reporting.
    func asStep(
        index stepIndex: Int,
        cumulativeTokens: Int = 0,
        cumulativeCostUSD: Double = 0.0
    ) -> AgentStepEvent {
        AgentStepEvent(
            toolEvent: self,
            stepIndex: stepIndex,
            cumulativeTokens: cumulativeTokens,
            cumulativeCostUSD: cumulativeCostUSD
        )
    }
}
