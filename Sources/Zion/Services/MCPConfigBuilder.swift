import Foundation

// MARK: - MCPToolDescriptor

/// Builds per-spawn MCP config files consumed by the claude CLI (`--mcp-config`)
/// so that every subprocess has the zion-mcp tool server registered automatically.
///
/// Usage:
/// ```swift
/// let configURL = try MCPConfigBuilder.build(cwd: repoURL)
/// // pass configURL.path to --mcp-config, then delete on stream termination:
/// try? FileManager.default.removeItem(at: configURL)
/// ```
enum MCPConfigBuilder {

    // MARK: - Public API

    /// Writes `$TMPDIR/zion-mcp-<uuid>.json` and returns its URL.
    ///
    /// - Parameters:
    ///   - cwd: The repository root the MCP server should observe (`--repo` arg).
    ///   - binaryPath: Override the binary path (used by unit tests). When nil,
    ///     `resolveBinaryPath()` is called to locate the production or dev binary.
    /// - Returns: URL of the written config file.
    /// - Throws: If JSON serialisation or the file write fails.
    static func build(cwd: URL, binaryPath: String? = nil) throws -> URL {
        let binary = binaryPath ?? resolveBinaryPath() ?? ""
        let config: [String: Any] = [
            "mcpServers": [
                "zion": [
                    "command": binary,
                    "args": ["--repo", cwd.path]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        let filename = "zion-mcp-\(UUID().uuidString).json"
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let fileURL = tmpDir.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// Resolves the path to the `zion-mcp` binary using the following priority order:
    ///
    /// 1. `ZION_MCP_BINARY_PATH` environment variable (CI, tests, custom installs).
    /// 2. Next to the main bundle executable — production `.app` bundle places both
    ///    executables in `Contents/MacOS/`.
    /// 3. SPM debug build output — `<bundle>/../../../zion-mcp` (two levels up from
    ///    `.build/debug/<Product>/<Product>.bundle` or the executable path).
    /// 4. Common SPM scratch paths scanned as a last resort.
    ///
    /// Returns nil when none of the candidates exist (binary not yet built).
    static func resolveBinaryPath() -> String? {
        let fm = FileManager.default

        // 1. Explicit env override (highest priority — allows CI/tests to inject a stub)
        if let envPath = ProcessInfo.processInfo.environment["ZION_MCP_BINARY_PATH"],
           !envPath.isEmpty {
            return envPath
        }

        // 2. Production bundle: Contents/MacOS/zion-mcp alongside the Zion executable
        let bundleMacOS = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("zion-mcp")
            .path
        if fm.fileExists(atPath: bundleMacOS) {
            return bundleMacOS
        }

        // 3. SPM dev build: executable lives at .build/{debug|release}/Zion
        //    zion-mcp is a peer product, so it's in the same directory.
        let executablePath = Bundle.main.executableURL?.path ?? ""
        let executableDir = (executablePath as NSString).deletingLastPathComponent
        let devCandidate = (executableDir as NSString).appendingPathComponent("zion-mcp")
        if fm.fileExists(atPath: devCandidate) {
            return devCandidate
        }

        // 4. Scan known SPM scratch paths relative to the current working directory
        let cwd = fm.currentDirectoryPath
        let knownScratch = [
            "\(cwd)/.build/debug/zion-mcp",
            "\(cwd)/.build/release/zion-mcp",
            "/tmp/zion-build-phase4/debug/zion-mcp",
            "/tmp/zion-build-phase4/release/zion-mcp",
        ]
        for path in knownScratch where fm.fileExists(atPath: path) {
            return path
        }

        return nil
    }

    // MARK: - Tool Registry

    /// All tool descriptors registered in the Zion-internal MCP path.
    /// Every provider family (Anthropic, OpenAI, Gemini, local, ReAct, CLI passthrough)
    /// sees these tools via the MCP server's `tools/list` or direct descriptor injection.
    static func allTools() -> [MCPToolDescriptor] {
        return [bashToolDescriptorTyped(), repoMapDescriptor(), findSymbolDescriptor()]
    }

    /// P14: Returns built-in tools PLUS tools advertised by user-configured MCP servers.
    /// Currently, user-server tool discovery is stubbed — returns built-in tools only.
    /// Full integration (querying each server's `tools/list` MCP method) is P15.
    static func allToolsIncludingUserServers(store: MCPRegistryStore?) -> [MCPToolDescriptor] {
        let builtIn = allTools()
        // TODO(P15): query each server in store.servers via JSON-RPC `tools/list` and merge.
        return builtIn
    }

    // MARK: - Dispatch

    /// Dispatch an MCP `tools/call` to the matching handler.
    /// - Parameters:
    ///   - name: Tool name from the JSON-RPC request.
    ///   - args: Decoded argument dictionary (`[String: Any]`).
    /// - Returns: Result string to surface to the AI.
    static func dispatch(name: String, args: [String: Any]) async throws -> String {
        switch name {
        case "repo_map":
            return try await dispatchRepoMap(args: args)
        case "find_symbol":
            return try await dispatchFindSymbol(args: args)
        default:
            throw MCPDispatchError.unknownTool(name)
        }
    }

    // MARK: - repo_map

    static func repoMapDescriptor() -> MCPToolDescriptor {
        MCPToolDescriptor(
            name: "repo_map",
            description: "Returns a Markdown outline of the most relevant files + their top-level symbols, ranked by PageRank. Use to discover where things live before grep'ing.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "focusFiles": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "File paths that should weigh heavily in the ranking"
                    ] as [String: Any],
                    "tokenBudget": [
                        "type": "integer",
                        "default": 4000,
                        "description": "Token budget for the output (default 4000)"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        )
    }

    static func dispatchRepoMap(args: [String: Any]) async throws -> String {
        let focusFiles = args["focusFiles"] as? [String] ?? []
        let tokenBudget = args["tokenBudget"] as? Int ?? 4000
        guard let indexer = SymbolIndexer.shared else {
            return "[error: SymbolIndexer not initialized — open a repo first]"
        }
        return try await indexer.buildRepoMap(focusFiles: focusFiles, tokenBudget: tokenBudget)
    }

    // MARK: - find_symbol

    static func findSymbolDescriptor() -> MCPToolDescriptor {
        MCPToolDescriptor(
            name: "find_symbol",
            description: "Find a symbol by exact or fuzzy name across the repo. Returns matching file paths + line numbers + kinds. Faster + more precise than grep for identifier search.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string"] as [String: Any],
                    "kind": [
                        "type": "string",
                        "description": "Optional filter: function, struct, class, protocol, enum, extension, variable, constant, enumCase"
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["name"]
            ]
        )
    }

    static func dispatchFindSymbol(args: [String: Any]) async throws -> String {
        let name = args["name"] as? String ?? ""
        let kindFilter = args["kind"] as? String
        guard let indexer = SymbolIndexer.shared else {
            return "[error: SymbolIndexer not initialized — open a repo first]"
        }
        let rows = try await indexer.symbolsByName(name, kind: kindFilter)
        if rows.isEmpty {
            return "No symbols found matching '\(name)'."
        }
        let lines = rows.map { "\($0.file):\($0.line) — \($0.kind) \($0.name)" }
        return lines.joined(separator: "\n")
    }

    // MARK: - Bash Tool Descriptor

    /// Returns the `bash` tool as a typed `MCPToolDescriptor` (used by `allTools()`).
    private static func bashToolDescriptorTyped() -> MCPToolDescriptor {
        MCPToolDescriptor(
            name: "bash",
            description: "Execute a shell command in the workspace. Respects approval tier.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "command": ["type": "string"] as [String: Any],
                    "timeoutSec": ["type": "integer", "minimum": 1, "maximum": 300] as [String: Any]
                ] as [String: Any],
                "required": ["command"]
            ]
        )
    }

    /// Returns the JSON schema descriptor for the `bash` MCP tool.
    ///
    /// This descriptor is used by the ZionMCP server to expose the bash tool to the claude CLI.
    /// Actual dispatch is wired in `Sources/ZionMCP/Tools/BashToolMCP.swift`.
    /// The `repoURL` is injected at spawn time from the chat session (T8: AgentRuntime will wire this).
    static func bashToolDescriptor() -> [String: Any] {
        return [
            "name": "bash",
            "description": "Execute a shell command in the workspace. Respects approval tier.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "command": ["type": "string"],
                    "timeoutSec": ["type": "integer", "minimum": 1, "maximum": 300]
                ],
                "required": ["command"]
            ] as [String: Any]
        ]
    }

    /// Removes stale `zion-mcp-*.json` files from `$TMPDIR` that are older than `maxAge`.
    ///
    /// - Parameters:
    ///   - now: Reference time (injectable for testing). Defaults to `Date()`.
    ///   - maxAge: Files whose modification date is older than `now - maxAge` are deleted.
    ///     Defaults to `Constants.Timing.mcpConfigStaleSeconds` (1 hour).
    static func sweepStaleConfigs(
        now: Date = Date(),
        maxAge: TimeInterval = Constants.Timing.mcpConfigStaleSeconds
    ) {
        let fm = FileManager.default
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let contents = try? fm.contentsOfDirectory(
            at: tmpDir,
            includingPropertiesForKeys: keys,
            options: .skipsHiddenFiles
        ) else { return }

        let cutoff = now.addingTimeInterval(-maxAge)
        for url in contents {
            guard url.lastPathComponent.hasPrefix("zion-mcp-"),
                  url.pathExtension == "json" else { continue }
            guard let mtime = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate
            else { continue }
            if mtime < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }
}

// MARK: - MCPDispatchError

enum MCPDispatchError: Error, LocalizedError {
    case unknownTool(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name): return "Unknown MCP tool: \(name)"
        }
    }
}
