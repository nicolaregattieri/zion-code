import XCTest
import SwiftTerm
@testable import Zion

private actor TerminalProcessOutputRecorder {
    private var payloads: [Data] = []

    func append(_ data: Data) {
        payloads.append(data)
    }

    func allPayloads() -> [Data] {
        payloads
    }
}

@MainActor
final class ZionTerminalViewTests: XCTestCase {
    func testProcessOutputPumpCoalescesRapidChunksIntoSingleFlush() async {
        let expectation = expectation(description: "coalesced flush")
        expectation.expectedFulfillmentCount = 1
        let recorder = TerminalProcessOutputRecorder()

        let pump = TerminalProcessOutputPump(
            label: "test.coalesced",
            flushIntervalNanos: 20_000_000,
            immediateFlushThreshold: 1024
        ) { data in
            Task {
                await recorder.append(data)
                expectation.fulfill()
            }
        }

        pump.enqueue(ArraySlice("hello ".utf8))
        pump.enqueue(ArraySlice("world".utf8))

        await fulfillment(of: [expectation], timeout: 1.0)
        let payloads = await recorder.allPayloads()
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(String(data: payloads[0], encoding: .utf8), "hello world")
    }

    func testProcessOutputPumpFlushesImmediatelyAtThreshold() async {
        let expectation = expectation(description: "threshold flush")
        expectation.expectedFulfillmentCount = 1
        let recorder = TerminalProcessOutputRecorder()

        let pump = TerminalProcessOutputPump(
            label: "test.threshold",
            flushIntervalNanos: 1_000_000_000,
            immediateFlushThreshold: 8
        ) { data in
            Task {
                await recorder.append(data)
                expectation.fulfill()
            }
        }

        pump.enqueue(ArraySlice("1234".utf8))
        pump.enqueue(ArraySlice("5678".utf8))

        await fulfillment(of: [expectation], timeout: 0.2)
        let received = await recorder.allPayloads().first
        XCTAssertEqual(String(data: received ?? Data(), encoding: .utf8), "12345678")
    }

    func testProcessOutputPumpImmediateFlushDecisionUsesThreshold() {
        XCTAssertFalse(
            TerminalProcessOutputPump.shouldFlushImmediately(
                bufferedByteCount: 31_999,
                threshold: 32_000
            )
        )
        XCTAssertTrue(
            TerminalProcessOutputPump.shouldFlushImmediately(
                bufferedByteCount: 32_000,
                threshold: 32_000
            )
        )
    }

    func testPreciseScrollUsesReducedRowHeightForSmootherTrackpadScroll() {
        XCTAssertEqual(
            ZionTerminalView.preciseScrollLineHeight(viewHeight: 180, terminalRows: 10),
            13.5,
            accuracy: 0.001
        )
    }

    func testPreciseScrollLineHeightHasMinimumFloor() {
        XCTAssertEqual(
            ZionTerminalView.preciseScrollLineHeight(viewHeight: 12, terminalRows: 10),
            4,
            accuracy: 0.001
        )
    }

    func testPreciseScrollAccumulatorAdvancesSoonerWithSmootherLineHeight() {
        let result = ZionTerminalView.accumulatePreciseScrollStep(
            accumulator: 0,
            deltaY: 8,
            lineHeight: 6
        )

        XCTAssertEqual(result.lines, 1)
        XCTAssertEqual(result.remainder, 0.3333333333, accuracy: 0.001)
    }

    func testPreciseScrollAccumulatorEmitsLinesWithoutJumpingToLargeStep() {
        let result = ZionTerminalView.accumulatePreciseScrollStep(
            accumulator: 0,
            deltaY: 24,
            lineHeight: 12
        )

        XCTAssertEqual(result.lines, 2)
        XCTAssertEqual(result.remainder, 0, accuracy: 0.001)
    }

    func testPreciseScrollAccumulatorClearsOppositeDirectionRemainder() {
        let result = ZionTerminalView.accumulatePreciseScrollStep(
            accumulator: 0.75,
            deltaY: -8,
            lineHeight: 8
        )

        XCTAssertEqual(result.lines, -1)
        XCTAssertEqual(result.remainder, 0, accuracy: 0.001)
    }

    func testPreciseScrollAccumulatorCapsLargeSingleEvent() {
        let result = ZionTerminalView.accumulatePreciseScrollStep(
            accumulator: 0,
            deltaY: 240,
            lineHeight: 10,
            maxLinesPerEvent: 6
        )

        XCTAssertEqual(result.lines, 6)
        XCTAssertEqual(result.remainder, 18, accuracy: 0.001)
    }

    func testPreciseScrollHandlingRequiresPreciseTrackpadDeltas() {
        XCTAssertTrue(
            ZionTerminalView.shouldHandlePreciseScroll(
                hasPreciseScrollingDeltas: true,
                canScroll: true
            )
        )
        XCTAssertFalse(
            ZionTerminalView.shouldHandlePreciseScroll(
                hasPreciseScrollingDeltas: false,
                canScroll: true
            )
        )
        XCTAssertFalse(
            ZionTerminalView.shouldHandlePreciseScroll(
                hasPreciseScrollingDeltas: true,
                canScroll: false
            )
        )
    }

    func testCoordinatorConsumesPreciseScrollWhenPointerIsOverScrollableTerminal() {
        XCTAssertTrue(
            TerminalTabView.Coordinator.shouldConsumePreciseScroll(
                hasPreciseScrollingDeltas: true,
                isTerminalFocused: true,
                hoveredTerminalMatches: true,
                canTerminalScroll: true
            )
        )
        XCTAssertFalse(
            TerminalTabView.Coordinator.shouldConsumePreciseScroll(
                hasPreciseScrollingDeltas: true,
                isTerminalFocused: true,
                hoveredTerminalMatches: false,
                canTerminalScroll: true
            )
        )
    }

    func testPreciseScrollAccumulatorResetTracksGestureEndAndMomentumEnd() {
        XCTAssertTrue(
            ZionTerminalView.shouldResetPreciseScrollAccumulator(
                phase: .ended,
                momentumPhase: []
            )
        )
        XCTAssertTrue(
            ZionTerminalView.shouldResetPreciseScrollAccumulator(
                phase: [],
                momentumPhase: .cancelled
            )
        )
        XCTAssertFalse(
            ZionTerminalView.shouldResetPreciseScrollAccumulator(
                phase: .began,
                momentumPhase: []
            )
        )
    }

    func testManualScrollFreezeIntentStartsWhenScrollingUpFromLiveBottom() {
        XCTAssertTrue(
            ZionTerminalView.shouldStartManualScrollFreezeIntent(
                scrollingDeltaY: 6,
                scrollPosition: 1,
                canScroll: true
            )
        )
        XCTAssertFalse(
            ZionTerminalView.shouldStartManualScrollFreezeIntent(
                scrollingDeltaY: -6,
                scrollPosition: 1,
                canScroll: true
            )
        )
        XCTAssertFalse(
            ZionTerminalView.shouldStartManualScrollFreezeIntent(
                scrollingDeltaY: 6,
                scrollPosition: 0.5,
                canScroll: true
            )
        )
    }

    func testManualScrollFreezeTracksViewportAwayFromBottom() {
        XCTAssertTrue(
            ZionTerminalView.shouldKeepManualScrollFreeze(
                scrollPosition: 0.5,
                canScroll: true
            )
        )
        XCTAssertFalse(
            ZionTerminalView.shouldKeepManualScrollFreeze(
                scrollPosition: 1,
                canScroll: true
            )
        )
        XCTAssertFalse(
            ZionTerminalView.shouldKeepManualScrollFreeze(
                scrollPosition: 0.5,
                canScroll: false
            )
        )
    }

    func testLiveBottomDetectionTreatsNearBottomAsLive() {
        XCTAssertTrue(ZionTerminalView.isAtLiveBottom(scrollPosition: 1))
        XCTAssertTrue(ZionTerminalView.isAtLiveBottom(scrollPosition: 0.99995))
        XCTAssertFalse(ZionTerminalView.isAtLiveBottom(scrollPosition: 0.99))
    }

    func testIsSubclassOfSwiftTermTerminalView() {
        let view: Any = ZionTerminalView(frame: .zero)
        XCTAssertTrue(view is SwiftTerm.TerminalView)
    }

    func testRegisteredDraggedTypesContainsFileURL() {
        let view = ZionTerminalView(frame: .zero)
        XCTAssertTrue(view.registeredDraggedTypes.contains(.fileURL))
    }

    func testRegisteredDraggedTypesDoesNotContainString() {
        let view = ZionTerminalView(frame: .zero)
        XCTAssertFalse(view.registeredDraggedTypes.contains(.string))
    }

    func testOnFileDropClosureReceivesShellEscapedPaths() {
        let view = ZionTerminalView(frame: .zero)
        var received: String?
        view.onFileDrop = { received = $0 }

        let escaped = TerminalShellEscaping.joinQuotedFileURLs([
            URL(fileURLWithPath: "/tmp/my file.txt"),
        ])
        view.onFileDrop?(escaped)
        XCTAssertEqual(received, "'/tmp/my file.txt'")
    }

    func testLinefeedPreservesSelectionDuringRegularCliOutput() {
        let view = ZionTerminalView(frame: .zero)
        view.feed(text: "hello world")
        view.selectAll(nil)

        XCTAssertGreaterThan(view.selectedRange().length, 0)
        XCTAssertEqual(view.getTerminal().mouseMode, .off)

        view.linefeed(source: view.getTerminal())

        XCTAssertGreaterThan(view.selectedRange().length, 0)
    }

    func testLinefeedPreservesSelectionForMouseReportingApps() {
        let view = ZionTerminalView(frame: .zero)
        view.prioritizeSelectionInteraction = true
        view.feed(text: "\u{1B}[?1000h") // Enable mouse reporting mode.
        view.feed(text: "hello world")
        view.selectAll(nil)

        XCTAssertGreaterThan(view.selectedRange().length, 0)
        XCTAssertNotEqual(view.getTerminal().mouseMode, .off)

        view.linefeed(source: view.getTerminal())

        XCTAssertGreaterThan(view.selectedRange().length, 0)
    }

    func testLinefeedClearsSelectionForMouseReportingWithoutSelectionPriority() {
        let view = ZionTerminalView(frame: .zero)
        view.feed(text: "\u{1B}[?1000h") // Enable mouse reporting mode.
        view.feed(text: "hello world")
        view.selectAll(nil)

        XCTAssertGreaterThan(view.selectedRange().length, 0)
        XCTAssertNotEqual(view.getTerminal().mouseMode, .off)

        view.linefeed(source: view.getTerminal())

        XCTAssertEqual(view.selectedRange().length, 0)
    }

    func testClosestTerminalViewFindsAncestorTerminal() {
        let terminal = ZionTerminalView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let wrapper = NSView(frame: terminal.bounds)
        let nested = NSView(frame: .zero)
        terminal.addSubview(wrapper)
        wrapper.addSubview(nested)

        let resolved = ZionTerminalView.closestTerminalView(from: nested)
        XCTAssertTrue(resolved === terminal)
    }

    func testClosestTerminalViewReturnsNilWhenNoAncestorMatches() {
        let root = NSView(frame: .zero)
        let child = NSView(frame: .zero)
        root.addSubview(child)

        XCTAssertNil(ZionTerminalView.closestTerminalView(from: child))
    }

}
