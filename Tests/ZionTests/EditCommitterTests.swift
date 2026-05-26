import XCTest
@testable import Zion

final class EditCommitterTests: XCTestCase {

    // Stub commit message provider — returns a fixed message.
    private let stubProvider: @Sendable (String, String) async throws -> String = { _, _ in
        return "fix thing"
    }

    // MARK: - testHappyPath

    func testHappyPath() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        let worker = RepositoryWorker()
        let committer = EditCommitter(worker: worker, commitMessageProvider: stubProvider)

        let beforeSHA = try await worker.runAction(args: ["rev-parse", "HEAD"], in: repoURL).clean

        let inputs = [EditCommitInput(path: "hello.swift", contents: "// hello world\n")]
        let result = await committer.commit(inputs: inputs, in: repoURL, branch: "main")

        XCTAssertNil(result.failureReason, "Should not fail: \(result.failureReason ?? "")")
        XCTAssertNotNil(result.commitSHA)
        XCTAssertNotEqual(result.commitSHA, beforeSHA, "HEAD should have advanced")

        // Verify commit message has aiedit: prefix
        let msg = try await worker.runAction(args: ["log", "-1", "--format=%s"], in: repoURL).clean
        XCTAssertTrue(msg.hasPrefix("aiedit:"), "Expected aiedit: prefix, got: \(msg)")
    }

    // MARK: - testNoChangesDetected (empty inputs)

    func testNoChangesDetected() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        let worker = RepositoryWorker()
        let committer = EditCommitter(worker: worker, commitMessageProvider: stubProvider)

        let result = await committer.commit(inputs: [], in: repoURL, branch: "main")

        XCTAssertEqual(result.failureReason, "no_inputs")
        XCTAssertNil(result.commitSHA)
    }

    // MARK: - testSnapshotCreatedWhenDirtyTreeExists

    func testSnapshotCreatedWhenDirtyTreeExists() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        // Leave an uncommitted file in the working tree
        let dirtyFile = repoURL.appendingPathComponent("dirty.txt")
        try "uncommitted change\n".write(to: dirtyFile, atomically: true, encoding: .utf8)

        let worker = RepositoryWorker()
        let committer = EditCommitter(worker: worker, commitMessageProvider: stubProvider)

        let inputs = [EditCommitInput(path: "new_file.swift", contents: "// new\n")]
        let result = await committer.commit(inputs: inputs, in: repoURL, branch: "main")

        XCTAssertNil(result.failureReason, "Should not fail: \(result.failureReason ?? "")")
        XCTAssertNotNil(result.snapshotRef, "Should have created a snapshot")

        let snapshotRef = try XCTUnwrap(result.snapshotRef)
        XCTAssertTrue(snapshotRef.hasPrefix("zion-pre-aiedit-"), "Unexpected ref: \(snapshotRef)")

        // Verify git stash list contains our label
        let stashList = try await worker.runAction(args: ["stash", "list"], in: repoURL)
        XCTAssertTrue(stashList.contains("zion-pre-aiedit-"), "Stash list should contain zion-pre-aiedit-*: \(stashList)")
    }

    // MARK: - testEmptyDiffSkipsCommit

    func testEmptyDiffSkipsCommit() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        // Write a file with known content and commit it
        let existingContent = "// existing content\n"
        try GitTestHelper.createFile(name: "existing.swift", content: existingContent, in: repoURL)
        try GitTestHelper.commitAll(message: "Add existing file", in: repoURL)

        let worker = RepositoryWorker()
        let committer = EditCommitter(worker: worker, commitMessageProvider: stubProvider)

        // Submit SAME contents — no diff after git add
        let inputs = [EditCommitInput(path: "existing.swift", contents: existingContent)]
        let result = await committer.commit(inputs: inputs, in: repoURL, branch: "main")

        XCTAssertEqual(result.failureReason, "no_changes")
        XCTAssertNil(result.commitSHA)
    }

    // MARK: - testCommitMessagePrefixedAuto

    func testCommitMessagePrefixedAuto() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        let worker = RepositoryWorker()

        // Provider returns a message WITHOUT the aiedit: prefix
        let provider: @Sendable (String, String) async throws -> String = { _, _ in "fix thing" }
        let committer = EditCommitter(worker: worker, commitMessageProvider: provider)

        let inputs = [EditCommitInput(path: "feature.swift", contents: "// feature\n")]
        let result = await committer.commit(inputs: inputs, in: repoURL, branch: "main")

        XCTAssertNil(result.failureReason, "Should not fail: \(result.failureReason ?? "")")
        let msg = try await worker.runAction(args: ["log", "-1", "--format=%s"], in: repoURL).clean
        XCTAssertEqual(msg, "aiedit: fix thing")
    }

    func testRejectsSymlinkEscapingRepositoryBeforeWriting() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }
        let outsideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zion-aiedit-outside-\(UUID().uuidString).swift")
        defer { try? FileManager.default.removeItem(at: outsideURL) }
        try "// original\n".write(to: outsideURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: repoURL.appendingPathComponent("Linked.swift"),
            withDestinationURL: outsideURL
        )

        let worker = RepositoryWorker()
        let committer = EditCommitter(worker: worker, commitMessageProvider: stubProvider)
        let result = await committer.commit(
            inputs: [EditCommitInput(path: "Linked.swift", contents: "// modified\n")],
            in: repoURL,
            branch: "main"
        )

        XCTAssertNotNil(result.failureReason)
        XCTAssertNil(result.commitSHA)
        XCTAssertEqual(try String(contentsOf: outsideURL, encoding: .utf8), "// original\n")
        let stashList = try await worker.runAction(args: ["stash", "list"], in: repoURL)
        XCTAssertTrue(stashList.isEmpty)
    }
}
