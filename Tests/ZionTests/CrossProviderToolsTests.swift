// CrossProviderToolsTests.swift — asserts repo_map + find_symbol are part of the
// shared MCP tool registry seen by every provider family.

import XCTest
@testable import Zion

final class CrossProviderToolsTests: XCTestCase {

    func test_allTools_includes_repo_map() {
        let tools = MCPConfigBuilder.allTools()
        XCTAssertTrue(tools.contains { $0.name == "repo_map" }, "repo_map must be registered for every provider family")
    }

    func test_allTools_includes_find_symbol() {
        let tools = MCPConfigBuilder.allTools()
        XCTAssertTrue(tools.contains { $0.name == "find_symbol" }, "find_symbol must be registered for every provider family")
    }

    func test_allTools_doesNotAdvertiseUnwiredBash() {
        let tools = MCPConfigBuilder.allTools()
        XCTAssertFalse(tools.contains { $0.name == "bash" }, "bash must stay hidden until it has a live dispatcher")
    }

    func test_repo_map_schema_object_with_properties() {
        guard let tool = MCPConfigBuilder.allTools().first(where: { $0.name == "repo_map" }) else {
            XCTFail("repo_map missing")
            return
        }
        XCTAssertEqual(tool.inputSchema["type"] as? String, "object")
        let props = tool.inputSchema["properties"] as? [String: Any]
        XCTAssertNotNil(props?["focusFiles"], "schema must declare focusFiles property")
        XCTAssertNotNil(props?["tokenBudget"], "schema must declare tokenBudget property")
    }

    func test_find_symbol_schema_requires_name() {
        guard let tool = MCPConfigBuilder.allTools().first(where: { $0.name == "find_symbol" }) else {
            XCTFail("find_symbol missing")
            return
        }
        XCTAssertEqual(tool.inputSchema["type"] as? String, "object")
        let required = tool.inputSchema["required"] as? [String]
        XCTAssertEqual(required, ["name"])
    }

    func test_tool_translation_to_provider_families() {
        // The schema translator turns the same MCPToolDescriptor into per-provider shapes.
        // Verify both new tools survive the translation for each native-tool-use family.
        let tools = MCPConfigBuilder.allTools()
        for family in [ProviderFamily.anthropic, .openai, .gemini] {
            let translated = ToolSchemaTranslator.translate(tools, for: family)
            XCTAssertFalse(translated.isEmpty, "translator produced no output for \(family.rawValue)")
            let containsRepoMap = String(describing: translated).contains("repo_map")
            let containsFindSymbol = String(describing: translated).contains("find_symbol")
            XCTAssertTrue(containsRepoMap, "repo_map missing in \(family.rawValue) schema")
            XCTAssertTrue(containsFindSymbol, "find_symbol missing in \(family.rawValue) schema")
        }
    }
}
