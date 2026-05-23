import XCTest
@testable import Zion

final class ProviderHealthTests: XCTestCase {

    // MARK: - isHealthy baseline

    func testFreshProviderIsHealthy() async {
        let health = ProviderHealth()
        let result = await health.isHealthy(.anthropic)
        XCTAssertTrue(result)
    }

    // MARK: - markRateLimited with explicit retryAfter

    func testMarkRateLimitedSetsDeadline() async {
        let health = ProviderHealth()
        let before = Date()
        await health.markRateLimited(.anthropic, retryAfter: 60)
        let deadline = await health.deadline(for: .anthropic)
        XCTAssertNotNil(deadline)
        // Deadline should be ~60s from now (allow 2s tolerance for test execution time).
        let diff = deadline!.timeIntervalSince(before)
        XCTAssertGreaterThanOrEqual(diff, 58)
        XCTAssertLessThanOrEqual(diff, 62)
    }

    func testIsHealthyFalseDuringWindow() async {
        let health = ProviderHealth()
        await health.markRateLimited(.openai, retryAfter: 300)
        // now = current time, well within the 300s window
        let result = await health.isHealthy(.openai, now: Date())
        XCTAssertFalse(result)
    }

    func testIsHealthyTrueAfterExpiry() async {
        let health = ProviderHealth()
        await health.markRateLimited(.openai, retryAfter: 10)
        // Simulate checking 20 seconds past the deadline.
        let futureDate = Date().addingTimeInterval(30)
        let result = await health.isHealthy(.openai, now: futureDate)
        XCTAssertTrue(result)
    }

    // MARK: - Default backoff escalation

    func testDefaultBackoffEscalatesOnRepeatedMarks() async {
        let health = ProviderHealth()

        // First mark — should use backoff[0] = 60s
        let t0 = Date()
        await health.markRateLimited(.gemini, retryAfter: nil)
        let d1 = await health.deadline(for: .gemini)!
        let delay1 = d1.timeIntervalSince(t0)
        XCTAssertGreaterThanOrEqual(delay1, 58, "First backoff should be ~60s")
        XCTAssertLessThanOrEqual(delay1, 62)

        // Second mark — should use backoff[1] = 120s
        let t1 = Date()
        await health.markRateLimited(.gemini, retryAfter: nil)
        let d2 = await health.deadline(for: .gemini)!
        let delay2 = d2.timeIntervalSince(t1)
        XCTAssertGreaterThanOrEqual(delay2, 118, "Second backoff should be ~120s")
        XCTAssertLessThanOrEqual(delay2, 122)

        // Third mark — should use backoff[2] = 300s
        let t2 = Date()
        await health.markRateLimited(.gemini, retryAfter: nil)
        let d3 = await health.deadline(for: .gemini)!
        let delay3 = d3.timeIntervalSince(t2)
        XCTAssertGreaterThanOrEqual(delay3, 298, "Third backoff should be ~300s")
        XCTAssertLessThanOrEqual(delay3, 302)
    }

    func testBackoffCapsAtMaximum() async {
        let health = ProviderHealth()
        // Fire markRateLimited 10 times (backoff schedule has 6 entries).
        for _ in 0..<10 {
            await health.markRateLimited(.claudeCLI, retryAfter: nil)
        }
        let t = Date()
        let deadline = await health.deadline(for: .claudeCLI)!
        let delay = deadline.timeIntervalSince(t)
        // Max backoff is 3600s.
        XCTAssertLessThanOrEqual(delay, 3602, "Backoff must not exceed 3600s")
        XCTAssertGreaterThanOrEqual(delay, 3598)
    }

    func testConsecutiveCountIncrements() async {
        let health = ProviderHealth()
        await health.markRateLimited(.anthropic, retryAfter: nil)
        let count1 = await health.consecutiveFailureCount(for: .anthropic)
        XCTAssertEqual(count1, 1)
        await health.markRateLimited(.anthropic, retryAfter: nil)
        let count2 = await health.consecutiveFailureCount(for: .anthropic)
        XCTAssertEqual(count2, 2)
    }

    // MARK: - markHealthy

    func testMarkHealthyClearsDeadline() async {
        let health = ProviderHealth()
        await health.markRateLimited(.anthropic, retryAfter: 60)
        await health.markHealthy(.anthropic)
        let deadline = await health.deadline(for: .anthropic)
        XCTAssertNil(deadline)
        let healthy = await health.isHealthy(.anthropic)
        XCTAssertTrue(healthy)
    }

    func testMarkHealthyResetsConsecutiveCount() async {
        let health = ProviderHealth()
        await health.markRateLimited(.anthropic, retryAfter: nil)
        await health.markRateLimited(.anthropic, retryAfter: nil)
        await health.markHealthy(.anthropic)
        let count = await health.consecutiveFailureCount(for: .anthropic)
        XCTAssertEqual(count, 0)
    }

    func testMarkHealthyAfterHealthyIsNoop() async {
        let health = ProviderHealth()
        await health.markHealthy(.openai)
        let healthy = await health.isHealthy(.openai)
        XCTAssertTrue(healthy)
        let count = await health.consecutiveFailureCount(for: .openai)
        XCTAssertEqual(count, 0)
    }

    // MARK: - Provider isolation

    func testProviderIsolation() async {
        let health = ProviderHealth()
        await health.markRateLimited(.anthropic, retryAfter: 300)
        let openAIHealthy = await health.isHealthy(.openai)
        XCTAssertTrue(openAIHealthy, "Rate-limiting one provider must not affect another")
    }

    // MARK: - AIError Equatable

    func testAIErrorEquatable() {
        XCTAssertEqual(AIError.rateLimited(retryAfter: 60), AIError.rateLimited(retryAfter: 60))
        XCTAssertNotEqual(AIError.rateLimited(retryAfter: 60), AIError.rateLimited(retryAfter: 120))
        XCTAssertEqual(AIError.rateLimited(retryAfter: nil), AIError.rateLimited(retryAfter: nil))
        XCTAssertNotEqual(AIError.rateLimited(retryAfter: nil), AIError.rateLimited(retryAfter: 60))
        XCTAssertEqual(AIError.networkFailure(underlying: "timeout"), AIError.networkFailure(underlying: "timeout"))
        XCTAssertNotEqual(AIError.networkFailure(underlying: "a"), AIError.networkFailure(underlying: "b"))
        XCTAssertNotEqual(AIError.rateLimited(retryAfter: nil), AIError.networkFailure(underlying: "x"))
    }
}
