import XCTest
@testable import Zion

// MARK: - URLProtocol Mock (isolated to this test class)

private final class DispatchMockURLProtocol: URLProtocol {

    nonisolated(unsafe) static var responseStatusCode: Int = 200
    nonisolated(unsafe) static var responseData: Data = Data()
    nonisolated(unsafe) static var responseHeaders: [String: String] = [:]

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

private func makeDispatchMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DispatchMockURLProtocol.self]
    return URLSession(configuration: config)
}

private func sseDispatchBody(_ lines: [String]) -> Data {
    Data(lines.joined(separator: "\n").utf8)
}

// MARK: - Tests

final class AIClientLocalDispatchTests: XCTestCase {

    // Isolated UserDefaults suite so we never pollute production defaults.
    private let testDefaults = UserDefaults(suiteName: "AIClientLocalDispatchTests")!

    private let testConfig = LocalLLMConfig(
        serverURL: "http://localhost:11434/v1",
        modelName: "dispatch-test-model",
        requestTimeoutSeconds: 30,
        apiKey: ""
    )

    override func setUp() async throws {
        try await super.setUp()
        // Persist config into the standard defaults key so loadLocalConfig() finds it.
        if let data = try? JSONEncoder().encode(testConfig) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.AI.localConfig)
        }
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.AI.localConfig)
        try await super.tearDown()
    }

    private func makePayload() -> AIPromptPayload {
        AIPromptPayload(
            systemInstructions: "You are a test assistant.",
            taskInstructions: "Respond with ping.",
            untrustedSections: [],
            suspiciousPatterns: []
        )
    }

    // MARK: - testLocalProviderDispatches

    func testLocalProviderDispatches() async throws {
        let sseLines = [
            #"data: {"choices":[{"delta":{"content":"pin"},"finish_reason":null}]}"#,
            "",
            #"data: {"choices":[{"delta":{"content":"g"},"finish_reason":null}]}"#,
            "",
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            "",
            "data: [DONE]",
            "",
        ]

        DispatchMockURLProtocol.responseStatusCode = 200
        DispatchMockURLProtocol.responseData = sseDispatchBody(sseLines)
        DispatchMockURLProtocol.responseHeaders = ["Content-Type": "text/event-stream"]

        let session = makeDispatchMockSession()
        let client = AIClient()
        await client.set_testURLSession(session)

        let result = try await client.call(
            payload: makePayload(),
            provider: .local,
            apiKey: "",
            maxTokens: 100,
            lane: .general,
            mode: .efficient
        )

        XCTAssertEqual(result, "ping", "Expected assembled text 'ping' from local dispatch")
    }
}
