import XCTest
@testable import Zion

// MARK: - URLProtocol Mock (local to this test file)

private final class ToolStreamMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseStatusCode: Int = 200
    nonisolated(unsafe) static var responseData: Data = Data()
    nonisolated(unsafe) static var responseHeaders: [String: String] = ["Content-Type": "text/event-stream"]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.responseStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: Self.responseHeaders
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ToolStreamMockURLProtocol.self]
    return URLSession(configuration: config)
}

private func sseData(_ lines: [String]) -> Data {
    Data(lines.joined(separator: "\n").utf8)
}

private func makePayload() -> AIPromptPayload {
    AIPromptPayload(
        systemInstructions: "You are a test assistant.",
        taskInstructions: "Run a tool.",
        untrustedSections: [],
        suspiciousPatterns: []
    )
}

private func collectEvents(
    _ stream: AsyncThrowingStream<StreamEvent, Error>
) async throws -> [StreamEvent] {
    var events: [StreamEvent] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}

// MARK: - Tests

final class ToolStreamingProtocolTests: XCTestCase {

    // MARK: - Anthropic SSE Line Parser Tests

    func testAnthropicTextDelta() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hello"}}"#
        let event = AIClient.parseAnthropicSSELine(line)
        guard case let .contentBlockDelta(index, deltaType, text, _) = event else {
            return XCTFail("Expected contentBlockDelta, got \(String(describing: event))")
        }
        XCTAssertEqual(index, 0)
        XCTAssertEqual(deltaType, "text_delta")
        XCTAssertEqual(text, "hello")
    }

    func testAnthropicToolCallFullCycle() {
        let startLine = #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_abc","name":"read_file"}}"#
        let deltaLine1 = #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"path\""}}"#
        let deltaLine2 = #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":":\"/foo.swift\"}"}}"#
        let stopLine = #"data: {"type":"content_block_stop","index":1}"#
        let messageLine = #"data: {"type":"message_stop"}"#

        let e1 = AIClient.parseAnthropicSSELine(startLine)
        let e2 = AIClient.parseAnthropicSSELine(deltaLine1)
        let e3 = AIClient.parseAnthropicSSELine(deltaLine2)
        let e4 = AIClient.parseAnthropicSSELine(stopLine)
        let e5 = AIClient.parseAnthropicSSELine(messageLine)

        guard case let .contentBlockStart(idx1, blockType, id, name) = e1 else {
            return XCTFail("Expected contentBlockStart, got \(String(describing: e1))")
        }
        XCTAssertEqual(idx1, 1)
        XCTAssertEqual(blockType, "tool_use")
        XCTAssertEqual(id, "toolu_abc")
        XCTAssertEqual(name, "read_file")

        guard case let .contentBlockDelta(_, deltaType2, _, partial1) = e2 else {
            return XCTFail("Expected contentBlockDelta, got \(String(describing: e2))")
        }
        XCTAssertEqual(deltaType2, "input_json_delta")
        XCTAssertEqual(partial1, "{\"path\"")

        guard case let .contentBlockDelta(_, _, _, partial2) = e3 else {
            return XCTFail("Expected contentBlockDelta, got \(String(describing: e3))")
        }
        XCTAssertEqual(partial2, ":\"/foo.swift\"}")

        guard case let .contentBlockStop(stopIdx) = e4 else {
            return XCTFail("Expected contentBlockStop, got \(String(describing: e4))")
        }
        XCTAssertEqual(stopIdx, 1)

        guard case .messageStop = e5 else {
            return XCTFail("Expected messageStop, got \(String(describing: e5))")
        }
    }

    func testAnthropicInputJsonDeltaAccumulation() async throws {
        let sseLines = [
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_xyz","name":"write"}}"#,
            "",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"pa"}}"#,
            "",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"th\":\"src/"}}"#,
            "",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"foo.swift\"}"}}"#,
            "",
            #"data: {"type":"content_block_stop","index":0}"#,
            "",
            #"data: {"type":"message_stop"}"#,
            "",
        ]

        ToolStreamMockURLProtocol.responseStatusCode = 200
        ToolStreamMockURLProtocol.responseData = sseData(sseLines)
        ToolStreamMockURLProtocol.responseHeaders = ["Content-Type": "text/event-stream"]

        let session = makeMockSession()
        let client = AIClient()
        await client.set_testURLSession(session)

        let events = try await collectEvents(
            client.streamAnthropicWithTools(
                payload: makePayload(),
                apiKey: "test-key",
                tools: [],
                maxTokens: 100
            )
        )

        let starts = events.filter { if case .toolCallStart = $0 { true } else { false } }
        let argDeltas = events.filter { if case .toolCallArgsDelta = $0 { true } else { false } }
        let completes = events.filter { if case .toolCallComplete = $0 { true } else { false } }
        let dones = events.filter { if case .done = $0 { true } else { false } }

        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(argDeltas.count, 3)
        XCTAssertEqual(completes.count, 1)
        XCTAssertEqual(dones.count, 1)

        guard case let .toolCallComplete(id, name, args) = completes[0] else {
            return XCTFail("Expected toolCallComplete")
        }
        XCTAssertEqual(id, "toolu_xyz")
        XCTAssertEqual(name, "write")
        XCTAssertEqual(args["path"] as? String, "src/foo.swift")
    }

    // MARK: - OpenAI SSE Line Parser Tests

    func testOpenAITextDelta() {
        let line = #"data: {"choices":[{"delta":{"content":"world"},"finish_reason":null}]}"#
        let event = AIClient.parseOpenAIToolSSELine(line)
        guard case let .textDelta(text) = event else {
            return XCTFail("Expected textDelta, got \(String(describing: event))")
        }
        XCTAssertEqual(text, "world")
    }

    func testOpenAIToolCallFullCycle() async throws {
        let sseLines = [
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"read","arguments":""}}]}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"path\""}}]}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":":\"/bar.swift\"}"}}]}}]}"#,
            "",
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
            "",
            "data: [DONE]",
            "",
        ]

        ToolStreamMockURLProtocol.responseStatusCode = 200
        ToolStreamMockURLProtocol.responseData = sseData(sseLines)
        ToolStreamMockURLProtocol.responseHeaders = ["Content-Type": "text/event-stream"]

        let session = makeMockSession()
        let client = AIClient()
        await client.set_testURLSession(session)

        let events = try await collectEvents(
            client.streamOpenAIWithTools(
                payload: makePayload(),
                apiKey: "test-key",
                tools: [],
                maxTokens: 100
            )
        )

        let starts = events.filter { if case .toolCallStart = $0 { true } else { false } }
        let completes = events.filter { if case .toolCallComplete = $0 { true } else { false } }
        let dones = events.filter { if case .done = $0 { true } else { false } }

        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(completes.count, 1)
        XCTAssertEqual(dones.count, 1)

        guard case let .toolCallComplete(id, name, args) = completes[0] else {
            return XCTFail("Expected toolCallComplete")
        }
        XCTAssertEqual(id, "call_abc")
        XCTAssertEqual(name, "read")
        XCTAssertEqual(args["path"] as? String, "/bar.swift")
    }

    // MARK: - Local OpenAI-compat (same shape as OpenAI)

    func testOpenAICompatLocal() async throws {
        let sseLines = [
            #"data: {"choices":[{"delta":{"content":"hi"},"finish_reason":null}]}"#,
            "",
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_local","type":"function","function":{"name":"list","arguments":""}}]}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"dir\":\"/tmp\"}"}}]}}]}"#,
            "",
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
            "",
            "data: [DONE]",
            "",
        ]

        ToolStreamMockURLProtocol.responseStatusCode = 200
        ToolStreamMockURLProtocol.responseData = sseData(sseLines)
        ToolStreamMockURLProtocol.responseHeaders = ["Content-Type": "text/event-stream"]

        let session = makeMockSession()
        let config = LocalLLMConfig(
            serverURL: "http://localhost:11434/v1",
            modelName: "local-model",
            requestTimeoutSeconds: 30,
            apiKey: ""
        )
        let client = AIClient()

        let events = try await collectEvents(
            client.streamLocalWithTools(
                payload: makePayload(),
                config: config,
                tools: [],
                maxTokens: 100,
                modelID: "local-model",
                urlSession: session
            )
        )

        let textDeltas = events.compactMap { event -> String? in
            if case let .textDelta(t) = event { return t }
            return nil
        }
        let starts = events.filter { if case .toolCallStart = $0 { true } else { false } }
        let completes = events.filter { if case .toolCallComplete = $0 { true } else { false } }

        XCTAssertEqual(textDeltas, ["hi"])
        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(completes.count, 1)

        guard case let .toolCallComplete(id, name, args) = completes[0] else {
            return XCTFail("Expected toolCallComplete")
        }
        XCTAssertEqual(id, "call_local")
        XCTAssertEqual(name, "list")
        XCTAssertEqual(args["dir"] as? String, "/tmp")
    }
}
