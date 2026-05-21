import XCTest
@testable import Zion

final class LocalLLMBackendTests: XCTestCase {
    func testDefaultURLs() {
        XCTAssertEqual(LocalLLMBackend.ollama.defaultURL, "http://localhost:11434")
        XCTAssertEqual(LocalLLMBackend.llamaCppServer.defaultURL, "http://localhost:8080")
        XCTAssertEqual(LocalLLMBackend.lmStudio.defaultURL, "http://localhost:1234")
        XCTAssertEqual(LocalLLMBackend.customOpenAI.defaultURL, "")
    }

    func testAllCasesPresent() {
        let cases = LocalLLMBackend.allCases.map(\.rawValue)
        XCTAssertTrue(cases.contains("ollama"))
        XCTAssertTrue(cases.contains("llamaCppServer"))
        XCTAssertTrue(cases.contains("lmStudio"))
        XCTAssertTrue(cases.contains("customOpenAI"))
    }

    func testIdentifiable() {
        for backend in LocalLLMBackend.allCases {
            XCTAssertEqual(backend.id, backend.rawValue)
        }
    }

    func testLabelsNonEmpty() {
        for backend in LocalLLMBackend.allCases {
            XCTAssertFalse(backend.label.isEmpty)
        }
    }
}
