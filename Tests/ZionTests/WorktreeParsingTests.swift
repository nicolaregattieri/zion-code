import XCTest
@testable import Zion

final class WorktreeParsingTests: XCTestCase {
    private let worker = RepositoryWorker()

    // MARK: - Basic Parsing

    func testParseSimpleWorktree() async {
        let output = """
        worktree /Users/dev/project
        HEAD abc123def456789012345678901234567890abcd
        branch refs/heads/main

        """
        let items = await worker.parseWorktrees(from: output, currentPath: "/Users/dev/other")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].path, "/Users/dev/project")
        XCTAssertEqual(items[0].head, "abc123de")  // 8 chars
        XCTAssertEqual(items[0].branch, "main")
        XCTAssertFalse(items[0].isDetached)
        XCTAssertFalse(items[0].isLocked)
        XCTAssertFalse(items[0].isPrunable)
    }

    func testParseDetachedWorktree() async {
        let output = """
        worktree /Users/dev/detached-wt
        HEAD abc123def456789012345678901234567890abcd
        detached

        """
        let items = await worker.parseWorktrees(from: output, currentPath: "/other")

        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isDetached)
        XCTAssertEqual(items[0].branch, "detached")
    }

    func testParseLockedWorktree() async {
        let output = """
        worktree /Users/dev/locked-wt
        HEAD abc123def456789012345678901234567890abcd
        branch refs/heads/feature
        locked

        """
        let items = await worker.parseWorktrees(from: output, currentPath: "/other")

        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isLocked)
        XCTAssertEqual(items[0].lockReason, "")
    }

    func testParseLockedWithReason() async {
        let output = """
        worktree /Users/dev/locked-wt
        HEAD abc123def456789012345678901234567890abcd
        branch refs/heads/feature
        locked working on experiment

        """
        let items = await worker.parseWorktrees(from: output, currentPath: "/other")

        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isLocked)
        XCTAssertEqual(items[0].lockReason, "working on experiment")
    }

    func testParsePrunableWorktree() async {
        let output = """
        worktree /Users/dev/prunable-wt
        HEAD abc123def456789012345678901234567890abcd
        branch refs/heads/old
        prunable gitdir file points to non-existent location

        """
        let items = await worker.parseWorktrees(from: output, currentPath: "/other")

        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isPrunable)
        XCTAssertEqual(items[0].pruneReason, "gitdir file points to non-existent location")
    }

    // MARK: - Multiple Worktrees

    func testParseMultipleWorktrees() async {
        let output = """
        worktree /Users/dev/project
        HEAD aaa1111111111111111111111111111111111111a
        branch refs/heads/main

        worktree /Users/dev/project-feature
        HEAD bbb2222222222222222222222222222222222222b
        branch refs/heads/feature

        worktree /Users/dev/project-hotfix
        HEAD ccc3333333333333333333333333333333333333c
        branch refs/heads/hotfix

        """
        let items = await worker.parseWorktrees(from: output, currentPath: "/other")

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].branch, "main")
        XCTAssertEqual(items[1].branch, "feature")
        XCTAssertEqual(items[2].branch, "hotfix")
    }

    // MARK: - isCurrent Detection

    func testIsCurrentBasedOnPath() async {
        let output = """
        worktree /Users/dev/project
        HEAD abc123def456789012345678901234567890abcd
        branch refs/heads/main

        """
        let items = await worker.parseWorktrees(from: output, currentPath: "/Users/dev/project")

        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isCurrent)
    }

    func testIsCurrentFalseForDifferentPath() async {
        let output = """
        worktree /Users/dev/project
        HEAD abc123def456789012345678901234567890abcd
        branch refs/heads/main

        """
        let items = await worker.parseWorktrees(from: output, currentPath: "/Users/dev/other-project")

        XCTAssertFalse(items[0].isCurrent)
    }

    // MARK: - Branch Normalization

    func testBranchRemovesRefsHeads() async {
        let output = """
        worktree /test
        HEAD abc123def456789012345678901234567890abcd
        branch refs/heads/feature/login

        """
        let items = await worker.parseWorktrees(from: output, currentPath: "/other")

        XCTAssertEqual(items[0].branch, "feature/login")
    }

    func testBranchRemovesRefsRemotes() async {
        let output = """
        worktree /test
        HEAD abc123def456789012345678901234567890abcd
        branch refs/remotes/origin/main

        """
        let items = await worker.parseWorktrees(from: output, currentPath: "/other")

        XCTAssertEqual(items[0].branch, "origin/main")
    }

    func testEmptyBranchBecomesDetached() async {
        let output = """
        worktree /test
        HEAD abc123def456789012345678901234567890abcd

        """
        let items = await worker.parseWorktrees(from: output, currentPath: "/other")

        XCTAssertEqual(items[0].branch, "detached")
    }

    // MARK: - Empty Output

    func testParseEmptyOutput() async {
        let items = await worker.parseWorktrees(from: "", currentPath: "/test")
        XCTAssertTrue(items.isEmpty)
    }
}
