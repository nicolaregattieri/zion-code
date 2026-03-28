import XCTest
@testable import Zion

final class RepositoryRefreshPolicyTests: XCTestCase {
    @MainActor
    func testFileWatcherRefreshIsNotSkippedWhileBusy() {
        XCTAssertFalse(
            RepositoryViewModel.shouldSkipRefreshWhileBusy(
                setBusy: false,
                isBusy: true,
                origin: .fileWatcher
            )
        )
    }

    @MainActor
    func testAutoTimerRefreshIsSkippedWhileBusy() {
        XCTAssertTrue(
            RepositoryViewModel.shouldSkipRefreshWhileBusy(
                setBusy: false,
                isBusy: true,
                origin: .autoTimer
            )
        )
    }

    @MainActor
    func testPartialRefreshPreservesTagsAndStashesWhenTheyWereNotReloaded() {
        let model = RepositoryViewModel()
        model.tags = ["v1.2.3"]
        model.stashes = ["stash@{0}: WIP on main"]
        model.selectedStash = "stash@{0}: WIP on main"

        let payload = RepositoryLoadPayload(
            currentBranch: "main",
            headShortHash: "abc1234",
            branchInfos: [],
            branches: [],
            focusedBranch: nil,
            branchTree: [],
            tags: [],
            stashes: [],
            selectedStash: "",
            worktrees: [],
            remotes: [],
            commits: [],
            hasMoreCommits: false,
            selectedCommitID: nil,
            hasConflicts: false,
            isMerging: false,
            isRebasing: false,
            isCherryPicking: false,
            isGitRepository: true,
            uncommittedChanges: [],
            uncommittedCount: 0,
            isBisecting: false,
            bisectCurrentHash: ""
        )

        model.applyTagAndStashPayload(payload, includeTagsAndStashes: false)

        XCTAssertEqual(model.tags, ["v1.2.3"])
        XCTAssertEqual(model.stashes, ["stash@{0}: WIP on main"])
        XCTAssertEqual(model.selectedStash, "stash@{0}: WIP on main")
    }

    @MainActor
    func testFullRefreshReplacesTagsAndStashesWhenTheyWereReloaded() {
        let model = RepositoryViewModel()
        model.tags = ["v1.2.3"]
        model.stashes = ["stash@{0}: old"]
        model.selectedStash = "stash@{0}: old"

        let payload = RepositoryLoadPayload(
            currentBranch: "main",
            headShortHash: "def5678",
            branchInfos: [],
            branches: [],
            focusedBranch: nil,
            branchTree: [],
            tags: ["v1.2.4"],
            stashes: ["stash@{0}: new"],
            selectedStash: "stash@{0}: new",
            worktrees: [],
            remotes: [],
            commits: [],
            hasMoreCommits: false,
            selectedCommitID: nil,
            hasConflicts: false,
            isMerging: false,
            isRebasing: false,
            isCherryPicking: false,
            isGitRepository: true,
            uncommittedChanges: [],
            uncommittedCount: 0,
            isBisecting: false,
            bisectCurrentHash: ""
        )

        model.applyTagAndStashPayload(payload, includeTagsAndStashes: true)

        XCTAssertEqual(model.tags, ["v1.2.4"])
        XCTAssertEqual(model.stashes, ["stash@{0}: new"])
        XCTAssertEqual(model.selectedStash, "stash@{0}: new")
    }
}
