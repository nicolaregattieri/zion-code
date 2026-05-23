import Foundation

// MARK: - ProviderOrchestrator

/// Routes AI requests to the best available provider based on health, cost caps,
/// and user-configured lane chains.
actor ProviderOrchestrator {

    // MARK: - Dependencies

    private let policy: RoutingPolicy
    private let health: ProviderHealth
    private let budget: CostBudget

    // MARK: - UserDefaults key

    private static let subscriptionFailoverKey = "chat.routing.subscriptionFailover"

    // MARK: - Init

    init(
        policy: RoutingPolicy = .load(),
        health: ProviderHealth = ProviderHealth(),
        budget: CostBudget = CostBudget()
    ) {
        self.policy = policy
        self.health = health
        self.budget = budget
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

        let chain = policy.chain(for: lane)
        return await firstEligible(in: chain, costCaps: costCaps) ?? .none
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
    private func firstEligible(
        in candidates: [AIProvider],
        costCaps: [AIProvider: Double]
    ) async -> AIProvider? {
        let subscriptionFailoverEnabled = UserDefaults.standard.bool(
            forKey: Self.subscriptionFailoverKey
        )

        for provider in candidates {
            // Health check
            guard await health.isHealthy(provider) else { continue }

            // Cost cap check
            let cap = costCaps[provider] ?? 0
            if budget.capExceeded(provider: provider, cap: cap) { continue }

            // Subscription CLI check — skip if failover is disabled
            if isSubscriptionCLI(provider) && !subscriptionFailoverEnabled { continue }

            return provider
        }
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
