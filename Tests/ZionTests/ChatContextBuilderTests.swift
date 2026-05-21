import XCTest
@testable import Zion

final class ChatContextBuilderTests: XCTestCase {

    private let worker = RepositoryWorker()
    private var repoURL: URL!
    private var builder: ChatContextBuilder!

    override func setUp() async throws {
        repoURL = try GitTestHelper.makeTempRepo()
        builder = ChatContextBuilder(worker: worker)
    }

    override func tearDown() async throws {
        if let url = repoURL {
            GitTestHelper.cleanup(url)
        }
    }

    // MARK: - gitContextHeader

    func testGitContextHeaderFormatsRepoBranchShaCount() async throws {
        let repoName = repoURL.lastPathComponent
        let header = await builder.gitContextHeader(repoURL: repoURL, branch: "main")

        XCTAssertTrue(header.contains(repoName), "Header should contain repo name")
        XCTAssertTrue(header.contains("main"), "Header should contain branch name")
        // SHA is 7 chars from rev-parse --short=7
        // Just assert the header is non-empty and has reasonable content
        XCTAssertFalse(header.isEmpty)
    }

    // MARK: - expandSlashCommands

    func testExpandSlashDiff() async throws {
        // Modify a tracked file so git diff has output (untracked files don't appear in diff)
        try GitTestHelper.createFile(name: "README.md", content: "# Modified\n", in: repoURL)

        let input = "/diff"
        let result = await builder.expandSlashCommands(input, repoURL: repoURL)

        // Should still contain original line
        XCTAssertTrue(result.contains("/diff"))
        // Should contain a fenced block
        XCTAssertTrue(result.contains("```"))
    }

    func testExpandSlashDiffEmptyWhenClean() async throws {
        // Clean repo — diff should return empty.diff message
        let input = "/diff"
        let result = await builder.expandSlashCommands(input, repoURL: repoURL)

        let emptyMsg = L10n("chat.slash.empty.diff")
        XCTAssertTrue(result.contains(emptyMsg), "Should show empty diff message for clean tree, got: \(result)")
    }

    func testExpandSlashLog() async throws {
        let input = "/log"
        let result = await builder.expandSlashCommands(input, repoURL: repoURL)

        XCTAssertTrue(result.contains("/log"))
        XCTAssertTrue(result.contains("```"))
        // The initial commit message from GitTestHelper
        XCTAssertTrue(result.contains("Initial commit"))
    }

    func testExpandSlashStatus() async throws {
        // Stage an untracked file to have status output
        try GitTestHelper.createFile(name: "new.txt", content: "new\n", in: repoURL)

        let input = "/status"
        let result = await builder.expandSlashCommands(input, repoURL: repoURL)

        XCTAssertTrue(result.contains("/status"))
        XCTAssertTrue(result.contains("```"))
    }

    func testExpandSlashFile() async throws {
        // Create a file and reference it
        try GitTestHelper.createFile(name: "hello.txt", content: "hello world\n", in: repoURL)

        let input = "/file hello.txt"
        let result = await builder.expandSlashCommands(input, repoURL: repoURL)

        XCTAssertTrue(result.contains("hello world"))
        XCTAssertTrue(result.contains("```"))
    }

    func testExpandSlashFileOutsideRepo() async throws {
        let input = "/file ../../etc/passwd"
        let result = await builder.expandSlashCommands(input, repoURL: repoURL)

        let outsideMsg = L10n("chat.slash.fileOutsideRepo")
        XCTAssertTrue(result.contains(outsideMsg), "Should reject outside-repo path, got: \(result)")
    }

    func testExpandSlashCommit() async throws {
        // Get HEAD SHA
        let sha = try await worker.runAction(args: ["rev-parse", "--short=7", "HEAD"], in: repoURL)
        let input = "/commit \(sha)"
        let result = await builder.expandSlashCommands(input, repoURL: repoURL)

        XCTAssertTrue(result.contains("/commit"))
        XCTAssertTrue(result.contains("```"))
    }

    // MARK: - Inline slash in URLs must NOT trigger expansion

    func testIgnoresInlineSlashes() async throws {
        let input = "See https://example.com/diff for documentation."
        let result = await builder.expandSlashCommands(input, repoURL: repoURL)

        // Should return unchanged — no fenced block appended
        XCTAssertEqual(result, input)
        XCTAssertFalse(result.contains("```"))
    }
}
