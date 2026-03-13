import XCTest
@testable import Zion

final class TerminalHelperInstallTests: XCTestCase {
    @MainActor
    func testInstallScriptsRefreshesGlobalZionImgHelpersWithCachePromptByDefault() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let homePath = tempRoot.path
        let binPath = tempRoot.appendingPathComponent(".zion/bin", isDirectory: true).path

        TerminalTabView.Coordinator.installScripts(
            aiImageDisplay: true,
            saveGeneratedImagesToProjectRoot: false,
            ntfyTopic: "",
            ntfyServer: "https://ntfy.sh",
            homeDirectoryPath: homePath,
            zionBinDirOverride: binPath
        )

        let codexSkillPath = tempRoot.appendingPathComponent(".agents/skills/zion-img/SKILL.md").path
        let claudeCommandPath = tempRoot.appendingPathComponent(".claude/commands/zion-img.md").path
        let geminiCommandPath = tempRoot.appendingPathComponent(".gemini/commands/zion-img.toml").path
        let displayPath = tempRoot.appendingPathComponent(".zion/bin/zion_display").path

        XCTAssertTrue(FileManager.default.fileExists(atPath: codexSkillPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: claudeCommandPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: geminiCommandPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: displayPath))

        let codexSkill = try String(contentsOfFile: codexSkillPath, encoding: .utf8)
        let claudeCommand = try String(contentsOfFile: claudeCommandPath, encoding: .utf8)
        let geminiCommand = try String(contentsOfFile: geminiCommandPath, encoding: .utf8)

        XCTAssertTrue(codexSkill.contains("~/Library/Caches/Zion/images/<name>.svg"))
        XCTAssertTrue(claudeCommand.contains("~/Library/Caches/Zion/images/<name>.svg"))
        XCTAssertTrue(geminiCommand.contains("~/Library/Caches/Zion/images/<name>.svg"))
        XCTAssertFalse(codexSkill.contains("zion-image/<name>.svg"))
        XCTAssertFalse(claudeCommand.contains("zion-image/<name>.svg"))
        XCTAssertFalse(geminiCommand.contains("zion-image/<name>.svg"))
        XCTAssertTrue(codexSkill.contains("Never use Playwright, browser tools, screenshots, or external viewers"))
        XCTAssertTrue(claudeCommand.contains("Never use Playwright, browser tools, screenshots, or external viewers"))
        XCTAssertTrue(geminiCommand.contains("Never use Playwright, browser tools, screenshots, or external viewers"))

        let displayScript = try String(contentsOfFile: displayPath, encoding: .utf8)
        XCTAssertTrue(displayScript.contains("printf '\\r\\n\\r\\n'"))
        XCTAssertTrue(displayScript.contains("printf '\\r\\n\\r\\n\\r\\n\\r\\n'"))
    }

    @MainActor
    func testInstallScriptsCanRefreshGlobalZionImgHelpersWithProjectRootPrompt() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let homePath = tempRoot.path
        let binPath = tempRoot.appendingPathComponent(".zion/bin", isDirectory: true).path

        TerminalTabView.Coordinator.installScripts(
            aiImageDisplay: true,
            saveGeneratedImagesToProjectRoot: true,
            ntfyTopic: "",
            ntfyServer: "https://ntfy.sh",
            homeDirectoryPath: homePath,
            zionBinDirOverride: binPath
        )

        let codexSkillPath = tempRoot.appendingPathComponent(".agents/skills/zion-img/SKILL.md").path
        let claudeCommandPath = tempRoot.appendingPathComponent(".claude/commands/zion-img.md").path
        let geminiCommandPath = tempRoot.appendingPathComponent(".gemini/commands/zion-img.toml").path

        let codexSkill = try String(contentsOfFile: codexSkillPath, encoding: .utf8)
        let claudeCommand = try String(contentsOfFile: claudeCommandPath, encoding: .utf8)
        let geminiCommand = try String(contentsOfFile: geminiCommandPath, encoding: .utf8)

        XCTAssertTrue(codexSkill.contains("Create `zion-image/` in the project root if needed"))
        XCTAssertTrue(claudeCommand.contains("Create `zion-image/` in the project root if needed"))
        XCTAssertTrue(geminiCommand.contains("Create zion-image/ in the project root if needed"))
        XCTAssertTrue(codexSkill.contains("zion-image/<name>.svg"))
        XCTAssertTrue(claudeCommand.contains("zion-image/<name>.svg"))
        XCTAssertTrue(geminiCommand.contains("zion-image/<name>.svg"))
        XCTAssertTrue(codexSkill.contains("Never open the generated SVG/PNG in a browser tab"))
        XCTAssertTrue(claudeCommand.contains("Never open the generated SVG/PNG in a browser tab"))
        XCTAssertTrue(geminiCommand.contains("Never open the generated SVG/PNG in a browser tab"))
    }
}
