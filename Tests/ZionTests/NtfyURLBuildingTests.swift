import XCTest
@testable import Zion

final class NtfyURLBuildingTests: XCTestCase {

    // MARK: - Standard cases

    func testBuildStandardURL() {
        let url = NtfyClient.buildNtfyURL(serverURL: "https://ntfy.sh", topic: "alerts")
        XCTAssertEqual(url?.absoluteString, "https://ntfy.sh/alerts")
    }

    func testBuildURLWithTrailingSlash() {
        let url = NtfyClient.buildNtfyURL(serverURL: "https://ntfy.sh/", topic: "alerts")
        XCTAssertEqual(url?.absoluteString, "https://ntfy.sh/alerts")
    }

    func testBuildURLWithPathPrefix() {
        let url = NtfyClient.buildNtfyURL(serverURL: "https://ntfy.sh/base", topic: "alerts")
        XCTAssertEqual(url?.absoluteString, "https://ntfy.sh/base/alerts")
    }

    func testBuildURLWithDeepPath() {
        let url = NtfyClient.buildNtfyURL(serverURL: "https://example.com/a/b/c", topic: "alerts")
        XCTAssertEqual(url?.absoluteString, "https://example.com/a/b/c/alerts")
    }

    func testBuildURLWithSpecialCharsInTopic() {
        let url = NtfyClient.buildNtfyURL(serverURL: "https://ntfy.sh", topic: "my.topic-v1_2")
        XCTAssertEqual(url?.absoluteString, "https://ntfy.sh/my.topic-v1_2")
    }

    func testBuildURLTrimsWhitespace() {
        let url = NtfyClient.buildNtfyURL(serverURL: "  https://ntfy.sh  ", topic: "  alerts  ")
        XCTAssertEqual(url?.absoluteString, "https://ntfy.sh/alerts")
    }

    // MARK: - Nil cases

    func testReturnsNilForHTTPServer() {
        XCTAssertNil(NtfyClient.buildNtfyURL(serverURL: "http://ntfy.sh", topic: "alerts"))
    }

    func testReturnsNilForInvalidTopic() {
        XCTAssertNil(NtfyClient.buildNtfyURL(serverURL: "https://ntfy.sh", topic: "bad topic"))
    }

    func testReturnsNilForEmptyServer() {
        XCTAssertNil(NtfyClient.buildNtfyURL(serverURL: "", topic: "alerts"))
    }

    func testReturnsNilForEmptyTopic() {
        XCTAssertNil(NtfyClient.buildNtfyURL(serverURL: "https://ntfy.sh", topic: ""))
    }

    // MARK: - Security: injection prevention

    func testRejectsQueryInjectionInTopic() {
        // Topics with ? are rejected by validateTopic
        XCTAssertNil(NtfyClient.buildNtfyURL(serverURL: "https://ntfy.sh", topic: "alerts?auth=token"))
    }

    func testRejectsFragmentInjectionInTopic() {
        XCTAssertNil(NtfyClient.buildNtfyURL(serverURL: "https://ntfy.sh", topic: "alerts#admin"))
    }

    func testRejectsUserinfoInServer() {
        XCTAssertNil(NtfyClient.buildNtfyURL(serverURL: "https://user:pass@ntfy.sh", topic: "alerts"))
    }

    // MARK: - Migrated from SecurityHardeningTests

    func testNtfyBuildURLUsesValidatedParts() {
        let url = NtfyClient.buildNtfyURL(serverURL: "https://ntfy.sh/base", topic: "prod-alerts")
        XCTAssertEqual(url?.absoluteString, "https://ntfy.sh/base/prod-alerts")
    }
}
