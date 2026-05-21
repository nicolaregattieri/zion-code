import XCTest
@testable import Zion

final class LocalLLMProviderEnumTests: XCTestCase {
    func testLocalCaseExists() {
        let allCases = AIProvider.allCases
        XCTAssertTrue(allCases.contains(.local), "AIProvider must contain .local case")
    }

    func testLocalRawValue() {
        XCTAssertEqual(AIProvider.local.rawValue, "local")
    }

    func testLocalIdentifiable() {
        XCTAssertEqual(AIProvider.local.id, "local")
    }

    func testLocalLabelIsNonEmpty() {
        XCTAssertFalse(AIProvider.local.label.isEmpty)
    }
}
