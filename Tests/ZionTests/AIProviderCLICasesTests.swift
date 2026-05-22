import XCTest
@testable import Zion

final class AIProviderCLICasesTests: XCTestCase {

    func test_claudeCLI_case_exists() {
        XCTAssertNotNil(AIProvider(rawValue: "claudeCLI"))
        XCTAssertEqual(AIProvider.claudeCLI.rawValue, "claudeCLI")
    }

    func test_codexCLI_case_exists() {
        XCTAssertNotNil(AIProvider(rawValue: "codexCLI"))
        XCTAssertEqual(AIProvider.codexCLI.rawValue, "codexCLI")
    }

    func test_labels_non_empty() {
        XCTAssertFalse(AIProvider.claudeCLI.label.isEmpty)
        XCTAssertFalse(AIProvider.codexCLI.label.isEmpty)
    }

    func test_in_allCases() {
        XCTAssertTrue(AIProvider.allCases.contains(.claudeCLI))
        XCTAssertTrue(AIProvider.allCases.contains(.codexCLI))
    }
}
