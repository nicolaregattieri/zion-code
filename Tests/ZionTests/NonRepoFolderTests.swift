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
}
