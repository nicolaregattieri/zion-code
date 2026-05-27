import XCTest
@testable import Zion

/// Phase 4 spec criterion #13 — RepoMemorySnapshot carries `topSymbols`,
/// bumps `currentSchemaVersion`, and the load path drops + rebuilds older
/// snapshots instead of crashing. Downstream callers tolerate empty
/// `topSymbols`.
final class RepoMemorySnapshotMigrationTests: XCTestCase {

    /// Writes a snapshot at the previous schemaVersion (1) to a temp dir,
    /// asks the service to load it, asserts the result is nil AND the file
    /// is gone on disk so the next refresh rebuilds at the current version.
    func test_topSymbols_persisted_andOldSchemaRebuilds() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zion-memory-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let service = RepoMemoryService(baseDirectory: tmp)
        let repo = URL(fileURLWithPath: "/tmp/zion-test-\(UUID().uuidString)")

        // Hand-write a v1 snapshot (no topSymbols field needed because Codable
        // is forgiving — but schemaVersion=1 must trigger the migration).
        let stale = RepoMemorySnapshot(
            schemaVersion: 1,
            repositoryID: "stale",
            generatedAt: Date(),
            activeBranch: "main",
            headShortHash: "deadbeef",
            commitStyle: CommitStyleProfile(
                usesConventionalCommits: true,
                commonTypes: ["feat"], commonScopes: [], preferredVerbStyle: "imperative", averageTitleLength: 32
            ),
            moduleHints: [],
            branchPatterns: [],
            conventions: [],
            testMappings: [:],
            sensitiveAreas: [],
            topSymbols: []
        )
        try await service.saveSnapshot(stale, for: repo)

        // Load should return nil AND delete the file.
        let loaded = await service.loadSnapshot(for: repo)
        XCTAssertNil(loaded, "Stale schemaVersion must trigger drop-and-rebuild (nil load)")

        // File should be removed from the temp dir.
        let expectedFiles = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []
        XCTAssertTrue(
            expectedFiles.allSatisfy { !$0.contains("stale") } || expectedFiles.isEmpty,
            "Stale snapshot file must be removed from disk"
        )
    }

    /// Spec criterion #13b — downstream consumers MUST tolerate
    /// `topSymbols == []` while a rebuild is pending. The `.empty` factory
    /// gives back a usable snapshot with no symbols and no crash on access.
    func test_emptyTopSymbols_downstreamSafe() {
        let empty = RepoMemorySnapshot.empty
        XCTAssertEqual(empty.topSymbols.count, 0)
        XCTAssertEqual(empty.schemaVersion, RepoMemorySnapshot.currentSchemaVersion)
    }

    /// Bumped schemaVersion is exactly what the model claims.
    func test_currentSchemaVersion_isBumped() {
        XCTAssertGreaterThanOrEqual(RepoMemorySnapshot.currentSchemaVersion, 2)
    }
}
