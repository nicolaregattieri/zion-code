import XCTest
@testable import Zion

final class ClaudeCLIStreamParserTests: XCTestCase {

    // MARK: - Helpers

    private func data(_ string: String) -> Data {
        string.data(using: .utf8)!
    }

    // MARK: - Text Delta

    func testTextDelta() {
        let json = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        XCTAssertEqual(event, .textDelta("hello"))
    }

    func testTextDeltaMultipleSegmentsConcatenated() {
        let json = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"foo"},{"type":"text","text":"bar"}]}}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        XCTAssertEqual(event, .textDelta("foobar"))
    }

    func testTextDeltaSkipsNonTextBlocks() {
        let json = """
        {"type":"assistant","message":{"content":[{"type":"image","source":{}},{"type":"text","text":"hello"}]}}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        XCTAssertEqual(event, .textDelta("hello"))
    }

    // MARK: - Tool Use (AC #15)

    func testToolUseEventEmission() {
        let json = """
        {"type":"tool_use","id":"t1","name":"Bash","input":{"command":"git status"}}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        guard case let .toolStart(id, name, description) = event else {
            XCTFail("Expected toolStart, got \(String(describing: event))")
            return
        }
        XCTAssertEqual(id, "t1")
        XCTAssertEqual(name, "Bash")
        XCTAssertTrue(description.contains("git status"), "description '\(description)' should contain 'git status'")
    }

    func testToolUseFilePathKey() {
        let json = """
        {"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"/tmp/foo.swift"}}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        guard case let .toolStart(_, _, description) = event else {
            XCTFail("Expected toolStart"); return
        }
        XCTAssertTrue(description.contains("/tmp/foo.swift"))
    }

    func testToolUseDescriptionTruncatedTo60Chars() {
        let longCommand = String(repeating: "x", count: 100)
        let json = """
        {"type":"tool_use","id":"t3","name":"Bash","input":{"command":"\(longCommand)"}}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        guard case let .toolStart(_, _, description) = event else {
            XCTFail("Expected toolStart"); return
        }
        XCTAssertLessThanOrEqual(description.count, 60)
    }

    // MARK: - Tool Result

    func testToolResultSuccess() {
        let json = """
        {"type":"tool_result","tool_use_id":"t1","is_error":false}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        XCTAssertEqual(event, .toolEnd(id: "t1", success: true))
    }

    func testToolResultFailure() {
        let json = """
        {"type":"tool_result","tool_use_id":"t1","is_error":true}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        XCTAssertEqual(event, .toolEnd(id: "t1", success: false))
    }

    func testToolResultDefaultsToSuccessWhenIsErrorAbsent() {
        let json = """
        {"type":"tool_result","tool_use_id":"t2"}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        XCTAssertEqual(event, .toolEnd(id: "t2", success: true))
    }

    // MARK: - Done

    func testResultDone() {
        let json = """
        {"type":"result","subtype":"success","cost_usd":0.01}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        XCTAssertEqual(event, .done)
    }

    // MARK: - Error

    func testErrorEvent() {
        let json = """
        {"type":"error","message":"API key invalid"}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        XCTAssertEqual(event, .error("API key invalid"))
    }

    func testErrorEventFallbackMessage() {
        let json = """
        {"type":"error"}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        XCTAssertEqual(event, .error("Unknown error"))
    }

    // MARK: - Malformed / Nil cases

    func testMalformedNil() {
        let event = AIClient.parseClaudeJSONLLine(data("not json at all !!"))
        XCTAssertNil(event)
    }

    func testEmptyDataNil() {
        let event = AIClient.parseClaudeJSONLLine(Data())
        XCTAssertNil(event)
    }

    func testUnknownTypeNil() {
        let json = """
        {"type":"system","message":"something"}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        XCTAssertNil(event)
    }

    func testMissingTypeNil() {
        let json = """
        {"content":"hello"}
        """
        let event = AIClient.parseClaudeJSONLLine(data(json))
        XCTAssertNil(event)
    }
}
