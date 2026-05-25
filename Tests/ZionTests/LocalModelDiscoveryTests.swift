import XCTest
@testable import Zion

final class LocalModelDiscoveryTests: XCTestCase {

    // MARK: - testParsesOpenAIModelsResponse

    func testParsesOpenAIModelsResponse() throws {
        let fixture = """
        {
            "object": "list",
            "data": [
                {"id": "qwen3-coder:30b", "object": "model"},
                {"id": "llama3.2:3b", "object": "model"}
            ]
        }
        """
        let data = Data(fixture.utf8)

        let ids = try AIClient.parseOpenAIModelsResponse(data)

        XCTAssertEqual(ids, ["qwen3-coder:30b", "llama3.2:3b"])
    }

    // MARK: - testThrowsOnMalformed

    func testThrowsOnMalformed() {
        let malformed = "this is not json"
        let data = Data(malformed.utf8)

        XCTAssertThrowsError(try AIClient.parseOpenAIModelsResponse(data)) { error in
            guard let aiError = error as? AIError else {
                XCTFail("Expected AIError, got \(error)")
                return
            }
            XCTAssertEqual(aiError, .invalidResponse)
        }
    }
}

// Equatable conformance lives in the Zion module (AIClient+Helpers.swift).
// This extension exists only to provide a richer == for older test files;
// kept as a non-conformance extension to silence the duplicate-conformance
// warning under Swift 6.
extension AIError {
    public static func == (lhs: AIError, rhs: AIError) -> Bool {
        switch (lhs, rhs) {
        case (.noProvider, .noProvider): return true
        case (.invalidKey, .invalidKey): return true
        case (.invalidResponse, .invalidResponse): return true
        case (.quotaExceeded, .quotaExceeded): return true
        case (.temporarilyUnavailable, .temporarilyUnavailable): return true
        case (.apiError(let a), .apiError(let b)): return a == b
        case (.localConnectionFailed, .localConnectionFailed): return true
        case (.localServerNotFound, .localServerNotFound): return true
        case (.localModelError, .localModelError): return true
        case (.localAPIError(let a), .localAPIError(let b)): return a == b
        case (.localToolCallingUnsupported, .localToolCallingUnsupported): return true
        default: return false
        }
    }
}
