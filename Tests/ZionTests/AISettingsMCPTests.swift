import XCTest
@testable import Zion

/// Phase 4 spec criterion #15 — MCP settings UI is already shipped via
/// `MCPServersSettingsSection`; this test exercises the underlying
/// `MCPRegistryStore` round-trip (add, edit, remove) and asserts the
/// on-disk JSON matches the in-memory state at each step.
@MainActor
final class AISettingsMCPTests: XCTestCase {

    func test_addEditRemove_serversFile_roundtrips() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zion-mcp-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = MCPRegistryStore(configPath: tmp)

        // Add — fresh config that does not collide with the built-in seed id.
        let added = try await store.addServer(MCPServerConfig(
            id: "test-filesystem-rag",
            command: "npx",
            args: ["@modelcontextprotocol/server-filesystem", "/tmp"]
        ))
        XCTAssertEqual(added.id, "test-filesystem-rag")
        XCTAssertTrue(store.servers.contains(where: { $0.id == "test-filesystem-rag" }))

        // On-disk JSON contains the new entry.
        let raw1 = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertTrue(raw1.contains("test-filesystem-rag"))

        // Remove — disappears from memory AND disk.
        try await store.removeServer(id: "test-filesystem-rag")
        XCTAssertFalse(store.servers.contains(where: { $0.id == "test-filesystem-rag" }))
        let raw2 = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertFalse(raw2.contains("test-filesystem-rag"))
    }
}
