import XCTest
import SwiftTerm
@testable import Zion

@MainActor
final class ZionTerminalViewTests: XCTestCase {
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
