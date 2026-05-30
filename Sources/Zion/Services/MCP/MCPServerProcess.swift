import Foundation

/// Wrapper around a running MCP server subprocess. Handles process
/// lifecycle, stderr ring-buffer, and JSON-RPC over stdio (initialize
/// + tools/list + tools/call) so the harness can dispatch
/// user-installed MCP tools at runtime.
actor MCPServerProcess {
    let config: MCPServerConfig
    private(set) var status: MCPServerStatus = .disabled
    private var stderrRingBuffer: [String] = []
    private static let stderrRingMaxBytes = 65_536  // 64 KB
    private var stderrCurrentBytes = 0
    private var process: Process?

    // MARK: - JSON-RPC plumbing

    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var nextRequestID: Int = 0
    /// Continuations awaiting a JSON-RPC response keyed by request id.
    private var pendingResponses: [Int: CheckedContinuation<Any, Error>] = [:]
    /// Tools published by the server after `initialize` + `tools/list`.
    private(set) var advertisedTools: [MCPToolDescriptor] = []

    /// Server-level routing instructions captured from the `initialize`
    /// response (`result.instructions` field per MCP spec). Many servers
    /// — context-mode, GitHub, Linear, etc. — ship a routing block here
    /// explaining when to prefer their tools over generic Read/Bash/etc.
    /// Surfaced in the chat system prompt so the model picks the right
    /// tool without the user memorising names.
    private(set) var serverInstructions: String = ""

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
        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()
        proc.standardError = stderrPipe
        proc.standardOutput = stdoutPipe
        proc.standardInput = stdinPipe

        try proc.run()

        // setsid equivalent on macOS: set process group so kill(-pgid) works
        setpgid(proc.processIdentifier, proc.processIdentifier)

        self.process = proc
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        status = .running(toolCount: 0)

        // Drain stderr asynchronously into ring buffer
        let stderrHandle = stderrPipe.fileHandleForReading
        Task.detached { [weak self] in
            for try await line in stderrHandle.bytes.lines {
                await self?.appendStderr(line)
            }
        }

        // Drain stdout as JSON-RPC frames (one JSON object per line).
        let outHandle = stdoutPipe.fileHandleForReading
        Task.detached { [weak self] in
            for try await line in outHandle.bytes.lines {
                await self?.handleStdoutLine(line)
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
        stdinHandle = nil
        stdoutHandle = nil
        status = .disabled
        // Fail any pending requests so callers don't hang.
        for (_, cont) in pendingResponses {
            cont.resume(throwing: MCPProcessError.terminated)
        }
        pendingResponses.removeAll()
    }

    func stderr() -> [String] { stderrRingBuffer }

    // MARK: - JSON-RPC

    /// Sends a JSON-RPC request and awaits the response. Returns the
    /// `result` field. Throws on JSON-RPC `error` or process death.
    func sendRequest(method: String, params: [String: Any] = [:]) async throws -> Any {
        guard let stdin = stdinHandle else {
            throw MCPProcessError.notRunning
        }
        nextRequestID += 1
        let id = nextRequestID
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = continuation
            do {
                stdin.write(data)
                stdin.write("\n".data(using: .utf8)!)
            } catch {
                pendingResponses.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    /// Runs `initialize` + `tools/list` and caches the result on
    /// `advertisedTools`. Idempotent — if tools were already loaded,
    /// returns the cached list.
    @discardableResult
    func loadAdvertisedTools() async throws -> [MCPToolDescriptor] {
        if !advertisedTools.isEmpty { return advertisedTools }
        let initResult = try? await sendRequest(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "clientInfo": ["name": "Zion", "version": "1.0"],
            "capabilities": [:] as [String: Any]
        ])
        if let initDict = initResult as? [String: Any],
           let instr = initDict["instructions"] as? String,
           !instr.isEmpty {
            serverInstructions = instr
        }
        let raw = try await sendRequest(method: "tools/list")
        guard let dict = raw as? [String: Any],
              let toolsArray = dict["tools"] as? [[String: Any]] else {
            return []
        }
        let tools: [MCPToolDescriptor] = toolsArray.compactMap { obj in
            guard let name = obj["name"] as? String else { return nil }
            let desc = (obj["description"] as? String) ?? ""
            let schema = (obj["inputSchema"] as? [String: Any]) ?? [:]
            return MCPToolDescriptor(name: name, description: desc, inputSchema: schema)
        }
        advertisedTools = tools
        if case .running = status {
            status = .running(toolCount: tools.count)
        }
        return tools
    }

    /// Calls `tools/call` and returns the textual content of the
    /// first response block. Throws when the server reports an error.
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        let raw = try await sendRequest(method: "tools/call", params: [
            "name": name,
            "arguments": arguments
        ])
        guard let dict = raw as? [String: Any] else {
            throw MCPProcessError.malformedResponse
        }
        if let content = dict["content"] as? [[String: Any]] {
            let textBlocks = content.compactMap { block -> String? in
                guard let type = block["type"] as? String, type == "text" else { return nil }
                return block["text"] as? String
            }
            if !textBlocks.isEmpty {
                return textBlocks.joined(separator: "\n")
            }
        }
        if let resultText = dict["result"] as? String {
            return resultText
        }
        return ""
    }

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

    private func handleStdoutLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return }
        // Resolve by id when present.
        if let id = dict["id"] as? Int,
           let continuation = pendingResponses.removeValue(forKey: id) {
            if let error = dict["error"] as? [String: Any] {
                continuation.resume(throwing: MCPProcessError.serverError(
                    message: (error["message"] as? String) ?? "JSON-RPC error"
                ))
                return
            }
            continuation.resume(returning: dict["result"] as Any)
            return
        }
        // Notifications (no id) — silently drop for now.
    }

    private func markCrashed(reason: String) {
        status = .crashed(reason: reason)
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        for (_, cont) in pendingResponses {
            cont.resume(throwing: MCPProcessError.serverError(message: reason))
        }
        pendingResponses.removeAll()
    }
}

enum MCPProcessError: Error, Equatable {
    case notRunning
    case terminated
    case malformedResponse
    case serverError(message: String)
}
