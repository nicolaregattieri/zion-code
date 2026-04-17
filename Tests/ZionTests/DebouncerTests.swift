import XCTest
@testable import Zion

@MainActor
final class DebouncerTests: XCTestCase {

    func testScheduleFiresAfterInterval() async throws {
        let debouncer = Debouncer(interval: 50_000_000) // 50ms
        var fired = 0
        debouncer.schedule { fired += 1 }

        XCTAssertEqual(fired, 0, "Debouncer must not fire synchronously")

        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        XCTAssertEqual(fired, 1, "Debouncer must fire once after interval")
    }

    func testRescheduleCancelsPrior() async throws {
        let debouncer = Debouncer(interval: 100_000_000) // 100ms
        var fired = 0
        debouncer.schedule { fired += 1 }
        try await Task.sleep(nanoseconds: 20_000_000)
        debouncer.schedule { fired += 1 } // reschedules — prior should cancel
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(fired, 1, "Only the latest scheduled closure should fire")
    }

    func testCancelPreventsFire() async throws {
        let debouncer = Debouncer(interval: 50_000_000)
        var fired = 0
        debouncer.schedule { fired += 1 }
        debouncer.cancel()
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(fired, 0, "Cancelled debouncer must not fire")
    }

    func testZeroIntervalStillYields() async throws {
        let debouncer = Debouncer(interval: 0)
        var fired = 0
        debouncer.schedule { fired += 1 }

        XCTAssertEqual(fired, 0, "Even interval 0 yields to the run loop")

        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(fired, 1)
    }

    func testDeinitCancelsPending() async throws {
        var fired = 0
        do {
            let debouncer = Debouncer(interval: 200_000_000)
            debouncer.schedule { fired += 1 }
        } // out of scope — deinit
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(fired, 0, "Deinit must cancel the pending work")
    }
}
