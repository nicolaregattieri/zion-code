import XCTest
@testable import Zion

// MARK: - URLProtocol Mock (cloud streaming)

private final class CloudMockURLProtocol: URLProtocol {

    nonisolated(unsafe) static var responseStatusCode: Int = 200
    nonisolated(unsafe) static var responseData: Data = Data()
    nonisolated(unsafe) static var responseHeaders: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let headers = Self.responseHeaders
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.responseStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeCloudMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CloudMockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makePayload() -> AIPromptPayload {
    AIPromptPayload(
        systemInstructions: "You are a test assistant.",
        taskInstructions: "Say something.",
        untrustedSections: [],
        suspiciousPatterns: []
    )
}

// MARK: - Tests

final class ChatStreamingCloudIntegrationTests: XCTestCase {

    // MARK: - testAnthropicAssemblesText

    func testAnthropicAssemblesText() async throws {
        let sseBytes = "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"hello\"}}\n\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"

        CloudMockURLProtocol.responseStatusCode = 200
        CloudMockURLProtocol.responseData = Data(sseBytes.utf8)
        CloudMockURLProtocol.responseHeaders = ["Content-Type": "text/event-stream"]

        let client = AIClient()
        await client.set_testURLSession(makeCloudMockSession())

        var assembled = ""
        for try await delta in await client.streamAnthropic(
            payload: makePayload(),
            apiKey: "test-key",
            maxTokens: 100,
            modelID: "claude-3-5-sonnet-20241022"
        ) {
            assembled += delta
        }

        XCTAssertEqual(assembled, "hello")
    }

    // MARK: - testOpenAIAssemblesText

    func testOpenAIAssemblesText() async throws {
        let sseLines = [
            #"data: {"choices":[{"delta":{"content":"hi"},"finish_reason":null}]}"#,
            "",
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            "",
            "data: [DONE]",
            "",
        ]

        CloudMockURLProtocol.responseStatusCode = 200
        CloudMockURLProtocol.responseData = Data(sseLines.joined(separator: "\n").utf8)
        CloudMockURLProtocol.responseHeaders = ["Content-Type": "text/event-stream"]

        let client = AIClient()
        await client.set_testURLSession(makeCloudMockSession())

        var assembled = ""
        for try await delta in await client.streamOpenAI(
            payload: makePayload(),
            apiKey: "test-key",
            maxTokens: 100,
            modelID: "gpt-4o"
        ) {
            assembled += delta
        }

        XCTAssertEqual(assembled, "hi")
    }

    // MARK: - testAnthropic401ThrowsAuthError

    func testAnthropic401ThrowsAuthError() async throws {
        CloudMockURLProtocol.responseStatusCode = 401
        CloudMockURLProtocol.responseData = Data()
        CloudMockURLProtocol.responseHeaders = [:]

        let client = AIClient()
        await client.set_testURLSession(makeCloudMockSession())

        do {
            for try await _ in await client.streamAnthropic(
                payload: makePayload(),
                apiKey: "bad-key",
                maxTokens: 100,
                modelID: "claude-3-5-sonnet-20241022"
            ) {}
            XCTFail("Expected error to be thrown")
        } catch let error as AIError {
            if case .localAPIError = error {
                // Pass — 401 maps to localAPIError
            } else {
                XCTFail("Expected AIError.localAPIError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
