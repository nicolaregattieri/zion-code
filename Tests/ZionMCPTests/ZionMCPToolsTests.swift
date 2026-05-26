// ZionMCPToolsTests.swift — Tests for EditTool and RepoMapTool (T8)

import XCTest
import CryptoKit
@testable import ZionMCP

final class ZionMCPToolsTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZionMCPTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func extractApplied(_ result: JSONValue) -> Bool? {
        guard case .object(let outer) = result,
              case .array(let content) = outer["content"],
              case .object(let first) = content.first,
              case .string(let text) = first["text"],
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let applied = json["applied"] as? Bool else { return nil }
        return applied
    }

    private func extractAvailable(_ result: JSONValue) -> Bool? {
        guard case .object(let outer) = result,
              case .array(let content) = outer["content"],
              case .object(let first) = content.first,
              case .string(let text) = first["text"],
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let available = json["available"] as? Bool else { return nil }
        return available
    }

    private func extractEntries(_ result: JSONValue) -> [[String: Any]]? {
        guard case .object(let outer) = result,
              case .array(let content) = outer["content"],
              case .object(let first) = content.first,
              case .string(let text) = first["text"],
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["entries"] as? [[String: Any]] else { return nil }
        return entries
    }

    private func extractResults(_ result: JSONValue) -> [[String: Any]]? {
        guard case .object(let outer) = result,
              case .array(let content) = outer["content"],
              case .object(let first) = content.first,
              case .string(let text) = first["text"],
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }
        return results
    }

    // MARK: - EditTool tests

    func testZionEditExactMatch() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("Fixture.swift")
        try "let x = 1\n".write(to: file, atomically: true, encoding: .utf8)

        let tool = EditTool(repoURL: dir)
        let result = try tool.call(args: [
            "path":    .string("Fixture.swift"),
            "search":  .string("let x = 1"),
            "replace": .string("let x = 2")
        ])

        XCTAssertEqual(extractApplied(result), true, "Should have applied the edit")
        let newContents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(newContents, "let x = 2\n", "File should contain the replacement")
    }

    func testZionEditFuzzy() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // File has trailing space after "1"; search lacks it — fuzzy ladder should catch it
        let file = dir.appendingPathComponent("Fuzzy.swift")
        try "let y = 1 \n".write(to: file, atomically: true, encoding: .utf8)

        let tool = EditTool(repoURL: dir)
        let result = try tool.call(args: [
            "path":    .string("Fuzzy.swift"),
            "search":  .string("let y = 1"),
            "replace": .string("let y = 99")
        ])

        // Either whitespaceNormalized or fuzzy should succeed
        XCTAssertEqual(extractApplied(result), true, "Ladder should apply via fuzzy/whitespace")
    }

    func testZionEditRejectAbsolutePath() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tool = EditTool(repoURL: dir)
        let result = try tool.call(args: [
            "path":    .string("/etc/passwd"),
            "search":  .string("root"),
            "replace": .string("evil")
        ])

        XCTAssertEqual(extractApplied(result), false, "Absolute path must be rejected")
    }

    func testZionEditRejectTraversal() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tool = EditTool(repoURL: dir)
        let result = try tool.call(args: [
            "path":    .string("../foo.swift"),
            "search":  .string("x"),
            "replace": .string("y")
        ])

        XCTAssertEqual(extractApplied(result), false, "Path traversal must be rejected")
    }

    func testZionEditRejectSymlinkEscapingRepository() throws {
        let repoDir = try makeTempDir()
        let outsideDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: repoDir)
            try? FileManager.default.removeItem(at: outsideDir)
        }

        let outsideFile = outsideDir.appendingPathComponent("Secret.swift")
        try "let secret = true\n".write(to: outsideFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: repoDir.appendingPathComponent("Linked.swift"),
            withDestinationURL: outsideFile
        )

        let tool = EditTool(repoURL: repoDir)
        let result = try tool.call(args: [
            "path":    .string("Linked.swift"),
            "search":  .string("true"),
            "replace": .string("false")
        ])

        XCTAssertEqual(extractApplied(result), false, "A symlink must not edit files outside the repo")
        XCTAssertEqual(try String(contentsOf: outsideFile, encoding: .utf8), "let secret = true\n")
    }

    func testReadOnlyRegistryOmitsMutationTools() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let registry = ToolRegistry()

        registerMutationTools(in: registry, repoURL: dir, allowEdits: false)

        XCTAssertNil(registry.tool(named: "zion_edit"))
        XCTAssertNil(registry.tool(named: "zion_stash_apply"))
    }

    func testEditableRegistryExposesMutationTools() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let registry = ToolRegistry()

        registerMutationTools(in: registry, repoURL: dir, allowEdits: true)

        XCTAssertNotNil(registry.tool(named: "zion_edit"))
        XCTAssertNotNil(registry.tool(named: "zion_stash_apply"))
    }

    func testSessionRegistryDoesNotAdvertiseUnimplementedTools() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let registry = ToolRegistry()

        registerSessionTools(in: registry, repoURL: dir, allowEdits: false)

        XCTAssertNotNil(registry.tool(named: "zion_repo_memory_search"))
        XCTAssertNil(registry.tool(named: "bash"))
        XCTAssertNil(registry.tool(named: "zion_open_in_editor"))
    }

    func testGitLogCapsRequestedResultCount() {
        XCTAssertEqual(GitLog.boundedLimit(nil), 50)
        XCTAssertEqual(GitLog.boundedLimit(0), 1)
        XCTAssertEqual(GitLog.boundedLimit(10_000), GitLog.maximumLimit)
    }

    func testGitToolsRejectOptionInjectionInRevisionArguments() throws {
        XCTAssertThrowsError(try GitLog.validatedBranch("--all"))
        XCTAssertThrowsError(try GitLog.validatedBranch("main..secret"))
        XCTAssertNoThrow(try GitLog.validatedBranch("feature/zion-talks"))
        XCTAssertNoThrow(try GitLog.validatedBranch("HEAD"))

        XCTAssertThrowsError(try CommitInspect.validatedSHA("--all"))
        XCTAssertNoThrow(try CommitInspect.validatedSHA("a1b2c3d4"))

        XCTAssertThrowsError(try StashApplyTool.validatedStashID("--index"))
        XCTAssertNoThrow(try StashApplyTool.validatedStashID("stash@{12}"))
    }

    // MARK: - RepoMapTool tests

    func testZionRepoMapNoSnapshot() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // snapshotDir is an empty temp dir → no file present
        let tool = RepoMapTool(repoURL: dir, snapshotDir: dir)
        let result = try tool.call(args: [
            "query": .string("SomeNonExistentSymbol")
        ])

        XCTAssertEqual(extractAvailable(result), false, "Should return available:false when no snapshot exists")
    }

    func testZionRepoMapRanksByQuery() throws {
        let repoDir = try makeTempDir()
        let snapshotDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: repoDir)
            try? FileManager.default.removeItem(at: snapshotDir)
        }

        // Build a stub snapshot with 3 entries
        let repoID = RepoMapTool.computeRepoID(for: repoDir)
        let entries: [[String: Any]] = [
            ["path": "Sources/Foo/Bar.swift", "kind": "struct", "name": "BarManager",  "score": 1.0, "snippet": ""],
            ["path": "Sources/Foo/Baz.swift", "kind": "func",   "name": "bazHelper",   "score": 0.5, "snippet": ""],
            ["path": "Sources/Foo/Qux.swift", "kind": "class",  "name": "QuxController","score": 0.8, "snippet": ""]
        ]
        let snapshot: [String: Any] = [
            "repoID": repoID,
            "indexedAt": Date().timeIntervalSince1970,
            "entries": entries,
            "references": [String: [String]]()
        ]

        let data = try JSONSerialization.data(withJSONObject: snapshot)
        try data.write(to: snapshotDir.appendingPathComponent("\(repoID).json"))

        let tool = RepoMapTool(repoURL: repoDir, snapshotDir: snapshotDir)
        let result = try tool.call(args: [
            "query": .string("BarManager")
        ])

        XCTAssertEqual(extractAvailable(result), true, "Should return available:true")
        let entries2 = try XCTUnwrap(extractEntries(result), "Should have entries array")
        XCTAssertFalse(entries2.isEmpty, "Should return at least one entry")
        let firstName = entries2[0]["name"] as? String
        XCTAssertEqual(firstName, "BarManager", "BarManager should be ranked first for query 'BarManager'")
    }

    func testRepoMemorySearchReturnsOnlyCurrentRepositorySnapshot() throws {
        let repoDir = try makeTempDir()
        let otherRepoDir = try makeTempDir()
        let snapshotDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: repoDir)
            try? FileManager.default.removeItem(at: otherRepoDir)
            try? FileManager.default.removeItem(at: snapshotDir)
        }

        func writeSnapshot(for repoURL: URL, module: String) throws {
            let fingerprint = RepoMapTool.computeRepoID(for: repoURL)
            let snapshot: [String: Any] = [
                "schemaVersion": 1,
                "repositoryID": "\(fingerprint)-remote",
                "generatedAt": "2026-05-26T10:00:00Z",
                "activeBranch": "main",
                "headShortHash": "abc1234",
                "commitStyle": [
                    "usesConventionalCommits": false,
                    "commonTypes": [],
                    "commonScopes": [],
                    "preferredVerbStyle": "imperative",
                    "averageTitleLength": 10
                ],
                "moduleHints": [module],
                "branchPatterns": [],
                "conventions": [],
                "testMappings": [:],
                "sensitiveAreas": []
            ]
            let data = try JSONSerialization.data(withJSONObject: snapshot)
            try data.write(to: snapshotDir.appendingPathComponent("\(fingerprint).json"))
        }

        try writeSnapshot(for: repoDir, module: "CurrentSecretModule")
        try writeSnapshot(for: otherRepoDir, module: "OtherSecretModule")

        let tool = RepoMemorySearchTool(repoURL: repoDir, snapshotsDir: snapshotDir)
        let result = try tool.call(args: ["query": .string("SecretModule")])
        let results = try XCTUnwrap(extractResults(result))
        let snippets = results.compactMap { $0["snippet"] as? String }
        let paths = results.compactMap { $0["path"] as? String }

        XCTAssertEqual(snippets, ["CurrentSecretModule"])
        XCTAssertFalse(snippets.contains("OtherSecretModule"))
        XCTAssertTrue(paths.allSatisfy { !$0.contains("/") }, "Storage directory should not be exposed")
    }

    func testRepoMapCapsRequestedResultCount() throws {
        let repoDir = try makeTempDir()
        let snapshotDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: repoDir)
            try? FileManager.default.removeItem(at: snapshotDir)
        }
        let repoID = RepoMapTool.computeRepoID(for: repoDir)
        let entries = (0..<60).map { index in
            ["path": "Sources/F\(index).swift", "kind": "func", "name": "match\(index)", "score": 1.0]
        }
        let snapshot: [String: Any] = [
            "repoID": repoID,
            "indexedAt": Date().timeIntervalSince1970,
            "entries": entries,
            "references": [String: [String]]()
        ]
        try JSONSerialization.data(withJSONObject: snapshot)
            .write(to: snapshotDir.appendingPathComponent("\(repoID).json"))

        let tool = RepoMapTool(repoURL: repoDir, snapshotDir: snapshotDir)
        let result = try tool.call(args: ["query": .string("match"), "limit": .int(10_000)])

        XCTAssertEqual(extractEntries(result)?.count, 50)
    }
}
