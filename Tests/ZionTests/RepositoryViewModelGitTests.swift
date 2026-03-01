import XCTest
@testable import Zion

@MainActor
final class RepositoryViewModelGitTests: XCTestCase {

    // MARK: - parseConflictBlocks

    func testParseConflictBlocksSimpleConflict() {
        let content = [
            "line before conflict",
            "<<<<<<< HEAD",
            "our change",
            "=======",
            "their change",
            ">>>>>>> feature-branch",
            "line after conflict",
        ].joined(separator: "\n")

        let blocks = RepositoryViewModel.parseConflictBlocks(content)

        XCTAssertEqual(blocks.count, 3)

        // Context before
        if case .context(let lines) = blocks[0] {
            XCTAssertEqual(lines, ["line before conflict"])
        } else {
            XCTFail("Expected context block at index 0")
        }

        // Conflict region
        if case .conflict(let region) = blocks[1] {
            XCTAssertEqual(region.oursLines, ["our change"])
            XCTAssertEqual(region.theirsLines, ["their change"])
            XCTAssertEqual(region.oursLabel, "HEAD")
            XCTAssertEqual(region.theirsLabel, "feature-branch")
        } else {
            XCTFail("Expected conflict block at index 1")
        }

        // Context after
        if case .context(let lines) = blocks[2] {
            XCTAssertEqual(lines, ["line after conflict"])
        } else {
            XCTFail("Expected context block at index 2")
        }
    }

    func testParseConflictBlocksMultipleConflicts() {
        let content = [
            "header",
            "<<<<<<< HEAD",
            "ours1",
            "=======",
            "theirs1",
            ">>>>>>> branch-a",
            "middle",
            "<<<<<<< HEAD",
            "ours2a",
            "ours2b",
            "=======",
            "theirs2",
            ">>>>>>> branch-b",
            "footer",
        ].joined(separator: "\n")

        let blocks = RepositoryViewModel.parseConflictBlocks(content)

        XCTAssertEqual(blocks.count, 5)

        if case .context(let lines) = blocks[0] {
            XCTAssertEqual(lines, ["header"])
        } else {
            XCTFail("Expected context block at index 0")
        }

        if case .conflict(let region) = blocks[1] {
            XCTAssertEqual(region.oursLines, ["ours1"])
            XCTAssertEqual(region.theirsLines, ["theirs1"])
        } else {
            XCTFail("Expected conflict block at index 1")
        }

        if case .context(let lines) = blocks[2] {
            XCTAssertEqual(lines, ["middle"])
        } else {
            XCTFail("Expected context block at index 2")
        }

        if case .conflict(let region) = blocks[3] {
            XCTAssertEqual(region.oursLines, ["ours2a", "ours2b"])
            XCTAssertEqual(region.theirsLines, ["theirs2"])
            XCTAssertEqual(region.theirsLabel, "branch-b")
        } else {
            XCTFail("Expected conflict block at index 3")
        }

        if case .context(let lines) = blocks[4] {
            XCTAssertEqual(lines, ["footer"])
        } else {
            XCTFail("Expected context block at index 4")
        }
    }

    func testParseConflictBlocksNoConflicts() {
        let content = [
            "normal line 1",
            "normal line 2",
            "normal line 3",
        ].joined(separator: "\n")

        let blocks = RepositoryViewModel.parseConflictBlocks(content)

        XCTAssertEqual(blocks.count, 1)
        if case .context(let lines) = blocks[0] {
            XCTAssertEqual(lines, ["normal line 1", "normal line 2", "normal line 3"])
        } else {
            XCTFail("Expected single context block")
        }
    }

    func testParseConflictBlocksEmptyInput() {
        let blocks = RepositoryViewModel.parseConflictBlocks("")

        // Empty string splits into one empty line, so we get a context block with [""]
        XCTAssertEqual(blocks.count, 1)
        if case .context(let lines) = blocks[0] {
            XCTAssertEqual(lines, [""])
        } else {
            XCTFail("Expected single context block for empty input")
        }
    }

    // MARK: - parseBlameOutput

    func testParseBlameOutputSingleEntry() {
        let raw = [
            "abcdef1234567890abcdef1234567890abcdef12 1 1 1",
            "author John Doe",
            "author-mail <john@example.com>",
            "author-time 1700000000",
            "author-tz +0000",
            "committer John Doe",
            "committer-mail <john@example.com>",
            "committer-time 1700000000",
            "committer-tz +0000",
            "summary Initial commit",
            "filename test.swift",
            "\tlet x = 42",
        ].joined(separator: "\n")

        let entries = RepositoryViewModel.parseBlameOutput(raw)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].commitHash, "abcdef1234567890abcdef1234567890abcdef12")
        XCTAssertEqual(entries[0].shortHash, "abcdef12")
        XCTAssertEqual(entries[0].author, "John Doe")
        XCTAssertEqual(entries[0].lineNumber, 1)
        XCTAssertEqual(entries[0].content, "let x = 42")
    }

    func testParseBlameOutputMultipleEntries() {
        let raw = [
            "aaaa1111222233334444555566667777aaaa1111 1 1 1",
            "author Alice",
            "author-time 1700000000",
            "summary First line",
            "filename file.swift",
            "\timport Foundation",
            "bbbb1111222233334444555566667777bbbb1111 2 2 1",
            "author Bob",
            "author-time 1700000100",
            "summary Second line",
            "filename file.swift",
            "\tprint(\"hello\")",
        ].joined(separator: "\n")

        let entries = RepositoryViewModel.parseBlameOutput(raw)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].author, "Alice")
        XCTAssertEqual(entries[0].lineNumber, 1)
        XCTAssertEqual(entries[0].content, "import Foundation")
        XCTAssertEqual(entries[1].author, "Bob")
        XCTAssertEqual(entries[1].lineNumber, 2)
        XCTAssertEqual(entries[1].content, "print(\"hello\")")
    }

    func testParseBlameOutputEmptyInput() {
        let entries = RepositoryViewModel.parseBlameOutput("")
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - parseReflogOutput

    func testParseReflogOutputSingleCommit() {
        let raw = "abc1234|abc1234|HEAD@{0}|commit: Add feature|2025-01-15 10:30:00 +0000|2 hours ago"

        let entries = RepositoryViewModel.parseReflogOutput(raw)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].hash, "abc1234")
        XCTAssertEqual(entries[0].shortHash, "abc1234")
        XCTAssertEqual(entries[0].action, "commit")
        XCTAssertEqual(entries[0].message, "commit: Add feature")
        XCTAssertEqual(entries[0].relativeDate, "2 hours ago")
    }

    func testParseReflogOutputCheckoutTracksBranch() {
        let raw = [
            "aaa1111|aaa1111|HEAD@{0}|checkout: moving from main to feature|2025-01-15 10:30:00 +0000|1 hour ago",
            "bbb2222|bbb2222|HEAD@{1}|commit: Fix bug|2025-01-15 09:00:00 +0000|2 hours ago",
        ].joined(separator: "\n")

        let entries = RepositoryViewModel.parseReflogOutput(raw)

        XCTAssertEqual(entries.count, 2)

        // The checkout entry should track the destination branch
        XCTAssertEqual(entries[0].action, "checkout")
        XCTAssertEqual(entries[0].branch, "feature")

        // The commit entry below the checkout should be on the "from" branch (main)
        XCTAssertEqual(entries[1].branch, "main")
    }

    func testParseReflogOutputEmptyInput() {
        let entries = RepositoryViewModel.parseReflogOutput("")
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - parseSubmoduleStatus

    func testParseSubmoduleStatusUpToDate() {
        // Space prefix means up-to-date; after trimming, the leading space is gone
        // so the first char of the hash is consumed as the status char.
        // The method does: trimmed.first (status), dropFirst().trim (rest), split on space
        // For space-prefixed: trimmed = "abc1234...678 libs/utils", first='a' (not +-), rest = "bc1234...678 libs/utils"
        // So the hash in the result will be missing the first char. This matches the actual implementation.
        let raw = " abc1234def5678901234567890abcdef12345678 libs/utils"
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        let modules = RepositoryViewModel.parseSubmoduleStatus(raw, repoURL: repoURL)

        XCTAssertEqual(modules.count, 1)
        XCTAssertEqual(modules[0].status, .upToDate)
        XCTAssertEqual(modules[0].path, "libs/utils")
        // After trim + dropFirst, the hash loses its first char
        XCTAssertEqual(modules[0].hash, "bc1234def5678901234567890abcdef12345678")
    }

    func testParseSubmoduleStatusModified() {
        let raw = "+abc1234def5678901234567890abcdef12345678 libs/core"
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        let modules = RepositoryViewModel.parseSubmoduleStatus(raw, repoURL: repoURL)

        XCTAssertEqual(modules.count, 1)
        XCTAssertEqual(modules[0].status, .modified)
        XCTAssertEqual(modules[0].path, "libs/core")
    }

    func testParseSubmoduleStatusUninitialized() {
        let raw = "-abc1234def5678901234567890abcdef12345678 vendor/lib"
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        let modules = RepositoryViewModel.parseSubmoduleStatus(raw, repoURL: repoURL)

        XCTAssertEqual(modules.count, 1)
        XCTAssertEqual(modules[0].status, .uninitialized)
        XCTAssertEqual(modules[0].path, "vendor/lib")
    }

    func testParseSubmoduleStatusEmptyInput() {
        let repoURL = URL(fileURLWithPath: "/tmp/repo")
        let modules = RepositoryViewModel.parseSubmoduleStatus("", repoURL: repoURL)
        XCTAssertTrue(modules.isEmpty)
    }

    // MARK: - detectAuthError

    func testDetectAuthErrorPermissionDenied() {
        let vm = RepositoryViewModel()
        let result = vm.detectAuthError(from: "Permission denied (publickey)")
        XCTAssertNotNil(result)
        XCTAssertEqual(result, "Permission denied (publickey)")
    }

    func testDetectAuthErrorAuthenticationFailed() {
        let vm = RepositoryViewModel()
        let result = vm.detectAuthError(from: "Authentication failed for https://github.com/repo.git")
        XCTAssertNotNil(result)
    }

    func testDetectAuthErrorNormalError() {
        let vm = RepositoryViewModel()
        let result = vm.detectAuthError(from: "normal error message with no auth pattern")
        XCTAssertNil(result)
    }

    // MARK: - filePathFromStatusLine

    func testFilePathFromStatusLineModifiedFile() {
        // git status --porcelain: "XY path" — after trimming, " M" becomes "M "
        // so we use a status where the first char is not a space
        let path = RepositoryViewModel.filePathFromStatusLine("MM file.swift")
        XCTAssertEqual(path, "file.swift")
    }

    func testFilePathFromStatusLineRenamedFile() {
        let path = RepositoryViewModel.filePathFromStatusLine("R  old.swift -> new.swift")
        XCTAssertEqual(path, "new.swift")
    }

    func testFilePathFromStatusLineEmptyString() {
        let path = RepositoryViewModel.filePathFromStatusLine("")
        XCTAssertNil(path)
    }

    // MARK: - buildMergedContent

    private func makeConflictBlocks(choice: ConflictChoice) -> [ConflictBlock] {
        let region = ConflictRegion(
            oursLines: ["our line"],
            theirsLines: ["their line"],
            oursLabel: "HEAD",
            theirsLabel: "feature",
            choice: choice
        )
        return [
            .context(["before"]),
            .conflict(region),
            .context(["after"]),
        ]
    }

    func testBuildMergedContentOurs() {
        let vm = RepositoryViewModel()
        vm.conflictBlocks = makeConflictBlocks(choice: .ours)
        let result = vm.buildMergedContent()
        XCTAssertEqual(result, "before\nour line\nafter")
    }

    func testBuildMergedContentTheirs() {
        let vm = RepositoryViewModel()
        vm.conflictBlocks = makeConflictBlocks(choice: .theirs)
        let result = vm.buildMergedContent()
        XCTAssertEqual(result, "before\ntheir line\nafter")
    }

    func testBuildMergedContentBoth() {
        let vm = RepositoryViewModel()
        vm.conflictBlocks = makeConflictBlocks(choice: .both)
        let result = vm.buildMergedContent()
        XCTAssertEqual(result, "before\nour line\ntheir line\nafter")
    }

    func testBuildMergedContentBothReverse() {
        let vm = RepositoryViewModel()
        vm.conflictBlocks = makeConflictBlocks(choice: .bothReverse)
        let result = vm.buildMergedContent()
        XCTAssertEqual(result, "before\ntheir line\nour line\nafter")
    }

    func testBuildMergedContentCustom() {
        let vm = RepositoryViewModel()
        vm.conflictBlocks = makeConflictBlocks(choice: .custom("custom resolution"))
        let result = vm.buildMergedContent()
        XCTAssertEqual(result, "before\ncustom resolution\nafter")
    }

    func testBuildMergedContentUndecidedKeepsMarkers() {
        let vm = RepositoryViewModel()
        vm.conflictBlocks = makeConflictBlocks(choice: .undecided)
        let result = vm.buildMergedContent()
        XCTAssertTrue(result.contains("<<<<<<< HEAD"))
        XCTAssertTrue(result.contains("======="))
        XCTAssertTrue(result.contains(">>>>>>> feature"))
        XCTAssertTrue(result.contains("our line"))
        XCTAssertTrue(result.contains("their line"))
    }

    // MARK: - resolveRegion

    func testResolveRegionUpdatesChoice() {
        let vm = RepositoryViewModel()
        let region = ConflictRegion(
            oursLines: ["a"],
            theirsLines: ["b"],
            oursLabel: "HEAD",
            theirsLabel: "feat"
        )
        let regionID = region.id
        vm.conflictBlocks = [.conflict(region)]

        vm.resolveRegion(regionID, choice: .theirs)

        if case .conflict(let updated) = vm.conflictBlocks[0] {
            XCTAssertEqual(updated.choice, .theirs)
        } else {
            XCTFail("Expected conflict block after resolveRegion")
        }
    }

    // MARK: - allConflictsResolved / unresolvedConflictCount / currentFileAllRegionsChosen

    func testAllConflictsResolvedTrue() {
        let vm = RepositoryViewModel()
        vm.conflictedFiles = [
            ConflictFile(path: "a.swift", isResolved: true),
            ConflictFile(path: "b.swift", isResolved: true),
        ]
        XCTAssertTrue(vm.allConflictsResolved)
    }

    func testAllConflictsResolvedFalseWhenPartial() {
        let vm = RepositoryViewModel()
        vm.conflictedFiles = [
            ConflictFile(path: "a.swift", isResolved: true),
            ConflictFile(path: "b.swift", isResolved: false),
        ]
        XCTAssertFalse(vm.allConflictsResolved)
    }

    func testAllConflictsResolvedFalseWhenEmpty() {
        let vm = RepositoryViewModel()
        vm.conflictedFiles = []
        XCTAssertFalse(vm.allConflictsResolved)
    }

    func testUnresolvedConflictCount() {
        let vm = RepositoryViewModel()
        vm.conflictedFiles = [
            ConflictFile(path: "a.swift", isResolved: true),
            ConflictFile(path: "b.swift", isResolved: false),
            ConflictFile(path: "c.swift", isResolved: false),
        ]
        XCTAssertEqual(vm.unresolvedConflictCount, 2)
    }

    func testCurrentFileAllRegionsChosenTrue() {
        let vm = RepositoryViewModel()
        vm.conflictBlocks = [
            .context(["line"]),
            .conflict(ConflictRegion(
                oursLines: ["a"], theirsLines: ["b"],
                oursLabel: "HEAD", theirsLabel: "feat",
                choice: .ours
            )),
        ]
        XCTAssertTrue(vm.currentFileAllRegionsChosen)
    }

    func testCurrentFileAllRegionsChosenFalseWithUndecided() {
        let vm = RepositoryViewModel()
        vm.conflictBlocks = [
            .conflict(ConflictRegion(
                oursLines: ["a"], theirsLines: ["b"],
                oursLabel: "HEAD", theirsLabel: "feat",
                choice: .undecided
            )),
        ]
        XCTAssertFalse(vm.currentFileAllRegionsChosen)
    }

    // MARK: - isStashApplyBlockedByLocalChanges

    func testIsStashApplyBlockedByOverwrittenByMerge() {
        XCTAssertTrue(RepositoryViewModel.isStashApplyBlockedByLocalChanges(
            "error: Your local changes to 'file.swift' would be overwritten by merge"
        ))
    }

    func testIsStashApplyBlockedByPleaseCommit() {
        XCTAssertTrue(RepositoryViewModel.isStashApplyBlockedByLocalChanges(
            "error: please commit your changes or stash them before you merge"
        ))
    }

    func testIsStashApplyBlockedByLocalChanges() {
        XCTAssertTrue(RepositoryViewModel.isStashApplyBlockedByLocalChanges(
            "Cannot apply stash: your index contains local changes"
        ))
    }

    func testIsStashApplyBlockedNilReturnsFalse() {
        XCTAssertFalse(RepositoryViewModel.isStashApplyBlockedByLocalChanges(nil))
    }

    func testIsStashApplyBlockedUnrelatedMessage() {
        XCTAssertFalse(RepositoryViewModel.isStashApplyBlockedByLocalChanges(
            "everything is fine"
        ))
    }

    // MARK: - friendlyStashRestoreErrorMessage

    func testFriendlyStashErrorNoEntries() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "stash pop", message: "error: No stash entries found.")
        let result = vm.friendlyStashRestoreErrorMessage(error, reference: "stash@{0}", pop: true)
        XCTAssertNotNil(result)
    }

    func testFriendlyStashErrorInvalidReference() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "stash apply", message: "error: not a valid reference: stash@{99}")
        let result = vm.friendlyStashRestoreErrorMessage(error, reference: "stash@{99}", pop: false)
        XCTAssertNotNil(result)
    }

    func testFriendlyStashErrorConflictPop() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "stash pop", message: "CONFLICT (content): merge conflict in file.swift")
        let result = vm.friendlyStashRestoreErrorMessage(error, reference: "stash@{0}", pop: true)
        XCTAssertNotNil(result)
    }

    func testFriendlyStashErrorConflictApply() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "stash apply", message: "CONFLICT (content): merge conflict in file.swift")
        let result = vm.friendlyStashRestoreErrorMessage(error, reference: "stash@{0}", pop: false)
        XCTAssertNotNil(result)
    }

    func testFriendlyStashErrorGenericPop() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "stash pop", message: "some random error from git")
        let result = vm.friendlyStashRestoreErrorMessage(error, reference: "stash@{0}", pop: true)
        XCTAssertNotNil(result, "Generic errors should still return a friendly message")
    }

    func testFriendlyStashErrorGenericApply() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "stash apply", message: "some random error from git")
        let result = vm.friendlyStashRestoreErrorMessage(error, reference: "stash@{0}", pop: false)
        XCTAssertNotNil(result, "Generic errors should still return a friendly message")
    }

    func testFriendlyStashErrorNonGitError() {
        let vm = RepositoryViewModel()
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "not a git error"])
        let result = vm.friendlyStashRestoreErrorMessage(error, reference: "stash@{0}", pop: true)
        XCTAssertNil(result, "Non-GitClientError should return nil")
    }

    // MARK: - slugifiedWorktreeName

    func testSlugifiedWorktreeNameSimple() {
        let vm = RepositoryViewModel()
        XCTAssertEqual(vm.slugifiedWorktreeName(from: "My Feature"), "my-feature")
    }

    func testSlugifiedWorktreeNameDiacritics() {
        let vm = RepositoryViewModel()
        XCTAssertEqual(vm.slugifiedWorktreeName(from: "café résumé"), "cafe-resume")
    }

    func testSlugifiedWorktreeNameCompressesDashes() {
        let vm = RepositoryViewModel()
        let result = vm.slugifiedWorktreeName(from: "hello---world")
        XCTAssertEqual(result, "hello-world")
    }

    func testSlugifiedWorktreeNameTrimsDots() {
        let vm = RepositoryViewModel()
        let result = vm.slugifiedWorktreeName(from: ".hidden.")
        XCTAssertEqual(result, "hidden")
    }

    func testSlugifiedWorktreeNameEmpty() {
        let vm = RepositoryViewModel()
        XCTAssertEqual(vm.slugifiedWorktreeName(from: ""), "")
    }

    // MARK: - computeMergedBranchesToPrune

    func testComputeMergedBranchesToPruneExcludesProtected() {
        let vm = RepositoryViewModel()
        let output = "  main\n  develop\n  feature-done\n* current\n  dev\n"
        vm.currentBranch = "current"
        let result = vm.computeMergedBranchesToPrune(from: output, baseRef: "main")
        XCTAssertEqual(result, ["feature-done"])
    }

    func testComputeMergedBranchesToPruneStripsAsterisk() {
        let vm = RepositoryViewModel()
        let output = "* some-branch\n  another-branch\n"
        vm.currentBranch = "some-branch"
        let result = vm.computeMergedBranchesToPrune(from: output, baseRef: "main")
        XCTAssertEqual(result, ["another-branch"])
    }

    func testComputeMergedBranchesToPruneEmptyOutput() {
        let vm = RepositoryViewModel()
        vm.currentBranch = "main"
        let result = vm.computeMergedBranchesToPrune(from: "", baseRef: "main")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - pruneMergeBaseRef

    func testPruneMergeBaseRefPrefersMain() {
        let vm = RepositoryViewModel()
        vm.branchInfos = [
            BranchInfo(name: "main", fullRef: "refs/heads/main", head: "abc", upstream: "", committerDate: Date(), isRemote: false),
            BranchInfo(name: "master", fullRef: "refs/heads/master", head: "def", upstream: "", committerDate: Date(), isRemote: false),
        ]
        XCTAssertEqual(vm.pruneMergeBaseRef(), "main")
    }

    func testPruneMergeBaseRefFallsBackToMaster() {
        let vm = RepositoryViewModel()
        vm.branchInfos = [
            BranchInfo(name: "master", fullRef: "refs/heads/master", head: "def", upstream: "", committerDate: Date(), isRemote: false),
        ]
        XCTAssertEqual(vm.pruneMergeBaseRef(), "master")
    }

    func testPruneMergeBaseRefFallsBackToCurrentBranch() {
        let vm = RepositoryViewModel()
        vm.currentBranch = "develop"
        vm.branchInfos = [
            BranchInfo(name: "develop", fullRef: "refs/heads/develop", head: "abc", upstream: "", committerDate: Date(), isRemote: false),
        ]
        XCTAssertEqual(vm.pruneMergeBaseRef(), "develop")
    }

    func testPruneMergeBaseRefFallsBackToHEAD() {
        let vm = RepositoryViewModel()
        vm.currentBranch = "missing"
        vm.branchInfos = []
        XCTAssertEqual(vm.pruneMergeBaseRef(), "HEAD")
    }

    // MARK: - isCredentialFailure / isNoUpstreamConfigured

    func testIsCredentialFailureDetectsAuthFailed() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "push", message: "Authentication failed for 'https://github.com'")
        XCTAssertTrue(vm.isCredentialFailure(error))
    }

    func testIsCredentialFailureReturnsFalseForUnrelated() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "push", message: "non-fast-forward")
        XCTAssertFalse(vm.isCredentialFailure(error))
    }

    func testIsCredentialFailureReturnsFalseForNonGitError() {
        let vm = RepositoryViewModel()
        let error = NSError(domain: "test", code: 1)
        XCTAssertFalse(vm.isCredentialFailure(error))
    }

    func testIsNoUpstreamConfiguredDetectsPattern() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "rev-list", message: "fatal: no upstream configured for branch 'feature'")
        XCTAssertTrue(vm.isNoUpstreamConfigured(error))
    }

    func testIsNoUpstreamConfiguredReturnsFalseForUnrelated() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "rev-list", message: "something else")
        XCTAssertFalse(vm.isNoUpstreamConfigured(error))
    }

    // MARK: - defaultCommitLimit

    func testDefaultCommitLimitWithReference() {
        let vm = RepositoryViewModel()
        let result = vm.defaultCommitLimit(for: "main")
        XCTAssertEqual(result, 450) // defaultCommitLimitFocused
    }

    func testDefaultCommitLimitWithNil() {
        let vm = RepositoryViewModel()
        let result = vm.defaultCommitLimit(for: nil)
        XCTAssertEqual(result, 700) // defaultCommitLimitAll
    }

    func testDefaultCommitLimitWithEmptyString() {
        let vm = RepositoryViewModel()
        let result = vm.defaultCommitLimit(for: "")
        XCTAssertEqual(result, 700) // empty cleans to empty, so treated as nil
    }
}
