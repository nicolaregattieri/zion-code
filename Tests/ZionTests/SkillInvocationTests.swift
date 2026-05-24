import XCTest
@testable import Zion

// Tests for ChatService.injectSkillIfMatched(text:skills:)
// This is a nonisolated static func — no MainActor needed.
final class SkillInvocationTests: XCTestCase {

    // MARK: - Fixture

    private func makeSkill(id: String, name: String, body: String) -> Skill {
        Skill(
            id: id,
            name: name,
            description: "test skill",
            scope: .user,
            path: URL(fileURLWithPath: "/tmp/\(id)/SKILL.md"),
            body: body,
            triggers: []
        )
    }

    // MARK: - Tests

    func test_injection_with_known_skill_returns_payload() {
        let skill = makeSkill(id: "foo", name: "foo", body: "do X")
        let result = ChatService.injectSkillIfMatched(
            text: "/foo make it blue",
            skills: [skill]
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("[skill: foo]"), "Should contain skill tag")
        XCTAssertTrue(result!.contains("do X"), "Should contain skill body")
        XCTAssertTrue(result!.contains("make it blue"), "Should contain rest of prompt")
    }

    func test_unknown_slash_returns_nil() {
        let result = ChatService.injectSkillIfMatched(
            text: "/unknown stuff",
            skills: []
        )
        XCTAssertNil(result)
    }

    func test_non_slash_returns_nil() {
        let skill = makeSkill(id: "foo", name: "foo", body: "do X")
        let result = ChatService.injectSkillIfMatched(
            text: "hello world",
            skills: [skill]
        )
        XCTAssertNil(result)
    }

    func test_skill_with_no_rest_returns_payload_with_empty_rest() {
        let skill = makeSkill(id: "foo", name: "foo", body: "skill body here")
        let result = ChatService.injectSkillIfMatched(
            text: "/foo",
            skills: [skill]
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("[skill: foo]"), "Should contain skill tag")
        XCTAssertTrue(result!.contains("skill body here"), "Should contain skill body")
    }

    func test_skill_match_is_by_id_not_name() {
        let skill = makeSkill(id: "code-review", name: "Code Review", body: "Review carefully")
        let result = ChatService.injectSkillIfMatched(
            text: "/code-review this PR",
            skills: [skill]
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("[skill: Code Review]"), "Tag should use skill name")
        XCTAssertTrue(result!.contains("this PR"), "Should preserve rest of message")
    }

    func test_slash_only_token_no_id_returns_nil() {
        // "/" alone — empty id after dropFirst
        let skill = makeSkill(id: "", name: "", body: "body")
        let result = ChatService.injectSkillIfMatched(
            text: "/",
            skills: [skill]
        )
        // Empty id should not match (guard !id.isEmpty)
        XCTAssertNil(result)
    }

    func test_whitespace_only_text_returns_nil() {
        let skill = makeSkill(id: "foo", name: "foo", body: "body")
        let result = ChatService.injectSkillIfMatched(
            text: "   \n  ",
            skills: [skill]
        )
        XCTAssertNil(result)
    }
}
