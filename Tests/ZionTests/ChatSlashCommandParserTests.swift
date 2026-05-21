import XCTest
@testable import Zion

final class ChatSlashCommandParserTests: XCTestCase {

    // MARK: - Happy path

    func testParseDiff() {
        XCTAssertEqual(ChatContextBuilder.parseSlashCommand("/diff"), .diff)
    }

    func testParseLog() {
        XCTAssertEqual(ChatContextBuilder.parseSlashCommand("/log"), .log)
    }

    func testParseStatus() {
        XCTAssertEqual(ChatContextBuilder.parseSlashCommand("/status"), .status)
    }

    func testParseFileWithPath() {
        XCTAssertEqual(
            ChatContextBuilder.parseSlashCommand("/file src/foo.swift"),
            .file(path: "src/foo.swift")
        )
    }

    func testParseCommitWithSHA() {
        XCTAssertEqual(
            ChatContextBuilder.parseSlashCommand("/commit abc1234"),
            .commit(sha: "abc1234")
        )
    }

    // MARK: - Rejection cases

    func testRejectsUnknownCommand() {
        XCTAssertNil(ChatContextBuilder.parseSlashCommand("/foo"))
    }

    func testRejectsMissingArgs() {
        XCTAssertNil(ChatContextBuilder.parseSlashCommand("/file"))
        XCTAssertNil(ChatContextBuilder.parseSlashCommand("/commit"))
    }

    // MARK: - Inline-slash in URLs must NOT match

    func testIgnoresInlineSlashInURL() {
        XCTAssertNil(ChatContextBuilder.parseSlashCommand("https://example.com/diff"))
        XCTAssertNil(ChatContextBuilder.parseSlashCommand("See https://example.com/status for details"))
        XCTAssertNil(ChatContextBuilder.parseSlashCommand("http://host/log"))
    }

    // MARK: - Leading whitespace is accepted

    func testLeadingWhitespaceAccepted() {
        XCTAssertEqual(ChatContextBuilder.parseSlashCommand("  /diff"), .diff)
        XCTAssertEqual(
            ChatContextBuilder.parseSlashCommand("  /file README.md"),
            .file(path: "README.md")
        )
    }
}
