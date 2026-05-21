import XCTest
@testable import Zion

final class LocalSSEStreamParserTests: XCTestCase {

    // MARK: - Helpers

    private func line(_ string: String) -> Data {
        Data(string.utf8)
    }

    // MARK: - Tests

    func testParsesIncrementalDeltas() {
        let lines = [
            #"data: {"choices":[{"delta":{"content":"hello"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{"content":" world"},"finish_reason":null}]}"#,
        ]

        let chunks = lines.compactMap { AIClient.parseOpenAISSELine(line($0)) }

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].text, "hello")
        XCTAssertFalse(chunks[0].done)
        XCTAssertEqual(chunks[1].text, " world")
        XCTAssertFalse(chunks[1].done)
    }

    func testStopsOnDoneSentinel() {
        let doneLine = "data: [DONE]"
        let chunk = AIClient.parseOpenAISSELine(line(doneLine))

        XCTAssertNotNil(chunk)
        XCTAssertTrue(chunk!.done)
        XCTAssertEqual(chunk!.text, "")
    }

    func testHandlesEmptyAndCommentLines() {
        let inputs = [
            "",
            "   ",
            ": keepalive",
            ": ",
        ]

        for input in inputs {
            let result = AIClient.parseOpenAISSELine(line(input))
            XCTAssertNil(result, "Expected nil for input: \(input.debugDescription)")
        }
    }

    func testStopsOnFinishReason() {
        let stopLine = #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#
        let chunk = AIClient.parseOpenAISSELine(line(stopLine))

        XCTAssertNotNil(chunk)
        XCTAssertTrue(chunk!.done)
        XCTAssertEqual(chunk!.text, "")
    }
}
