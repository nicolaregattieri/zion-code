import XCTest
@testable import ZionMCP

final class ZionMCPSmokeTests: XCTestCase {
    func testTargetCompiles() {
        // Smoke test: ensures the ZionMCP target builds and links.
        // Tool-level tests live in ZionTests because the helpers are colocated.
        XCTAssertTrue(true)
    }
}
