import XCTest
@testable import Zion

final class TerminalHelperInstallTests: XCTestCase {
    @MainActor
    func testInstallScriptsRefreshesGlobalZionImgHelpersWithPreviewFirstPrompt() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let homePath = tempRoot.path
        let binPath = tempRoot.appendingPathComponent(".zion/bin", isDirectory: true).path

        TerminalTabView.Coordinator.installScripts(
            aiImageDisplay: true,
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

        XCTAssertTrue(codexSkill.contains("Generate an image file for preview in Zion."))
        XCTAssertTrue(claudeCommand.contains("Generate an image file for preview in Zion."))
        XCTAssertTrue(geminiCommand.contains("Generate an image file for preview in Zion."))
        XCTAssertTrue(codexSkill.contains("Create `zion-image/` in the project root if needed"))
        XCTAssertTrue(claudeCommand.contains("Create `zion-image/` in the project root if needed"))
        XCTAssertTrue(geminiCommand.contains("Create zion-image/ in the project root if needed"))
        XCTAssertTrue(codexSkill.contains("Stop after saving the file and tell the user it is ready for preview in Zion."))
        XCTAssertTrue(claudeCommand.contains("Stop after saving the file and tell the user it is ready for preview in Zion."))
        XCTAssertTrue(geminiCommand.contains("Stop after saving the file and tell the user it is ready for preview in Zion."))
        XCTAssertTrue(codexSkill.contains("Do not attempt inline terminal display from AI CLIs"))
        XCTAssertTrue(claudeCommand.contains("Do not attempt inline terminal display from AI CLIs"))
        XCTAssertTrue(geminiCommand.contains("Do not attempt inline terminal display from AI CLIs"))
        XCTAssertFalse(codexSkill.contains("~/Library/Caches/Zion/images/<name>.svg"))
        XCTAssertFalse(claudeCommand.contains("~/Library/Caches/Zion/images/<name>.svg"))
        XCTAssertFalse(geminiCommand.contains("~/Library/Caches/Zion/images/<name>.svg"))
        XCTAssertFalse(codexSkill.contains("generate and display images inline"))
        XCTAssertFalse(claudeCommand.contains("generate and display images inline"))
        XCTAssertFalse(geminiCommand.contains("generate and display images inline"))

        let displayScript = try String(contentsOfFile: displayPath, encoding: .utf8)
        XCTAssertTrue(displayScript.contains("printf '\\r\\n\\r\\n'"))
        XCTAssertTrue(displayScript.contains("printf '\\r\\n\\r\\n\\r\\n\\r\\n'"))
    }
}
