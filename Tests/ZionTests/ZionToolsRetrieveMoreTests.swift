import XCTest
@testable import Zion

/// Phase 6 — `retrieve_more` MCP tool wiring.
final class ZionToolsRetrieveMoreTests: XCTestCase {

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
        XCTAssertTrue(names.contains("retrieve_more"))
    }

    func test_schema_requiresQuery() {
        let descriptor = MCPConfigBuilder.retrieveMoreDescriptor()
        XCTAssertEqual(descriptor.name, "retrieve_more")
        let required = descriptor.inputSchema["required"] as? [String]
        XCTAssertEqual(required, ["query"])
    }

    func test_missingQuery_returnsError() async throws {
        let result = try await MCPConfigBuilder.dispatchRetrieveMore(args: [:])
        XCTAssertTrue(result.contains("missing query"))
    }

    func test_noLocator_returnsNotReady() async throws {
        let result = try await MCPConfigBuilder.dispatchRetrieveMore(args: ["query": "foo"])
        XCTAssertEqual(result, L10n("rag.tool.notReady"))
    }
}
