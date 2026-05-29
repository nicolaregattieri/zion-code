import XCTest
@testable import Zion

/// Phase 6.5 — `use_skill(id)` tool. Model dispatches it to activate
/// an installed skill; we return the skill body so the conversation
/// can apply it without a slash command from the user.
final class UseSkillToolTests: XCTestCase {

    func test_useSkill_descriptor_listedInAllTools() {
        let names = MCPConfigBuilder.allTools().map { $0.name }
        XCTAssertTrue(names.contains("use_skill"))
    }

    func test_useSkill_missingID_returnsErrorMarker() async throws {
        let r = try await MCPConfigBuilder.dispatch(name: "use_skill", args: [:])
        XCTAssertTrue(r.contains("missing 'id'"))
    }

    func test_useSkill_emptyID_returnsErrorMarker() async throws {
        let r = try await MCPConfigBuilder.dispatch(name: "use_skill", args: ["id": "  "])
        XCTAssertTrue(r.contains("empty id"))
    }

    func test_useSkill_unknownID_listsKnown() async throws {
        let r = try await MCPConfigBuilder.dispatch(name: "use_skill", args: ["id": "does-not-exist-\(UUID().uuidString)"])
        XCTAssertTrue(r.contains("no skill named"))
        XCTAssertTrue(r.contains("Installed:"))
    }
}
