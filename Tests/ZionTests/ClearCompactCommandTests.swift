import XCTest
@testable import Zion

@MainActor
final class ClearCompactCommandTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a HelpCardPayload using real registries and a custom SkillIndex.
    private func makePayload(skillIndex: SkillIndex? = nil) -> HelpCardPayload {
        // ChatContextBuilder requires a RepositoryWorker, but buildHelpPayload is synchronous
        // and never calls worker methods — inject a stub URL.
        let worker = RepositoryWorker()
        let builder = ChatContextBuilder(worker: worker)
        let index = skillIndex ?? SkillIndex()
        let registry = SlashCommandRegistry(skillIndex: index)
        return builder.buildHelpPayload(registry: registry, skillIndex: index, mcpStore: nil)
    }

    // MARK: - Test 1: built-in items include /diff

    func test_help_payload_includes_builtin_diff() {
        let payload = makePayload()
        let ids = payload.builtInItems.map { $0.id }
        XCTAssertTrue(ids.contains("diff"), "Expected 'diff' in builtInItems, got: \(ids)")
    }

    // MARK: - Test 2: mentions count equals 4

    func test_help_payload_includes_mentions_count_4() {
        let payload = makePayload()
        XCTAssertEqual(payload.mentions.count, 4, "Expected 4 @mention items, got \(payload.mentions.count)")
    }

    // MARK: - Test 3: HelpCardPayload equality round-trip

    func test_chatMessage_with_helpCardPayload_equals_self() {
        let item = HelpCardPayload.HelpCardItem(id: "test", label: "/test", description: "A test")
        let p1 = HelpCardPayload(
            builtInItems: [item],
            projectSkills: [],
            userSkills: [],
            mentions: [],
            mcpTools: [],
            shortcuts: []
        )
        let p2 = HelpCardPayload(
            builtInItems: [item],
            projectSkills: [],
            userSkills: [],
            mentions: [],
            mcpTools: [],
            shortcuts: []
        )
        XCTAssertEqual(p1, p2)

        let msg = ChatMessage(role: .assistant, content: "", isStreaming: false, helpCardPayload: p1)
        XCTAssertEqual(msg, msg)
        XCTAssertEqual(msg.helpCardPayload, p1)
    }

    // MARK: - Test 4: project vs user skill separation

    func test_help_payload_separates_project_vs_user_skills() async {
        // Create temp directories with one project skill and one user skill
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ClearCompactTests-\(UUID().uuidString)")
        let projectRoot = tmp.appendingPathComponent("project")
        let userRoot = tmp.appendingPathComponent("user")

        // Project skill: "p-skill"
        let projectSkillDir = projectRoot.appendingPathComponent("p-skill")
        try! FileManager.default.createDirectory(at: projectSkillDir, withIntermediateDirectories: true)
        let projectSkillFile = projectSkillDir.appendingPathComponent("SKILL.md")
        try! """
        ---
        description: A project skill
        ---
        Body here.
        """.write(to: projectSkillFile, atomically: true, encoding: .utf8)

        // User skill: "u-skill"
        let userSkillDir = userRoot.appendingPathComponent("u-skill")
        try! FileManager.default.createDirectory(at: userSkillDir, withIntermediateDirectories: true)
        let userSkillFile = userSkillDir.appendingPathComponent("SKILL.md")
        try! """
        ---
        description: A user skill
        ---
        Body here.
        """.write(to: userSkillFile, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tmp) }

        let skillIndex = SkillIndex(userRoot: userRoot, projectRoot: projectRoot)
        await skillIndex.reload()

        let payload = makePayload(skillIndex: skillIndex)

        XCTAssertEqual(payload.projectSkills.count, 1, "Expected 1 project skill, got \(payload.projectSkills.count)")
        XCTAssertEqual(payload.userSkills.count, 1, "Expected 1 user skill, got \(payload.userSkills.count)")
        XCTAssertEqual(payload.projectSkills.first?.id, "p-skill")
        XCTAssertEqual(payload.userSkills.first?.id, "u-skill")
    }

    // MARK: - Test 5: shortcuts include send and newline

    func test_shortcuts_section_includes_send_and_newline() {
        let payload = makePayload()
        let ids = payload.shortcuts.map { $0.id }
        XCTAssertTrue(ids.contains("send"), "Expected 'send' shortcut, got: \(ids)")
        XCTAssertTrue(ids.contains("newline"), "Expected 'newline' shortcut, got: \(ids)")
    }
}
