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

    /// Most recent launch outcomes from `warm`. Callers (ChatService)
    /// consume this to surface a transient notice when a registered
    /// server failed to spawn. Cleared at the start of every `warm`.
    private(set) var lastWarmErrors: [(serverID: String, message: String)] = []

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
        await warmServers(servers, forceReload: false)
    }

    /// Reads `~/.zion/mcp.json` directly (no MainActor coupling) and
    /// warms each enabled server. This is the hot-path entry used by
    /// the native tool loops — the ad-hoc `MCPRegistryStore()` they
    /// previously instantiated never called `load()`, so `servers`
    /// stayed empty and user MCPs were silently absent.
    func warmFromDisk(forceReload: Bool = false) async {
        if forceReload {
            for (_, proc) in processes { await proc.terminate() }
            processes.removeAll()
            toolToServer.removeAll()
        }
        let servers = Self.readServersFromDisk()
        await warmServers(servers, forceReload: false)
    }

    private func warmServers(_ servers: [MCPServerConfig], forceReload: Bool) async {
        lastWarmErrors.removeAll()
        for config in servers where !config.disabled {
            if processes[config.id] != nil { continue }
            let proc = MCPServerProcess(config: config)
            do {
                // Hard cap launch + tools/list at 10 s. Without this a
                // server that never responds to `initialize` (cold npx
                // install, broken stdio handshake) blocks the whole
                // turn — and, worse, hangs `swift test` in CI when a
                // test environment runs warm.
                try await Self.withTimeout(seconds: 10) {
                    try await proc.launch()
                    _ = try await proc.loadAdvertisedTools()
                }
                let tools = await proc.advertisedTools
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
                await proc.terminate()
                lastWarmErrors.append((serverID: config.id, message: error.localizedDescription))
                continue
            }
        }
    }

    /// Race a body against a deadline. Throws `MCPDispatchError.timeout`
    /// when the body does not finish in time so the caller can recycle
    /// the subprocess.
    private static func withTimeout(seconds: Double, _ body: @escaping @Sendable () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw MCPDispatchError.timeout
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private static func readServersFromDisk() -> [MCPServerConfig] {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zion/mcp.json")
        guard let data = try? Data(contentsOf: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["mcpServers"] as? [String: [String: Any]]
        else { return [] }
        var out: [MCPServerConfig] = []
        for (id, dict) in raw {
            let command = (dict["command"] as? String) ?? ""
            let args = (dict["args"] as? [String]) ?? []
            let env = (dict["env"] as? [String: String]) ?? [:]
            let transport = (dict["transport"] as? String) ?? "stdio"
            let disabled = (dict["disabled"] as? Bool) ?? false
            let autoApprove = (dict["autoApprove"] as? [String]) ?? []
            out.append(MCPServerConfig(
                id: id,
                command: command,
                args: args,
                env: env,
                transport: transport,
                disabled: disabled,
                autoApprove: autoApprove
            ))
        }
        return out
    }

    /// Snapshot consumed by ChatService after a warm to surface launch
    /// failures via `showTransientNotice`. Read-and-clear semantics.
    func consumeWarmErrors() -> [(serverID: String, message: String)] {
        let errs = lastWarmErrors
        lastWarmErrors.removeAll()
        return errs
    }

    /// Per-server routing instructions captured during `initialize`.
    /// Surfaced in the chat system prompt so the model knows when to
    /// call each MCP's tools without the user memorising names.
    func allServerInstructions() async -> [(serverID: String, instructions: String)] {
        var out: [(String, String)] = []
        for (id, proc) in processes {
            let instr = await proc.serverInstructions
            guard !instr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            out.append((id, instr))
        }
        return out.sorted { $0.0 < $1.0 }
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
