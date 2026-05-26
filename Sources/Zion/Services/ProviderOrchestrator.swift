import Foundation

// MARK: - OrchestratorRefusal

/// Reason a provider switch was refused.
enum OrchestratorRefusal: Equatable {
    /// An agentic loop is currently running; provider switches are locked until it completes.
    case loopActive
    /// The requested provider is not in the current lane chain.
    case notInChain
}

// MARK: - SwitchResult

/// Outcome of a `requestSwitch(to:lane:)` call.
enum SwitchResult: Equatable {
    case allowed(AIProvider)
    case refused(OrchestratorRefusal)
}

// MARK: - AgentLoopStateProvider

/// Read-only protocol that exposes whether an agentic loop is currently active.
/// Implemented by `AgentRuntime`; a test mock can implement it too.
protocol AgentLoopStateProvider: AnyObject, Sendable {
    @MainActor var isLoopActive: Bool { get }
}

// MARK: - AgentRuntime: AgentLoopStateProvider

// Conformance declared here (AgentRuntime is @MainActor, satisfies @MainActor var isLoopActive).
extension AgentRuntime: AgentLoopStateProvider {}

// MARK: - ProviderOrchestrator

/// Routes AI requests to the best available provider based on health, cost caps,
/// and user-configured lane chains.
actor ProviderOrchestrator {

    // MARK: - Dependencies

    private let policy: RoutingPolicy
    private let health: ProviderHealth
    private let budget: CostBudget
    private let connectivityCheck: @Sendable (AIProvider) -> Bool

    /// Optional reference to the agent runtime for sticky-lock enforcement.
    /// Set via `attachAgentRuntime(_:)` at app boot. Nil = lock disabled.
    private weak var agentRuntime: (any AgentLoopStateProvider)?

    // MARK: - UserDefaults key

    private static let subscriptionFailoverKey = "chat.routing.subscriptionFailover"

    // MARK: - Init

    init(
        policy: RoutingPolicy = .load(),
        health: ProviderHealth = ProviderHealth(),
        budget: CostBudget = CostBudget(),
        connectivityCheck: @escaping @Sendable (AIProvider) -> Bool = {
            AIProviderSupport.isConnected(provider: $0)
        }
    ) {
        self.policy = policy
        self.health = health
        self.budget = budget
        self.connectivityCheck = connectivityCheck
        self.agentRuntime = nil
    }

    // MARK: - Agent Runtime Attachment

    /// Call once at app boot to wire in the AgentRuntime sticky lock.
    func attachAgentRuntime(_ runtime: any AgentLoopStateProvider) {
        agentRuntime = runtime
    }

    // MARK: - Request Switch

    /// Attempts to switch the active provider to `to` for the given lane.
    /// Refuses with `.loopActive` if an agentic loop is currently running.
    /// Refuses with `.notInChain` if `to` is not in the lane chain.
    func requestSwitch(
        to provider: AIProvider,
        lane: AITaskLane = .general
    ) async -> SwitchResult {
        // Sticky lock: refuse while agentic loop is active
        if let runtime = agentRuntime {
            let loopActive = await runtime.isLoopActive
            if loopActive {
                return .refused(.loopActive)
            }
        }

        // Chain membership check
        let chain = policy.chain(for: lane)
        guard chain.contains(provider) else {
            return .refused(.notInChain)
        }

        return .allowed(provider)
    }

    // MARK: - Resolve

    /// Resolve the best provider for a request.
    ///
    /// - When `requested` is a concrete provider (not `.auto` / `.none`), it is
    ///   returned immediately — the orchestrator only kicks in on retries / auto.
    /// - When `.auto`, walks the lane chain and returns the first eligible provider,
    ///   or `.none` if every option is ineligible.
    func resolve(
        lane: AITaskLane,
        requested: AIProvider,
        costCaps: [AIProvider: Double] = [:]
    ) async -> AIProvider {
        // Explicit provider — pass straight through.
        if requested != .auto && requested != .none {
            return requested
        }

        await DiagnosticLogger.shared.log(.info,
            "orchestrator.resolve lane=\(lane.rawValue) requested=\(requested.rawValue)",
            source: "orchestrator")
        let chain = policy.chain(for: lane)
        if let primary = await firstEligible(in: chain, costCaps: costCaps) {
            return primary
        }
        // Graceful degrade: lane chain dry → fall back to cheapSummary chain
        // (always includes `.local`).
        if lane != .cheapSummary {
            await DiagnosticLogger.shared.log(.warn,
                "lane \(lane.rawValue) chain dry — falling back to cheapSummary chain",
                source: "orchestrator")
            let fallback = policy.chain(for: .cheapSummary)
            if let any = await firstEligible(in: fallback, costCaps: costCaps) {
                return any
            }
        }
        await DiagnosticLogger.shared.log(.error,
            "orchestrator returning .none — no provider passes any chain",
            source: "orchestrator")
        return .none
    }

    // MARK: - Fallback

    /// Returns the next eligible provider after `current` in the lane chain,
    /// or `nil` when none remain.
    func nextFallback(
        from current: AIProvider,
        lane: AITaskLane,
        costCaps: [AIProvider: Double] = [:]
    ) async -> AIProvider? {
        let chain = policy.chain(for: lane)
        guard let currentIndex = chain.firstIndex(of: current) else {
            // current not in chain — search from the start
            return await firstEligible(in: chain, costCaps: costCaps)
        }
        let tail = Array(chain.dropFirst(currentIndex + 1))
        return await firstEligible(in: tail, costCaps: costCaps)
    }

    // MARK: - Delegation

    func markRateLimited(_ provider: AIProvider, retryAfter: TimeInterval?) async {
        await health.markRateLimited(provider, retryAfter: retryAfter)
    }

    func markHealthy(_ provider: AIProvider) async {
        await health.markHealthy(provider)
    }

    func recordCost(_ provider: AIProvider, usd: Double) {
        budget.record(provider: provider, usd: usd)
    }

    // MARK: - Private Helpers

    /// Returns the first provider from `candidates` that passes all eligibility checks.
    ///
    /// Walks the chain in declared order applying the same health + cost-cap +
    /// connectivity gate to every provider. Subscription CLIs (claudeCLI /
    /// codexCLI) used to be gated behind `chat.routing.subscriptionFailover`,
    /// but Smart Auto inverts the policy: if the user installed + authenticated
    /// the CLI, they want it as a first-class candidate (no extra opt-in).
    /// Diagnostic logs are emitted so a "No AI provider configured" outcome
    /// can be debugged from `~/Library/Logs/Zion/`.
    private func firstEligible(
        in candidates: [AIProvider],
        costCaps: [AIProvider: Double]
    ) async -> AIProvider? {
        let chainSummary = candidates.map(\.rawValue).joined(separator: ",")
        await DiagnosticLogger.shared.log(.info,
            "orchestrator.firstEligible candidates=\(chainSummary)",
            source: "orchestrator")

        for provider in candidates {
            let healthy = await health.isHealthy(provider)
            if !healthy {
                await DiagnosticLogger.shared.log(.warn,
                    "skip \(provider.rawValue): unhealthy (rate-limit cool-down)",
                    source: "orchestrator")
                continue
            }
            let cap = costCaps[provider] ?? 0
            if budget.capExceeded(provider: provider, cap: cap) {
                await DiagnosticLogger.shared.log(.warn,
                    "skip \(provider.rawValue): cost cap exceeded",
                    source: "orchestrator")
                continue
            }
            if !connectivityCheck(provider) {
                await DiagnosticLogger.shared.log(.warn,
                    "skip \(provider.rawValue): not connected (no key / CLI not installed / local server down)",
                    source: "orchestrator")
                continue
            }
            await DiagnosticLogger.shared.log(.info,
                "picked \(provider.rawValue)",
                source: "orchestrator")
            return provider
        }
        await DiagnosticLogger.shared.log(.warn,
            "chain exhausted — no eligible provider",
            source: "orchestrator")
        return nil
    }

    /// Returns true for providers that use a local subscription CLI (no API key required).
    private func isSubscriptionCLI(_ provider: AIProvider) -> Bool {
        switch provider {
        case .claudeCLI, .codexCLI: return true
        default: return false
        }
    }
}
