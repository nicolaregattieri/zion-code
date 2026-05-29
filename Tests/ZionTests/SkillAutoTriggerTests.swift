import XCTest
@testable import Zion

/// Phase 6.5 — skill `triggers` array is consulted server-side. When
/// any trigger is a case-insensitive substring of the user message,
/// the skill body is injected into hiddenContext so the model
/// applies it without the user typing `/<id>` literally.
final class SkillAutoTriggerTests: XCTestCase {

    private func makeSkill(id: String, triggers: [String], body: String = "body") -> Skill {
        Skill(
            id: id,
            name: id,
            description: "d",
            scope: .user,
            path: FileManager.default.temporaryDirectory.appendingPathComponent("\(id).md"),
            body: body,
            triggers: triggers
        )
    }

    func test_emptyText_returnsEmpty() {
        let s = makeSkill(id: "x", triggers: ["foo"])
        XCTAssertEqual(ChatService.autoInjectedSkillBodies(text: "", skills: [s]), "")
    }

    func test_noTriggers_returnsEmpty() {
        let s = makeSkill(id: "x", triggers: [])
        XCTAssertEqual(ChatService.autoInjectedSkillBodies(text: "anything", skills: [s]), "")
    }

    func test_substringMatch_caseInsensitive_injectsBody() {
        let s = makeSkill(id: "review", triggers: ["code review"], body: "checklist here")
        let out = ChatService.autoInjectedSkillBodies(text: "please do a Code Review on this PR", skills: [s])
        XCTAssertTrue(out.contains("[auto-skill: review]"))
        XCTAssertTrue(out.contains("checklist here"))
    }

    func test_noMatch_returnsEmpty() {
        let s = makeSkill(id: "review", triggers: ["code review"])
        XCTAssertEqual(ChatService.autoInjectedSkillBodies(text: "what time is it?", skills: [s]), "")
    }

    func test_multipleSkillsMatch_concatenated_capAt3() {
        let skills = (0..<5).map { i in
            makeSkill(id: "s\(i)", triggers: ["go\(i)"], body: "b\(i)")
        }
        let out = ChatService.autoInjectedSkillBodies(
            text: "go0 go1 go2 go3 go4",
            skills: skills
        )
        XCTAssertTrue(out.contains("b0"))
        XCTAssertTrue(out.contains("b1"))
        XCTAssertTrue(out.contains("b2"))
        XCTAssertFalse(out.contains("b3"))
        XCTAssertFalse(out.contains("b4"))
    }

    func test_emptyTriggerStringIgnored() {
        let s = makeSkill(id: "x", triggers: ["   "])
        XCTAssertEqual(ChatService.autoInjectedSkillBodies(text: "anything", skills: [s]), "")
    }
}
