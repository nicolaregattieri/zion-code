import XCTest
@testable import Zion

final class RepositoryRefreshPolicyTests: XCTestCase {
    @MainActor
    func testFileWatcherRefreshIsNotSkippedWhileBusy() {
        XCTAssertFalse(
            RepositoryViewModel.shouldSkipRefreshWhileBusy(
                setBusy: false,
                isBusy: true,
                origin: .fileWatcher
            )
        )
    }

    @MainActor
    func testAutoTimerRefreshIsSkippedWhileBusy() {
        XCTAssertTrue(
            RepositoryViewModel.shouldSkipRefreshWhileBusy(
                setBusy: false,
                isBusy: true,
                origin: .autoTimer
            )
        )
    }
}
