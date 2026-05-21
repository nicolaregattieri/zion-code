import XCTest
@testable import Zion

final class OpenAIStreamParserTests: XCTestCase {

    // MARK: - Helpers

    private func line(_ string: String) -> Data {
        Data(string.utf8)
    }

    // MARK: - Tests

    func testCloudDeltaContentExtracted() {
        let input = #"data: {"choices":[{"delta":{"content":"hi"}}]}"#
        let chunk = AIClient.parseOpenAISSELine(line(input))

        XCTAssertNotNil(chunk)
        XCTAssertEqual(chunk!.text, "hi")
        XCTAssertFalse(chunk!.done)
    }

    func testCloudDoneSentinel() {
        let input = "data: [DONE]"
        let chunk = AIClient.parseOpenAISSELine(line(input))

        XCTAssertNotNil(chunk)
        XCTAssertTrue(chunk!.done)
        XCTAssertEqual(chunk!.text, "")
    }

    func testCloudFinishReasonMarksDone() {
        let input = #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#
        let chunk = AIClient.parseOpenAISSELine(line(input))

        XCTAssertNotNil(chunk)
        XCTAssertTrue(chunk!.done)
    }

    func testCloudEmptyDeltaSkipped() {
        let input = #"data: {"choices":[{"delta":{}}]}"#
        let chunk = AIClient.parseOpenAISSELine(line(input))

        // A delta with no content key should either return nil or return empty non-done text
        if let chunk = chunk {
            XCTAssertEqual(chunk.text, "")
            XCTAssertFalse(chunk.done)
        }
        // nil is also acceptable — empty delta carries no meaningful content
    }
}
