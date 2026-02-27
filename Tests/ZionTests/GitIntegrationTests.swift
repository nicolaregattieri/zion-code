import XCTest
@testable import Zion

final class GitIntegrationTests: XCTestCase {
    private let worker = RepositoryWorker()
    private var repoURL: URL!

    override func setUp() async throws {
        repoURL = try GitTestHelper.makeTempRepo()
    }

    override func tearDown() async throws {
        if let url = repoURL {
            GitTestHelper.cleanup(url)
        }
    }

    // MARK: - Repository Detection

    func testIsGitRepository() async {
        let result = await worker.isGitRepository(at: repoURL)
        XCTAssertTrue(result)
    }

    func testIsNotGitRepositoryForEmptyDir() async throws {
        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zion-test-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { GitTestHelper.cleanup(emptyDir) }

        let result = await worker.isGitRepository(at: emptyDir)
        XCTAssertFalse(result)
    }

    // MARK: - Commit Operations

    func testCommitAppearsInLog() async throws {
        try GitTestHelper.createFile(name: "test.swift", content: "// test\n", in: repoURL)
        try GitTestHelper.commitAll(message: "Add test file", in: repoURL)

        let payload = try await worker.loadCommits(
            in: repoURL, reference: nil, selectedCommitID: nil, limit: 50
        )

        XCTAssertGreaterThanOrEqual(payload.commits.count, 2)  // initial + new
        XCTAssertTrue(payload.commits.contains(where: { $0.subject == "Add test file" }))
    }

    func testLoadCommitsLimitRespectsHasMore() async throws {
        // Create many commits
        for i in 0..<5 {
            try GitTestHelper.createFile(name: "file\(i).txt", content: "content \(i)\n", in: repoURL)
            try GitTestHelper.commitAll(message: "Commit \(i)", in: repoURL)
        }

        // Load with small limit — but effective limit is max(150, limit), so hasMore requires 151+ commits
        let payload = try await worker.loadCommits(
            in: repoURL, reference: nil, selectedCommitID: nil, limit: 150
        )

        // We have 6 commits total (initial + 5), well under 150, so hasMore = false
        XCTAssertFalse(payload.hasMore)
        XCTAssertEqual(payload.commits.count, 6)
    }

    // MARK: - Branch Operations

    func testCreateAndCheckoutBranch() async throws {
        // Create a new branch via git
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "checkout", "-b", "test-branch"]
        process.currentDirectoryURL = repoURL
        try process.run()
        process.waitUntilExit()

        let branchInfos = try await worker.branchInfoList(in: repoURL)
        let branchNames = branchInfos.map(\.name)

        XCTAssertTrue(branchNames.contains("test-branch"))
    }

    // MARK: - loadRepository Full Cycle

    func testLoadRepositoryFullCycle() async throws {
        let payload = try await worker.loadRepository(
            in: repoURL,
            focusedBranch: nil,
            selectedCommitID: nil,
            selectedStash: "",
            options: .full,
            limit: 50
        )

        XCTAssertTrue(payload.isGitRepository)
        XCTAssertFalse(payload.currentBranch.isEmpty)
        XCTAssertFalse(payload.headShortHash.isEmpty)
        XCTAssertGreaterThanOrEqual(payload.commits.count, 1)
        XCTAssertFalse(payload.hasConflicts)
        XCTAssertFalse(payload.isMerging)
        XCTAssertFalse(payload.isRebasing)
        XCTAssertFalse(payload.isCherryPicking)
    }

    func testLoadRepositoryNonGitDirectory() async throws {
        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zion-test-nongit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { GitTestHelper.cleanup(emptyDir) }

        let payload = try await worker.loadRepository(
            in: emptyDir,
            focusedBranch: nil,
            selectedCommitID: nil,
            selectedStash: "",
            limit: 50
        )

        XCTAssertFalse(payload.isGitRepository)
        XCTAssertEqual(payload.currentBranch, "-")
        XCTAssertTrue(payload.commits.isEmpty)
    }

    // MARK: - Active Operation Detection

    func testDetectNoActiveOperation() async {
        let op = await worker.detectActiveOperation(in: repoURL)
        XCTAssertNil(op)
    }

    // MARK: - Stash Operations

    func testStashPushAndList() async throws {
        try GitTestHelper.createFile(name: "dirty.txt", content: "uncommitted\n", in: repoURL)

        // Stage the file but don't commit
        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        addProcess.arguments = ["git", "add", "dirty.txt"]
        addProcess.currentDirectoryURL = repoURL
        try addProcess.run()
        addProcess.waitUntilExit()

        // Stash
        let stashProcess = Process()
        stashProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        stashProcess.arguments = ["git", "stash", "push", "-m", "test stash"]
        stashProcess.currentDirectoryURL = repoURL
        try stashProcess.run()
        stashProcess.waitUntilExit()

        // Load repository and verify stash appears
        let payload = try await worker.loadRepository(
            in: repoURL,
            focusedBranch: nil,
            selectedCommitID: nil,
            selectedStash: "",
            options: .full,
            limit: 50
        )

        XCTAssertFalse(payload.stashes.isEmpty)
        XCTAssertTrue(payload.stashes.first?.contains("test stash") ?? false)
    }

    // MARK: - Tag Operations

    func testTagCreateAndList() async throws {
        // Create a tag
        let tagProcess = Process()
        tagProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        tagProcess.arguments = ["git", "tag", "v1.0.0"]
        tagProcess.currentDirectoryURL = repoURL
        try tagProcess.run()
        tagProcess.waitUntilExit()

        let payload = try await worker.loadRepository(
            in: repoURL,
            focusedBranch: nil,
            selectedCommitID: nil,
            selectedStash: "",
            options: .full,
            limit: 50
        )

        XCTAssertTrue(payload.tags.contains("v1.0.0"))
    }

    // MARK: - Conflict Detection

    func testListConflictedFilesWithNoConflicts() async throws {
        let files = try await worker.listConflictedFiles(in: repoURL)
        XCTAssertTrue(files.isEmpty)
    }

    // MARK: - Security: Path Traversal

    func testReadConflictFileContentPathTraversal() async {
        do {
            _ = try await worker.readConflictFileContent(path: "../../etc/passwd", in: repoURL)
            XCTFail("Expected error for path traversal attempt")
        } catch {
            // Expected: should throw for invalid path
            XCTAssertTrue(error.localizedDescription.contains("Invalid path"))
        }
    }

    // MARK: - Commit Details Validation

    func testLoadCommitDetailsInvalidHash() async {
        do {
            _ = try await worker.loadCommitDetails(in: repoURL, commitID: "not-hex!")
            XCTFail("Expected error for invalid commit ID")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Invalid commit ID"))
        }
    }

    func testLoadCommitDetailsValidHash() async throws {
        let payload = try await worker.loadCommits(
            in: repoURL, reference: nil, selectedCommitID: nil, limit: 1
        )
        guard let commitID = payload.commits.first?.id else {
            XCTFail("No commits found")
            return
        }

        let details = try await worker.loadCommitDetails(in: repoURL, commitID: commitID)
        XCTAssertFalse(details.isEmpty)
    }

    // MARK: - Uncommitted Changes

    func testUncommittedChangesDetected() async throws {
        try GitTestHelper.createFile(name: "uncommitted.txt", content: "new\n", in: repoURL)

        let payload = try await worker.loadRepository(
            in: repoURL,
            focusedBranch: nil,
            selectedCommitID: nil,
            selectedStash: "",
            options: .full,
            limit: 50
        )

        XCTAssertGreaterThan(payload.uncommittedCount, 0)
        XCTAssertFalse(payload.uncommittedChanges.isEmpty)
    }

    // MARK: - Commit Stats

    func testFetchCommitStats() async throws {
        // Add a file with content so there are insertions
        try GitTestHelper.createFile(name: "stats.txt", content: "line1\nline2\nline3\n", in: repoURL)
        try GitTestHelper.commitAll(message: "Add stats file", in: repoURL)

        let payload = try await worker.loadCommits(
            in: repoURL, reference: nil, selectedCommitID: nil, limit: 50
        )
        let hashes = payload.commits.map(\.id)

        let stats = try await worker.fetchCommitStats(in: repoURL, hashes: hashes)

        // At least one commit should have stats
        XCTAssertFalse(stats.isEmpty)
        // The "Add stats file" commit should have insertions
        let hasInsertions = stats.values.contains { $0.0 > 0 }
        XCTAssertTrue(hasInsertions)
    }

    // MARK: - Worktree List

    func testWorktreeListContainsMain() async throws {
        let payload = try await worker.loadRepository(
            in: repoURL,
            focusedBranch: nil,
            selectedCommitID: nil,
            selectedStash: "",
            options: .full,
            limit: 50
        )

        // At minimum there should be one worktree (the main one)
        XCTAssertGreaterThanOrEqual(payload.worktrees.count, 1)
    }
}
