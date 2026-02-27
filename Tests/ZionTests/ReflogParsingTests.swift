import XCTest
@testable import Zion

@MainActor
final class ReflogParsingTests: XCTestCase {

    // MARK: - parseReflogOutput

    // Format: hash|shortHash|refName|message|date|relativeDate
    // action is derived from message by splitting on ":"

    func testParseCheckoutEntry() {
        let raw = "abc1234|abc1|HEAD@{0}|checkout: moving from main to feature|2025-01-15 10:30:00 +0000|5 minutes ago"
        let entries = RepositoryViewModel.parseReflogOutput(raw)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].action, "checkout")
        XCTAssertEqual(entries[0].branch, "feature")
    }

    func testParseCommitEntry() {
        let raw = "abc1234|abc1|HEAD@{0}|commit: Add new feature|2025-01-15 10:30:00 +0000|2 hours ago"
        let entries = RepositoryViewModel.parseReflogOutput(raw)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].action, "commit")
        XCTAssertEqual(entries[0].detail, "Add new feature")
    }

    func testParseMultipleEntries() {
        let raw = [
            "abc1234|abc1|HEAD@{0}|commit: Third|2025-01-15 12:00:00 +0000|1 min ago",
            "def5678|def5|HEAD@{1}|checkout: moving from main to feature|2025-01-15 11:00:00 +0000|1 hour ago",
            "ghi9012|ghi9|HEAD@{2}|commit: First|2025-01-15 10:00:00 +0000|2 hours ago",
        ].joined(separator: "\n")
        let entries = RepositoryViewModel.parseReflogOutput(raw)

        XCTAssertEqual(entries.count, 3)
    }

    func testParseEmptyOutput() {
        let entries = RepositoryViewModel.parseReflogOutput("")
        XCTAssertTrue(entries.isEmpty)
    }

    func testParseTooFewFieldsIgnored() {
        let raw = "abc1234|abc1|HEAD@{0}|commit"  // Only 4 fields, need >= 6
        let entries = RepositoryViewModel.parseReflogOutput(raw)

        XCTAssertTrue(entries.isEmpty)
    }

    func testBranchTrackingAfterCheckout() {
        // Entries are newest→oldest. A checkout at index 1 sets branchStack for entries below.
        let raw = [
            "abc1234|abc1|HEAD@{0}|commit: Work on feature|2025-01-15 12:00:00 +0000|1 min ago",
            "def5678|def5|HEAD@{1}|checkout: moving from main to feature|2025-01-15 11:00:00 +0000|1 hour ago",
            "ghi9012|ghi9|HEAD@{2}|commit: Work on main|2025-01-15 10:00:00 +0000|2 hours ago",
        ].joined(separator: "\n")
        let entries = RepositoryViewModel.parseReflogOutput(raw)

        // Entry 0: commit, should be on "feature" (the "to" of the first checkout)
        XCTAssertEqual(entries[0].branch, "feature")
        // Entry 1: checkout itself, branch = "feature" (the "to")
        XCTAssertEqual(entries[1].branch, "feature")
        // Entry 2: after processing checkout, branchStack = "main" (the "from")
        XCTAssertEqual(entries[2].branch, "main")
    }

    func testParseDateFormat() {
        let raw = "abc1234|abc1|HEAD@{0}|commit: test|2025-06-15 14:30:00 +0000|now"
        let entries = RepositoryViewModel.parseReflogOutput(raw)

        XCTAssertEqual(entries.count, 1)
        XCTAssertNotEqual(entries[0].date, .distantPast)
    }

    // MARK: - parseCheckoutBranches

    func testParseCheckoutBranchesValid() {
        let result = ReflogEntry.parseCheckoutBranches(from: "checkout: moving from main to feature/login")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.from, "main")
        XCTAssertEqual(result?.to, "feature/login")
    }

    func testParseCheckoutBranchesInvalidMessage() {
        let result = ReflogEntry.parseCheckoutBranches(from: "commit: Add new feature")
        XCTAssertNil(result)
    }

    func testParseCheckoutBranchesNoMovingFrom() {
        let result = ReflogEntry.parseCheckoutBranches(from: "checkout: something else entirely")
        XCTAssertNil(result)
    }

    // MARK: - humanDetail

    func testHumanDetailCommit() {
        let detail = ReflogEntry.humanDetail(from: "commit: Add login page", action: "commit")
        XCTAssertEqual(detail, "Add login page")
    }

    func testHumanDetailCommitInitial() {
        let detail = ReflogEntry.humanDetail(from: "commit (initial): Initial commit", action: "commit (initial)")
        XCTAssertEqual(detail, "Initial commit")
    }

    func testHumanDetailCommitAmend() {
        let detail = ReflogEntry.humanDetail(from: "commit (amend): Fix typo", action: "commit (amend)")
        XCTAssertEqual(detail, "Amended: Fix typo")
    }

    func testHumanDetailCheckout() {
        let detail = ReflogEntry.humanDetail(from: "checkout: moving from main to develop", action: "checkout")
        XCTAssertEqual(detail, "main → develop")
    }

    func testHumanDetailMerge() {
        let detail = ReflogEntry.humanDetail(from: "merge: feature/login", action: "merge")
        XCTAssertEqual(detail, "Merged feature/login")
    }

    func testHumanDetailRebaseFinish() {
        let detail = ReflogEntry.humanDetail(from: "rebase (finish): refs/heads/main onto abc1234", action: "rebase")
        XCTAssertEqual(detail, "Rebase completed")
    }

    func testHumanDetailRebaseStart() {
        let detail = ReflogEntry.humanDetail(from: "rebase (start): checkout abc1234", action: "rebase")
        XCTAssertEqual(detail, "Rebase started")
    }

    func testHumanDetailReset() {
        let detail = ReflogEntry.humanDetail(from: "reset: moving to HEAD", action: "reset")
        XCTAssertEqual(detail, "Discarded staged changes")
    }

    func testHumanDetailResetToCommit() {
        let detail = ReflogEntry.humanDetail(from: "reset: moving to abc12345678", action: "reset")
        XCTAssertEqual(detail, "Moved HEAD to abc12345…")
    }

    func testHumanDetailPull() {
        let detail = ReflogEntry.humanDetail(from: "pull: Fast-forward", action: "pull")
        XCTAssertEqual(detail, "Pulled remote changes")
    }

    func testHumanDetailCherryPick() {
        let detail = ReflogEntry.humanDetail(from: "cherry-pick: Fix critical bug", action: "cherry-pick")
        XCTAssertEqual(detail, "Fix critical bug")
    }

    // MARK: - tooltip

    func testTooltipForKnownActions() {
        XCTAssertNotNil(ReflogEntry.tooltip(for: "reset"))
        XCTAssertNotNil(ReflogEntry.tooltip(for: "rebase"))
        XCTAssertNotNil(ReflogEntry.tooltip(for: "cherry-pick"))
        XCTAssertNotNil(ReflogEntry.tooltip(for: "merge"))
        XCTAssertNotNil(ReflogEntry.tooltip(for: "checkout"))
    }

    func testTooltipForUnknownActionIsNil() {
        XCTAssertNil(ReflogEntry.tooltip(for: "commit"))
        XCTAssertNil(ReflogEntry.tooltip(for: "pull"))
        XCTAssertNil(ReflogEntry.tooltip(for: "unknown"))
    }
}
