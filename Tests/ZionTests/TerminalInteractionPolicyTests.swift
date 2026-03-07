import XCTest
@testable import Zion

@MainActor
final class TerminalInteractionPolicyTests: XCTestCase {
    func testShouldStartDragFreezeWhenSelectionTakesPriority() {
        XCTAssertTrue(
            TerminalTabView.Coordinator.shouldStartDragFreeze(
                isPointerDownInTerminal: true,
                isTerminalFocused: true,
                allowMouseReporting: true,
                prioritizeSelectionInteraction: true
            )
        )
    }

    func testShouldNotStartDragFreezeWhenNotFocusedOrNotDragging() {
        XCTAssertFalse(
            TerminalTabView.Coordinator.shouldStartDragFreeze(
                isPointerDownInTerminal: false,
                isTerminalFocused: true,
                allowMouseReporting: true,
                prioritizeSelectionInteraction: true
            )
        )
        XCTAssertFalse(
            TerminalTabView.Coordinator.shouldStartDragFreeze(
                isPointerDownInTerminal: true,
                isTerminalFocused: false,
                allowMouseReporting: true,
                prioritizeSelectionInteraction: true
            )
        )
    }

    func testShouldNotStartDragFreezeWhenMouseReportingDisabledOrSelectionNotPrioritized() {
        XCTAssertFalse(
            TerminalTabView.Coordinator.shouldStartDragFreeze(
                isPointerDownInTerminal: true,
                isTerminalFocused: true,
                allowMouseReporting: false,
                prioritizeSelectionInteraction: true
            )
        )
        XCTAssertFalse(
            TerminalTabView.Coordinator.shouldStartDragFreeze(
                isPointerDownInTerminal: true,
                isTerminalFocused: true,
                allowMouseReporting: true,
                prioritizeSelectionInteraction: false
            )
        )
    }

    func testShouldForceFlushWhileDragFrozenAtLimit() {
        XCTAssertFalse(
            TerminalTabView.Coordinator.shouldForceFlushWhileDragFrozen(
                bufferedByteCount: 1023,
                maxBufferedBytes: 1024
            )
        )
        XCTAssertTrue(
            TerminalTabView.Coordinator.shouldForceFlushWhileDragFrozen(
                bufferedByteCount: 1024,
                maxBufferedBytes: 1024
            )
        )
        XCTAssertTrue(
            TerminalTabView.Coordinator.shouldForceFlushWhileDragFrozen(
                bufferedByteCount: 2048,
                maxBufferedBytes: 1024
            )
        )
    }
}
