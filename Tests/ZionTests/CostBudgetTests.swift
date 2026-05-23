import XCTest
@testable import Zion

final class CostBudgetTests: XCTestCase {

    // Use a fresh suite per test to avoid cross-test pollution.
    private func makeSuite(name: String = #function) -> UserDefaults {
        let suite = UserDefaults(suiteName: "CostBudgetTests.\(name)")!
        // Wipe all keys so prior runs don't bleed in.
        suite.removePersistentDomain(forName: "CostBudgetTests.\(name)")
        return suite
    }

    // MARK: - record + spent

    func testRecordAndSpent() {
        let defaults = makeSuite()
        let budget = CostBudget(defaults: defaults)
        XCTAssertEqual(budget.spent(provider: .anthropic), 0)
        budget.record(provider: .anthropic, usd: 0.05)
        XCTAssertEqual(budget.spent(provider: .anthropic), 0.05, accuracy: 1e-9)
        budget.record(provider: .anthropic, usd: 0.10)
        XCTAssertEqual(budget.spent(provider: .anthropic), 0.15, accuracy: 1e-9)
    }

    func testRecordIsolatedByProvider() {
        let defaults = makeSuite()
        let budget = CostBudget(defaults: defaults)
        budget.record(provider: .anthropic, usd: 1.00)
        XCTAssertEqual(budget.spent(provider: .openai), 0)
        XCTAssertEqual(budget.spent(provider: .gemini), 0)
    }

    // MARK: - Rollover / date isolation

    func testYesterdaySpendDoesNotCountToday() {
        let defaults = makeSuite()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let budget = CostBudget(defaults: defaults, calendar: calendar)

        // Write directly to yesterday's key.
        let yesterday = Date().addingTimeInterval(-86400)
        let components = calendar.dateComponents([.year, .month, .day], from: yesterday)
        let y = components.year ?? 0
        let m = components.month ?? 0
        let d = components.day ?? 0
        let yesterdayKey = String(format: "cost.budget.%@.%04d-%02d-%02d",
                                  AIProvider.anthropic.rawValue, y, m, d)
        defaults.set(99.0, forKey: yesterdayKey)

        // Today's spend must remain 0.
        XCTAssertEqual(budget.spent(provider: .anthropic), 0)
    }

    // MARK: - capExceeded

    func testCapExceededFalseWhenUnderCap() {
        let defaults = makeSuite()
        let budget = CostBudget(defaults: defaults)
        budget.record(provider: .openai, usd: 0.49)
        XCTAssertFalse(budget.capExceeded(provider: .openai, cap: 0.50))
    }

    func testCapExceededTrueWhenAtCap() {
        let defaults = makeSuite()
        let budget = CostBudget(defaults: defaults)
        budget.record(provider: .openai, usd: 0.50)
        XCTAssertTrue(budget.capExceeded(provider: .openai, cap: 0.50))
    }

    func testCapExceededTrueWhenOverCap() {
        let defaults = makeSuite()
        let budget = CostBudget(defaults: defaults)
        budget.record(provider: .openai, usd: 1.00)
        XCTAssertTrue(budget.capExceeded(provider: .openai, cap: 0.50))
    }

    func testCapExceededFalseWhenCapIsZero() {
        let defaults = makeSuite()
        let budget = CostBudget(defaults: defaults)
        budget.record(provider: .anthropic, usd: 100.00)
        // cap == 0 means "no cap" — always false.
        XCTAssertFalse(budget.capExceeded(provider: .anthropic, cap: 0))
    }

    func testCapExceededFalseWhenCapIsNegative() {
        let defaults = makeSuite()
        let budget = CostBudget(defaults: defaults)
        budget.record(provider: .anthropic, usd: 100.00)
        XCTAssertFalse(budget.capExceeded(provider: .anthropic, cap: -1))
    }
}
