import XCTest
@testable import Zion

/// System prompt MUST list installed skills and installed user MCP
/// servers. Without this the model is blind to extensions — it tells
/// the user to "edit JSON" or claims the feature does not exist.
final class PromptCatalogTests: XCTestCase {

    // MARK: - Skill catalog

    func test_skillCatalog_empty_returnsEmptyString() {
        XCTAssertTrue(ChatService.skillCatalogAppendixForTesting(skills: []).isEmpty)
    }

    func test_skillCatalog_listsIDAndDescription() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-\(UUID().uuidString).md")
        let skill = Skill(
            id: "review-pr",
            name: "Review PR",
            description: "Code review checklist for pull requests.",
            scope: .user,
            path: tmp,
            body: "body",
            triggers: []
        )
        let s = ChatService.skillCatalogAppendixForTesting(skills: [skill])
        XCTAssertTrue(s.contains("## Available skills"))
        XCTAssertTrue(s.contains("`/review-pr`"))
        XCTAssertTrue(s.contains("Code review checklist"))
    }

    func test_skillCatalog_capsAt30() {
        let tmp = FileManager.default.temporaryDirectory
        let many = (0..<35).map { i in
            Skill(
                id: "s\(i)",
                name: "Skill \(i)",
                description: "desc \(i)",
                scope: .user,
                path: tmp.appendingPathComponent("s\(i).md"),
                body: "",
                triggers: []
            )
        }
        let s = ChatService.skillCatalogAppendixForTesting(skills: many)
        XCTAssertTrue(s.contains("/s0"))
        XCTAssertTrue(s.contains("/s29"))
        XCTAssertFalse(s.contains("/s30"))
        XCTAssertTrue(s.contains("5 more"))
    }

    // MARK: - User MCP catalog

    func test_userMCPCatalog_skipsBuiltInZion() {
        // The function reads ~/.zion/mcp.json directly. We can't mock the path,
        // but we can assert that whatever the catalog returns, it never names
        // the built-in `zion` seed — that one ships with the app and is not a
        // user installation.
        let s = ChatService.userMCPCatalogAppendixForTesting()
        XCTAssertFalse(s.contains("`zion`"), "Built-in zion seed must be hidden from the user MCP catalog")
    }
}
