import XCTest
@testable import Zion

/// Phase 4 spec criterion #14 — `symbols(query:)` tool is registered with
/// `MCPConfigBuilder.allTools()` (the canonical registry) and behaves as a
/// keyword lookup over the cached snapshot.
final class ZionToolsSymbolsTests: XCTestCase {

    func test_symbolsTool_registeredInMCPConfigBuilder() {
        let tools = MCPConfigBuilder.allTools()
        let names = tools.map { $0.name }
        XCTAssertTrue(names.contains("symbols"),
                      "symbols tool must be registered in MCPConfigBuilder.allTools(); got \(names)")
    }

    func test_symbolsTool_schemaHasQueryString() {
        let descriptor = MCPConfigBuilder.symbolsDescriptor()
        XCTAssertEqual(descriptor.name, "symbols")
        let schema = descriptor.inputSchema
        let properties = schema["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["query"])
        let required = schema["required"] as? [String]
        XCTAssertEqual(required, ["query"])
    }

    /// Missing query argument surfaces a structured error string instead of
    /// throwing. Matches the convention of other tools in this file.
    func test_symbolsTool_missingQuery_returnsError() async throws {
        let result = try await MCPConfigBuilder.dispatchSymbols(args: [:])
        XCTAssertTrue(result.contains("missing query"))
    }

    /// SymbolIndexer is nil when no repo is open. The handler MUST degrade
    /// gracefully with a clear error rather than crashing.
    func test_symbolsTool_noIndexer_returnsError() async throws {
        let priorIndexer = SymbolIndexer.shared
        SymbolIndexer.shared = nil
        defer { SymbolIndexer.shared = priorIndexer }

        let result = try await MCPConfigBuilder.dispatchSymbols(args: ["query": "foo"])
        XCTAssertTrue(result.contains("SymbolIndexer not initialized"))
    }
}
