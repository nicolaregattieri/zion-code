import XCTest
@testable import Zion

/// Phase 6.3 — `install_mcp_server` + `create_skill` MCP tools.
@MainActor
final class InstallMCPAndCreateSkillTests: XCTestCase {

    // MARK: - install_mcp_server

    func test_installMCP_registeredInAllTools() {
        let names = MCPConfigBuilder.allTools().map { $0.name }
        XCTAssertTrue(names.contains("install_mcp_server"))
        XCTAssertTrue(names.contains("create_skill"))
    }

    func test_parseMCPConfigPayload_singleServer_shape() throws {
        let raw = #"""
        {"id":"fs","command":"npx","args":["-y","@modelcontextprotocol/server-filesystem","/tmp"]}
        """#
        let configs = try MCPConfigBuilder.parseMCPConfigPayload(raw)
        XCTAssertEqual(configs.count, 1)
        XCTAssertEqual(configs.first?.id, "fs")
        XCTAssertEqual(configs.first?.command, "npx")
        XCTAssertEqual(configs.first?.args, ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])
    }

    func test_parseMCPConfigPayload_namedSingle_shape() throws {
        let raw = #"""
        {"my-fs":{"command":"npx","args":["-y","@org/server"]}}
        """#
        let configs = try MCPConfigBuilder.parseMCPConfigPayload(raw)
        XCTAssertEqual(configs.count, 1)
        XCTAssertEqual(configs.first?.id, "my-fs")
    }

    func test_parseMCPConfigPayload_fullMap_shape() throws {
        let raw = #"""
        {"mcpServers":{"a":{"command":"npx","args":["a"]},"b":{"command":"node","args":["b.js"]}}}
        """#
        let configs = try MCPConfigBuilder.parseMCPConfigPayload(raw)
        XCTAssertEqual(configs.count, 2)
        XCTAssertEqual(Set(configs.map { $0.id }), Set(["a", "b"]))
    }

    func test_parseMCPConfigPayload_emptyMissingCommand_ignored() throws {
        let raw = #"""
        {"mcpServers":{"bad":{"args":["x"]}}}
        """#
        let configs = try MCPConfigBuilder.parseMCPConfigPayload(raw)
        XCTAssertEqual(configs.count, 0, "Entries without `command` must be skipped")
    }

    func test_installMCP_missingJSON_returnsError() async throws {
        let result = try await MCPConfigBuilder.dispatchInstallMCPServer(args: [:])
        XCTAssertTrue(result.contains("missing json"))
    }

    // MARK: - create_skill

    func test_slugify_normalizesNameToKebab() {
        XCTAssertEqual(MCPConfigBuilder.slugify("Hello World"), "hello-world")
        XCTAssertEqual(MCPConfigBuilder.slugify("Foo / Bar — Baz!"), "foo-bar-baz")
        XCTAssertEqual(MCPConfigBuilder.slugify("trim-dashes--"), "trim-dashes")
    }

    func test_renderSkillMarkdown_includesFrontmatterAndBody() {
        let md = MCPConfigBuilder.renderSkillMarkdown(
            name: "Demo",
            description: "Demo skill.",
            body: "Run X then Y.",
            triggers: ["demo this", "demo that"]
        )
        XCTAssertTrue(md.hasPrefix("---\n"))
        XCTAssertTrue(md.contains("name: Demo"))
        XCTAssertTrue(md.contains("description: Demo skill."))
        XCTAssertTrue(md.contains("triggers:"))
        XCTAssertTrue(md.contains("  - demo this"))
        XCTAssertTrue(md.contains("Run X then Y."))
    }

    func test_renderSkillMarkdown_omitsTriggersWhenEmpty() {
        let md = MCPConfigBuilder.renderSkillMarkdown(
            name: "A", description: "B", body: "C", triggers: []
        )
        XCTAssertFalse(md.contains("triggers:"))
    }

    func test_createSkill_missingName_returnsError() async throws {
        let r = try await MCPConfigBuilder.dispatchCreateSkill(args: [
            "description": "d", "body": "b"
        ])
        XCTAssertTrue(r.contains("missing name"))
    }

    func test_createSkill_writesUserSkillFile() async throws {
        // Use a unique name so we don't collide with real skills.
        let unique = "zion-test-skill-\(UUID().uuidString.prefix(8))"
        let result = try await MCPConfigBuilder.dispatchCreateSkill(args: [
            "name": unique,
            "description": "Throwaway test skill",
            "body": "Step 1\nStep 2",
            "scope": "user"
        ])
        defer {
            let slug = MCPConfigBuilder.slugify(unique)
            let path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".zion/skills/\(slug)", isDirectory: true)
            try? FileManager.default.removeItem(at: path)
        }
        XCTAssertTrue(result.hasPrefix("Created skill `"), "got: \(result)")
        XCTAssertTrue(result.contains(".zion/skills/"),
                      "Skills must land in the provider-agnostic .zion namespace, not .claude")
    }
}
