import XCTest
@testable import Zion

final class SecurityHardeningTests: XCTestCase {
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

    @MainActor
    func testDiagnosticLoggerRedactsNtfyTopic() {
        let logger = DiagnosticLogger.shared
        logger.clear()

        logger.log(.info, "POST https://ntfy.sh/zion-code-Ab3xY7z")
        logger.log(.warn, "ntfy response", context: "https://my.server.com/zion-code-Q9w-mZ_p")

        let output = logger.exportLog()
        XCTAssertFalse(output.contains("zion-code-Ab3xY7z"))
        XCTAssertFalse(output.contains("zion-code-Q9w-mZ_p"))
        XCTAssertTrue(output.contains("/[REDACTED]"))
    }

    func testNtfyClientRedactTopicHelper() {
        let raw = "https://ntfy.sh/zion-code-Ab3xY7z"
        XCTAssertEqual(NtfyClient.redactTopic(in: raw), "https://ntfy.sh/[REDACTED]")
        // Non-topic URLs pass through unchanged.
        XCTAssertEqual(
            NtfyClient.redactTopic(in: "https://github.com/owner/repo"),
            "https://github.com/owner/repo"
        )
    }
}
