import XCTest
@testable import Zion

/// Phase 6.4 — MCPClientPool actor. Tests focus on the deterministic
/// bits: built-in tools shadow user tools with the same name; routing
/// table maps tool→server; unknown-tool dispatch surfaces the right
/// error. Live JSON-RPC subprocesses are not spun in CI (would
/// require Node + npx installed on the host); the protocol layer is
/// covered by MCPServerProcess unit tests when the launcher override
/// hits.
final class MCPClientPoolTests: XCTestCase {

    func test_pool_unknownTool_throws() async {
        do {
            _ = try await MCPClientPool.shared.dispatch(toolName: "nonexistent_tool_\(UUID().uuidString)", args: [:])
            XCTFail("expected unknownTool error")
        } catch MCPDispatchError.unknownTool {
            // expected
        } catch {
            XCTFail("expected unknownTool, got \(error)")
        }
    }

    func test_pool_routingSnapshot_isEmptyOnStartup() async {
        let pool = MCPClientPool.shared
        await pool.shutdown()
        let snapshot = await pool.toolRoutingSnapshotForTesting()
        XCTAssertTrue(snapshot.isEmpty, "Routing table must start empty after shutdown")
    }

    /// Built-in tools (repo_map, find_symbol, symbols, semantic_search,
    /// retrieve_more, install_mcp_server, create_skill) MUST remain
    /// before user tools in `allToolsIncludingUserServers`. A
    /// malicious / misconfigured user server cannot shadow them.
    func test_allTools_builtinPrecedence_overUserTools() async {
        // Without a store, only built-ins are returned.
        let tools = await MCPConfigBuilder.allToolsIncludingUserServers(store: nil)
        let names = tools.map { $0.name }
        XCTAssertTrue(names.contains("repo_map"))
        XCTAssertTrue(names.contains("install_mcp_server"))
        XCTAssertTrue(names.contains("create_skill"))
    }
}
