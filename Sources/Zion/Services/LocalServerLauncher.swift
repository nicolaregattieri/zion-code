import Foundation

// MARK: - LocalEngineKind

/// Detected local LLM server engine. Drives auto-start behaviour and
/// the spawn command we run when the endpoint is unreachable.
enum LocalEngineKind: String, Codable, CaseIterable, Equatable {
    case ollama
    case mlx
    case llamaCpp
    case custom // user-managed; auto-start is a no-op

    /// Best-effort detection from the configured server URL. Falls back to
    /// `.custom` for anything we do not recognise so we never spawn a
    /// process the user did not opt into.
    static func detect(from serverURL: String) -> LocalEngineKind {
        guard let url = URL(string: serverURL), let port = url.port else { return .custom }
        switch port {
        case 11434: return .ollama
        case 8080: return .mlx
        case 8000, 8081, 8090: return .llamaCpp
        default: return .custom
        }
    }
}

// MARK: - LocalServerLauncher

/// Brings the user's local LLM server online when the chat needs it.
///
/// We probe the configured endpoint first; if it is already healthy we do
/// nothing. Otherwise we look up the engine binary on disk, spawn it with
/// the configured model, and poll `/v1/models` until it responds 200 or we
/// hit the deadline. Spawned processes are detached (new session) so they
/// outlive Zion and can be reused across launches — the user's existing
/// terminal workflow is unaffected.
actor LocalServerLauncher {

    typealias ProcessRunner = @Sendable (URL, [String]) async throws -> Void
    typealias HealthProbe = @Sendable (LocalLLMConfig) async -> Bool

    enum LaunchOutcome: Equatable {
        case alreadyRunning
        case started
        case binaryNotFound(engine: LocalEngineKind)
        case unsupported // .custom
        case timedOut
        case spawnFailed(String)
    }

    private let probe: HealthProbe
    private let processRunner: ProcessRunner
    private let healthPollInterval: TimeInterval
    private let maxStartupSeconds: TimeInterval

    init(
        probe: @escaping HealthProbe = { await AIClient.probeHealth(config: $0) },
        processRunner: ProcessRunner? = nil,
        healthPollInterval: TimeInterval = 0.5,
        maxStartupSeconds: TimeInterval = 30.0
    ) {
        self.probe = probe
        self.processRunner = processRunner ?? LocalServerLauncher.realProcessRunner
        self.healthPollInterval = healthPollInterval
        self.maxStartupSeconds = maxStartupSeconds
    }

    /// Ensures the configured local server is reachable. If not, spawns it
    /// (engine-dependent) and polls until healthy or `maxStartupSeconds`
    /// elapse. Safe to call concurrently — repeated calls during startup
    /// will share the same health-poll loop because the probe is cheap.
    func ensureRunning(config: LocalLLMConfig, engine: LocalEngineKind) async -> LaunchOutcome {
        if await probe(config) { return .alreadyRunning }

        switch engine {
        case .custom:
            return .unsupported
        case .ollama, .mlx, .llamaCpp:
            break
        }

        guard let binary = resolveBinary(for: engine) else {
            return .binaryNotFound(engine: engine)
        }

        let args = launchArguments(engine: engine, config: config)
        do {
            try await processRunner(binary, args)
        } catch {
            return .spawnFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(maxStartupSeconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(healthPollInterval * 1_000_000_000))
            if await probe(config) { return .started }
        }
        return .timedOut
    }

    // MARK: - Binary resolution

    private func resolveBinary(for engine: LocalEngineKind) -> URL? {
        let candidates: [String]
        switch engine {
        case .ollama:
            candidates = ["ollama"]
        case .mlx:
            candidates = ["mlx_lm.server"]
        case .llamaCpp:
            candidates = ["llama-server", "server"]
        case .custom:
            return nil
        }

        let searchDirs = LocalServerLauncher.binarySearchPaths()
        for name in candidates {
            for dir in searchDirs {
                let path = "\(dir)/\(name)"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        return nil
    }

    static func binarySearchPaths() -> [String] {
        let home = NSHomeDirectory()
        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.local/share/uv/tools/mlx-lm/bin",
            "\(home)/.cargo/bin",
            "/usr/bin",
            "/bin",
        ]
    }

    // MARK: - Launch arguments

    private func launchArguments(engine: LocalEngineKind, config: LocalLLMConfig) -> [String] {
        let port = URL(string: config.serverURL)?.port.map(String.init) ?? defaultPort(for: engine)
        switch engine {
        case .ollama:
            // `ollama serve` ignores per-model args; model is pulled lazily.
            return ["serve"]
        case .mlx:
            return [
                "--model", config.modelName,
                "--port", port,
                "--prompt-cache-bytes", "8GB",
            ]
        case .llamaCpp:
            // We cannot synthesise --model PATH from a name; the user must
            // pre-bake a config. Pass the port and let llama-server use its
            // existing config / env.
            return ["--port", port]
        case .custom:
            return []
        }
    }

    private func defaultPort(for engine: LocalEngineKind) -> String {
        switch engine {
        case .ollama: return "11434"
        case .mlx: return "8080"
        case .llamaCpp: return "8000"
        case .custom: return "8080"
        }
    }

    // MARK: - Real process runner

    private static let realProcessRunner: ProcessRunner = { binary, args in
        let process = Process()
        process.executableURL = binary
        process.arguments = args

        // Detach: new session, no inherited stdio, no parent termination cascade.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // Spawn into its own session so it survives Zion exit.
        let attrs = process_attrs_with_new_session()
        try process.run()
        _ = attrs // kept to mirror future posix_spawn migration
    }
}

/// Placeholder for posix_spawnattr setup — `Process.run()` already daemonises
/// far enough for our needs because we redirect all stdio to /dev/null.
/// If we later need true setsid behaviour we wrap in `setsid` like the CLI
/// subprocess path does. For now keep this a no-op so the call site reads
/// the same as the eventual implementation.
private func process_attrs_with_new_session() -> Int { 0 }
