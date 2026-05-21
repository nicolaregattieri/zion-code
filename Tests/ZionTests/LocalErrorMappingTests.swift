import XCTest
@testable import Zion

final class LocalErrorMappingTests: XCTestCase {

    // MARK: - Parser-level malformed body maps to AIError.invalidResponse

    func testMalformedJSONThrowsInvalidResponse() {
        let data = Data("not json at all".utf8)

        XCTAssertThrowsError(try AIClient.parseOpenAIModelsResponse(data)) { error in
            XCTAssertEqual(error as? AIError, .invalidResponse)
        }
    }

    func testMissingDataKeyThrowsInvalidResponse() {
        let json = """
        {"object": "list", "models": [{"id": "some-model"}]}
        """
        let data = Data(json.utf8)

        XCTAssertThrowsError(try AIClient.parseOpenAIModelsResponse(data)) { error in
            XCTAssertEqual(error as? AIError, .invalidResponse)
        }
    }

    func testDataIsNotArrayThrowsInvalidResponse() {
        let json = """
        {"object": "list", "data": "not-an-array"}
        """
        let data = Data(json.utf8)

        XCTAssertThrowsError(try AIClient.parseOpenAIModelsResponse(data)) { error in
            XCTAssertEqual(error as? AIError, .invalidResponse)
        }
    }

    func testEmptyDataArrayReturnsEmptyList() throws {
        let json = """
        {"object": "list", "data": []}
        """
        let data = Data(json.utf8)

        let ids = try AIClient.parseOpenAIModelsResponse(data)
        XCTAssertTrue(ids.isEmpty)
    }
}
