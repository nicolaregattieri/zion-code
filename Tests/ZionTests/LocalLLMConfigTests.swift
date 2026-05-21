import XCTest
@testable import Zion

final class LocalLLMConfigTests: XCTestCase {
    func testDefaultsMatchSpec() {
        let config = LocalLLMConfig()
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.serverURL, "http://localhost:11434/v1")
        XCTAssertEqual(config.modelName, "qwen3-coder:30b")
        XCTAssertEqual(config.requestTimeoutSeconds, 60)
        XCTAssertEqual(config.apiKey, "")
    }

    func testCodableRoundTripPreservesVersion() throws {
        var config = LocalLLMConfig()
        config.version = 3
        config.serverURL = "http://localhost:1234/v1"
        config.modelName = "mistral:7b"
        config.requestTimeoutSeconds = 120
        config.apiKey = "test-key"

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(LocalLLMConfig.self, from: data)

        XCTAssertEqual(decoded.version, 3)
        XCTAssertEqual(decoded.serverURL, "http://localhost:1234/v1")
        XCTAssertEqual(decoded.modelName, "mistral:7b")
        XCTAssertEqual(decoded.requestTimeoutSeconds, 120)
        XCTAssertEqual(decoded.apiKey, "test-key")
    }

    func testTimeoutClampedAtDecode() throws {
        let json = """
        {"version":1,"serverURL":"http://localhost:11434/v1","modelName":"test","requestTimeoutSeconds":999,"apiKey":""}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LocalLLMConfig.self, from: json)
        XCTAssertEqual(decoded.requestTimeoutSeconds, 600)

        let jsonLow = """
        {"version":1,"serverURL":"http://localhost:11434/v1","modelName":"test","requestTimeoutSeconds":1,"apiKey":""}
        """.data(using: .utf8)!
        let decodedLow = try JSONDecoder().decode(LocalLLMConfig.self, from: jsonLow)
        XCTAssertEqual(decodedLow.requestTimeoutSeconds, 5)
    }

    func testEndpointURLParsed() {
        let config = LocalLLMConfig()
        XCTAssertEqual(config.endpointURL, URL(string: "http://localhost:11434/v1"))
    }

    func testEndpointURLNilForEmpty() {
        var config = LocalLLMConfig()
        config.serverURL = ""
        XCTAssertNil(config.endpointURL)
    }
}
