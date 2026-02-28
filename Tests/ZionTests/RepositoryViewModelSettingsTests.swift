import XCTest
@testable import Zion

@MainActor
final class RepositoryViewModelSettingsTests: XCTestCase {

    // MARK: - languageName(for:)

    func testSwiftExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "swift"), "Swift")
    }

    func testTypeScriptExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "ts"), "TypeScript")
    }

    func testTSXExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "tsx"), "TypeScript")
    }

    func testPythonExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "py"), "Python")
    }

    func testGoExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "go"), "Go")
    }

    func testRustExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "rs"), "Rust")
    }

    func testMarkdownExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "md"), "Markdown")
    }

    func testUnknownExtensionUppercased() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "xyz"), "XYZ")
    }

    func testEmptyExtensionReturnsEmpty() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: ""), "")
    }

    // MARK: - Additional known extensions

    func testJavaScriptExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "js"), "JavaScript")
    }

    func testJSXExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "jsx"), "JavaScript")
    }

    func testRubyExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "rb"), "Ruby")
    }

    func testJavaExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "java"), "Java")
    }

    func testHTMLExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "html"), "HTML")
    }

    func testCSSExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "css"), "CSS")
    }

    func testJSONExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "json"), "JSON")
    }

    func testYAMLExtensions() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "yaml"), "YAML")
        XCTAssertEqual(RepositoryViewModel.languageName(for: "yml"), "YAML")
    }

    func testShellExtensions() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "sh"), "Shell")
        XCTAssertEqual(RepositoryViewModel.languageName(for: "bash"), "Shell")
        XCTAssertEqual(RepositoryViewModel.languageName(for: "zsh"), "Shell")
    }
}
