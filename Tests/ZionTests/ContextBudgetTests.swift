import XCTest
@testable import Zion

final class ContextBudgetTests: XCTestCase {

    // MARK: - 1. Anthropic default window minus reserve

    func test_anthropic_default_window_minus_reserve() async {
        let budget = ContextBudget()
        let available = await budget.available(forProvider: .anthropic, model: "claude-3-5-sonnet")
        XCTAssertEqual(available, 200_000 - 16_000)
    }

    // MARK: - 2. OpenAI gpt-4o returns 128k minus reserve

    func test_openai_4o_returns_128k_minus_reserve() async {
        let budget = ContextBudget()
        let available = await budget.available(forProvider: .openai, model: "gpt-4o")
        XCTAssertEqual(available, 128_000 - 16_000)
    }

    // MARK: - 3. Gemini returns 1M minus reserve

    func test_gemini_returns_1m_minus_reserve() async {
        let budget = ContextBudget()
        let available = await budget.available(forProvider: .gemini, model: "gemini-2.5-pro")
        XCTAssertEqual(available, 1_000_000 - 16_000)
    }

    // MARK: - 4. Consume decrements available

    func test_consume_decrements_available() async {
        let budget = ContextBudget()
        await budget.consume(50_000, layer: .history)
        let available = await budget.available(forProvider: .anthropic, model: "claude-3-5-sonnet")
        XCTAssertEqual(available, 200_000 - 16_000 - 50_000)
    }

    // MARK: - 5. fits returns false when over budget

    func test_fits_returns_false_when_over() async {
        let budget = ContextBudget()
        // Consume 180k — leaves 200k - 16k - 180k = 4k
        await budget.consume(180_000, layer: .history)
        let canFit = await budget.fits(20_000, forProvider: .anthropic, model: "claude-3-5-sonnet")
        XCTAssertFalse(canFit, "20k should not fit when only 4k remains")
    }

    // MARK: - 6. Reset clears consumption

    func test_reset_clears_consumption() async {
        let budget = ContextBudget()
        await budget.consume(50_000, layer: .history)
        await budget.reset()
        let available = await budget.available(forProvider: .anthropic, model: "claude-3-5-sonnet")
        XCTAssertEqual(available, 200_000 - 16_000, "After reset, available should equal window - reserve")
    }
}
