import XCTest
@testable import Zion

final class SpendLedgerTests: XCTestCase {

    private var tempURL: URL!
    private var ledger: SpendLedger!

    override func setUp() async throws {
        try await super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpendLedgerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempURL = dir.appendingPathComponent("spend.sqlite")
        ledger = try SpendLedger(path: tempURL)
    }

    override func tearDown() async throws {
        ledger = nil
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        tempURL = nil
        try await super.tearDown()
    }

    // MARK: - Test 1: append_and_monthly_roundtrip

    func test_append_and_monthly_roundtrip() async throws {
        let row = ProviderSpendRow(
            provider: "anthropic",
            model: "claude-3-5-haiku",
            inputTokens: 100,
            outputTokens: 200,
            cacheReadTokens: 50,
            usdCost: 0.001,
            billingMode: .api
        )
        let now = Date()
        try await ledger.append(row, at: now)

        let totals = try await ledger.monthlyTotals(forMonth: now)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].provider, "anthropic")
        XCTAssertEqual(totals[0].model, "claude-3-5-haiku")
        XCTAssertEqual(totals[0].inputTokens, 100)
        XCTAssertEqual(totals[0].outputTokens, 200)
        XCTAssertEqual(totals[0].usdCost, 0.001, accuracy: 1e-9)
    }

    // MARK: - Test 2: multiple_models_aggregate_correctly

    func test_multiple_models_aggregate_correctly() async throws {
        let now = Date()
        let models = ["model-a", "model-b", "model-c"]
        for m in models {
            let row = ProviderSpendRow(
                provider: "openai",
                model: m,
                inputTokens: 10,
                outputTokens: 20,
                cacheReadTokens: 0,
                usdCost: 0.01,
                billingMode: .api
            )
            try await ledger.append(row, at: now)
        }

        let totals = try await ledger.monthlyTotals(forMonth: now)
        XCTAssertEqual(totals.count, 3)
        let returnedModels = Set(totals.map { $0.model })
        XCTAssertEqual(returnedModels, Set(models))
    }

    // MARK: - Test 3: same_model_aggregates_tokens_and_cost

    func test_same_model_aggregates_tokens_and_cost() async throws {
        let now = Date()
        let row1 = ProviderSpendRow(
            provider: "anthropic",
            model: "claude-opus-4",
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 100,
            usdCost: 0.05,
            billingMode: .api
        )
        let row2 = ProviderSpendRow(
            provider: "anthropic",
            model: "claude-opus-4",
            inputTokens: 2000,
            outputTokens: 1000,
            cacheReadTokens: 200,
            usdCost: 0.10,
            billingMode: .api
        )
        try await ledger.append(row1, at: now)
        try await ledger.append(row2, at: now)

        let totals = try await ledger.monthlyTotals(forMonth: now)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].inputTokens, 3000)
        XCTAssertEqual(totals[0].outputTokens, 1500)
        XCTAssertEqual(totals[0].cacheReadTokens, 300)
        XCTAssertEqual(totals[0].usdCost, 0.15, accuracy: 1e-9)
    }

    // MARK: - Test 4: cache_read_tokens_preserved

    func test_cache_read_tokens_preserved() async throws {
        let now = Date()
        let row = ProviderSpendRow(
            provider: "anthropic",
            model: "claude-3-5-sonnet",
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 500,
            usdCost: 0.0,
            billingMode: .api
        )
        try await ledger.append(row, at: now)

        let totals = try await ledger.monthlyTotals(forMonth: now)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].cacheReadTokens, 500)
    }

    // MARK: - Test 5: previous_month_excluded

    func test_previous_month_excluded() async throws {
        let now = Date()
        let sixtyDaysAgo = Date(timeIntervalSinceNow: -60 * 24 * 60 * 60)

        let recentRow = ProviderSpendRow(
            provider: "gemini",
            model: "gemini-2.5-pro",
            inputTokens: 100,
            outputTokens: 100,
            cacheReadTokens: 0,
            usdCost: 0.02,
            billingMode: .api
        )
        let oldRow = ProviderSpendRow(
            provider: "gemini",
            model: "gemini-2.5-pro",
            inputTokens: 999,
            outputTokens: 999,
            cacheReadTokens: 0,
            usdCost: 99.0,
            billingMode: .api
        )

        try await ledger.append(recentRow, at: now)
        try await ledger.append(oldRow, at: sixtyDaysAgo)

        let totals = try await ledger.monthlyTotals(forMonth: now)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].inputTokens, 100)
        XCTAssertEqual(totals[0].usdCost, 0.02, accuracy: 1e-9)
    }

    // MARK: - Test 6: modelPricing_ratesAsOf_present

    func test_modelPricing_ratesAsOf_present() {
        let ratesAsOf = ModelPricing.ratesAsOf
        let cutoff = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
        XCTAssertTrue(ratesAsOf > cutoff, "ratesAsOf should be after 2026-01-01")
    }

    // MARK: - Test 7: modelPricing_computeCost_anthropic_haiku

    func test_modelPricing_computeCost_anthropic_haiku() {
        let cost = ModelPricing.computeCost(
            model: "claude-3-5-haiku",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadTokens: 0
        )
        // input: 1M * $0.80/M = $0.80, output: 1M * $4.00/M = $4.00 → total $4.80
        XCTAssertEqual(cost, 4.80, accuracy: 0.001)
    }
}
