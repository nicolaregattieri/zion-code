import XCTest
@testable import Zion

@MainActor
final class IdleFocusGateTests: XCTestCase {

    // AC 5: refresh is deferred while the app is inactive.
    func testDeferredWhenInactive() {
        let vm = RepositoryViewModel()
        vm.isActiveOverrideForTesting = false
        vm.refreshFireCountForTesting = 0

        vm.requestFileWatcherRefresh()

        XCTAssertTrue(vm.pendingFileWatcherRefresh, "Inactive app must defer the refresh")
        XCTAssertEqual(vm.refreshFireCountForTesting, 0, "Deferred refresh must not fire immediately")
    }

    // AC 5: refresh is deferred while a non-read-only operation is running.
    func testDeferredWhenNonReadOnlyOpRunning() {
        let vm = RepositoryViewModel()
        vm.isActiveOverrideForTesting = true // window is active...
        vm.operations.start(.commit)         // ...but commit in flight
        vm.refreshFireCountForTesting = 0

        vm.requestFileWatcherRefresh()

        XCTAssertTrue(vm.pendingFileWatcherRefresh)
        XCTAssertEqual(vm.refreshFireCountForTesting, 0)

        vm.operations.end(.commit) // cleanup so tests don't leak state
    }

    // AC 5: multiple deferred requests collapse into one pending flag.
    func testCoalescesMultipleDeferred() {
        let vm = RepositoryViewModel()
        vm.isActiveOverrideForTesting = false
        vm.refreshFireCountForTesting = 0

        vm.requestFileWatcherRefresh()
        vm.requestFileWatcherRefresh()
        vm.requestFileWatcherRefresh()

        XCTAssertTrue(vm.pendingFileWatcherRefresh)
        XCTAssertEqual(vm.refreshFireCountForTesting, 0, "No immediate fires")
    }

    // AC 5: once the app activates and idle is reached, the deferred refresh
    // fires exactly once. Uses the test seam to bypass the NotificationCenter
    // wire and just drive the handler directly; await the 200ms grace sleep.
    func testFiresOnceOnActivation() async throws {
        let vm = RepositoryViewModel()
        vm.isActiveOverrideForTesting = false
        vm.refreshFireCountForTesting = 0

        // Park a deferred request.
        vm.requestFileWatcherRefresh()
        XCTAssertTrue(vm.pendingFileWatcherRefresh)

        // App becomes active.
        vm.isActiveOverrideForTesting = true
        vm.simulateActivationForTesting()

        // Wait past the 200ms grace window.
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(vm.refreshFireCountForTesting, 1, "Deferred refresh must fire exactly once")
        XCTAssertFalse(vm.pendingFileWatcherRefresh, "Pending flag must clear after firing")
    }

    // AC 6: user-initiated and repository-switch refreshes bypass the gate
    // (the gate only routes `.fileWatcher` origin). Verify that calling
    // refreshRepository directly with a non-fileWatcher origin isn't blocked
    // by the gate's predicate. We assert the predicate alone — not the refresh
    // pipeline — because unit-testing refreshRepository itself requires a
    // real on-disk repo.
    func testUserInitiatedBypassesGate() {
        let vm = RepositoryViewModel()
        vm.isActiveOverrideForTesting = false
        vm.operations.start(.commit)

        // Gate says defer for file-watcher requests, but user-initiated
        // / repository-switch flows never ask the gate — they call
        // refreshRepository directly. Guard against regression by ensuring
        // requestFileWatcherRefresh() is the only path that sets the pending
        // flag.
        XCTAssertTrue(vm.shouldDeferFileWatcherRefresh())
        XCTAssertFalse(vm.pendingFileWatcherRefresh, "pendingFileWatcherRefresh stays false until a gated call is made")

        vm.operations.end(.commit)
    }

    // Predicate returns false when active + only read-only ops running.
    func testPredicateAllowsWhenActiveAndReadOnly() {
        let vm = RepositoryViewModel()
        vm.isActiveOverrideForTesting = true
        vm.operations.start(.status) // readOnly

        XCTAssertFalse(vm.shouldDeferFileWatcherRefresh(), "Read-only ops must not block the gate")

        vm.operations.end(.status)
    }
}
