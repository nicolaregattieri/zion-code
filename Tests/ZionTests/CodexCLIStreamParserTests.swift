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
        XCTAssertEqual(event, .toolEnd(id: "c1", success: true, output: nil))
    }

    func testFunctionCallEndFailure() {
        let json = """
        {"msg":{"type":"function_call_end","call_id":"c1","exit_code":1}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertEqual(event, .toolEnd(id: "c1", success: false, output: nil))
    }

    func testFunctionCallEndNonZeroExitFailure() {
        let json = """
        {"msg":{"type":"function_call_end","call_id":"c3","exit_code":127}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertEqual(event, .toolEnd(id: "c3", success: false, output: nil))
    }

    func testFunctionCallEndMissingExitCodeDefaultsToFailure() {
        let json = """
        {"msg":{"type":"function_call_end","call_id":"c4"}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertEqual(event, .toolEnd(id: "c4", success: false, output: nil))
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

    func testUnknownMsgTypeNil() {
        let json = """
        {"msg":{"type":"heartbeat","ts":1234567890}}
        """
        let event = AIClient.parseCodexJSONLLine(data(json))
        XCTAssertNil(event)
    }

    // MARK: - v0.131+ schema (top-level type + nested item)

    func testV0131AgentMessage() {
        let json = #"{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"Hi there friend"}}"#
        XCTAssertEqual(AIClient.parseCodexJSONLLine(data(json)), .textDelta("Hi there friend"))
    }

    func testV0131TurnCompleted() {
        let json = #"{"type":"turn.completed","usage":{"input_tokens":1}}"#
        XCTAssertEqual(AIClient.parseCodexJSONLLine(data(json)), .done)
    }

    func testV0131TurnCompletedEventsEmitUsageThenDone() {
        let json = #"{"type":"turn.completed","usage":{"input_tokens":28298,"output_tokens":7}}"#
        let events = AIClient.parseCodexJSONLEvents(data(json))
        XCTAssertEqual(events, [.turnUsage(inputTokens: 28298, outputTokens: 7), .done])
    }

    func testV0131ThreadStartedYieldsSessionID() {
        let json = #"{"type":"thread.started","thread_id":"abc"}"#
        XCTAssertEqual(AIClient.parseCodexJSONLLine(data(json)), .sessionStarted(id: "abc"))
    }

    func testV0131FunctionCall() {
        let json = #"{"type":"item.completed","item":{"id":"call_1","type":"function_call","name":"shell","arguments":"ls -la"}}"#
        let event = AIClient.parseCodexJSONLLine(data(json))
        if case .toolStart(let id, let name, let desc) = event {
            XCTAssertEqual(id, "call_1")
            XCTAssertEqual(name, "shell")
            XCTAssertEqual(desc, "ls -la")
        } else {
            XCTFail("Expected toolStart, got \(String(describing: event))")
        }
    }

    func testV0131Error() {
        let json = #"{"type":"error","message":"network unreachable"}"#
        if case .error(let m) = AIClient.parseCodexJSONLLine(data(json)) {
            XCTAssertEqual(m, "network unreachable")
        } else {
            XCTFail("Expected .error event")
        }
    }
}
