import XCTest
@testable import Zion

@MainActor
final class SlashCommandRegistryTests: XCTestCase {

    // MARK: - Helpers

    private func makeEmptyRegistry() -> SlashCommandRegistry {
        let index = SkillIndex(
            userRoot: URL(fileURLWithPath: "/tmp/nonexistent-user-skills"),
            projectRoot: nil
        )
        return SlashCommandRegistry(skillIndex: index)
    }

    // MARK: - Test 1: builtin_diff_argHint

    func test_builtin_diff_argHint() {
        let registry = makeEmptyRegistry()
        let diffItem = registry.all.first { $0.id == "diff" }
        XCTAssertNotNil(diffItem, "Registry must contain /diff")
        XCTAssertEqual(diffItem?.argHint, "[ref]")
    }

    // MARK: - Test 2: match_prefix_/di_returns_diff

    func test_match_prefix_di_returns_diff() {
        let registry = makeEmptyRegistry()
        let results = registry.match(prefix: "/di")
        XCTAssertFalse(results.isEmpty, "Match for /di must not be empty")
        XCTAssertEqual(results.first?.id, "diff")
    }

    // MARK: - Test 3: skillIndex_parses_frontmatter_fixture

    func test_skillIndex_parses_frontmatter_fixture() {
        let content = "---\nname: foo\ndescription: bar\n---\nBody"
        let (fm, body) = SkillIndex.parseFrontmatter(content: content)
        XCTAssertEqual(fm["name"], "foo")
        XCTAssertEqual(fm["description"], "bar")
        XCTAssertEqual(body, "Body")
    }

    // MARK: - Test 4: skillIndex_handles_missing_frontmatter

    func test_skillIndex_handles_missing_frontmatter() {
        let content = "Just some plain content\nNo frontmatter here."
        let (fm, body) = SkillIndex.parseFrontmatter(content: content)
        XCTAssertTrue(fm.isEmpty, "Frontmatter map should be empty when no --- delimiters")
        XCTAssertEqual(body, content)
    }

    // MARK: - Test 5: skillIndex_scan_temp_root

    func test_skillIndex_scan_temp_root() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlashTest-\(UUID().uuidString)")
        let skillDir = tmp.appendingPathComponent("foo")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let skillMD = """
        ---
        name: Foo Skill
        description: A test skill
        ---

        This is the body.
        """
        try skillMD.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let index = SkillIndex(userRoot: tmp, projectRoot: nil)
        await index.reload()

        XCTAssertEqual(index.skills.count, 1)
        XCTAssertEqual(index.skills[0].id, "foo")
        XCTAssertEqual(index.skills[0].name, "Foo Skill")
        XCTAssertEqual(index.skills[0].description, "A test skill")
        XCTAssertFalse(index.skills[0].body.isEmpty)
    }

    // MARK: - Test 6: project_shadows_user_when_names_collide

    func test_project_shadows_user_when_names_collide() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlashShadow-\(UUID().uuidString)")
        let userRoot = tmp.appendingPathComponent("user")
        let projectRoot = tmp.appendingPathComponent("project")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Both have a skill named "foo"
        for root in [userRoot, projectRoot] {
            let skillDir = root.appendingPathComponent("foo")
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
            let scope = root == projectRoot ? "project" : "user"
            let md = "---\nname: Foo \(scope)\ndescription: From \(scope)\n---\nBody"
            try md.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }

        let index = SkillIndex(userRoot: userRoot, projectRoot: projectRoot)
        await index.reload()

        // Only one "foo" should survive, and it should be the project version
        let fooSkills = index.skills.filter { $0.id == "foo" }
        XCTAssertEqual(fooSkills.count, 1, "Collision should produce exactly one skill")
        XCTAssertEqual(fooSkills[0].scope, .project, "Project skill should shadow user skill")
        XCTAssertEqual(fooSkills[0].description, "From project")
    }

    // MARK: - Test 7: builtin_list_is_at_least_8

    func test_builtin_list_is_at_least_8() {
        XCTAssertGreaterThanOrEqual(BuiltInSlashCommands.all.count, 8)
    }

    // MARK: - Test 8: match_limit_caps_at_6

    func test_match_limit_caps_at_6() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlashLimit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // Create 20 skills named aaa01 through aaa20 — all match prefix "/"
        for i in 1...20 {
            let slug = String(format: "aaa%02d", i)
            let dir = tmp.appendingPathComponent(slug)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let md = "---\nname: \(slug)\ndescription: Test \(i)\n---\nBody"
            try md.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }

        let index = SkillIndex(userRoot: tmp, projectRoot: nil)
        await index.reload()
        XCTAssertEqual(index.skills.count, 20, "Should have loaded 20 skills")

        let registry = SlashCommandRegistry(skillIndex: index)
        let results = registry.match(prefix: "/", limit: 6)
        XCTAssertLessThanOrEqual(results.count, 6, "match(prefix:limit:) must cap at limit")
    }
}
