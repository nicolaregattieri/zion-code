import XCTest
@testable import Zion

@MainActor
final class DiffParsingTests: XCTestCase {

    // MARK: - Basic Hunk Parsing

    func testParseSimpleHunkWithAdditionsAndDeletions() {
        let diff = [
            "diff --git a/file.swift b/file.swift",
            "index 1234567..abcdefg 100644",
            "--- a/file.swift",
            "+++ b/file.swift",
            "@@ -1,3 +1,4 @@",
            " unchanged line",
            "-old line",
            "+new line",
            "+added line",
            " another unchanged",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)

        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0].oldStart, 1)
        XCTAssertEqual(hunks[0].oldCount, 3)
        XCTAssertEqual(hunks[0].newStart, 1)
        XCTAssertEqual(hunks[0].newCount, 4)

        let lines = hunks[0].lines
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines[0].type, .context)
        XCTAssertEqual(lines[1].type, .deletion)
        XCTAssertEqual(lines[2].type, .addition)
        XCTAssertEqual(lines[3].type, .addition)
        XCTAssertEqual(lines[4].type, .context)
    }

    func testParseMultipleHunks() {
        let diff = [
            "diff --git a/file.swift b/file.swift",
            "--- a/file.swift",
            "+++ b/file.swift",
            "@@ -1,3 +1,3 @@",
            " context",
            "-old1",
            "+new1",
            " context",
            "@@ -10,3 +10,3 @@",
            " context2",
            "-old2",
            "+new2",
            " context2",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)

        XCTAssertEqual(hunks.count, 2)
        XCTAssertEqual(hunks[0].oldStart, 1)
        XCTAssertEqual(hunks[1].oldStart, 10)
    }

    // MARK: - New File (Only Additions)

    func testParseNewFileOnlyAdditions() {
        let diff = [
            "diff --git a/new.swift b/new.swift",
            "new file mode 100644",
            "--- /dev/null",
            "+++ b/new.swift",
            "@@ -0,0 +1,3 @@",
            "+line one",
            "+line two",
            "+line three",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)

        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0].oldStart, 0)
        XCTAssertEqual(hunks[0].oldCount, 0)
        XCTAssertEqual(hunks[0].newStart, 1)
        XCTAssertEqual(hunks[0].newCount, 3)
        XCTAssertTrue(hunks[0].lines.allSatisfy { $0.type == .addition })
    }

    // MARK: - Deleted File (Only Deletions)

    func testParseDeletedFileOnlyDeletions() {
        let diff = [
            "diff --git a/old.swift b/old.swift",
            "deleted file mode 100644",
            "--- a/old.swift",
            "+++ /dev/null",
            "@@ -1,2 +0,0 @@",
            "-removed line 1",
            "-removed line 2",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)

        XCTAssertEqual(hunks.count, 1)
        XCTAssertTrue(hunks[0].lines.allSatisfy { $0.type == .deletion })
        XCTAssertEqual(hunks[0].lines.count, 2)
    }

    // MARK: - Line Numbering

    func testContextLineNumbering() {
        let diff = [
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -5,3 +5,3 @@",
            " context",
            "-old",
            "+new",
            " context",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)
        let lines = hunks[0].lines

        // First context line: old=5, new=5
        XCTAssertEqual(lines[0].oldLineNumber, 5)
        XCTAssertEqual(lines[0].newLineNumber, 5)

        // Deletion: old=6, new=nil
        XCTAssertEqual(lines[1].oldLineNumber, 6)
        XCTAssertNil(lines[1].newLineNumber)

        // Addition: old=nil, new=6
        XCTAssertNil(lines[2].oldLineNumber)
        XCTAssertEqual(lines[2].newLineNumber, 6)

        // Last context: old=7, new=7
        XCTAssertEqual(lines[3].oldLineNumber, 7)
        XCTAssertEqual(lines[3].newLineNumber, 7)
    }

    func testLineNumberingWithMixedChanges() {
        let diff = [
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,4 +1,5 @@",
            " unchanged",
            "-deleted",
            "+added1",
            "+added2",
            " unchanged",
            " unchanged",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)
        let lines = hunks[0].lines

        // context: old=1, new=1
        XCTAssertEqual(lines[0].oldLineNumber, 1)
        XCTAssertEqual(lines[0].newLineNumber, 1)

        // deletion: old=2, new=nil
        XCTAssertEqual(lines[1].oldLineNumber, 2)
        XCTAssertNil(lines[1].newLineNumber)

        // addition1: old=nil, new=2
        XCTAssertNil(lines[2].oldLineNumber)
        XCTAssertEqual(lines[2].newLineNumber, 2)

        // addition2: old=nil, new=3
        XCTAssertNil(lines[3].oldLineNumber)
        XCTAssertEqual(lines[3].newLineNumber, 3)

        // context: old=3, new=4
        XCTAssertEqual(lines[4].oldLineNumber, 3)
        XCTAssertEqual(lines[4].newLineNumber, 4)
    }

    // MARK: - Hunk Header Formats

    func testParseHunkWithoutCount() {
        let diff = [
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1 +1 @@",
            "-old",
            "+new",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)

        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0].oldCount, 0)
        XCTAssertEqual(hunks[0].newCount, 0)
    }

    func testParseHunkFullFormat() {
        let diff = [
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -10,20 +15,25 @@ func example()",
            " context",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)

        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0].oldStart, 10)
        XCTAssertEqual(hunks[0].oldCount, 20)
        XCTAssertEqual(hunks[0].newStart, 15)
        XCTAssertEqual(hunks[0].newCount, 25)
    }

    // MARK: - Special Lines

    func testNoNewlineAtEndOfFileIsSkipped() {
        let diff = [
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,2 +1,2 @@",
            "-old line",
            "+new line",
            "\\ No newline at end of file",
            " context",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)
        let lines = hunks[0].lines

        XCTAssertTrue(lines.allSatisfy { line in
            !line.content.contains("No newline at end of file")
        })
    }

    // MARK: - Empty Input

    func testParseEmptyDiff() {
        let hunks = RepositoryViewModel.parseDiffHunks("")
        XCTAssertTrue(hunks.isEmpty)
    }

    func testParseDiffWithOnlyHeaders() {
        let diff = [
            "diff --git a/file.swift b/file.swift",
            "index 1234567..abcdefg 100644",
            "--- a/file.swift",
            "+++ b/file.swift",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)
        XCTAssertTrue(hunks.isEmpty)
    }

    // MARK: - Line Types

    func testAllLineTypesCorrect() {
        let diff = [
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,3 +1,3 @@",
            " context line",
            "-deletion line",
            "+addition line",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)
        let lines = hunks[0].lines

        XCTAssertEqual(lines[0].type, .context)
        XCTAssertEqual(lines[0].content, "context line")
        XCTAssertEqual(lines[1].type, .deletion)
        XCTAssertEqual(lines[1].content, "deletion line")
        XCTAssertEqual(lines[2].type, .addition)
        XCTAssertEqual(lines[2].content, "addition line")
    }

    // MARK: - Empty Lines in Diff

    func testEmptyContextLines() {
        let diff = [
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,3 +1,3 @@",
            " line one",
            "",
            " line three",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)

        XCTAssertEqual(hunks[0].lines.count, 3)
    }

    // MARK: - Content Extraction

    func testAdditionContentStripsPrefix() {
        let diff = [
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,1 +1,2 @@",
            " existing",
            "+new content here",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)
        let additionLine = hunks[0].lines.first { $0.type == .addition }

        XCTAssertEqual(additionLine?.content, "new content here")
    }

    func testDeletionContentStripsPrefix() {
        let diff = [
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,2 +1,1 @@",
            "-removed content here",
            " existing",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)
        let deletionLine = hunks[0].lines.first { $0.type == .deletion }

        XCTAssertEqual(deletionLine?.content, "removed content here")
    }

    func testHeaderIsPreserved() {
        let diff = [
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,3 +1,3 @@ func example()",
            " context",
        ].joined(separator: "\n")
        let hunks = RepositoryViewModel.parseDiffHunks(diff)

        XCTAssertTrue(hunks[0].header.hasPrefix("@@"))
        XCTAssertTrue(hunks[0].header.contains("func example()"))
    }
}
