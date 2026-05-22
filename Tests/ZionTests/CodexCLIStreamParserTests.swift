import XCTest
@testable import Zion

final class CodexCLIStreamParserTests: XCTestCase {

    // MARK: - Helpers

    private func data(_ string: String) -> Data {
        string.data(using: .utf8)!
    }

    // MARK: - Agent Message

    func testAgentMessage() {
        let json = """
        {"msg":{"type":"agent_message","text":"Processing your request..."}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertEqual(event, .textDelta("Processing your request..."))
    }

    func testAgentMessageEmptyTextNil() {
        let json = """
        {"msg":{"type":"agent_message","text":""}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertNil(event)
    }

    // MARK: - Function Call Begin

    func testFunctionCallBegin() {
        let json = """
        {"msg":{"type":"function_call_begin","call_id":"c1","function_name":"shell","args":"ls -la"}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        guard case let .toolStart(id, name, description) = event else {
            XCTFail("Expected toolStart, got \(String(describing: event))")
            return
        }
        XCTAssertEqual(id, "c1")
        XCTAssertEqual(name, "shell")
        XCTAssertTrue(description.contains("ls -la"))
    }

    func testFunctionCallBeginArgsTruncatedTo60Chars() {
        let longArgs = String(repeating: "a", count: 100)
        let json = """
        {"msg":{"type":"function_call_begin","call_id":"c2","function_name":"shell","args":"\(longArgs)"}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        guard case let .toolStart(_, _, description) = event else {
            XCTFail("Expected toolStart"); return
        }
        XCTAssertLessThanOrEqual(description.count, 60)
    }

    func testFunctionCallBeginMissingCallIdNil() {
        let json = """
        {"msg":{"type":"function_call_begin","function_name":"shell","args":"ls"}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertNil(event)
    }

    // MARK: - Function Call End

    func testFunctionCallEndSuccess() {
        let json = """
        {"msg":{"type":"function_call_end","call_id":"c1","exit_code":0}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertEqual(event, .toolEnd(id: "c1", success: true))
    }

    func testFunctionCallEndFailure() {
        let json = """
        {"msg":{"type":"function_call_end","call_id":"c1","exit_code":1}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertEqual(event, .toolEnd(id: "c1", success: false))
    }

    func testFunctionCallEndNonZeroExitFailure() {
        let json = """
        {"msg":{"type":"function_call_end","call_id":"c3","exit_code":127}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertEqual(event, .toolEnd(id: "c3", success: false))
    }

    func testFunctionCallEndMissingExitCodeDefaultsToFailure() {
        let json = """
        {"msg":{"type":"function_call_end","call_id":"c4"}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertEqual(event, .toolEnd(id: "c4", success: false))
    }

    // MARK: - Task Complete

    func testTaskComplete() {
        let json = """
        {"msg":{"type":"task_complete"}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertEqual(event, .done)
    }

    // MARK: - Malformed / Nil cases

    func testMalformedNil() {
        let event = AIClient.parseCodexJSONLLine(data("garbage line !!"))
        XCTAssertNil(event)
    }

    func testEmptyDataNil() {
        let event = AIClient.parseCodexJSONLLine(Data())
        XCTAssertNil(event)
    }

    func testMissingMsgKeyNil() {
        let json = """
        {"type":"agent_message","text":"hello"}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertNil(event)
    }

    func testUnknownMsgTypeNil() {
        let json = """
        {"msg":{"type":"heartbeat","ts":1234567890}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertNil(event)
    }
}
