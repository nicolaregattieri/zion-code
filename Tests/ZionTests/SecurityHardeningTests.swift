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
}
