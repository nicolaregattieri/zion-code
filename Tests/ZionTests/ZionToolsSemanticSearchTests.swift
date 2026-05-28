import XCTest
@testable import Zion

/// Phase 5 spec criterion #10 — `semantic_search` is registered in
/// `MCPConfigBuilder.allTools()` and surfaces a localized "index not
/// ready" message when no `RAGQueryService` is wired.
final class ZionToolsSemanticSearchTests: XCTestCase {

    override func setUp() {
        super.setUp()
        RAGQueryServiceLocator.shared = nil
    }

    override func tearDown() {
        RAGQueryServiceLocator.shared = nil
        super.tearDown()
    }

    func test_tool_registeredInMCPConfigBuilder() {
        let names = MCPConfigBuilder.allTools().map { $0.name }
        XCTAssertTrue(names.contains("semantic_search"), "expected semantic_search in registry, got \(names)")
    }

    func test_schema_requiresQuery() {
        let descriptor = MCPConfigBuilder.semanticSearchDescriptor()
        XCTAssertEqual(descriptor.name, "semantic_search")
        let required = descriptor.inputSchema["required"] as? [String]
        XCTAssertEqual(required, ["query"])
    }

    func test_missingQuery_returnsError() async throws {
        let result = try await MCPConfigBuilder.dispatchSemanticSearch(args: [:])
        XCTAssertTrue(result.contains("missing query"))
    }

    func test_noLocator_returnsNotReady() async throws {
        let result = try await MCPConfigBuilder.dispatchSemanticSearch(args: ["query": "foo"])
        XCTAssertEqual(result, L10n("rag.tool.notReady"))
    }
}
