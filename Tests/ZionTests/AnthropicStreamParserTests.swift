import XCTest
@testable import Zion

final class AnthropicStreamParserTests: XCTestCase {

    // MARK: - Helpers

    private func data(_ string: String) -> Data {
        string.data(using: .utf8)!
    }

    // MARK: - Tests

    func testContentBlockTextDelta() throws {
        let json = """
        {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
        """
        let chunk = AIClient.parseAnthropicSSEEvent(eventName: "content_block_delta", data: data(json))
        XCTAssertNotNil(chunk)
        XCTAssertEqual(chunk?.text, "Hello")
        XCTAssertEqual(chunk?.done, false)
    }

    func testNonTextDeltaIgnored() throws {
        let json = """
        {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{}"}}
        """
        let chunk = AIClient.parseAnthropicSSEEvent(eventName: "content_block_delta", data: data(json))
        XCTAssertNil(chunk)
    }

    func testMessageStopMarksDone() throws {
        let json = """
        {"type":"message_stop"}
        """
        let chunk = AIClient.parseAnthropicSSEEvent(eventName: "message_stop", data: data(json))
        XCTAssertNotNil(chunk)
        XCTAssertEqual(chunk?.text, "")
        XCTAssertEqual(chunk?.done, true)
    }

    func testMalformedJSONReturnsNil() throws {
        let malformed = data("{not valid json!!!}")
        let chunk = AIClient.parseAnthropicSSEEvent(eventName: "content_block_delta", data: malformed)
        XCTAssertNil(chunk)
    }

    func testUnknownEventReturnsNil() throws {
        let json = """
        {"type":"ping"}
        """
        let chunk = AIClient.parseAnthropicSSEEvent(eventName: "ping", data: data(json))
        XCTAssertNil(chunk)
    }

    // MARK: - Additional coverage for ignored event types

    func testMessageStartReturnsNil() {
        let chunk = AIClient.parseAnthropicSSEEvent(
            eventName: "message_start",
            data: data(#"{"type":"message_start"}"#)
        )
        XCTAssertNil(chunk)
    }

    func testContentBlockStartReturnsNil() {
        let chunk = AIClient.parseAnthropicSSEEvent(
            eventName: "content_block_start",
            data: data(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
        )
        XCTAssertNil(chunk)
    }

    func testContentBlockStopReturnsNil() {
        let chunk = AIClient.parseAnthropicSSEEvent(
            eventName: "content_block_stop",
            data: data(#"{"type":"content_block_stop","index":0}"#)
        )
        XCTAssertNil(chunk)
    }

    func testMessageDeltaReturnsNil() {
        let chunk = AIClient.parseAnthropicSSEEvent(
            eventName: "message_delta",
            data: data(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#)
        )
        XCTAssertNil(chunk)
    }
}
