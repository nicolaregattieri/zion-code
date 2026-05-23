import XCTest
@testable import Zion

final class AIClientGeminiToolUseTests: XCTestCase {

    // MARK: - Text accumulation

    func testTextAccumulationProducesEndTurn() {
        let sse = """
        data: {"candidates":[{"content":{"parts":[{"text":"hello "}]},"finishReason":"STOP"}]}

        data: {"candidates":[{"content":{"parts":[{"text":"world"}]}}]}

        """
        let outcome = AIClient.parseGeminiSSE(sse, history: [])
        XCTAssertEqual(outcome.text, "hello world")
        XCTAssertEqual(outcome.stopReason, .endTurn)
        XCTAssertTrue(outcome.toolCalls.isEmpty)
    }

    // MARK: - Function call

    func testFunctionCallProducesToolUseStopReason() {
        let sse = """
        data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"read_file","args":{"path":"X"}}}]}}]}

        """
        let outcome = AIClient.parseGeminiSSE(sse, history: [])
        XCTAssertEqual(outcome.stopReason, .toolUse)
        XCTAssertEqual(outcome.toolCalls.count, 1)
        XCTAssertEqual(outcome.toolCalls[0].name, "read_file")
        XCTAssertEqual(outcome.toolCalls[0].args["path"] as? String, "X")
        XCTAssertFalse(outcome.toolCalls[0].id.isEmpty)
    }

    // MARK: - MAX_TOKENS finish reason

    func testMaxTokensFinishReasonMapsToMaxTokens() {
        let sse = """
        data: {"candidates":[{"content":{"parts":[{"text":"truncated"}]},"finishReason":"MAX_TOKENS"}]}

        """
        let outcome = AIClient.parseGeminiSSE(sse, history: [])
        XCTAssertEqual(outcome.stopReason, .maxTokens)
        XCTAssertEqual(outcome.text, "truncated")
    }

    // MARK: - supportsToolCalling for Gemini

    func testGeminiProviderSupportsToolCalling() {
        XCTAssertTrue(AIProvider.gemini.supportsToolCalling)
    }

    func testNoneProviderDoesNotSupportToolCalling() {
        XCTAssertFalse(AIProvider.none.supportsToolCalling)
    }
}
