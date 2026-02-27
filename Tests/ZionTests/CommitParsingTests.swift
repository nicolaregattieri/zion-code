import XCTest
@testable import Zion

final class CommitParsingTests: XCTestCase {
    private let worker = RepositoryWorker()
    private let rs = String(UnicodeScalar(0x1E))  // record separator
    private let fs = String(UnicodeScalar(0x1F))  // field separator

    private func makeRecord(
        hash: String = "abc123def456789012345678901234567890abcd",
        parents: String = "parent1234567890123456789012345678901234",
        author: String = "Test User",
        email: String = "test@example.com",
        date: String = "2025-01-15T10:30:00+00:00",
        subject: String = "Fix bug",
        decorations: String = ""
    ) -> String {
        [hash, parents, author, email, date, subject, decorations].joined(separator: fs)
    }

    // MARK: - Basic Parsing

    func testParseSingleCommit() async {
        let output = makeRecord() + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].hash, "abc123def456789012345678901234567890abcd")
        XCTAssertEqual(commits[0].author, "Test User")
        XCTAssertEqual(commits[0].email, "test@example.com")
        XCTAssertEqual(commits[0].subject, "Fix bug")
    }

    func testParseParents() async {
        let output = makeRecord(parents: "aaaa1111 bbbb2222") + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertEqual(commits[0].parents, ["aaaa1111", "bbbb2222"])
    }

    func testParseMergeCommitTwoParents() async {
        let output = makeRecord(
            parents: "aaa111aaa111aaa111aaa111aaa111aaa111aaa1 bbb222bbb222bbb222bbb222bbb222bbb222bbb2",
            subject: "Merge branch 'feature'"
        ) + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertEqual(commits[0].parents.count, 2)
        XCTAssertEqual(commits[0].subject, "Merge branch 'feature'")
    }

    func testParseRootCommitNoParents() async {
        let output = makeRecord(parents: "") + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertEqual(commits[0].parents, [])
    }

    // MARK: - Decorations

    func testParseDecorations() async {
        let output = makeRecord(decorations: "HEAD -> main, origin/main, tag: v1.0") + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertEqual(commits[0].decorations.count, 3)
        XCTAssertTrue(commits[0].decorations.contains("HEAD -> main"))
        XCTAssertTrue(commits[0].decorations.contains("origin/main"))
        XCTAssertTrue(commits[0].decorations.contains("tag: v1.0"))
    }

    func testParseEmptyDecorations() async {
        let output = makeRecord(decorations: "") + rs
        let commits = await worker.parseCommits(from: output)

        // Empty string split by "," will produce one empty element after trimming
        // but the parser keeps trimmed non-empty entries
        XCTAssertTrue(commits[0].decorations.isEmpty || commits[0].decorations == [""])
    }

    // MARK: - Special Characters

    func testParseSubjectWithEmoji() async {
        let output = makeRecord(subject: "🚀 Deploy new feature") + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertEqual(commits[0].subject, "🚀 Deploy new feature")
    }

    func testParseSubjectWithQuotes() async {
        let output = makeRecord(subject: "Fix \"quoted\" strings in parser") + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertEqual(commits[0].subject, "Fix \"quoted\" strings in parser")
    }

    func testParseEmptyAuthor() async {
        let output = makeRecord(author: "", email: "") + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].author, "")
        XCTAssertEqual(commits[0].email, "")
    }

    // MARK: - Edge Cases

    func testParseEmptyOutput() async {
        let commits = await worker.parseCommits(from: "")
        XCTAssertTrue(commits.isEmpty)
    }

    func testParseMalformedTooFewFields() async {
        // Only 4 fields instead of 7 — should be discarded by compactMap
        let output = ["hash", "parents", "author", "email"].joined(separator: fs) + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertTrue(commits.isEmpty)
    }

    func testParseMultipleCommits() async {
        let record1 = makeRecord(hash: "aaaa" + String(repeating: "0", count: 36), subject: "First")
        let record2 = makeRecord(hash: "bbbb" + String(repeating: "1", count: 36), subject: "Second")
        let record3 = makeRecord(hash: "cccc" + String(repeating: "2", count: 36), subject: "Third")
        let output = [record1, record2, record3].joined(separator: rs) + rs

        let commits = await worker.parseCommits(from: output)

        XCTAssertEqual(commits.count, 3)
        XCTAssertEqual(commits[0].subject, "First")
        XCTAssertEqual(commits[1].subject, "Second")
        XCTAssertEqual(commits[2].subject, "Third")
    }

    func testParseEmptyHashDiscarded() async {
        // Hash is empty after trimming — should be discarded
        let output = makeRecord(hash: "  ") + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertTrue(commits.isEmpty)
    }

    // MARK: - Date Parsing

    func testParseDateISO8601() async {
        let output = makeRecord(date: "2025-06-15T14:30:00+00:00") + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertEqual(commits.count, 1)
        // Verify the date is not epoch (fallback)
        XCTAssertNotEqual(commits[0].date, Date(timeIntervalSince1970: 0))
    }

    func testParseDateISO8601WithFractions() async {
        let output = makeRecord(date: "2025-06-15T14:30:00.123+00:00") + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertEqual(commits.count, 1)
        XCTAssertNotEqual(commits[0].date, Date(timeIntervalSince1970: 0))
    }

    func testParseInvalidDateFallsBackToEpoch() async {
        let output = makeRecord(date: "not-a-date") + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].date, Date(timeIntervalSince1970: 0))
    }

    // MARK: - Whitespace Handling

    func testParseTrimsWhitespace() async {
        let output = makeRecord(
            hash: "  abc123def456789012345678901234567890abcd  ",
            author: "  Test User  ",
            subject: "  Trim me  "
        ) + rs
        let commits = await worker.parseCommits(from: output)

        XCTAssertEqual(commits[0].hash, "abc123def456789012345678901234567890abcd")
        XCTAssertEqual(commits[0].author, "Test User")
        XCTAssertEqual(commits[0].subject, "Trim me")
    }

    func testParseMultipleRecordSeparators() async {
        // Multiple record separators between entries should not produce phantom commits
        let record1 = makeRecord(hash: "aaaa" + String(repeating: "0", count: 36), subject: "First")
        let record2 = makeRecord(hash: "bbbb" + String(repeating: "1", count: 36), subject: "Second")
        let output = record1 + rs + rs + record2 + rs

        let commits = await worker.parseCommits(from: output)
        XCTAssertEqual(commits.count, 2)
    }
}
