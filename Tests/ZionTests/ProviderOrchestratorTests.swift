import XCTest
@testable import Zion

final class ProviderOrchestratorTests: XCTestCase {

    // MARK: - Helpers

    private static let failoverKey = "chat.routing.subscriptionFailover"

    override func setUp() {
        super.setUp()
        // Default: subscription failover enabled so CLI providers are reachable
        UserDefaults.standard.set(true, forKey: Self.failoverKey)
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: Self.failoverKey)
    }

    /// Builds a policy with a simple 3-provider general chain:
    ///   claudeCLI → anthropic → openai
    ///
    /// Injects a connectivity stub that always returns true so eligibility is
    /// driven entirely by the health/cost-cap state under test, not by whether
    /// the CI machine happens to have API keys configured.
    private func makeOrchestrator(health: ProviderHealth = ProviderHealth(),
                                  budget: CostBudget = CostBudget()) -> ProviderOrchestrator {
        var chains: [String: [String]] = [:]
        chains[AITaskLane.general.rawValue] = [
            AIProvider.claudeCLI.rawValue,
            AIProvider.anthropic.rawValue,
            AIProvider.openai.rawValue
        ]
        let policy = RoutingPolicy(chains: chains)
        return ProviderOrchestrator(
            policy: policy,
            health: health,
            budget: budget,
            connectivityCheck: { _ in true }
        )
    }

    // MARK: - Tests

    /// Explicit (non-auto, non-none) provider is returned as-is, even when rate-limited.
    func testExplicitProviderPassesThrough() async throws {
        let health = ProviderHealth()
        // Mark anthropic rate-limited for 1 hour
        await health.markRateLimited(.anthropic, retryAfter: 3600)

        let orchestrator = makeOrchestrator(health: health)
        let result = await orchestrator.resolve(lane: .general, requested: .anthropic)
        XCTAssertEqual(result, .anthropic, "Explicit provider must pass through even when unhealthy")
    }

    /// Auto selects the first healthy provider in the chain.
    func testAutoSelectsFirstHealthy() async throws {
        let orchestrator = makeOrchestrator()
        // All providers healthy by default; claudeCLI is first
        UserDefaults.standard.set(true, forKey: Self.failoverKey)
        let result = await orchestrator.resolve(lane: .general, requested: .auto)
        XCTAssertEqual(result, .claudeCLI)
    }

    /// Auto skips a rate-limited first provider and returns the next healthy one.
    func testAutoSkipsRateLimited() async throws {
        let health = ProviderHealth()
        await health.markRateLimited(.claudeCLI, retryAfter: 3600)

        let orchestrator = makeOrchestrator(health: health)
        let result = await orchestrator.resolve(lane: .general, requested: .auto)
        XCTAssertEqual(result, .anthropic)
    }

    /// Auto skips a provider whose cost cap is exceeded.
    func testAutoSkipsCostCapped() async throws {
        let defaults = UserDefaults(suiteName: "test.costcap.\(UUID().uuidString)")!
        let budget = CostBudget(defaults: defaults)
        // Record $5 for claudeCLI — exceeds $1 cap
        budget.record(provider: .claudeCLI, usd: 5.0)

        let orchestrator = makeOrchestrator(budget: budget)
        let costCaps: [AIProvider: Double] = [.claudeCLI: 1.0]
        let result = await orchestrator.resolve(lane: .general, requested: .auto, costCaps: costCaps)
        XCTAssertEqual(result, .anthropic)
    }

    /// When subscriptionFailover is false, CLI providers are skipped even if healthy.
    func testSubscriptionFailoverOptIn() async throws {
        UserDefaults.standard.set(false, forKey: Self.failoverKey)
        // chain: claudeCLI → anthropic → openai
        // claudeCLI is a subscription CLI and failover is off → skip it
        let orchestrator = makeOrchestrator()
        let result = await orchestrator.resolve(lane: .general, requested: .auto)
        XCTAssertEqual(result, .anthropic, "CLI providers must be skipped when subscriptionFailover is false")
    }

    /// A user's explicit CLI choice remains available when automatic subscription failover is off.
    func testExplicitCLISelectionIgnoresSubscriptionFailoverSetting() async throws {
        UserDefaults.standard.set(false, forKey: Self.failoverKey)
        let orchestrator = makeOrchestrator()
        let result = await orchestrator.resolve(lane: .general, requested: .claudeCLI)
        XCTAssertEqual(result, .claudeCLI)
    }

    /// nextFallback returns nil when no providers after current are eligible.
    func testNextFallbackReturnsNilWhenExhausted() async throws {
        let health = ProviderHealth()
        // Rate-limit all providers
        await health.markRateLimited(.anthropic, retryAfter: 3600)
        await health.markRateLimited(.openai, retryAfter: 3600)

        let orchestrator = makeOrchestrator(health: health)
        // Ask for fallback from claudeCLI; remaining chain is anthropic + openai (both unhealthy)
        let result = await orchestrator.nextFallback(from: .claudeCLI, lane: .general)
        XCTAssertNil(result, "nextFallback should return nil when all remaining providers are unhealthy")
    }

    /// nextFallback returns the next healthy provider after `current`.
    func testNextFallbackSkipsToNextHealthy() async throws {
        let health = ProviderHealth()
        await health.markRateLimited(.anthropic, retryAfter: 3600)

        let orchestrator = makeOrchestrator(health: health)
        // chain: claudeCLI → anthropic (unhealthy) → openai
        let result = await orchestrator.nextFallback(from: .claudeCLI, lane: .general)
        XCTAssertEqual(result, .openai)
    }

    /// recordCost delegates to budget without throwing.
    func testRecordCostDelegatesToBudget() async throws {
        let defaults = UserDefaults(suiteName: "test.record.\(UUID().uuidString)")!
        let budget = CostBudget(defaults: defaults)
        let orchestrator = makeOrchestrator(budget: budget)

        await orchestrator.recordCost(.anthropic, usd: 0.05)
        XCTAssertEqual(budget.spent(provider: .anthropic), 0.05, accuracy: 0.001)
    }
}
