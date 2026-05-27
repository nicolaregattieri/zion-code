import XCTest
@testable import Zion

/// Regression guard for the SEARCH/REPLACE marker leak (#38).
/// `ChatService.stripEditBlockMarkers(from:)` is wired into `consumeStream`
/// at 4 call sites. This test pins the contract: any text that contained a
/// well-formed marker block MUST come back without `<<<<<<< SEARCH`,
/// `=======`, or `>>>>>>> REPLACE` after the strip pass.
final class EditBlockParserDispatchTests: XCTestCase {

    func test_streamingResponse_strippedMarkersInBubble() throws {
        let raw = """
        Sure, here's the change:

        <<<<<<< SEARCH: Sources/Zion/Sample.swift
        old line
        =======
        new line
        >>>>>>> REPLACE

        Done.
        """

        let stripped = ChatService.stripEditBlockMarkers(from: raw)

        XCTAssertFalse(stripped.contains("<<<<<<< SEARCH"),
                       "SEARCH marker leaked into the bubble body")
        XCTAssertFalse(stripped.contains("======="),
                       "separator marker leaked into the bubble body")
        XCTAssertFalse(stripped.contains(">>>>>>> REPLACE"),
                       "REPLACE marker leaked into the bubble body")
        XCTAssertTrue(stripped.contains("Sure, here's the change"),
                      "surrounding prose must survive the strip pass")
        XCTAssertTrue(stripped.contains("Done."),
                      "trailing prose must survive the strip pass")
    }

    func test_multipleBlocks_allStripped() throws {
        let raw = """
        First:

        <<<<<<< SEARCH: a.swift
        x
        =======
        y
        >>>>>>> REPLACE

        Second:

        <<<<<<< SEARCH: b.swift
        z
        =======
        w
        >>>>>>> REPLACE
        """

        let stripped = ChatService.stripEditBlockMarkers(from: raw)

        XCTAssertFalse(stripped.contains("<<<<<<< SEARCH"))
        XCTAssertFalse(stripped.contains(">>>>>>> REPLACE"))
        XCTAssertTrue(stripped.contains("First:"))
        XCTAssertTrue(stripped.contains("Second:"))
    }

    func test_proseWithoutMarkers_unchanged() throws {
        let raw = "Just a plain assistant reply with no edit blocks."
        let stripped = ChatService.stripEditBlockMarkers(from: raw)
        XCTAssertEqual(stripped, raw)
    }
}
