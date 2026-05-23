import Foundation

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
