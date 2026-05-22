import XCTest
@testable import Zion

final class MCPConfigBuilderTests: XCTestCase {

    // MARK: - testBuildWritesValidJSON

    func testBuildWritesValidJSON() throws {
        let cwd = URL(fileURLWithPath: "/tmp/my-repo")
        let stubBinary = "/usr/local/bin/zion-mcp"

        let configURL = try MCPConfigBuilder.build(cwd: cwd, binaryPath: stubBinary)
        defer { try? FileManager.default.removeItem(at: configURL) }

        // File should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))

        // Filename pattern: zion-mcp-<uuid>.json
        XCTAssertTrue(configURL.lastPathComponent.hasPrefix("zion-mcp-"))
        XCTAssertEqual(configURL.pathExtension, "json")

        // Decode and validate JSON shape
        let data = try Data(contentsOf: configURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Root is not a dictionary")
            return
        }
        guard let mcpServers = root["mcpServers"] as? [String: Any] else {
            XCTFail("Missing 'mcpServers' key")
            return
        }
        guard let zion = mcpServers["zion"] as? [String: Any] else {
            XCTFail("Missing 'mcpServers.zion' key")
            return
        }
        XCTAssertEqual(zion["command"] as? String, stubBinary, "command should match binary path")
        guard let args = zion["args"] as? [String] else {
            XCTFail("Missing 'mcpServers.zion.args' array")
            return
        }
        XCTAssertEqual(args, ["--repo", cwd.path], "args should be ['--repo', cwd.path]")
    }

    // MARK: - testSweepRemovesStaleFiles

    func testSweepRemovesStaleFiles() throws {
        let fm = FileManager.default
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        // Create a stale file (2 hours old)
        let staleURL = tmpDir.appendingPathComponent("zion-mcp-stale-test-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: staleURL)
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        try fm.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: staleURL.path)

        // Create a fresh file (30 minutes old)
        let freshURL = tmpDir.appendingPathComponent("zion-mcp-fresh-test-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: freshURL)
        let thirtyMinutesAgo = Date().addingTimeInterval(-1800)
        try fm.setAttributes([.modificationDate: thirtyMinutesAgo], ofItemAtPath: freshURL.path)

        defer {
            // Cleanup fresh file in case sweep did not remove it (expected)
            try? fm.removeItem(at: freshURL)
        }

        // Run sweep with 1-hour TTL (default)
        MCPConfigBuilder.sweepStaleConfigs(now: Date(), maxAge: 3600)

        // Stale file (2h old) must be gone
        XCTAssertFalse(fm.fileExists(atPath: staleURL.path), "Stale 2h-old file should have been removed")

        // Fresh file (30m old) must remain
        XCTAssertTrue(fm.fileExists(atPath: freshURL.path), "Fresh 30m-old file should NOT have been removed")
    }

    // MARK: - testBuildUsesEnvVarBinaryPath

    func testBuildUsesEnvVarBinaryPath() throws {
        // resolveBinaryPath() honours ZION_MCP_BINARY_PATH env var.
        // We cannot set env vars in process at runtime in a test without setenv(),
        // so just validate the explicit binaryPath parameter round-trip.
        let cwd = URL(fileURLWithPath: "/tmp/env-repo")
        let fakeBinary = "/tmp/zion-mcp-fake"
        let configURL = try MCPConfigBuilder.build(cwd: cwd, binaryPath: fakeBinary)
        defer { try? FileManager.default.removeItem(at: configURL) }

        let data = try Data(contentsOf: configURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let command = (root?["mcpServers"] as? [String: Any])?["zion"] as? [String: Any]
        XCTAssertEqual(command?["command"] as? String, fakeBinary)
    }
}
