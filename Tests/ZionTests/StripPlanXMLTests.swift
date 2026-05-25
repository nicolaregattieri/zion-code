import XCTest
@testable import Zion

final class StripPlanXMLTests: XCTestCase {

    func test_singlePlanBlock_removed() {
        let input = """
        Here is my plan:
        <plan>
          <step>do thing</step>
        </plan>
        Follow-up text.
        """
        let result = ChatService.stripPlanXML(from: input)
        XCTAssertFalse(result.contains("<plan>"))
        XCTAssertFalse(result.contains("</plan>"))
        XCTAssertTrue(result.contains("Here is my plan:"))
        XCTAssertTrue(result.contains("Follow-up text."))
    }

    func test_multiplePlanBlocks_allRemoved() {
        let input = """
        <plan><step>one</step></plan>
        between
        <plan><step>two</step></plan>
        tail
        """
        let result = ChatService.stripPlanXML(from: input)
        XCTAssertFalse(result.contains("<plan>"))
        XCTAssertTrue(result.contains("between"))
        XCTAssertTrue(result.contains("tail"))
    }

    func test_planInsideCodeFence_preserved() {
        let input = """
        Example of the format:
        ```
        <plan>
          <step>example</step>
        </plan>
        ```
        Now your real plan:
        <plan><step>real</step></plan>
        """
        let result = ChatService.stripPlanXML(from: input)
        // The fenced example survives.
        XCTAssertTrue(result.contains("```"))
        XCTAssertTrue(result.contains("<step>example</step>"))
        // The real plan block is stripped.
        XCTAssertFalse(result.contains("<step>real</step>"))
    }

    func test_noPlan_returnsOriginal() {
        let input = "Plain text without any plan markers."
        XCTAssertEqual(ChatService.stripPlanXML(from: input), input)
    }

    func test_malformedPlanWithoutClose_untouched() {
        let input = "Open: <plan> never closed"
        XCTAssertEqual(ChatService.stripPlanXML(from: input), input)
    }
}
