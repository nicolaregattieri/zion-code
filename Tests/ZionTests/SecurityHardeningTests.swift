import XCTest
@testable import Zion

final class SecurityHardeningTests: XCTestCase {
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

    func testNtfyBuildURLUsesValidatedParts() {
        let url = NtfyClient.buildNtfyURL(serverURL: "https://ntfy.sh/base", topic: "prod-alerts")
        XCTAssertEqual(url?.absoluteString, "https://ntfy.sh/base/prod-alerts")
    }

    @MainActor
    func testDiagnosticLoggerRedactsSensitiveTokens() {
        let logger = DiagnosticLogger.shared
        logger.clear()

        logger.log(.info, "Bearer abcdefghijklmnopqrstuvwxyz0123456789")
        logger.log(.info, "Token ghp_abcdefghijklmnopqrstuvwxyz123456")
        logger.log(.info, "URL https://user:password@example.com/path")

        let output = logger.exportLog()
        XCTAssertFalse(output.contains("abcdefghijklmnopqrstuvwxyz0123456789"))
        XCTAssertFalse(output.contains("ghp_abcdefghijklmnopqrstuvwxyz123456"))
        XCTAssertFalse(output.contains("user:password@"))
        XCTAssertTrue(output.contains("Bearer [REDACTED]"))
        XCTAssertTrue(output.contains("[REDACTED]@example.com"))
    }
}
