import XCTest
@testable import Zion

// MARK: - StubURLProtocol

private final class StubURLProtocol: URLProtocol {

    // Shared state — configure before each test, reset after.
    nonisolated(unsafe) static var responseStatusCode: Int = 200
    nonisolated(unsafe) static var responseHeaders: [String: String] = [:]
    nonisolated(unsafe) static var responseData: Data = Data()
    nonisolated(unsafe) static var shouldFail: Bool = false
    nonisolated(unsafe) static var failureError: Error = URLError(.notConnectedToInternet)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if Self.shouldFail {
            client?.urlProtocol(self, didFailWithError: Self.failureError)
            return
        }
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

private func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

/// Minimal valid Anthropic 200 response body so `callAnthropic` doesn't throw `invalidResponse`
/// after a hypothetical 200 (unused in rate-limit tests, but handy).
private let anthropicOKBody = Data("""
{"content":[{"type":"text","text":"ok"}]}
""".utf8)

/// Minimal valid OpenAI 200 response body.
private let openAIOKBody = Data("""
{"choices":[{"message":{"role":"assistant","content":"ok"}}]}
""".utf8)

private func makePayload() -> AIPromptPayload {
    AIPromptPayload(
        systemInstructions: "test",
        taskInstructions: "test",
        untrustedSections: [],
        suspiciousPatterns: []
    )
}

// MARK: - Tests

@MainActor
final class AIClientRateLimitTests: XCTestCase {

    private var client: AIClient!
    private var session: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        client = AIClient()
        session = makeStubSession()
        await client.set_testURLSession(session)

        // Reset stub state
        StubURLProtocol.responseStatusCode = 200
        StubURLProtocol.responseHeaders = [:]
        StubURLProtocol.responseData = Data()
        StubURLProtocol.shouldFail = false
        StubURLProtocol.failureError = URLError(.notConnectedToInternet)
    }

    override func tearDown() async throws {
        client = nil
        session = nil
        try await super.tearDown()
    }

    // MARK: - testAnthropicCall429RaisesRateLimited

    func testAnthropicCall429RaisesRateLimited() async throws {
        StubURLProtocol.responseStatusCode = 429
        StubURLProtocol.responseHeaders = ["Retry-After": "60"]
        StubURLProtocol.responseData = Data()

        do {
            let payload = makePayload()
            _ = try await client.call(
                payload: payload,
                provider: .anthropic,
                apiKey: "test-key",
                maxTokens: 100,
                lane: .general,
                mode: .efficient
            )
            XCTFail("Expected AIError.rateLimited to be thrown")
        } catch let error as AIError {
            if case .rateLimited(let retryAfter) = error {
                XCTAssertEqual(retryAfter ?? -1, 60, accuracy: 0.001)
            } else {
                XCTFail("Expected .rateLimited, got \(error)")
            }
        }
    }

    // MARK: - testOpenAICall429ParsesHTTPDate

    func testOpenAICall429ParsesHTTPDate() async throws {
        // Build an HTTP-date 120 seconds in the future.
        let future = Date(timeIntervalSinceNow: 120)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        let httpDate = formatter.string(from: future)

        StubURLProtocol.responseStatusCode = 429
        StubURLProtocol.responseHeaders = ["Retry-After": httpDate]
        StubURLProtocol.responseData = Data()

        do {
            let payload = makePayload()
            _ = try await client.call(
                payload: payload,
                provider: .openai,
                apiKey: "test-key",
                maxTokens: 100,
                lane: .general,
                mode: .efficient
            )
            XCTFail("Expected AIError.rateLimited to be thrown")
        } catch let error as AIError {
            if case .rateLimited(let retryAfter) = error {
                let delay: TimeInterval = try XCTUnwrap(retryAfter, "Expected non-nil retryAfter for HTTP-date header")
                XCTAssertGreaterThan(delay, 0, "Expected positive retryAfter from HTTP-date header")
                // Allow ±5s clock drift during the test.
                XCTAssertLessThan(delay, 125.0, "Parsed delay should be close to 120s")
            } else {
                XCTFail("Expected .rateLimited, got \(error)")
            }
        }
    }

    // MARK: - testNetworkFailureTranslates

    func testNetworkFailureTranslates() async throws {
        StubURLProtocol.shouldFail = true
        StubURLProtocol.failureError = URLError(.notConnectedToInternet)

        do {
            let payload = makePayload()
            _ = try await client.call(
                payload: payload,
                provider: .anthropic,
                apiKey: "test-key",
                maxTokens: 100,
                lane: .general,
                mode: .efficient
            )
            XCTFail("Expected AIError.networkFailure to be thrown")
        } catch let error as AIError {
            if case .networkFailure(let underlying) = error {
                XCTAssertFalse(underlying.isEmpty, "networkFailure should include a description")
            } else {
                XCTFail("Expected .networkFailure, got \(error)")
            }
        }
    }

    // MARK: - testRetryAfterWithoutHeader

    func testRetryAfterWithoutHeader() async throws {
        StubURLProtocol.responseStatusCode = 429
        StubURLProtocol.responseHeaders = [:]  // no Retry-After
        StubURLProtocol.responseData = Data()

        do {
            let payload = makePayload()
            _ = try await client.call(
                payload: payload,
                provider: .anthropic,
                apiKey: "test-key",
                maxTokens: 100,
                lane: .general,
                mode: .efficient
            )
            XCTFail("Expected AIError.rateLimited to be thrown")
        } catch let error as AIError {
            if case .rateLimited(let retryAfter) = error {
                XCTAssertNil(retryAfter, "Expected nil retryAfter when Retry-After header is absent")
            } else {
                XCTFail("Expected .rateLimited, got \(error)")
            }
        }
    }

    // MARK: - testParseRetryAfterIntegerHeader

    func testParseRetryAfterIntegerHeader() {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: ["Retry-After": "120"]
        )!
        let result = AIClient.parseRetryAfter(from: response)
        XCTAssertEqual(result ?? -1, 120, accuracy: 0.001)
    }

    // MARK: - testParseRetryAfterMissingHeader

    func testParseRetryAfterMissingHeader() {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        XCTAssertNil(AIClient.parseRetryAfter(from: response))
    }

    // MARK: - testParseRetryAfterHTTPDateFormat

    func testParseRetryAfterHTTPDateFormat() throws {
        let future = Date(timeIntervalSinceNow: 300)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        let httpDate = formatter.string(from: future)

        let response = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: ["Retry-After": httpDate]
        )!
        let delay: TimeInterval = try XCTUnwrap(AIClient.parseRetryAfter(from: response), "Expected non-nil retryAfter")
        XCTAssertGreaterThan(delay, 0)
        XCTAssertLessThan(delay, 305.0)
    }
}
