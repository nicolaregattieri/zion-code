import Foundation

/// Wrapper around a running MCP server subprocess.
/// Gate actual process spawn behind `processLauncherOverride` for test injection.
actor MCPServerProcess {
    let config: MCPServerConfig
    private(set) var status: MCPServerStatus = .disabled
    private var stderrRingBuffer: [String] = []
    private static let stderrRingMaxBytes = 65_536  // 64 KB
    private var stderrCurrentBytes = 0
    private var process: Process?

    // MARK: - Test injection
    /// When set, called instead of spawning a real subprocess.
    /// The override receives the config and may set status directly via the actor.
    nonisolated(unsafe) static var processLauncherOverride: ((MCPServerConfig) -> Void)?

    init(config: MCPServerConfig) {
        self.config = config
    }

    // MARK: - Lifecycle

    func launch() async throws {
        guard !config.disabled else {
            status = .disabled
            return
        }
        status = .starting

        if let override = MCPServerProcess.processLauncherOverride {
            override(config)
            // Override may set status; default to .running if still .starting
            if case .starting = status {
                status = .running(toolCount: 0)
            }
            return
        }

        // Production path: spawn a real subprocess
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [config.command] + config.args
        if !config.env.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in config.env { env[key] = value }
            proc.environment = env
        }

        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        proc.standardOutput = Pipe()  // discard stdout for now

        try proc.run()

        // setsid equivalent on macOS: set process group so kill(-pgid) works
        setpgid(proc.processIdentifier, proc.processIdentifier)

        self.process = proc
        status = .running(toolCount: 0)

        // Drain stderr asynchronously into ring buffer
        let stderrHandle = stderrPipe.fileHandleForReading
        Task.detached { [weak self] in
            for try await line in stderrHandle.bytes.lines {
                await self?.appendStderr(line)
            }
        }

        // Watch for termination
        proc.terminationHandler = { [weak self] terminatedProc in
            guard let self else { return }
            let reason = "exit code \(terminatedProc.terminationStatus)"
            Task { await self.markCrashed(reason: reason) }
        }
    }

    func terminate() async {
        if let proc = process, proc.isRunning {
            let pid = proc.processIdentifier
            kill(-pid, SIGTERM)
        }
        process = nil
        status = .disabled
    }

    func stderr() -> [String] { stderrRingBuffer }

    // MARK: - Private helpers

    private func appendStderr(_ line: String) {
        let bytes = line.utf8.count + 1  // +1 for newline
        // Evict oldest lines until we fit within the cap
        while stderrCurrentBytes + bytes > MCPServerProcess.stderrRingMaxBytes,
              !stderrRingBuffer.isEmpty {
            let removed = stderrRingBuffer.removeFirst()
            stderrCurrentBytes -= removed.utf8.count + 1
        }
        stderrRingBuffer.append(line)
        stderrCurrentBytes += bytes
    }

    private func markCrashed(reason: String) {
        status = .crashed(reason: reason)
        process = nil
    }
}
