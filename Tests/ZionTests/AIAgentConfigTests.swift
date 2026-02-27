import XCTest
@testable import Zion

final class AIAgentConfigTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIAgentConfigTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Enum: Agent count

    func testAgentCount() {
        XCTAssertEqual(AIAgent.allCases.count, 14, "Agent count changed — update tests")
    }

    // MARK: - Enum: Labels

    func testAllAgentsHaveNonEmptyLabels() {
        for agent in AIAgent.allCases {
            XCTAssertFalse(agent.label.isEmpty, "\(agent.rawValue) has empty label")
        }
    }

    // MARK: - Enum: Config paths

    func testAllAgentsHaveNonEmptyPaths() {
        for agent in AIAgent.allCases {
            XCTAssertFalse(agent.globalConfigRelativePath.isEmpty, "\(agent.rawValue) has empty path")
        }
    }

    func testNoPathContainsTraversal() {
        for agent in AIAgent.allCases {
            XCTAssertFalse(
                agent.globalConfigRelativePath.contains(".."),
                "\(agent.rawValue) path contains '..' traversal"
            )
        }
    }

    func testUniquePaths() {
        let paths = AIAgent.allCases.map(\.globalConfigRelativePath)
        XCTAssertEqual(Set(paths).count, paths.count, "Duplicate config paths found")
    }

    // MARK: - Enum: Dedicated file correctness

    func testDedicatedFileAgents() {
        let shared = AIAgent.allCases.filter { !$0.usesDedicatedFile }
        let sharedIds = Set(shared.map(\.rawValue))
        XCTAssertEqual(sharedIds, ["geminiCLI", "windsurf", "aider"])
    }

    // MARK: - Enum: YAML

    func testOnlyAiderIsYAML() {
        let yamlAgents = AIAgent.allCases.filter(\.isYAML)
        XCTAssertEqual(yamlAgents.count, 1)
        XCTAssertEqual(yamlAgents.first, .aider)
    }

    // MARK: - Enum: globalConfigURL with baseDirectory

    func testGlobalConfigURLUsesBaseDirectory() {
        let base = URL(fileURLWithPath: "/tmp/test-home")
        let url = AIAgent.claudeCode.globalConfigURL(baseDirectory: base)
        XCTAssertTrue(url.path.hasPrefix("/tmp/test-home"))
        XCTAssertTrue(url.path.hasSuffix(AIAgent.claudeCode.globalConfigRelativePath))
    }

    func testUniqueRawValues() {
        let rawValues = AIAgent.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count, "Duplicate raw values found")
    }

    // MARK: - Lifecycle: Dedicated file install

    func testInstallDedicatedFileCreatesFileAndParentDirs() {
        let agent = AIAgent.claudeCode
        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)
        let fileURL = agent.globalConfigURL(baseDirectory: tempDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testInstallDedicatedFileContent() throws {
        let agent = AIAgent.cursor
        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)
        let fileURL = agent.globalConfigURL(baseDirectory: tempDir)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("ZION:NTFY:START"))
        XCTAssertTrue(content.contains("curl"))
        XCTAssertTrue(content.contains("ZION:NTFY:END"))
    }

    // MARK: - Lifecycle: Dedicated file remove

    func testRemoveDedicatedFileDeletesFileAndEmptyParent() throws {
        let agent = AIAgent.claudeCode
        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)
        AIAgentConfigManager.removeGlobalRule(for: agent, baseDirectory: tempDir)
        let fileURL = agent.globalConfigURL(baseDirectory: tempDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Lifecycle: Shared file install

    func testInstallSharedFileCreatesNewFile() throws {
        let agent = AIAgent.geminiCLI
        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)
        let fileURL = agent.globalConfigURL(baseDirectory: tempDir)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("ZION:NTFY:START"))
    }

    func testInstallSharedFileAppendsToExisting() throws {
        let agent = AIAgent.windsurf
        let fileURL = agent.globalConfigURL(baseDirectory: tempDir)
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try "# Existing rules\nSome content here\n".write(to: fileURL, atomically: true, encoding: .utf8)

        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("Existing rules"))
        XCTAssertTrue(content.contains("ZION:NTFY:START"))
    }

    func testIdempotentInstallOnlyOneBlock() throws {
        let agent = AIAgent.windsurf
        let fileURL = agent.globalConfigURL(baseDirectory: tempDir)
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        // Pre-populate file with existing content so removeBlock doesn't delete it
        try "# Existing content\n".write(to: fileURL, atomically: true, encoding: .utf8)

        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)
        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let count = content.components(separatedBy: "ZION:NTFY:START").count - 1
        XCTAssertEqual(count, 1, "Expected exactly one ZION:NTFY:START marker")
    }

    // MARK: - Lifecycle: Shared file remove

    func testRemoveSharedPreservesOtherContent() throws {
        let agent = AIAgent.windsurf
        let fileURL = agent.globalConfigURL(baseDirectory: tempDir)
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try "# Existing rules\n".write(to: fileURL, atomically: true, encoding: .utf8)

        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)
        AIAgentConfigManager.removeGlobalRule(for: agent, baseDirectory: tempDir)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("Existing rules"))
        XCTAssertFalse(content.contains("ZION:NTFY:START"))
    }

    func testRemoveSharedDeletesFileIfEmpty() throws {
        let agent = AIAgent.geminiCLI
        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)
        AIAgentConfigManager.removeGlobalRule(for: agent, baseDirectory: tempDir)
        let fileURL = agent.globalConfigURL(baseDirectory: tempDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - isGlobalRuleInstalled

    func testIsInstalledReturnsTrueForDedicated() {
        let agent = AIAgent.cursor
        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)
        XCTAssertTrue(AIAgentConfigManager.isGlobalRuleInstalled(for: agent, baseDirectory: tempDir))
    }

    func testIsInstalledReturnsFalseForDedicated() {
        let agent = AIAgent.cursor
        XCTAssertFalse(AIAgentConfigManager.isGlobalRuleInstalled(for: agent, baseDirectory: tempDir))
    }

    func testIsInstalledReturnsTrueForShared() {
        let agent = AIAgent.geminiCLI
        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)
        XCTAssertTrue(AIAgentConfigManager.isGlobalRuleInstalled(for: agent, baseDirectory: tempDir))
    }

    func testIsInstalledReturnsFalseForShared() {
        let agent = AIAgent.geminiCLI
        XCTAssertFalse(AIAgentConfigManager.isGlobalRuleInstalled(for: agent, baseDirectory: tempDir))
    }

    // MARK: - Aider (YAML)

    func testAiderUsesYAMLMarkers() throws {
        let agent = AIAgent.aider
        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)
        let fileURL = agent.globalConfigURL(baseDirectory: tempDir)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("# ZION:NTFY:START"))
        XCTAssertTrue(content.contains("# ZION:NTFY:END"))
        // Should NOT contain HTML-style markers
        XCTAssertFalse(content.contains("<!-- ZION:NTFY:START"))
    }

    // MARK: - Block content security

    func testBlockContentContainsCurlInstruction() throws {
        let agent = AIAgent.claudeCode
        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)
        let fileURL = agent.globalConfigURL(baseDirectory: tempDir)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("curl"))
        XCTAssertTrue(content.contains("config.json"))
    }

    func testBlockContentDoesNotContainHardcodedSecrets() throws {
        let agent = AIAgent.claudeCode
        AIAgentConfigManager.installGlobalRule(for: agent, baseDirectory: tempDir)
        let fileURL = agent.globalConfigURL(baseDirectory: tempDir)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        // Should not have any hardcoded topics or server URLs
        XCTAssertFalse(content.contains("ntfy.sh/"))
        XCTAssertFalse(content.contains("zion-code-"))
    }

    // MARK: - Partial markers (robustness)

    func testPartialStartMarkerDoesNotCrash() throws {
        let agent = AIAgent.windsurf
        let fileURL = agent.globalConfigURL(baseDirectory: tempDir)
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        // Write only a start marker without an end marker
        try "<!-- ZION:NTFY:START (managed by Zion Git Client) -->\nOrphan content\n".write(
            to: fileURL, atomically: true, encoding: .utf8
        )
        // removeBlock should not crash when end marker is missing
        AIAgentConfigManager.removeGlobalRule(for: agent, baseDirectory: tempDir)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        // Content should still be there since removal requires both markers
        XCTAssertTrue(content.contains("Orphan content"))
    }
}
