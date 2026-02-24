import XCTest
@testable import Zion

final class TerminalShellEscapingTests: XCTestCase {
    func testQuotePathSimple() {
        XCTAssertEqual(
            TerminalShellEscaping.quotePath("/tmp/file.txt"),
            "'/tmp/file.txt'"
        )
    }

    func testQuotePathEscapesSingleQuotes() {
        XCTAssertEqual(
            TerminalShellEscaping.quotePath("/tmp/it's me.txt"),
            "'/tmp/it'\\''s me.txt'"
        )
    }

    func testJoinQuotedPathsUsesSpaceSeparatorAndSkipsEmpty() {
        XCTAssertEqual(
            TerminalShellEscaping.joinQuotedPaths(["/tmp/one", "", "/tmp/two files"]),
            "'/tmp/one' '/tmp/two files'"
        )
    }

    func testJoinQuotedFileURLsFiltersNonFileURLsAndPreservesOrder() {
        let first = URL(fileURLWithPath: "/tmp/first file.txt")
        let second = URL(fileURLWithPath: "/tmp/second's file.txt")
        let remote = URL(string: "https://example.com/file.txt")!

        XCTAssertEqual(
            TerminalShellEscaping.joinQuotedFileURLs([first, remote, second]),
            "'/tmp/first file.txt' '/tmp/second'\\''s file.txt'"
        )
    }
}
