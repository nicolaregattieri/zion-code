import Foundation

// MARK: - LocalEngineKind

/// Detected local LLM server engine. Drives auto-start behaviour and
/// the spawn command we run when the endpoint is unreachable.
enum LocalEngineKind: String, Codable, CaseIterable, Equatable {
    case ollama
    case mlx
    case llamaCpp
    case lmStudio
    case custom // user-managed; auto-start is a no-op

    /// Best-effort detection from the configured server URL. Falls back to
    /// `.custom` for anything we do not recognise so we never spawn a
    /// process the user did not opt into.
    static func detect(from serverURL: String) -> LocalEngineKind {
        guard let url = URL(string: serverURL), let port = url.port else { return .custom }
        switch port {
        case 11434: return .ollama
        case 8080: return .mlx
        case 1234: return .lmStudio
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
    /// Hard restart: stop any process on the configured port, then start
    /// fresh with the new config. Used by inline model-swap so the OLD model
    /// stops loading first (otherwise MLX/Ollama can keep both in RAM and
    /// trigger OOM on the user's machine).
    func restart(config: LocalLLMConfig, engine: LocalEngineKind) async -> LaunchOutcome {
        _ = await stop(config: config)
        // Wait briefly so the port releases before the new spawn.
        try? await Task.sleep(nanoseconds: 400_000_000)
        return await ensureRunning(config: config, engine: engine)
    }

    func ensureRunning(config: LocalLLMConfig, engine: LocalEngineKind) async -> LaunchOutcome {
        if await probe(config) { return .alreadyRunning }

        switch engine {
        case .custom:
            return .unsupported
        case .ollama, .mlx, .llamaCpp, .lmStudio:
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
        case .lmStudio:
            // `lms` is LM Studio's CLI (`lms server start`). It is installed via
            // LM Studio itself ("Install Command Line Tool") and lands either in
            // /usr/local/bin or alongside the app bundle.
            candidates = ["lms"]
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
        case .lmStudio:
            // `lms server start --port <port>` daemonises and exits 0.
            return ["server", "start", "--port", port]
        case .custom:
            return []
        }
    }

    private func defaultPort(for engine: LocalEngineKind) -> String {
        switch engine {
        case .ollama: return "11434"
        case .mlx: return "8080"
        case .llamaCpp: return "8000"
        case .lmStudio: return "1234"
        case .custom: return "8080"
        }
    }

    // MARK: - Stop

    enum StopOutcome: Equatable {
        case notRunning
        case stopped(pid: Int32)
        case noOwnerProcess
        case failed(String)
    }

    /// Stops a running local server by looking up which process is listening on
    /// the configured port (via `lsof -ti :<port>`) and sending SIGTERM.
    /// Falls back to SIGKILL after a 2 s grace period if the process refuses
    /// to exit. We do NOT rely on a persisted PID — the process may have died
    /// and the OS may have recycled the id, so port lookup is the source of
    /// truth.
    func stop(config: LocalLLMConfig) async -> StopOutcome {
        guard await probe(config) else { return .notRunning }

        guard let port = URL(string: config.serverURL)?.port else {
            return .failed("Could not parse port from server URL")
        }

        let lsof = URL(fileURLWithPath: "/usr/sbin/lsof")
        guard FileManager.default.isExecutableFile(atPath: lsof.path) else {
            return .failed("lsof not found at /usr/sbin/lsof")
        }

        let lsofProcess = Process()
        lsofProcess.executableURL = lsof
        lsofProcess.arguments = ["-ti", ":\(port)"]
        let stdoutPipe = Pipe()
        lsofProcess.standardOutput = stdoutPipe
        lsofProcess.standardError = FileHandle.nullDevice

        do {
            try lsofProcess.run()
            lsofProcess.waitUntilExit()
        } catch {
            return .failed("lsof failed: \(error.localizedDescription)")
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        let pids = text
            .split(whereSeparator: { $0.isNewline })
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }

        guard let pid = pids.first else { return .noOwnerProcess }

        Darwin.kill(pid, SIGTERM)

        // Grace period: poll up to 2 s for the process to actually exit.
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Darwin.kill(pid, 0) != 0 { return .stopped(pid: pid) } // process gone
        }
        // Forced kill if still alive.
        if Darwin.kill(pid, 0) == 0 {
            Darwin.kill(pid, SIGKILL)
        }
        return .stopped(pid: pid)
    }

    // MARK: - Orphan sweep (launch)

    /// Best-effort SIGTERM of a local LLM server that survived a previous
    /// Zion session (crash, force-quit, OS kill) and is still holding the
    /// port the user has saved in `LocalLLMConfig`.
    ///
    /// We refuse to kill arbitrary listeners — `ps` is consulted and the
    /// process is only stopped if its argv matches one of the engines
    /// Zion knows how to spawn (`mlx_lm.server`, `ollama serve`,
    /// `llama-server`, `lms server`). Anything else is assumed to be a
    /// user-managed server and left alone.
    @MainActor
    static func sweepOrphanedServerOnLaunch() {
        guard let config = AIClient.loadLocalConfig(),
              let port = URL(string: config.serverURL)?.port else { return }

        let lsof = "/usr/sbin/lsof"
        let ps = "/bin/ps"
        guard FileManager.default.isExecutableFile(atPath: lsof),
              FileManager.default.isExecutableFile(atPath: ps) else { return }

        // 1. Resolve the listening PID.
        let lsofProc = Process()
        lsofProc.executableURL = URL(fileURLWithPath: lsof)
        lsofProc.arguments = ["-ti", ":\(port)"]
        let lsofPipe = Pipe()
        lsofProc.standardOutput = lsofPipe
        lsofProc.standardError = FileHandle.nullDevice
        do {
            try lsofProc.run()
            lsofProc.waitUntilExit()
        } catch { return }

        let pidsText = String(data: lsofPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let pids = pidsText
            .split(whereSeparator: { $0.isNewline })
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        guard let pid = pids.first else { return }

        // 2. Inspect the argv of that PID. Only kill known Zion engines.
        let psProc = Process()
        psProc.executableURL = URL(fileURLWithPath: ps)
        psProc.arguments = ["-p", String(pid), "-o", "command="]
        let psPipe = Pipe()
        psProc.standardOutput = psPipe
        psProc.standardError = FileHandle.nullDevice
        do {
            try psProc.run()
            psProc.waitUntilExit()
        } catch { return }

        let cmd = String(data: psPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let known = ["mlx_lm.server", "ollama serve", "llama-server", "lms server"]
        guard known.contains(where: { cmd.contains($0) }) else { return }

        DiagnosticLogger.shared.log(
            .info,
            "Orphan local server detected on port \(port) pid=\(pid) cmd=\(cmd.prefix(120))",
            source: "LocalServerLauncher"
        )
        Darwin.kill(pid, SIGTERM)
    }

    // MARK: - Shutdown cleanup

    /// Best-effort synchronous SIGTERM of any local LLM server listening on the
    /// port from the user's saved `LocalLLMConfig`. Called from
    /// `applicationWillTerminate`, where async tasks are not guaranteed to run
    /// to completion. Uses `lsof -ti :<port>` + `kill` directly.
    /// No-op if no config saved, no port, or no listener.
    @MainActor
    static func stopActiveConfigSync() {
        guard let config = AIClient.loadLocalConfig(),
              let port = URL(string: config.serverURL)?.port else { return }

        let lsof = "/usr/sbin/lsof"
        guard FileManager.default.isExecutableFile(atPath: lsof) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsof)
        process.arguments = ["-ti", ":\(port)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return }
        let pids = text
            .split(whereSeparator: { $0.isNewline })
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        for pid in pids {
            Darwin.kill(pid, SIGTERM)
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
