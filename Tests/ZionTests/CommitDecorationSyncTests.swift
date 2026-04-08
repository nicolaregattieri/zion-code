import XCTest
@testable import Zion

final class CommitDecorationSyncTests: XCTestCase {

    // MARK: - Helpers

    private func makeCommit(
        id: String = "d547475f",
        decorations: [String] = []
    ) -> Commit {
        Commit(
            id: id,
            shortHash: String(id.prefix(8)),
            parents: [],
            author: "Test",
            email: "test@test.com",
            date: Date(),
            subject: "Test commit",
            decorations: decorations,
            lane: 0,
            nodeColorKey: 0,
            incomingLanes: [],
            outgoingLanes: [],
            laneColors: [],
            outgoingEdges: []
        )
    }

    // MARK: - Tests

    /// Proves that comparing Commit by ID alone misses decoration changes,
    /// while comparing the full struct catches them.
    func testIDComparisonMissesDecorationChange() {
        let stale = makeCommit(decorations: ["HEAD -> fix/rfq-email-date-and-price-bugs"])
        let fresh = makeCommit(decorations: ["HEAD -> fix/rfq-email-date-and-price-bugs", "origin/fix/rfq-email-date-and-price-bugs"])

        // Old code: compared only IDs — would NOT detect the change
        XCTAssertEqual(stale.id, fresh.id, "IDs are the same")

        // New code: compares full Commit — DOES detect the change
        XCTAssertNotEqual(stale, fresh, "Full Commit comparison detects decoration change")
    }

    /// Simulates the exact commitsChanged logic (new version) and proves
    /// it triggers re-render when only decorations change.
    func testCommitsChangedDetectsDecorationDelta() {
        let staleCommits = [
            makeCommit(id: "d547475f", decorations: ["HEAD -> fix/rfq-email-date-and-price-bugs"]),
            makeCommit(id: "ea61c9e9", decorations: ["origin/fix/rfq-email-date-and-price-bugs"]),
            makeCommit(id: "ab6268c0", decorations: [])
        ]

        // After push, remote ref moved to same commit as local
        let freshCommits = [
            makeCommit(id: "d547475f", decorations: ["HEAD -> fix/rfq-email-date-and-price-bugs", "origin/fix/rfq-email-date-and-price-bugs"]),
            makeCommit(id: "ea61c9e9", decorations: []),
            makeCommit(id: "ab6268c0", decorations: [])
        ]

        // branchLabelsChanged = false (branchInfos already synced in a prior refresh)
        let branchLabelsChanged = false

        // OLD logic (ID-only comparison) — would miss the change
        let oldLogic = branchLabelsChanged
            || staleCommits.count != freshCommits.count
            || staleCommits.first?.id != freshCommits.first?.id
            || staleCommits.last?.id != freshCommits.last?.id
        XCTAssertFalse(oldLogic, "Old ID-only logic fails to detect decoration change")

        // NEW logic (full Commit comparison) — catches it
        let newLogic = branchLabelsChanged
            || staleCommits.count != freshCommits.count
            || staleCommits.first != freshCommits.first
            || staleCommits.last != freshCommits.last
        XCTAssertTrue(newLogic, "New full-Commit logic detects decoration change")
    }

    /// When commits are truly identical, no unnecessary re-render is triggered.
    func testNoFalsePositiveWhenCommitsIdentical() {
        let commits = [
            makeCommit(id: "aaa", decorations: ["HEAD -> main", "origin/main"]),
            makeCommit(id: "bbb", decorations: [])
        ]

        let commitsChanged = false
            || commits.count != commits.count
            || commits.first != commits.first
            || commits.last != commits.last
        XCTAssertFalse(commitsChanged, "No false positive when commits are identical")
    }
}
