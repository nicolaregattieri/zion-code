import XCTest
@testable import Zion

@MainActor
final class MCPRegistryStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempPath() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MCPRegistryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mcp.json")
    }

    override func setUp() async throws {
        // Disable real process launch for ALL tests
        MCPServerProcess.processLauncherOverride = { _ in }
    }

    override func tearDown() async throws {
        MCPServerProcess.processLauncherOverride = nil
    }

    // MARK: - Test 1: missing file auto-creates with seed

    func test_missing_file_auto_creates_with_seed() async throws {
        let path = makeTempPath()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))

        let store = MCPRegistryStore(configPath: path)
        try await store.load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), "mcp.json should be created")
        XCTAssertTrue(store.servers.contains { $0.id == "zion" }, "seed server 'zion' should be present")
    }

    // MARK: - Test 2: reads existing mcpServers map

    func test_reads_existing_mcpServers_map() async throws {
        let path = makeTempPath()
        let json = """
        {
          "mcpServers": {
            "filesystem": {
              "command": "npx",
              "args": ["@modelcontextprotocol/server-filesystem", "/tmp"]
            },
            "git": {
              "command": "uvx",
              "args": ["mcp-server-git"]
            }
          }
        }
        """
        try json.data(using: .utf8)!.write(to: path)

        let store = MCPRegistryStore(configPath: path)
        try await store.load()

        XCTAssertEqual(store.servers.count, 2)
        let ids = Set(store.servers.map { $0.id })
        XCTAssertTrue(ids.contains("filesystem"))
        XCTAssertTrue(ids.contains("git"))
        let fs = store.servers.first { $0.id == "filesystem" }!
        XCTAssertEqual(fs.command, "npx")
    }

    // MARK: - Test 3: save roundtrip

    func test_save_roundtrip() async throws {
        let path = makeTempPath()
        // Start with an empty-ish file
        let json = """
        { "mcpServers": {} }
        """
        try json.data(using: .utf8)!.write(to: path)

        let store = MCPRegistryStore(configPath: path)
        try await store.load()

        let newServer = MCPServerConfig(
            id: "my-tool",
            command: "node",
            args: ["server.js"]
        )
        try await store.addServer(newServer)

        // Reread from disk
        let data = try Data(contentsOf: path)
        let reloaded = try MCPRegistryStore.decode(data: data)
        XCTAssertTrue(reloaded.contains { $0.id == "my-tool" }, "new server should persist to disk")
        let found = reloaded.first { $0.id == "my-tool" }!
        XCTAssertEqual(found.command, "node")
        XCTAssertEqual(found.args, ["server.js"])
    }

    // MARK: - Test 4: remove server persists deletion

    func test_remove_server_persists_deletion() async throws {
        let path = makeTempPath()
        let json = """
        {
          "mcpServers": {
            "alpha": { "command": "alpha", "args": [] },
            "beta":  { "command": "beta",  "args": [] }
          }
        }
        """
        try json.data(using: .utf8)!.write(to: path)

        let store = MCPRegistryStore(configPath: path)
        try await store.load()
        XCTAssertEqual(store.servers.count, 2)

        try await store.removeServer(id: "alpha")

        // Verify in-memory
        XCTAssertEqual(store.servers.count, 1)
        XCTAssertFalse(store.servers.contains { $0.id == "alpha" })

        // Verify on disk
        let data = try Data(contentsOf: path)
        let reloaded = try MCPRegistryStore.decode(data: data)
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded[0].id, "beta")
    }

    // MARK: - Test 5: status returns disabled for unknown id

    func test_status_returns_disabled_for_unknown_id() async throws {
        let path = makeTempPath()
        let store = MCPRegistryStore(configPath: path)
        // No load — store is empty
        let result = await store.status(forID: "ghost")
        XCTAssertEqual(result, .disabled)
    }

    // MARK: - Test 6: builtIn seed includes zion

    func test_builtin_seed_includes_zion() {
        let seed = MCPRegistryStore.builtInSeed
        XCTAssertEqual(seed.id, "zion")
        XCTAssertTrue(seed.autoApprove.contains("repo_map"), "autoApprove should include 'repo_map'")
        XCTAssertTrue(seed.autoApprove.contains("find_symbol"), "autoApprove should include 'find_symbol'")
        XCTAssertEqual(seed.transport, "stdio")
        XCTAssertFalse(seed.disabled)
    }

    // MARK: - Test 7: addServer does not launch when disabled

    func test_addServer_does_not_launch_when_disabled() async throws {
        let path = makeTempPath()
        let json = """
        { "mcpServers": {} }
        """
        try json.data(using: .utf8)!.write(to: path)

        var launchCallCount = 0
        MCPServerProcess.processLauncherOverride = { _ in
            launchCallCount += 1
        }

        let store = MCPRegistryStore(configPath: path)
        try await store.load()

        let disabledServer = MCPServerConfig(
            id: "disabled-tool",
            command: "echo",
            args: ["hello"],
            env: [:],
            transport: "stdio",
            disabled: true,
            autoApprove: []
        )
        try await store.addServer(disabledServer)

        XCTAssertEqual(launchCallCount, 0, "disabled server should not trigger launch")
        XCTAssertTrue(store.servers.contains { $0.id == "disabled-tool" })
    }
}
