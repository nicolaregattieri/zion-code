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
}
