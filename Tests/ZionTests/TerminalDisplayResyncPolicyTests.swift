import XCTest
@testable import Zion

@MainActor
final class TerminalDisplayResyncPolicyTests: XCTestCase {
    func testCanPerformDisplayResyncRequiresAttachedWindowAndNonZeroBounds() {
        XCTAssertTrue(
            TerminalTabView.Coordinator.canPerformDisplayResync(
                hasWindow: true,
                bounds: CGSize(width: 320, height: 200)
            )
        )
        XCTAssertFalse(
            TerminalTabView.Coordinator.canPerformDisplayResync(
                hasWindow: false,
                bounds: CGSize(width: 320, height: 200)
            )
        )
        XCTAssertFalse(
            TerminalTabView.Coordinator.canPerformDisplayResync(
                hasWindow: true,
                bounds: .zero
            )
        )
    }

    func testShouldRetryDisplayResyncWhileViewIsNotReadyAndAttemptsRemain() {
        XCTAssertTrue(
            TerminalTabView.Coordinator.shouldRetryDisplayResync(
                hasWindow: false,
                bounds: CGSize(width: 320, height: 200),
                attempt: 0,
                maxAttempts: 3
            )
        )
        XCTAssertTrue(
            TerminalTabView.Coordinator.shouldRetryDisplayResync(
                hasWindow: true,
                bounds: .zero,
                attempt: 1,
                maxAttempts: 3
            )
        )
        XCTAssertFalse(
            TerminalTabView.Coordinator.shouldRetryDisplayResync(
                hasWindow: true,
                bounds: CGSize(width: 320, height: 200),
                attempt: 0,
                maxAttempts: 3
            )
        )
        XCTAssertFalse(
            TerminalTabView.Coordinator.shouldRetryDisplayResync(
                hasWindow: false,
                bounds: .zero,
                attempt: 2,
                maxAttempts: 3
            )
        )
    }
}
