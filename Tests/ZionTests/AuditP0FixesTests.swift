import XCTest
@testable import Zion

/// Audit P0/P1 fixes (2026-05-29). Pins the contracts the audit exposed:
/// - `MCPClientPool.warmFromDisk` reads `~/.zion/mcp.json` directly.
/// - `laneForIntent` maps git intents onto the right `AITaskLane`.
final class AuditP0FixesTests: XCTestCase {

    // MARK: - Lane-for-intent mapping

    func test_laneForIntent_status_mapsToCheapSummary() {
        XCTAssertEqual(ChatService.laneForIntent(text: "what's the status?"), .cheapSummary)
    }

    func test_laneForIntent_recentHistory_mapsToCheapSummary() {
        XCTAssertEqual(ChatService.laneForIntent(text: "show recent commits"), .cheapSummary)
    }

    func test_laneForIntent_currentChanges_mapsToReview() {
        XCTAssertEqual(ChatService.laneForIntent(text: "review my current changes"), .review)
    }

    func test_laneForIntent_lastCommit_mapsToGeneral() {
        XCTAssertEqual(ChatService.laneForIntent(text: "show me the last commit"), .general)
    }

    func test_laneForIntent_unknown_returnsNil() {
        XCTAssertNil(ChatService.laneForIntent(text: "tell me a joke"))
    }

    // MARK: - Pool warm-from-disk smoke

    func test_pool_warmFromDisk_consumeErrors_resetsAfterRead() async {
        // Smoke: we can't safely mutate ~/.zion/mcp.json from tests, but we
        // CAN exercise the consume-and-clear semantics on a fresh actor.
        let errs1 = await MCPClientPool.shared.consumeWarmErrors()
        let errs2 = await MCPClientPool.shared.consumeWarmErrors()
        // Second consume must always be empty regardless of first.
        XCTAssertTrue(errs2.isEmpty, "consumeWarmErrors must reset")
        // First consume is non-deterministic across test runs (may contain
        // residue from prior warms), so we only assert idempotency.
        _ = errs1
    }
}
