import XCTest
@testable import Zion

@MainActor
final class ThrottlerTests: XCTestCase {

    func testFirstCallFiresImmediately() async throws {
        let throttler = Throttler(interval: 0)
        var fired = 0

        throttler.schedule {
            fired += 1
        }

        // Give the Task a tick to run.
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(fired, 1, "First schedule should fire")
    }

    func testBurstCollapsesToAtMostTwoRuns() async throws {
        let throttler = Throttler(interval: 0)
        var fired = 0

        // Fire a burst of 100 schedules; throttler should collapse to current + one follow-up.
        for _ in 0..<100 {
            throttler.schedule {
                fired += 1
                // Make current take a tiny bit of time so subsequent schedules
                // coalesce into `next` instead of each becoming a new current.
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }

        // Wait long enough for current + follow-up to complete.
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertLessThanOrEqual(fired, 2, "Throttler must collapse a 100-call burst to ≤ 2 runs (got \(fired))")
        XCTAssertGreaterThanOrEqual(fired, 1, "At least one run must have happened")
    }

    func testSequentialIdleAllowsMultiple() async throws {
        let throttler = Throttler(interval: 0)
        var fired = 0

        for _ in 0..<3 {
            throttler.schedule { fired += 1 }
            try await Task.sleep(nanoseconds: 30_000_000) // let it fire + drain
        }

        XCTAssertEqual(fired, 3, "Idle between calls means each fires")
    }

    func testCancelClearsPending() async throws {
        let throttler = Throttler(interval: 0)
        var fired = 0

        throttler.schedule {
            try? await Task.sleep(nanoseconds: 50_000_000)
            fired += 1
        }
        throttler.schedule { fired += 10 } // queued as next
        throttler.cancel()

        try await Task.sleep(nanoseconds: 150_000_000)
        // The first run may or may not have finished depending on timing;
        // the key invariant is that the queued next never fires.
        XCTAssertLessThan(fired, 10, "Cancelled throttler must not run the queued follow-up")
    }
}
