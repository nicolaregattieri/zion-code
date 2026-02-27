import XCTest
@testable import Zion

final class AIAgentLegacyCleanupTests: XCTestCase {
    private var tempRepoDir: URL!

    override func setUp() {
        super.setUp()
        tempRepoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIAgentLegacyCleanupTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempRepoDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRepoDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func writeLegacyFile(relativePath: String, content: String) throws {
        let fileURL = tempRepoDir.appendingPathComponent(relativePath)
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func readFile(relativePath: String) throws -> String {
        let fileURL = tempRepoDir.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func fileExists(relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: tempRepoDir.appendingPathComponent(relativePath).path)
    }

    // MARK: - Markdown block removal

    func testRemovesMarkdownBlock() throws {
        let content = """
        # Project Rules

        <!-- ZION:NTFY:START (managed by Zion Git Client) -->
        ## Push Notifications
        When you complete a significant task, notify the user:
        1. Read `~/.config/ntfy/config.json` to get `topic` and `server`
        2. Send: `curl -s -H "Title: Done" -d "msg" 'server/topic'`
        <!-- ZION:NTFY:END -->

        # Other content
        """
        try writeLegacyFile(relativePath: "CLAUDE.md", content: content)

        AIAgentConfigManager.removeLegacyRepoBlocks(repoPath: tempRepoDir)

        let result = try readFile(relativePath: "CLAUDE.md")
        XCTAssertFalse(result.contains("ZION:NTFY:START"))
        XCTAssertTrue(result.contains("Other content"))
    }

    // MARK: - YAML block removal

    func testRemovesYAMLBlock() throws {
        let content = """
        # Some aider config
        # ZION:NTFY:START (managed by Zion Git Client)
        # Notification instructions here
        # ZION:NTFY:END
        # More config
        """
        try writeLegacyFile(relativePath: ".aider.conf.yml", content: content)

        AIAgentConfigManager.removeLegacyRepoBlocks(repoPath: tempRepoDir)

        let result = try readFile(relativePath: ".aider.conf.yml")
        XCTAssertFalse(result.contains("ZION:NTFY:START"))
        XCTAssertTrue(result.contains("More config"))
    }

    // MARK: - Preserves other content

    func testPreservesUnrelatedContent() throws {
        let content = """
        # My Project
        Important project rules that should not be removed.
        """
        try writeLegacyFile(relativePath: "CLAUDE.md", content: content)

        AIAgentConfigManager.removeLegacyRepoBlocks(repoPath: tempRepoDir)

        let result = try readFile(relativePath: "CLAUDE.md")
        XCTAssertTrue(result.contains("Important project rules"))
    }

    // MARK: - Deduplicated paths (openaiCodex + sourcegraphAmp share AGENTS.md)

    func testHandlesDeduplicatedPaths() throws {
        // Both openaiCodex and sourcegraphAmp use AGENTS.md
        let content = """
        # Agents
        <!-- ZION:NTFY:START (managed by Zion Git Client) -->
        Block content
        <!-- ZION:NTFY:END -->
        # Rest
        """
        try writeLegacyFile(relativePath: "AGENTS.md", content: content)

        AIAgentConfigManager.removeLegacyRepoBlocks(repoPath: tempRepoDir)

        let result = try readFile(relativePath: "AGENTS.md")
        XCTAssertFalse(result.contains("ZION:NTFY:START"))
        XCTAssertTrue(result.contains("Rest"))
    }

    // MARK: - No-op on clean repo

    func testNoOpOnCleanRepo() {
        // No files exist — should not crash
        AIAgentConfigManager.removeLegacyRepoBlocks(repoPath: tempRepoDir)
        // Just verifying no crash occurred
    }

    // MARK: - Deletes empty files

    func testDeletesFileIfOnlyBlockContent() throws {
        let content = """
        <!-- ZION:NTFY:START (managed by Zion Git Client) -->
        Block content only
        <!-- ZION:NTFY:END -->
        """
        try writeLegacyFile(relativePath: ".clinerules", content: content)

        AIAgentConfigManager.removeLegacyRepoBlocks(repoPath: tempRepoDir)

        XCTAssertFalse(fileExists(relativePath: ".clinerules"))
    }
}
