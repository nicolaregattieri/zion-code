// CapabilityProbeTests.swift

import XCTest
@testable import Zion

@MainActor
final class CapabilityProbeTests: XCTestCase {

    // MARK: - Setup

    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CapabilityProbeTests_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeProbe() -> CapabilityProbe {
        let d = self.defaults!
        return CapabilityProbe(defaults: d)
    }

    // MARK: - Tests: Cache miss calls probe

    func test_cacheMiss_callsProbeAndCachesResult() async {
        let probe = makeProbe()

        let counter = _ProbeCallCounter()
        let result = await probe.supportsTools(provider: .openai, modelID: "gpt-4o") {
            counter.n += 1
            return true
        }

        XCTAssertTrue(result)
        XCTAssertEqual(counter.n, 1)
    }

    // MARK: - Tests: Cache hit skips probe

    func test_cacheHit_skipsProbe() async {
        let probe = makeProbe()

        // First call stores the result
        _ = await probe.supportsTools(provider: .openai, modelID: "gpt-4o") { true }

        // Second call should NOT invoke the probe again
        let counter = _ProbeCallCounter()
        let result = await probe.supportsTools(provider: .openai, modelID: "gpt-4o") {
            counter.n += 1
            return false
        }

        XCTAssertTrue(result)   // returns cached positive
        XCTAssertEqual(counter.n, 0)
    }

    // MARK: - Tests: Negative result is cached

    func test_negativeResult_isCached() async {
        let probe = makeProbe()

        // Cache a negative result
        _ = await probe.supportsTools(provider: .gemini, modelID: "gemini-flash") { false }

        // Second call returns the cached false without re-running probe
        let counter = _ProbeCallCounter()
        let result = await probe.supportsTools(provider: .gemini, modelID: "gemini-flash") {
            counter.n += 1
            return true
        }

        XCTAssertFalse(result)
        XCTAssertEqual(counter.n, 0)
    }

    // MARK: - Tests: Stale cache re-runs probe

    func test_staleCache_reRunsProbe() async {
        let probe = makeProbe()

        // Inject an old cache entry (25 hours ago — beyond 24h TTL)
        let oldDate = Date().addingTimeInterval(-(CapabilityProbe.ttlSeconds + 3_600))
        probe.injectCacheEntry(provider: .openai, modelID: "gpt-4o", supported: true, checkedAt: oldDate)

        let counter = _ProbeCallCounter()
        let result = await probe.supportsTools(provider: .openai, modelID: "gpt-4o") {
            counter.n += 1
            return false  // probe now returns false
        }

        XCTAssertFalse(result)
        XCTAssertEqual(counter.n, 1)  // probe was re-run
    }

    // MARK: - Tests: Fresh cache within TTL is respected

    func test_freshCache_withinTTL_skipsProbe() async {
        let probe = makeProbe()

        // Inject a fresh entry (1 hour ago — within 24h TTL)
        let recentDate = Date().addingTimeInterval(-3_600)
        probe.injectCacheEntry(provider: .anthropic, modelID: "claude-3-5-sonnet", supported: true, checkedAt: recentDate)

        let counter = _ProbeCallCounter()
        let result = await probe.supportsTools(provider: .anthropic, modelID: "claude-3-5-sonnet") {
            counter.n += 1
            return false
        }

        XCTAssertTrue(result)    // returns cached true
        XCTAssertEqual(counter.n, 0)
    }

    // MARK: - Tests: Probe throwing defaults to false

    func test_probeThrows_defaultsFalse() async {
        let probe = makeProbe()

        let result = await probe.supportsTools(provider: .local, modelID: "llama3") {
            throw NSError(domain: "test", code: 1)
        }

        XCTAssertFalse(result)
    }

    // MARK: - Tests: Different providers cached independently

    func test_differentProviders_cachedIndependently() async {
        let probe = makeProbe()

        _ = await probe.supportsTools(provider: .openai, modelID: "gpt-4o") { true }
        _ = await probe.supportsTools(provider: .anthropic, modelID: "gpt-4o") { false }

        let openaiCounter = _ProbeCallCounter()
        let anthropicCounter = _ProbeCallCounter()

        let openaiResult = await probe.supportsTools(provider: .openai, modelID: "gpt-4o") {
            openaiCounter.n += 1; return false
        }
        let anthropicResult = await probe.supportsTools(provider: .anthropic, modelID: "gpt-4o") {
            anthropicCounter.n += 1; return true
        }

        XCTAssertTrue(openaiResult)
        XCTAssertFalse(anthropicResult)
        XCTAssertEqual(openaiCounter.n, 0)
        XCTAssertEqual(anthropicCounter.n, 0)
    }

    // MARK: - Tests: Evict clears cache

    func test_evict_clearsCacheEntry() async {
        let probe = makeProbe()

        _ = await probe.supportsTools(provider: .openai, modelID: "gpt-4o") { true }

        probe.evict(provider: .openai, modelID: "gpt-4o")

        let counter = _ProbeCallCounter()
        _ = await probe.supportsTools(provider: .openai, modelID: "gpt-4o") {
            counter.n += 1
            return false
        }

        XCTAssertEqual(counter.n, 1)  // probe re-ran after eviction
    }

    // MARK: - Tests: TTL boundary (exactly at 24h is stale)

    func test_exactTTL_boundary_isStale() async {
        let probe = makeProbe()

        // Inject exactly at TTL boundary
        let exactTTLDate = Date().addingTimeInterval(-CapabilityProbe.ttlSeconds)
        probe.injectCacheEntry(provider: .openai, modelID: "model-x", supported: true, checkedAt: exactTTLDate)

        let counter = _ProbeCallCounter()
        _ = await probe.supportsTools(provider: .openai, modelID: "model-x") {
            counter.n += 1
            return false
        }

        // Should have re-run since age >= TTL
        XCTAssertEqual(counter.n, 1)
    }
}

/// Reference-typed counter so `@Sendable` probe closures can mutate count.
/// `@unchecked Sendable` is safe: tests await every probe before reading.
private final class _ProbeCallCounter: @unchecked Sendable {
    var n: Int = 0
}
