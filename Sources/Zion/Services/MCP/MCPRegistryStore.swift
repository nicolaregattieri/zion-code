import Foundation

/// Codable shape of ~/.zion/mcp.json
private struct MCPRegistryFile: Codable {
    var mcpServers: [String: MCPServerConfigPayload]

    struct MCPServerConfigPayload: Codable {
        var command: String
        var args: [String]
        var env: [String: String]?
        var transport: String?
        var disabled: Bool?
        var autoApprove: [String]?
    }
}

// MARK: -

@MainActor
@Observable
final class MCPRegistryStore {
    static let defaultPath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".zion/mcp.json")

    let configPath: URL
    private(set) var servers: [MCPServerConfig] = []
    private var processes: [String: MCPServerProcess] = [:]

    // FSEvent watcher token — retained to keep watcher alive
    private var watcherTask: Task<Void, Never>?

    init(configPath: URL = MCPRegistryStore.defaultPath) {
        self.configPath = configPath
    }

    // MARK: - Seed

    /// Built-in Zion seed config (the zion-mcp binary co-located with the app).
    static let builtInSeed: MCPServerConfig = MCPServerConfig(
        id: "zion",
        command: "zion-mcp",
        args: [],
        env: [:],
        transport: "stdio",
        disabled: false,
        autoApprove: ["repo_map", "find_symbol"]
    )

    // MARK: - Load

    /// Loads servers from disk. Creates the file with built-in Zion seed if missing.
    func load() async throws {
        let fm = FileManager.default
        let dir = configPath.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: configPath.path) {
            // Auto-create with seed
            servers = [MCPRegistryStore.builtInSeed]
            try persistToDisk()
            return
        }

        let data = try Data(contentsOf: configPath)
        servers = try Self.decode(data: data)
        await reconcileProcesses()
    }

    // MARK: - Save

    /// Persists current `servers` to disk and reconciles process lifecycles.
    func save() async throws {
        try persistToDisk()
        await reconcileProcesses()
    }

    // MARK: - Mutations

    /// Adds a server, persists, launches its process. Returns the new config.
    @discardableResult
    func addServer(_ config: MCPServerConfig) async throws -> MCPServerConfig {
        // Replace if same id exists, otherwise append
        if let idx = servers.firstIndex(where: { $0.id == config.id }) {
            servers[idx] = config
        } else {
            servers.append(config)
        }
        try await save()
        return config
    }

    /// Removes a server, persists, terminates its process.
    func removeServer(id: String) async throws {
        servers.removeAll { $0.id == id }
        if let proc = processes.removeValue(forKey: id) {
            await proc.terminate()
        }
        try persistToDisk()
    }

    // MARK: - Status

    /// Status snapshot for the UI layer.
    func status(forID id: String) async -> MCPServerStatus {
        guard let proc = processes[id] else { return .disabled }
        return await proc.status
    }

    // MARK: - Hot reload

    /// Starts an FSEventStream watcher on the config file. Auto-reloads on change.
    func startWatching() {
        watcherTask?.cancel()
        watcherTask = Task { [weak self] in
            guard let self else { return }
            let path = self.configPath.path
            // Poll via DispatchSource (FSEvents requires AppKit run loop in some configs)
            var lastModified: Date? = nil
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s poll
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      let modified = attrs[.modificationDate] as? Date else { continue }
                if let prev = lastModified, modified > prev {
                    try? await self.load()
                }
                lastModified = modified
            }
        }
    }

    func stopWatching() {
        watcherTask?.cancel()
        watcherTask = nil
    }

    // MARK: - Private helpers

    private func persistToDisk() throws {
        let data = try Self.encode(servers: servers)
        try data.write(to: configPath, options: .atomic)
    }

    private func reconcileProcesses() async {
        // Launch processes for enabled servers that don't have one yet
        for server in servers where !server.disabled {
            if processes[server.id] == nil {
                let proc = MCPServerProcess(config: server)
                processes[server.id] = proc
                try? await proc.launch()
            }
        }
        // Terminate processes for servers that were removed or disabled
        let activeIDs = Set(servers.filter { !$0.disabled }.map { $0.id })
        for (id, proc) in processes where !activeIDs.contains(id) {
            await proc.terminate()
            processes.removeValue(forKey: id)
        }
    }

    // MARK: - Codable helpers

    static func decode(data: Data) throws -> [MCPServerConfig] {
        let file = try JSONDecoder().decode(MCPRegistryFile.self, from: data)
        return file.mcpServers.map { (key, payload) in
            MCPServerConfig(
                id: key,
                command: payload.command,
                args: payload.args,
                env: payload.env ?? [:],
                transport: payload.transport ?? "stdio",
                disabled: payload.disabled ?? false,
                autoApprove: payload.autoApprove ?? []
            )
        }.sorted { $0.id < $1.id }
    }

    static func encode(servers: [MCPServerConfig]) throws -> Data {
        var payloads: [String: MCPRegistryFile.MCPServerConfigPayload] = [:]
        for server in servers {
            payloads[server.id] = MCPRegistryFile.MCPServerConfigPayload(
                command: server.command,
                args: server.args,
                env: server.env.isEmpty ? nil : server.env,
                transport: server.transport,
                disabled: server.disabled ? true : nil,
                autoApprove: server.autoApprove.isEmpty ? nil : server.autoApprove
            )
        }
        let file = MCPRegistryFile(mcpServers: payloads)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }
}
