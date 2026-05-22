import XCTest
@testable import Zion

// MARK: - URLProtocol Mock

private final class MockURLProtocol: URLProtocol {

    // Set before each test
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

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func sseBody(_ lines: [String]) -> Data {
    Data(lines.joined(separator: "\n").utf8)
}

// MARK: - Tests

final class LocalStreamingIntegrationTests: XCTestCase {

    private let config = LocalLLMConfig(
        serverURL: "http://localhost:11434/v1",
        modelName: "test-model",
        requestTimeoutSeconds: 30,
        apiKey: ""
    )

    private func makePayload() -> AIPromptPayload {
        AIPromptPayload(
            systemInstructions: "You are a test assistant.",
            taskInstructions: "Say hello.",
            untrustedSections: [],
            suspiciousPatterns: []
        )
    }

    // MARK: - testStreamedCallReturnsAssembledText

    func testStreamedCallReturnsAssembledText() async throws {
        let sseLines = [
            #"data: {"choices":[{"delta":{"content":"hel"},"finish_reason":null}]}"#,
            "",
            #"data: {"choices":[{"delta":{"content":"lo"},"finish_reason":null}]}"#,
            "",
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            "",
            "data: [DONE]",
            "",
        ]

        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseData = sseBody(sseLines)
        MockURLProtocol.responseHeaders = ["Content-Type": "text/event-stream"]

        let session = makeMockSession()
        let client = AIClient()

        let result = try await client.callLocalLLM(
            payload: makePayload(),
            config: config,
            maxTokens: 100,
            modelID: "test-model",
            urlSession: session
        )

        XCTAssertEqual(result, "hello")
    }

    // MARK: - testServerNotFoundError

    func testServerNotFoundError() async throws {
        MockURLProtocol.responseStatusCode = 404
        MockURLProtocol.responseData = Data()
        MockURLProtocol.responseHeaders = [:]

        let session = makeMockSession()
        let client = AIClient()

        do {
            _ = try await client.callLocalLLM(
                payload: makePayload(),
                config: config,
                maxTokens: 100,
                modelID: "test-model",
                urlSession: session
            )
            XCTFail("Expected AIError.localModelError to be thrown")
        } catch let error as AIError {
            XCTAssertEqual(error, AIError.localModelError)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
