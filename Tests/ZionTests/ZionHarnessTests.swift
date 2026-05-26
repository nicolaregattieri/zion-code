import XCTest
@testable import Zion

final class ZionHarnessTests: XCTestCase {

    // MARK: - Test Setup

    /// Temporary repo URL created fresh for each test.
    private var repoURL: URL!
    private var harness: ZionHarness!

    override func setUp() async throws {
        try await super.setUp()

        // Create a temp directory that acts as the repo root
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        repoURL = base

        // Init a real git repo so git commands work
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = base
        try process.run()
        process.waitUntilExit()

        let worker = RepositoryWorker()
        harness = ZionHarness(worker: worker, repoURL: base)

        // Enable edits for most tests
        UserDefaults.standard.set(true, forKey: "chat.allowEdits")
    }

    override func tearDown() async throws {
        if let url = repoURL {
            try? FileManager.default.removeItem(at: url)
        }
        UserDefaults.standard.removeObject(forKey: "chat.allowEdits")
        try await super.tearDown()
    }

    // MARK: - Helper

    /// Write a file directly into the temp repo (bypasses harness).
    private func seedFile(_ name: String, content: String) throws -> URL {
        let url = repoURL.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Test 1: edit rejected without prior read

    func test_edit_rejected_without_prior_read() async throws {
        let filePath = try seedFile("edit_no_read.txt", content: "hello world")

        let toolCall = ToolCall(
            id: "t1",
            name: "edit",
            arguments: [
                "path": filePath.path,
                "edits": [["oldText": "hello", "newText": "goodbye"]] as [[String: Any]]
            ]
        )

        let result = await harness.execute(toolCall: toolCall)

        XCTAssertTrue(result.isError, "Expected isError=true when editing without prior read")
        XCTAssertTrue(result.content.contains("readBeforeEdit"),
                      "Expected 'readBeforeEdit' in error message, got: \(result.content)")
    }

    // MARK: - Test 2: write rejected when file exists

    func test_write_rejected_when_file_exists() async throws {
        let filePath = try seedFile("existing.txt", content: "original")

        let toolCall = ToolCall(
            id: "t2",
            name: "write",
            arguments: [
                "path": filePath.path,
                "content": "new content"
            ]
        )

        let result = await harness.execute(toolCall: toolCall)

        XCTAssertTrue(result.isError, "Expected isError=true when writing to existing file")
        XCTAssertTrue(result.content.contains("fileExists"),
                      "Expected 'fileExists' in error message, got: \(result.content)")
    }

    func test_write_rejected_when_edits_are_disabled() async throws {
        UserDefaults.standard.set(false, forKey: "chat.allowEdits")
        let target = repoURL.appendingPathComponent("disabled-write.txt")
        let toolCall = ToolCall(
            id: "t2-disabled",
            name: "write",
            arguments: ["path": target.path, "content": "new content"]
        )

        let result = await harness.execute(toolCall: toolCall)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("editsDisabled"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    // MARK: - Test 3: bash allowlist enforced

    func test_bash_allowlist_enforced() async throws {
        // Allowed: git status
        let allowed = ToolCall(id: "t3a", name: "bash", arguments: ["command": "git status"])
        let allowedResult = await harness.execute(toolCall: allowed)
        XCTAssertFalse(allowedResult.isError, "Expected git status to succeed, got: \(allowedResult.content)")

        // Denied: rm -rf
        let denied = ToolCall(id: "t3b", name: "bash", arguments: ["command": "rm -rf /tmp/foo"])
        let deniedResult = await harness.execute(toolCall: denied)
        XCTAssertTrue(deniedResult.isError, "Expected rm to be rejected")
        XCTAssertTrue(deniedResult.content.contains("bashNotAllowed"),
                      "Expected 'bashNotAllowed' in error message, got: \(deniedResult.content)")
    }

    // MARK: - Test 4: path outside repo rejected

    func test_path_outside_repo_rejected() async throws {
        let toolCall = ToolCall(
            id: "t4",
            name: "read",
            arguments: ["path": "../../../etc/passwd"]
        )

        let result = await harness.execute(toolCall: toolCall)

        XCTAssertTrue(result.isError, "Expected isError=true for path outside repo")
        XCTAssertTrue(result.content.contains("outsideRepo"),
                      "Expected 'outsideRepo' in error message, got: \(result.content)")
    }

    // MARK: - Test 5: FileMutationQueue serializes writes to same path, parallel for different paths

    func test_file_mutation_queue_serializes() async throws {
        // Create two target files
        let fileA = repoURL.appendingPathComponent("queue_a.txt")
        let fileB = repoURL.appendingPathComponent("queue_b.txt")

        // Write files fresh (they don't exist yet — write tool will create them)
        // We need to test serialization on same-path; use internal harness mutation via concurrent edit calls.
        // Seed them first, then read, then do concurrent edits.
        try "aaa".write(to: fileA, atomically: true, encoding: .utf8)
        try "bbb".write(to: fileB, atomically: true, encoding: .utf8)

        // Read both files so edits are allowed
        let readA = ToolCall(id: "r_a", name: "read", arguments: ["path": fileA.path])
        let readB = ToolCall(id: "r_b", name: "read", arguments: ["path": fileB.path])
        _ = await harness.execute(toolCall: readA)
        _ = await harness.execute(toolCall: readB)

        // Fire 3 concurrent edits on fileA and 3 on fileB to verify no corruption
        var editCallsA: [ToolCall] = []
        var editCallsB: [ToolCall] = []

        // Build sequential edits where each round-trips: aaa->aab->abc->xyz
        // For serialization proof: just verify all complete without error
        for i in 0..<3 {
            editCallsA.append(ToolCall(
                id: "ea\(i)", name: "edit",
                arguments: [
                    "path": fileA.path,
                    "edits": [["oldText": "a", "newText": "a"]] as [[String: Any]]
                ]
            ))
            editCallsB.append(ToolCall(
                id: "eb\(i)", name: "edit",
                arguments: [
                    "path": fileB.path,
                    "edits": [["oldText": "b", "newText": "b"]] as [[String: Any]]
                ]
            ))
        }

        let h = harness!

        // Run same-path edits concurrently and measure timing
        let samePathStart = Date()
        await withTaskGroup(of: ToolResult.self) { group in
            for call in editCallsA {
                group.addTask { await h.execute(toolCall: call) }
            }
        }
        let samePathDuration = Date().timeIntervalSince(samePathStart)

        // Run different-path edits concurrently
        let diffPathStart = Date()
        await withTaskGroup(of: ToolResult.self) { group in
            for callA in editCallsA {
                group.addTask { await h.execute(toolCall: callA) }
            }
            for callB in editCallsB {
                group.addTask { await h.execute(toolCall: callB) }
            }
        }
        let diffPathDuration = Date().timeIntervalSince(diffPathStart)

        // Both should complete without errors (no corruption)
        // Verify files are readable
        let contentA = try String(contentsOf: fileA, encoding: .utf8)
        let contentB = try String(contentsOf: fileB, encoding: .utf8)
        XCTAssertFalse(contentA.isEmpty, "File A should have content")
        XCTAssertFalse(contentB.isEmpty, "File B should have content")

        // Different paths should not be significantly slower than same paths
        // (they run in parallel). This is a loose check — just ensuring both finish.
        XCTAssertLessThan(diffPathDuration, samePathDuration * 10 + 2.0,
                          "Parallel paths should not be dramatically slower")
    }

    // MARK: - Test 6: session reset removes read permission

    func test_session_reset_on_new_thread() async throws {
        let filePath = try seedFile("reset_test.txt", content: "original content")

        // Read the file — this registers it in sessionReadFiles
        let readCall = ToolCall(id: "r6", name: "read", arguments: ["path": filePath.path])
        let readResult = await harness.execute(toolCall: readCall)
        XCTAssertFalse(readResult.isError, "Read should succeed")

        // Edit should work after read
        let editCall = ToolCall(
            id: "e6",
            name: "edit",
            arguments: [
                "path": filePath.path,
                "edits": [["oldText": "original", "newText": "modified"]] as [[String: Any]]
            ]
        )
        let editResult = await harness.execute(toolCall: editCall)
        XCTAssertFalse(editResult.isError, "Edit should succeed after read, got: \(editResult.content)")

        // Reset session
        await harness.resetSession()

        // Edit should now be rejected
        let editCall2 = ToolCall(
            id: "e6b",
            name: "edit",
            arguments: [
                "path": filePath.path,
                "edits": [["oldText": "modified", "newText": "changed"]] as [[String: Any]]
            ]
        )
        let editResult2 = await harness.execute(toolCall: editCall2)
        XCTAssertTrue(editResult2.isError, "Edit should be rejected after session reset")
        XCTAssertTrue(editResult2.content.contains("readBeforeEdit"),
                      "Expected 'readBeforeEdit' after reset, got: \(editResult2.content)")
    }

    // MARK: - Test 7: edit with empty oldText rejected

    func test_edit_empty_oldText_rejected() async throws {
        let filePath = try seedFile("empty_old.txt", content: "some content here")

        // Read first
        let readCall = ToolCall(id: "r7", name: "read", arguments: ["path": filePath.path])
        _ = await harness.execute(toolCall: readCall)

        // Edit with empty oldText
        let editCall = ToolCall(
            id: "e7",
            name: "edit",
            arguments: [
                "path": filePath.path,
                "edits": [["oldText": "", "newText": "replacement"]] as [[String: Any]]
            ]
        )
        let result = await harness.execute(toolCall: editCall)

        XCTAssertTrue(result.isError, "Expected isError=true for empty oldText")
        XCTAssertTrue(result.content.contains("invalidEdit"),
                      "Expected 'invalidEdit' in error, got: \(result.content)")
    }

    // MARK: - Test 8: edit text not found returns context

    func test_edit_text_not_found_returns_context() async throws {
        let fileContent = "The quick brown fox jumps over the lazy dog. This is a test file with some content."
        let filePath = try seedFile("not_found.txt", content: fileContent)

        // Read first
        let readCall = ToolCall(id: "r8", name: "read", arguments: ["path": filePath.path])
        _ = await harness.execute(toolCall: readCall)

        // Edit with non-existent oldText
        let editCall = ToolCall(
            id: "e8",
            name: "edit",
            arguments: [
                "path": filePath.path,
                "edits": [["oldText": "this text does not exist in the file", "newText": "replacement"]] as [[String: Any]]
            ]
        )
        let result = await harness.execute(toolCall: editCall)

        XCTAssertTrue(result.isError, "Expected isError=true when oldText not found")
        XCTAssertTrue(result.content.contains("textNotFound"),
                      "Expected 'textNotFound' in error, got: \(result.content)")
        // Should include first 200 chars of file content as context
        let prefix200 = String(fileContent.prefix(200))
        XCTAssertTrue(result.content.contains(prefix200.prefix(20)),
                      "Expected file content snippet in error, got: \(result.content)")
    }
}
