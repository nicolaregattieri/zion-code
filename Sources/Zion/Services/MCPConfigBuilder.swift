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
    ///   - allowEdits: Adds mutating MCP tools only after the user has enabled CLI edits.
    /// - Returns: URL of the written config file.
    /// - Throws: If JSON serialisation or the file write fails.
    static func build(cwd: URL, binaryPath: String? = nil, allowEdits: Bool = false) throws -> URL {
        let binary = binaryPath ?? resolveBinaryPath() ?? ""
        var serverArgs = ["--repo", cwd.path]
        if allowEdits {
            serverArgs.append("--allow-edits")
        }
        var mcpServers: [String: Any] = [
            "zion": [
                "command": binary,
                "args": serverArgs
            ]
        ]

        // Bridge user-installed MCP servers from ~/.zion/mcp.json into the
        // CLI subprocess config so Claude Code / Codex see the same MCP
        // catalog the native chat sees. Built-in `zion` keeps precedence.
        if let userServers = readUserMCPServersForCLI() {
            for (id, dict) in userServers where mcpServers[id] == nil {
                mcpServers[id] = dict
            }
        }

        let config: [String: Any] = ["mcpServers": mcpServers]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        let filename = "zion-mcp-\(UUID().uuidString).json"
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let fileURL = tmpDir.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// Reads `~/.zion/mcp.json` synchronously and returns each enabled
    /// server as the dictionary shape Claude Code / Codex expect under
    /// `mcpServers`. Returns nil when the file is missing or unreadable.
    private static func readUserMCPServersForCLI() -> [String: [String: Any]]? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zion/mcp.json")
        guard let data = try? Data(contentsOf: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: [String: Any]]
        else { return nil }
        var out: [String: [String: Any]] = [:]
        for (id, raw) in servers {
            if let disabled = raw["disabled"] as? Bool, disabled { continue }
            var entry: [String: Any] = [:]
            if let cmd = raw["command"] as? String { entry["command"] = cmd }
            if let args = raw["args"] as? [String] { entry["args"] = args }
            if let env = raw["env"] as? [String: String], !env.isEmpty { entry["env"] = env }
            if entry["command"] != nil { out[id] = entry }
        }
        return out.isEmpty ? nil : out
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

    /// UserDefaults key for the chat-composer toggle that controls whether
    /// native provider loops (Anthropic / OpenAI / Gemini tool use) may call
    /// the `bash` tool. Default OFF — the user opts in per session from the
    /// composer pill (more visible than burying the toggle in Settings).
    /// Independent of the CLI passthrough bash, which is always on inside
    /// the claude/codex CLI's own approval flow.
    static let bashToolToggleKey = "chat.allowBashTool"

    static var bashToolEnabled: Bool {
        UserDefaults.standard.bool(forKey: bashToolToggleKey)
    }

    /// Tool descriptors backed by Zion's in-process handlers for native provider loops.
    /// Mutation tools are wired in ZionHarness.dispatch; we conditionally
    /// surface bash here so the LLM only learns about it when the user has
    /// explicitly turned the composer pill on.
    static func allTools() -> [MCPToolDescriptor] {
        var tools: [MCPToolDescriptor] = [
            repoMapDescriptor(),
            findSymbolDescriptor(),
            symbolsDescriptor(),
            semanticSearchDescriptor(),
            retrieveMoreDescriptor(),
            installMCPServerDescriptor(),
            createSkillDescriptor(),
            useSkillDescriptor()
        ]
        if bashToolEnabled {
            tools.append(bashToolDescriptorTyped())
        }
        return tools
    }

    /// Lets the model activate an installed skill by id. Returns the
    /// skill body as tool_result so the conversation can apply it
    /// without a slash from the user.
    static func useSkillDescriptor() -> MCPToolDescriptor {
        MCPToolDescriptor(
            name: "use_skill",
            description: "Activate an installed skill by id. Returns the skill body (markdown). Use when the user's request maps to a skill listed in the system prompt's 'Available skills' section.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Skill slug (the `/<id>` part)."] as [String: Any]
                ] as [String: Any],
                "required": ["id"]
            ]
        )
    }

    /// Typed descriptor for the `bash` tool. Mirrors the JSON in
    /// `bashToolDescriptor()` but in the structured form `allTools()` expects.
    static func bashToolDescriptorTyped() -> MCPToolDescriptor {
        MCPToolDescriptor(
            name: "bash",
            description: "Execute a shell command in the workspace. Respects approval tier and the per-session composer toggle.",
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

    /// Built-in tools PLUS tools advertised by user-configured MCP
    /// servers. Phase 6.4 wires the user-server side via
    /// `MCPClientPool.shared`: pool warms on first call (spawns each
    /// registered server, queries `tools/list`) and the routing table
    /// then powers `dispatch(name:args:)`. Built-in tools take
    /// precedence so a poorly-named user tool can't shadow `bash` /
    /// `read` / `repo_map` / etc.
    static func allToolsIncludingUserServers(store: MCPRegistryStore?) async -> [MCPToolDescriptor] {
        let builtIn = allTools()
        guard let store else { return builtIn }
        await MCPClientPool.shared.warm(from: store)
        let userTools = await MCPClientPool.shared.allUserTools()
        let builtInNames = Set(builtIn.map { $0.name })
        let merged = builtIn + userTools.filter { !builtInNames.contains($0.name) }
        return merged
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
        case "symbols":
            return try await dispatchSymbols(args: args)
        case "semantic_search":
            return try await dispatchSemanticSearch(args: args)
        case "retrieve_more":
            return try await dispatchRetrieveMore(args: args)
        case "install_mcp_server":
            return try await dispatchInstallMCPServer(args: args)
        case "create_skill":
            return try await dispatchCreateSkill(args: args)
        case "use_skill":
            return try await dispatchUseSkill(args: args)
        default:
            // Phase 6.4 — fall through to MCPClientPool so calls to
            // user-installed MCP tools (filesystem, brave-search, etc.)
            // dispatch to the right subprocess over JSON-RPC stdio
            // instead of hitting `unknownTool`. Re-encode args through
            // JSON to land them on the actor with a Sendable shape.
            let data = try JSONSerialization.data(withJSONObject: args)
            let safe = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            return try await MCPClientPool.shared.dispatch(toolName: name, args: safe)
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
