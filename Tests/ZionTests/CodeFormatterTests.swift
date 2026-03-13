import XCTest
@testable import Zion

final class CodeFormatterTests: XCTestCase {
    func testJSONFormatterSortsKeysWhenEnabled() {
        let source = #"{"z":1,"a":2,"m":{"b":1,"a":2}}"#
        let options = FormatOptions(tabSize: 2, useTabs: false, jsonSortKeys: true)

        let result = CodeFormatter.format(source, fileExtension: "json", options: options)

        guard case let .success(formatted) = result else {
            return XCTFail("Expected JSON formatting to succeed")
        }

        let outerA = formatted.range(of: "\"a\"")?.lowerBound.utf16Offset(in: formatted) ?? .max
        let outerZ = formatted.range(of: "\"z\"")?.lowerBound.utf16Offset(in: formatted) ?? .max
        XCTAssertLessThan(outerA, outerZ)

        guard let nestedRange = formatted.range(of: "\"m\"") else {
            return XCTFail("Expected nested object to be present")
        }

        let nestedA = formatted.range(
            of: "\"a\" : 2",
            range: nestedRange.upperBound..<formatted.endIndex
        )?.lowerBound.utf16Offset(in: formatted) ?? .max
        let nestedB = formatted.range(
            of: "\"b\" : 1",
            range: nestedRange.upperBound..<formatted.endIndex
        )?.lowerBound.utf16Offset(in: formatted) ?? .max
        XCTAssertLessThan(nestedA, nestedB)
    }

    func testJSONFormatterReturnsParseErrorForInvalidJSON() {
        let source = #"{"z":1,"a":}"#
        let options = FormatOptions(tabSize: 2, useTabs: false, jsonSortKeys: true)

        let result = CodeFormatter.format(source, fileExtension: "json", options: options)

        guard case let .failure(error) = result else {
            return XCTFail("Expected invalid JSON to fail formatting")
        }

        XCTAssertNotNil(error.errorDescription)
    }
}
