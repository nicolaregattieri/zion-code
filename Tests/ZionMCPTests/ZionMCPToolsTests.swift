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
}
