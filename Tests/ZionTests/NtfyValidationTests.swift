import XCTest
@testable import Zion

final class NtfyValidationTests: XCTestCase {

    // MARK: - validateTopic: Accept

    func testAcceptsAlphanumericTopic() {
        XCTAssertTrue(NtfyClient.validateTopic("alerts"))
    }

    func testAcceptsTopicWithDots() {
        XCTAssertTrue(NtfyClient.validateTopic("team.updates"))
    }

    func testAcceptsTopicWithUnderscores() {
        XCTAssertTrue(NtfyClient.validateTopic("prod_alerts"))
    }

    func testAcceptsTopicWithHyphens() {
        XCTAssertTrue(NtfyClient.validateTopic("my-topic"))
    }

    func testAcceptsMixedValidChars() {
        XCTAssertTrue(NtfyClient.validateTopic("team-updates_v1.2"))
    }

    func testAcceptsSingleCharTopic() {
        XCTAssertTrue(NtfyClient.validateTopic("a"))
    }

    func testAccepts64CharTopic() {
        let topic = String(repeating: "a", count: 64)
        XCTAssertTrue(NtfyClient.validateTopic(topic))
    }

    func testTrimsWhitespaceBeforeValidation() {
        XCTAssertTrue(NtfyClient.validateTopic("  alerts  "))
    }

    func testTrimsNewlinesBeforeValidation() {
        XCTAssertTrue(NtfyClient.validateTopic("\nalerts\n"))
    }

    // MARK: - validateTopic: Reject

    func testRejectsEmptyTopic() {
        XCTAssertFalse(NtfyClient.validateTopic(""))
    }

    func testRejectsWhitespaceOnlyTopic() {
        XCTAssertFalse(NtfyClient.validateTopic("   "))
    }

    func testRejectsTopicWithSpaces() {
        XCTAssertFalse(NtfyClient.validateTopic("invalid topic"))
    }

    func testRejectsTopicWithSlash() {
        XCTAssertFalse(NtfyClient.validateTopic("topic/path"))
    }

    func testPathTraversalDotsAreValidTopicChars() {
        // ".." matches [A-Za-z0-9._-] — dots and hyphens are valid topic chars.
        // Path traversal is prevented by URL building (topic goes into a single path segment).
        XCTAssertTrue(NtfyClient.validateTopic(".."))
    }

    func testRejectsTopicWithQueryChar() {
        XCTAssertFalse(NtfyClient.validateTopic("topic?key=val"))
    }

    func testRejectsTopicWithFragment() {
        XCTAssertFalse(NtfyClient.validateTopic("topic#section"))
    }

    func testRejectsTopicWithAtSign() {
        XCTAssertFalse(NtfyClient.validateTopic("user@topic"))
    }

    func testRejectsTopicWithColon() {
        XCTAssertFalse(NtfyClient.validateTopic("topic:sub"))
    }

    func testRejectsTopicWithNewlineInside() {
        XCTAssertFalse(NtfyClient.validateTopic("topic\ninjection"))
    }

    func testRejectsTopicWithNullByte() {
        XCTAssertFalse(NtfyClient.validateTopic("topic\0evil"))
    }

    func testRejectsTopicWithEmoji() {
        XCTAssertFalse(NtfyClient.validateTopic("alerts🔥"))
    }

    func testRejectsTopicWithBackslash() {
        XCTAssertFalse(NtfyClient.validateTopic("topic\\sub"))
    }

    func testRejectsTopicOver64Chars() {
        let topic = String(repeating: "a", count: 65)
        XCTAssertFalse(NtfyClient.validateTopic(topic))
    }

    // MARK: - validateServerURL: Accept

    func testAcceptsStandardHTTPS() {
        XCTAssertTrue(NtfyClient.validateServerURL("https://ntfy.sh"))
    }

    func testAcceptsHTTPSWithCustomPort() {
        XCTAssertTrue(NtfyClient.validateServerURL("https://ntfy.example.com:8443"))
    }

    func testAcceptsHTTPSWithPath() {
        XCTAssertTrue(NtfyClient.validateServerURL("https://example.com/ntfy"))
    }

    func testTrimsWhitespaceForServerURL() {
        XCTAssertTrue(NtfyClient.validateServerURL("  https://ntfy.sh  "))
    }

    // MARK: - validateServerURL: Reject

    func testRejectsHTTP() {
        XCTAssertFalse(NtfyClient.validateServerURL("http://ntfy.sh"))
    }

    func testRejectsNoScheme() {
        XCTAssertFalse(NtfyClient.validateServerURL("ntfy.sh"))
    }

    func testRejectsFTP() {
        XCTAssertFalse(NtfyClient.validateServerURL("ftp://ntfy.sh"))
    }

    func testRejectsFileScheme() {
        XCTAssertFalse(NtfyClient.validateServerURL("file:///etc/passwd"))
    }

    func testRejectsJavascriptScheme() {
        XCTAssertFalse(NtfyClient.validateServerURL("javascript:alert(1)"))
    }

    func testRejectsDataScheme() {
        XCTAssertFalse(NtfyClient.validateServerURL("data:text/html,<h1>hi</h1>"))
    }

    func testRejectsEmptyServerURL() {
        XCTAssertFalse(NtfyClient.validateServerURL(""))
    }

    func testRejectsHTTPSWithNoHost() {
        XCTAssertFalse(NtfyClient.validateServerURL("https://"))
    }

    func testRejectsTypoScheme() {
        XCTAssertFalse(NtfyClient.validateServerURL("hhtps://ntfy.sh"))
    }

    // MARK: - validateServerURL: Security — userinfo rejection

    func testRejectsUserinfoInURL() {
        XCTAssertFalse(NtfyClient.validateServerURL("https://user:pass@ntfy.sh"))
    }

    func testRejectsUserOnlyInURL() {
        XCTAssertFalse(NtfyClient.validateServerURL("https://user@ntfy.sh"))
    }

    // MARK: - Migrated from SecurityHardeningTests

    func testNtfyValidationAcceptsSecureConfig() {
        XCTAssertTrue(NtfyClient.validateServerURL("https://ntfy.sh"))
        XCTAssertTrue(NtfyClient.validateTopic("team-updates_v1.2"))
    }

    func testNtfyValidationRejectsInvalidConfig() {
        XCTAssertFalse(NtfyClient.validateServerURL("http://ntfy.sh"))
        XCTAssertFalse(NtfyClient.validateServerURL("hhtps://ntfy.sh"))
        XCTAssertFalse(NtfyClient.validateTopic("invalid topic with spaces"))
        XCTAssertFalse(NtfyClient.validateTopic("topic/with/slash"))
    }
}
