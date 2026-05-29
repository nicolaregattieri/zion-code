import Foundation

/// Process-wide pool of running MCP server subprocesses. Resolves
/// user-installed servers from `MCPRegistryStore`, lazily launches
/// each, and exposes a single `dispatch(toolName:args:)` entry point
/// the harness uses to route user-tool calls to the right subprocess
/// over JSON-RPC stdio.
actor MCPClientPool {

    static let shared = MCPClientPool()

    private var processes: [String: MCPServerProcess] = [:] // keyed by config.id
    private var toolToServer: [String: String] = [:]        // toolName -> server id

    private init() {}

    /// Launches every enabled server in `store`, queries `tools/list`,
    /// and caches the tool→server routing table. Subsequent calls
    /// reuse cached state; pass `forceReload: true` to rebuild from
    /// scratch after a registry change.
    func warm(from store: MCPRegistryStore, forceReload: Bool = false) async {
        if forceReload {
            for (_, proc) in processes { await proc.terminate() }
            processes.removeAll()
            toolToServer.removeAll()
        }
        let servers = await MainActor.run { store.servers }
        for config in servers where !config.disabled {
            if processes[config.id] != nil { continue }
            let proc = MCPServerProcess(config: config)
            do {
                try await proc.launch()
                let tools = try await proc.loadAdvertisedTools()
                processes[config.id] = proc
                for tool in tools {
                    // First server claiming a tool name wins; later
                    // servers with the same name are ignored so the
                    // dispatch table stays deterministic.
                    if toolToServer[tool.name] == nil {
                        toolToServer[tool.name] = config.id
                    }
                }
            } catch {
                // Server failed to launch — skip silently; stderr ring
                // buffer captures the reason for the Settings UI.
                continue
            }
        }
    }

    /// All tools advertised across every running user server. Order
    /// matches registration order; duplicates dropped.
    func allUserTools() async -> [MCPToolDescriptor] {
        var seen: Set<String> = []
        var out: [MCPToolDescriptor] = []
        for (_, proc) in processes {
            let tools = await proc.advertisedTools
            for tool in tools where !seen.contains(tool.name) {
                seen.insert(tool.name)
                out.append(tool)
            }
        }
        return out
    }

    /// Dispatches a tool call to the owning server. Returns the text
    /// payload. Throws when the tool is unknown or the server reports
    /// an error.
    func dispatch(toolName: String, args: [String: Any]) async throws -> String {
        guard let serverID = toolToServer[toolName],
              let proc = processes[serverID] else {
            throw MCPDispatchError.unknownTool(toolName)
        }
        // Re-serialize through JSON so the [String: Any] crosses the
        // actor boundary as a provably Sendable-equivalent dictionary.
        let data = try JSONSerialization.data(withJSONObject: args)
        let safe = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return try await proc.callTool(name: toolName, arguments: safe)
    }

    /// Tears down every running subprocess. Called on app shutdown.
    func shutdown() async {
        for (_, proc) in processes { await proc.terminate() }
        processes.removeAll()
        toolToServer.removeAll()
    }

    /// Test hook — exposes the routing table for assertions.
    func toolRoutingSnapshotForTesting() -> [String: String] {
        toolToServer
    }
}
