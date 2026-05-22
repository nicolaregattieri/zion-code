import Foundation
import Darwin

// MARK: - CLIStreamEvent

enum CLIStreamEvent: Equatable {
    case textDelta(String)
    case toolStart(id: String, name: String, description: String)
    case toolEnd(id: String, success: Bool, output: String?)
    /// Emitted once per stream when the CLI exposes a session/thread identifier
    /// the next turn can resume against (`claude --resume`, `codex exec resume`).
    case sessionStarted(id: String)
    /// Emitted at end-of-turn when the CLI reports a USD cost
    /// (claude `total_cost_usd`). Codex Plus is unmetered → never emits.
    case turnCost(usd: Double)
    /// Emitted at end-of-turn with token counts so we can show usage even when
    /// the provider does not report a dollar figure (codex Plus / local LLM).
    case turnUsage(inputTokens: Int, outputTokens: Int)
    case done
    case error(String)
}

// MARK: - CLI Stream Parsers

extension AIClient {

    // MARK: Claude JSONL Parser

    /// Parses a single JSONL line emitted by `claude --output-format stream-json`.
    /// Returns the events the line resolves to (most lines produce 0 or 1, but
    /// `result` can emit both a `turnCost` and a terminal `done`). Callers that
    /// only care about the first event can use the legacy single-return helper.
    static func parseClaudeJSONLEvents(_ line: Data) -> [CLIStreamEvent] {
        guard let event = parseClaudeJSONLLine(line) else { return [] }
        // Result line carries cost + usage + done semantics. Emit all.
        if case .turnCost = event {
            var events: [CLIStreamEvent] = [event]
            if let usage = claudeResultUsage(line: line) {
                events.append(usage)
            }
            events.append(.done)
            return events
        }
        return [event]
    }

    /// Extracts a `.turnUsage` event from a `result` JSONL line. Separate from
    /// the single-event parser because result lines also carry cost+done.
    private static func claudeResultUsage(line: Data) -> CLIStreamEvent? {
        guard let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              (root["type"] as? String) == "result",
              let usage = root["usage"] as? [String: Any] else { return nil }
        let input = (usage["input_tokens"] as? Int) ?? 0
        let output = (usage["output_tokens"] as? Int) ?? 0
        if input == 0 && output == 0 { return nil }
        return .turnUsage(inputTokens: input, outputTokens: output)
    }

    /// Parses a single JSONL line emitted by `claude --output-format stream-json`.
    /// Returns nil for malformed input or unrecognised event types.
    /// Use `parseClaudeJSONLEvents` when you need every event the line yields.
    static func parseClaudeJSONLLine(_ line: Data) -> CLIStreamEvent? {
        guard !line.isEmpty,
              let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        else { return nil }

        guard let type = root["type"] as? String else { return nil }

        switch type {
        case "system":
            // {type:"system", subtype:"init", session_id:"<uuid>"}
            if let subtype = root["subtype"] as? String,
               subtype == "init",
               let sessionID = root["session_id"] as? String,
               !sessionID.isEmpty {
                return .sessionStarted(id: sessionID)
            }
            return nil

        case "assistant":
            // {type:"assistant", message:{content:[{type:"text", text:"..."}]}}
            guard let message = root["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { return nil }

            let text = content.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }.joined()

            guard !text.isEmpty else { return nil }
            return .textDelta(text)

        case "tool_use":
            // {type:"tool_use", id, name, input:{...}}
            guard let id = root["id"] as? String,
                  let name = root["name"] as? String
            else { return nil }

            let description: String
            if let input = root["input"] as? [String: Any] {
                description = claudeToolDescription(from: input)
            } else {
                description = ""
            }
            return .toolStart(id: id, name: name, description: description)

        case "tool_result":
            // {type:"tool_result", tool_use_id, is_error:bool, content: string|[blocks]}
            guard let toolUseId = root["tool_use_id"] as? String else { return nil }
            let isError = root["is_error"] as? Bool ?? false
            let output = claudeToolOutput(from: root["content"])
            return .toolEnd(id: toolUseId, success: !isError, output: output)

        case "result":
            // End-of-turn. Claude reports total_cost_usd on this event.
            if let cost = root["total_cost_usd"] as? Double, cost > 0 {
                return .turnCost(usd: cost)
            }
            return .done

        case "error":
            let message = root["message"] as? String ?? "Unknown error"
            return .error(message)

        default:
            return nil
        }
    }

    // MARK: Codex JSONL Parser

    /// Multi-event variant — see `parseClaudeJSONLEvents`.
    static func parseCodexJSONLEvents(_ line: Data) -> [CLIStreamEvent] {
        guard let event = parseCodexJSONLLine(line) else { return [] }
        // turn.completed for codex carries usage but no $ cost. Emit usage + done.
        // (claude variant emits cost + usage + done — handled above.)
        if case .done = event, let usage = codexTurnUsage(line: line) {
            return [usage, event]
        }
        if case .turnCost = event {
            var events: [CLIStreamEvent] = [event]
            if let usage = codexTurnUsage(line: line) {
                events.append(usage)
            }
            events.append(.done)
            return events
        }
        return [event]
    }

    private static func codexTurnUsage(line: Data) -> CLIStreamEvent? {
        guard let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return nil }
        // v0.131+ top-level usage; legacy msg.usage. Either works.
        let usage = (root["usage"] as? [String: Any])
            ?? ((root["msg"] as? [String: Any])?["usage"] as? [String: Any])
        guard let usage else { return nil }
        let input = (usage["input_tokens"] as? Int) ?? 0
        let output = (usage["output_tokens"] as? Int) ?? 0
        if input == 0 && output == 0 { return nil }
        return .turnUsage(inputTokens: input, outputTokens: output)
    }

    /// Parses a single JSONL line emitted by `codex exec --json` (v0.131+).
    /// The schema places event details under a top-level `type` key, with
    /// item payloads nested under `item`. Older `msg.type` schemas are also
    /// accepted as a fallback so older codex builds keep working.
    static func parseCodexJSONLLine(_ line: Data) -> CLIStreamEvent? {
        guard !line.isEmpty,
              let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        else { return nil }

        // v0.131+: top-level `type` + nested `item`/`usage` payloads.
        if let topType = root["type"] as? String {
            switch topType {
            case "thread.started":
                if let threadID = root["thread_id"] as? String, !threadID.isEmpty {
                    return .sessionStarted(id: threadID)
                }
                return nil

            case "item.completed":
                guard let item = root["item"] as? [String: Any],
                      let itemType = item["type"] as? String
                else { return nil }
                switch itemType {
                case "agent_message":
                    guard let text = item["text"] as? String, !text.isEmpty else { return nil }
                    return .textDelta(text)
                case "function_call", "tool_call":
                    let id = (item["id"] as? String) ?? (item["call_id"] as? String) ?? UUID().uuidString
                    let name = (item["name"] as? String) ?? (item["function_name"] as? String) ?? "tool"
                    let argsRaw = (item["arguments"] as? String) ?? (item["args"] as? String) ?? ""
                    return .toolStart(id: id, name: name, description: String(argsRaw.prefix(60)))
                case "tool_result":
                    let id = (item["id"] as? String) ?? (item["call_id"] as? String) ?? ""
                    let success = (item["status"] as? String) == "success"
                        || (item["exit_code"] as? Int) == 0
                    let output = (item["output"] as? String) ?? (item["result"] as? String)
                    return .toolEnd(id: id, success: success, output: output.map { String($0.prefix(1024)) })
                default:
                    return nil
                }

            case "turn.completed", "task_complete":
                if let usage = root["usage"] as? [String: Any],
                   let cost = usage["total_cost_usd"] as? Double, cost > 0 {
                    return .turnCost(usd: cost)
                }
                return .done

            case "error":
                let message = root["message"] as? String ?? "codex error"
                return .error(message)

            default:
                return nil
            }
        }

        // Legacy schema fallback: { "msg": { "type": ..., ... } }
        guard let msg = root["msg"] as? [String: Any],
              let msgType = msg["type"] as? String
        else { return nil }

        switch msgType {
        case "agent_message":
            guard let text = msg["text"] as? String, !text.isEmpty else { return nil }
            return .textDelta(text)

        case "function_call_begin":
            guard let callId = msg["call_id"] as? String,
                  let functionName = msg["function_name"] as? String
            else { return nil }
            let args = msg["args"] as? String ?? ""
            return .toolStart(id: callId, name: functionName, description: String(args.prefix(60)))

        case "function_call_end":
            guard let callId = msg["call_id"] as? String else { return nil }
            let exitCode = msg["exit_code"] as? Int ?? 1
            let output = (msg["output"] as? String) ?? (msg["stdout"] as? String)
            return .toolEnd(id: callId, success: exitCode == 0, output: output.map { String($0.prefix(1024)) })

        case "task_complete":
            return .done

        default:
            return nil
        }
    }

    // MARK: - Private Helpers

    /// Extracts a UTF-8 string from Claude's `tool_result.content`.
    /// The content can be a bare string OR an array of text blocks
    /// (`[{"type":"text","text":"..."}]`). Truncated to 1024 chars so a giant
    /// file read doesn't bloat persisted messages.
    private static func claudeToolOutput(from raw: Any?) -> String? {
        if let text = raw as? String, !text.isEmpty {
            return String(text.prefix(1024))
        }
        if let blocks = raw as? [[String: Any]] {
            let joined = blocks.compactMap { ($0["text"] as? String) }.joined(separator: "\n")
            return joined.isEmpty ? nil : String(joined.prefix(1024))
        }
        return nil
    }

    /// Builds a ≤60-char description from a Claude tool input dict.
    /// Priority: command > file_path > pattern > path > first string value.
    private static func claudeToolDescription(from input: [String: Any]) -> String {
        let preferredKeys = ["command", "file_path", "pattern", "path"]
        for key in preferredKeys {
            if let value = input[key] as? String, !value.isEmpty {
                return String(value.prefix(60))
            }
        }
        // Fallback: first string value in dict
        for (_, value) in input {
            if let stringValue = value as? String, !stringValue.isEmpty {
                return String(stringValue.prefix(60))
            }
        }
        return ""
    }
}

// MARK: - CLI Subprocess Streaming

extension AIClient {

    // MARK: Public API

    /// Streams events from a `claude` CLI subprocess.
    /// - Parameters:
    ///   - payload: Prompt payload; `renderUserMessage` is written to stdin.
    ///   - cwd: Working directory for the subprocess.
    ///   - maxTokens: Token budget passed via `--max-tokens`.
    ///   - allowEdits: When true, uses `acceptEdits` permission mode; otherwise `plan`.
    func streamClaudeCLI(
        payload: AIPromptPayload,
        cwd: URL,
        maxTokens: Int,
        allowEdits: Bool,
        resumeSessionID: String? = nil
    ) async -> AsyncThrowingStream<CLIStreamEvent, Error> {
        let discovery = CLIDiscoveryService()
        let toolStatus = await discovery.status(for: .claude)

        guard toolStatus.installed, let toolPath = toolStatus.path else {
            return AsyncThrowingStream { $0.finish(throwing: AIError.cliNotInstalled(.claude)) }
        }

        let absPath = toolPath.path
        let permissionMode = allowEdits ? "acceptEdits" : "plan"
        _ = maxTokens // Claude CLI does not expose a max-tokens flag; budget is gated via --max-budget-usd.
        var args: [String] = [
            "-p", "-",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-mode", permissionMode,
            "--max-budget-usd", "1.00"
        ]
        // Resume a prior server-side session if we captured one on the previous
        // turn. Skips re-sending the entire conversation context.
        if let sid = resumeSessionID, !sid.isEmpty {
            args.append(contentsOf: ["--resume", sid])
        }

        let prompt = AIClient.renderUserMessage(from: payload)
        return spawnCLIStream(absPath: absPath, args: args, cwd: cwd, stdinData: Data(prompt.utf8)) { line in
            AIClient.parseClaudeJSONLEvents(line)
        }
    }

    /// Streams events from a `codex` CLI subprocess.
    /// - Parameters:
    ///   - payload: Prompt payload; `renderUserMessage` is written to stdin.
    ///   - cwd: Working directory for the subprocess.
    ///   - allowEdits: When true, uses `workspace-write` sandbox; otherwise `read-only`.
    func streamCodexCLI(
        payload: AIPromptPayload,
        cwd: URL,
        allowEdits: Bool,
        resumeSessionID: String? = nil
    ) async -> AsyncThrowingStream<CLIStreamEvent, Error> {
        let discovery = CLIDiscoveryService()
        let toolStatus = await discovery.status(for: .codex)

        guard toolStatus.installed, let toolPath = toolStatus.path else {
            return AsyncThrowingStream { $0.finish(throwing: AIError.cliNotInstalled(.codex)) }
        }

        let absPath = toolPath.path
        let sandbox = allowEdits ? "workspace-write" : "read-only"
        var args: [String]
        if let sid = resumeSessionID, !sid.isEmpty {
            // `codex exec resume <id>` continues the prior conversation rather
            // than starting fresh; sandbox / cd flags still apply.
            args = [
                "exec",
                "--json",
                "--skip-git-repo-check",
                "-C", cwd.path,
                "-s", sandbox,
                "resume", sid,
                "-"
            ]
        } else {
            args = [
                "exec",
                "--json",
                "--skip-git-repo-check",
                "-C", cwd.path,
                "-s", sandbox,
                "-"
            ]
        }

        let prompt = AIClient.renderUserMessage(from: payload)
        return spawnCLIStream(absPath: absPath, args: args, cwd: cwd, stdinData: Data(prompt.utf8)) { line in
            AIClient.parseCodexJSONLEvents(line)
        }
    }

    /// Non-streaming Claude CLI call: concatenates all textDelta events and returns the full text.
    func callClaudeCLI(payload: AIPromptPayload, cwd: URL, maxTokens: Int) async throws -> String {
        let stream = await streamClaudeCLI(payload: payload, cwd: cwd, maxTokens: maxTokens, allowEdits: false)
        var result = ""
        for try await event in stream {
            if case .textDelta(let text) = event {
                result += text
            }
        }
        return result
    }

    /// Non-streaming Codex CLI call: concatenates all textDelta events and returns the full text.
    func callCodexCLI(payload: AIPromptPayload, cwd: URL) async throws -> String {
        let stream = await streamCodexCLI(payload: payload, cwd: cwd, allowEdits: false)
        var result = ""
        for try await event in stream {
            if case .textDelta(let text) = event {
                result += text
            }
        }
        return result
    }

    // MARK: - Internal: Process Group Spawn

    /// Spawns a CLI process as a new process group (via setsid or posix_spawn SETPGROUP).
    /// Reads stdout line-by-line, parsing each line with `parser`.
    /// On AsyncThrowingStream termination (cancel or finish), sends SIGTERM then SIGKILL.
    ///
    /// - Parameters:
    ///   - absPath: Absolute path to the CLI binary.
    ///   - args: Arguments passed to the binary.
    ///   - cwd: Working directory.
    ///   - stdinData: Data to write to the process stdin, then close.
    ///   - parser: Closure that parses a JSONL line (Data) into a CLIStreamEvent, or nil to skip.
    nonisolated func spawnCLIStream(
        absPath: String,
        args: [String],
        cwd: URL,
        stdinData: Data,
        parser: @escaping @Sendable (Data) -> [CLIStreamEvent]
    ) -> AsyncThrowingStream<CLIStreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            let process = Process()
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.currentDirectoryURL = cwd
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = AIClient.buildCLIEnvironment(binaryPath: absPath)

            // Wrap with setsid (or posix_spawn group) so child becomes new process group leader
            let useSetsid = FileManager.default.fileExists(atPath: "/usr/bin/setsid")
            if useSetsid {
                // Shell wrapper: exec setsid <absPath> <args...>
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                var shellCmd = "exec /usr/bin/setsid \(shellEscape(absPath))"
                for arg in args {
                    shellCmd += " \(shellEscape(arg))"
                }
                process.arguments = ["-c", shellCmd]
            } else {
                // Direct launch — set process group via posix_spawn attribute
                // We use a QualityOfService-aware approach: set the group after launch
                process.executableURL = URL(fileURLWithPath: absPath)
                process.arguments = args
            }

            // Cancellation: SIGTERM the process group, then SIGKILL after grace
            continuation.onTermination = { [weak process] _ in
                guard let process = process else { return }
                let pid = process.processIdentifier
                guard pid > 0 else { return }
                // Kill the entire process group (negative pid = group)
                Darwin.kill(-pid, SIGTERM)
                let graceNanos = UInt64(Constants.Timing.cliSigkillGrace * 1_000_000_000)
                Task {
                    try? await Task.sleep(nanoseconds: graceNanos)
                    if process.isRunning {
                        Darwin.kill(-pid, SIGKILL)
                    }
                }
            }

            // Launch
            do {
                try process.run()
            } catch {
                continuation.finish(throwing: AIError.cliError(stderr: error.localizedDescription, exitCode: -1))
                return
            }

            // If not using setsid, set process group manually after launch
            if !useSetsid {
                let pid = process.processIdentifier
                if pid > 0 {
                    Darwin.setpgid(pid, pid)
                }
            }

            // Write stdin then close
            let stdinHandle = stdinPipe.fileHandleForWriting
            do {
                try stdinHandle.write(contentsOf: stdinData)
                try stdinHandle.close()
            } catch {
                // Non-fatal; process may still start
            }

            // Drain stderr concurrently (keep last 2KB)
            let stderrHandle = stderrPipe.fileHandleForReading
            let stderrBuffer = StderrBuffer()

            Task {
                let stderrData = stderrHandle.readDataToEndOfFile()
                if let text = String(data: stderrData, encoding: .utf8) {
                    await stderrBuffer.append(text)
                }
            }

            // Read stdout line by line using async bytes sequence
            Task {
                let stdoutHandle = stdoutPipe.fileHandleForReading
                var lineBuffer = Data()
                let newlineByte = UInt8(ascii: "\n")

                for try await byte in stdoutHandle.bytes {
                    if byte == newlineByte {
                        if !lineBuffer.isEmpty {
                            for event in parser(lineBuffer) {
                                continuation.yield(event)
                            }
                            lineBuffer.removeAll(keepingCapacity: true)
                        }
                    } else {
                        lineBuffer.append(byte)
                    }
                }

                // Flush any trailing partial line (no trailing newline)
                if !lineBuffer.isEmpty {
                    for event in parser(lineBuffer) {
                        continuation.yield(event)
                    }
                }

                // Wait for process to exit
                process.waitUntilExit()
                let exitCode = process.terminationStatus

                if exitCode != 0 {
                    let stderrText = await stderrBuffer.last2KB()
                    continuation.finish(throwing: AIError.cliError(stderr: stderrText, exitCode: exitCode))
                } else {
                    continuation.finish()
                }
            }
        }
    }
}

// MARK: - CLI Environment

extension AIClient {
    /// Builds a minimal, deterministic environment for CLI subprocesses.
    ///
    /// CLI tools (claude, codex) require certain variables to function correctly under
    /// the Hardened Runtime, where the parent process inherits an empty environment when
    /// none is provided to Process. Specifically:
    /// - `HOME` so the CLI can locate `~/.claude/` and `~/.codex/` config directories.
    /// - `USER` so macOS Keychain APIs (used by Claude Code for OAuth tokens) can
    ///   resolve the current user identity. Without it Claude returns "Not logged in".
    /// - `PATH` containing the parent directory of the CLI binary plus common system bins.
    ///   nvm/Homebrew installs depend on co-located helpers (`node`, `npx`, etc.).
    /// - `LANG` for UTF-8 stdout when the CLI streams non-ASCII content.
    /// - `TMPDIR` so tools that create temporary files (e.g. session caches) succeed.
    ///
    /// This list is intentionally narrow — we do not inherit the full parent environment
    /// to avoid leaking secrets or test variables into the subprocess.
    static func buildCLIEnvironment(binaryPath: String) -> [String: String] {
        let parentEnv = ProcessInfo.processInfo.environment
        let binaryDir = (binaryPath as NSString).deletingLastPathComponent
        let basePaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        var pathComponents = [binaryDir]
        pathComponents.append(contentsOf: basePaths.filter { $0 != binaryDir })

        var env: [String: String] = [
            "HOME": NSHomeDirectory(),
            "PATH": pathComponents.joined(separator: ":"),
            "LANG": parentEnv["LANG"] ?? "en_US.UTF-8"
        ]
        if let user = parentEnv["USER"] ?? parentEnv["LOGNAME"] {
            env["USER"] = user
            env["LOGNAME"] = user
        } else {
            // Fallback: NSUserName() works under Hardened Runtime without env propagation.
            let user = NSUserName()
            env["USER"] = user
            env["LOGNAME"] = user
        }
        if let tmp = parentEnv["TMPDIR"] {
            env["TMPDIR"] = tmp
        }
        // Pass through shell so any helpers that spawn sub-shells use a sane default.
        env["SHELL"] = parentEnv["SHELL"] ?? "/bin/sh"
        return env
    }
}

// MARK: - Shell Escaping Helper

private func shellEscape(_ str: String) -> String {
    // Wrap in single quotes, escape any embedded single quotes
    let escaped = str.replacingOccurrences(of: "'", with: "'\\''")
    return "'\(escaped)'"
}

// MARK: - Stderr Buffer Actor

/// Thread-safe buffer that keeps the last 2KB of stderr output.
private actor StderrBuffer {
    private var text: String = ""
    private static let maxLength = 2048

    func append(_ chunk: String) {
        text += chunk
        if text.count > Self.maxLength {
            let dropCount = text.count - Self.maxLength
            text = String(text.dropFirst(dropCount))
        }
    }

    func last2KB() -> String {
        return text
    }
}
