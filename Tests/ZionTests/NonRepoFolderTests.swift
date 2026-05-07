import XCTest
@testable import Zion

@MainActor
final class NonRepoFolderTests: XCTestCase {

    func testRefreshForCodeTabOnlyOnNonRepoCallsOnFinishAndClearsStaleFields() {
        let model = RepositoryViewModel()
        model.repositoryURL = URL(fileURLWithPath: "/tmp")
        model.isGitRepository = false

        // Stale fields from a previous repo open.
        model.currentBranch = "feature/x"
        model.headShortHash = "abc1234"
        model.uncommittedChanges = ["?? a.txt"]
        model.uncommittedCount = 1
        model.hasConflicts = true

        var onFinishCount = 0
        model.refreshForCodeTabOnly { onFinishCount += 1 }

        XCTAssertEqual(onFinishCount, 1, "onFinish must be called exactly once on the non-repo path")
        XCTAssertEqual(model.currentBranch, "")
        XCTAssertEqual(model.headShortHash, "")
        XCTAssertEqual(model.uncommittedChanges, [])
        XCTAssertEqual(model.uncommittedCount, 0)
        XCTAssertFalse(model.hasConflicts)
    }

    func testRefreshCodeMinimalOnNonRepoIsNoOp() {
        let model = RepositoryViewModel()
        model.repositoryURL = URL(fileURLWithPath: "/tmp")
        model.isGitRepository = false
        model.currentBranch = "main"
        model.treeOpsDataStale = false

        model.refreshCodeMinimal()

        // The guard returns immediately. Field stays untouched and the stale
        // flag is NOT flipped (no tree-ops drift on a non-repo folder).
        XCTAssertEqual(model.currentBranch, "main")
        XCTAssertFalse(model.treeOpsDataStale)
    }

    func testRefreshRepositoryWithoutURLCallsOnFinish() {
        let model = RepositoryViewModel()
        model.repositoryURL = nil

        var onFinishCount = 0
        model.refreshRepository(setBusy: false, origin: .userInitiated) {
            onFinishCount += 1
        }

        XCTAssertEqual(onFinishCount, 1, "refreshRepository must drain onFinish even when repositoryURL is nil")
    }

    func testRefreshRepositoryZenSkipPathCallsOnFinish() {
        let model = RepositoryViewModel()
        model.repositoryURL = URL(fileURLWithPath: "/tmp")
        model.isZenModePaused = true

        var onFinishCount = 0
        // .autoTimer + zen-paused -> evaluateRefreshGate returns .skip
        model.refreshRepository(setBusy: false, origin: .autoTimer) {
            onFinishCount += 1
        }

        XCTAssertEqual(onFinishCount, 1, "refreshRepository .skip path must drain onFinish")
    }

    func testRefreshRepositoryRedirectPathCallsOnFinish() {
        let model = RepositoryViewModel()
        model.repositoryURL = URL(fileURLWithPath: "/tmp")
        model.isGitRepository = false  // refreshCodeMinimal early-returns
        model.activeSection = .code

        var onFinishCount = 0
        // .fileWatcher + Code section -> .redirect to refreshCodeMinimal
        // (which itself early-returns because !isGitRepository).
        // The outer caller's onFinish must still drain.
        model.refreshRepository(setBusy: false, origin: .fileWatcher) {
            onFinishCount += 1
        }

        XCTAssertEqual(onFinishCount, 1, "refreshRepository .redirect path must drain onFinish")
    }

    func testWipeRepoStateForNonRepoClearsAllGitFields() {
        let model = RepositoryViewModel()
        model.currentBranch = "main"
        model.headShortHash = "abc1234"
        model.focusedBranch = "feature/x"
        model.branches = ["main", "feature/x"]
        model.tags = ["v1.0"]
        model.stashes = ["stash@{0}: WIP"]
        model.selectedStash = "stash@{0}: WIP"
        model.worktrees = []
        model.commits = []
        model.uncommittedChanges = ["?? a.txt"]
        model.uncommittedCount = 1
        model.hasConflicts = true
        model.isMerging = true
        model.isRebasing = true
        model.hasMoreCommits = true
        model.selectedCommitID = "deadbeef"

        model.wipeRepoStateForNonRepo()

        XCTAssertEqual(model.currentBranch, "")
        XCTAssertEqual(model.headShortHash, "")
        XCTAssertNil(model.focusedBranch)
        XCTAssertEqual(model.branches, [])
        XCTAssertEqual(model.tags, [])
        XCTAssertEqual(model.stashes, [])
        XCTAssertEqual(model.selectedStash, "")
        XCTAssertEqual(model.uncommittedChanges, [])
        XCTAssertEqual(model.uncommittedCount, 0)
        XCTAssertFalse(model.hasConflicts)
        XCTAssertFalse(model.isMerging)
        XCTAssertFalse(model.isRebasing)
        XCTAssertFalse(model.hasMoreCommits)
        XCTAssertNil(model.selectedCommitID)
    }
}
