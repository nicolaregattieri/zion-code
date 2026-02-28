import XCTest
@testable import Zion

@MainActor
final class RepositoryViewModelFileBrowserTests: XCTestCase {

    // MARK: - parseFindInFilesOutput

    func testParseFindInFilesOutputMultipleMatchesAcrossFiles() {
        let output = [
            "Sources/App.swift:10:import Foundation",
            "Sources/App.swift:25:let app = App()",
            "Tests/AppTests.swift:5:@testable import App",
        ].joined(separator: "\n")

        let results = RepositoryViewModel.parseFindInFilesOutput(output, maxMatches: 100)

        XCTAssertEqual(results.count, 2)

        // First file group
        XCTAssertEqual(results[0].file, "Sources/App.swift")
        XCTAssertEqual(results[0].matches.count, 2)
        XCTAssertEqual(results[0].matches[0].line, 10)
        XCTAssertEqual(results[0].matches[0].preview, "import Foundation")
        XCTAssertEqual(results[0].matches[1].line, 25)
        XCTAssertEqual(results[0].matches[1].preview, "let app = App()")

        // Second file group
        XCTAssertEqual(results[1].file, "Tests/AppTests.swift")
        XCTAssertEqual(results[1].matches.count, 1)
        XCTAssertEqual(results[1].matches[0].line, 5)
        XCTAssertEqual(results[1].matches[0].preview, "@testable import App")
    }

    func testParseFindInFilesOutputMaxMatchesLimit() {
        let output = [
            "a.swift:1:line one",
            "a.swift:2:line two",
            "a.swift:3:line three",
            "b.swift:1:should not appear",
        ].joined(separator: "\n")

        let results = RepositoryViewModel.parseFindInFilesOutput(output, maxMatches: 2)

        let totalMatches = results.reduce(0) { $0 + $1.matches.count }
        XCTAssertEqual(totalMatches, 2)
        XCTAssertEqual(results[0].matches[0].preview, "line one")
        XCTAssertEqual(results[0].matches[1].preview, "line two")
    }

    func testParseFindInFilesOutputEmptyInput() {
        let results = RepositoryViewModel.parseFindInFilesOutput("", maxMatches: 100)
        XCTAssertTrue(results.isEmpty)
    }

    func testParseFindInFilesOutputSingleMatch() {
        let output = "README.md:1:# Project Title"

        let results = RepositoryViewModel.parseFindInFilesOutput(output, maxMatches: 100)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].file, "README.md")
        XCTAssertEqual(results[0].matches.count, 1)
        XCTAssertEqual(results[0].matches[0].line, 1)
        XCTAssertEqual(results[0].matches[0].preview, "# Project Title")
    }
}
