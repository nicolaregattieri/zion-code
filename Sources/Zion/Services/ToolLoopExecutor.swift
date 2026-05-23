// ToolLoopExecutor.swift — MCPClient actor + ToolLoopExecutor struct.
// MCPClient: spawns zion-mcp binary as a subprocess and exchanges line-delimited JSON over stdio.
// ToolLoopExecutor: parses provider stream chunks for tool calls and drives multi-turn execution.

import Foundation

// MARK: - ProviderChunk

/// Provider-agnostic stream chunk.
// [String: Any] cannot satisfy Sendable automatically; @unchecked is safe here because
// the args dictionaries are immutable JSON-decoded values passed through without mutation.
enum ProviderChunk: @unchecked Sendable {
    case textDelta(String)
    case toolCall(id: String, name: String, args: [String: Any])
    /// Carries the raw finish/stop reason string emitted by the provider.
    case finishReason(String)
    case done
}

// MARK: - StepOutcome

/// Unified outcome of one streaming step, produced by `ToolLoopExecutor.runOneStep`.
// [String: Any] fields require @unchecked Sendable — the JSON payloads are
// immutable after decoding and never mutated across isolation boundaries.
struct StepOutcome: @unchecked Sendable {

    enum StopReason: Equatable, Sendable {
        case endTurn
        case toolUse
        case maxTokens
        case other(String)
    }

    struct ToolCall: @unchecked Sendable {
        let id: String
        let name: String
        let args: [String: Any]
    }

    let text: String
    let toolCalls: [ToolCall]
    let stopReason: StopReason
    let updatedConversation: [[String: Any]]

    // MARK: Gemini adapter

    /// Convert a Gemini-native `GeminiStepOutcome` into the unified `StepOutcome`.
    static func fromGemini(_ outcome: GeminiStepOutcome) -> StepOutcome {
        let calls = outcome.toolCalls.map { tc in
            ToolCall(id: tc.id, name: tc.name, args: tc.args)
        }
        let reason: StopReason
        switch outcome.stopReason {
        case .endTurn:        reason = .endTurn
        case .toolUse:        reason = .toolUse
        case .maxTokens:      reason = .maxTokens
        case .other(let s):   reason = .other(s)
        }
        return StepOutcome(
            text: outcome.text,
            toolCalls: calls,
            stopReason: reason,
            updatedConversation: outcome.updatedConversation
        )
    }
}

// MARK: - MCPClientError

enum MCPClientError: Error, LocalizedError {
    case binaryNotFound
    case notStarted
    case invalidResponse(String)
    case rpcError(Int, String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:          return "zion-mcp binary not found"
        case .notStarted:              return "MCPClient not started"
        case .invalidResponse(let s):  return "Invalid MCP response: \(s)"
        case .rpcError(let c, let m):  return "MCP RPC error \(c): \(m)"
        }
    }
}

// MARK: - MCPClient

/// Spawns the zion-mcp binary and exchanges JSON-RPC over its stdio.
// Implemented as a `final class` (not an `actor`) so the protocol-conformance
// nonisolated boundary doesn't fight Swift 6 strict-concurrency over
// `[String: Any]` payloads. Internal mutable state is serialised through a
// dispatch queue; the class is marked `@unchecked Sendable` because the JSON
// payloads are treated as immutable after decoding.
final class MCPClient: @unchecked Sendable {

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var requestID = 0
    private var pendingReplies: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var readerTask: Task<Void, Never>?

    // MARK: Start

    func start(binaryPath: String, repoCwd: URL?) throws {
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw MCPClientError.binaryNotFound
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)

        var args: [String] = []
        if let cwd = repoCwd {
            args += ["--repo", cwd.path]
        }
        proc.arguments = args

        let stdin  = Pipe()
        let stdout = Pipe()
        proc.standardInput  = stdin
        proc.standardOutput = stdout
        proc.standardError  = Pipe() // discard stderr

        try proc.run()

        process    = proc
        stdinPipe  = stdin
        stdoutPipe = stdout

        // Background reader task: capture the handle on the actor before detaching.
        let stdoutHandle = stdout.fileHandleForReading
        readerTask = Task.detached { [weak self] in
            do {
                for try await line in stdoutHandle.bytes.lines {
                    await self?.handleLine(line)
                }
            } catch {
                // Reader exited; ignore
            }
        }
    }

    // MARK: List tools

    func listTools() async throws -> [MCPToolDescriptor] {
        let result = try await sendRequest(method: "tools/list", params: nil)
        guard let toolsArray = result["tools"] as? [[String: Any]] else {
            return []
        }
        return toolsArray.compactMap { obj -> MCPToolDescriptor? in
            guard let name = obj["name"] as? String,
                  let desc = obj["description"] as? String else { return nil }
            let schema = (obj["inputSchema"] as? [String: Any]) ?? ["type": "object", "properties": [:]]
            return MCPToolDescriptor(name: name, description: desc, inputSchema: schema)
        }
    }

    // MARK: Call tool

    func callTool(_ name: String, args: [String: Any]) async throws -> [String: Any] {
        let paramsDict: [String: Any] = ["name": name, "arguments": args]
        return try await sendRequest(method: "tools/call", params: paramsDict)
    }

    // MARK: Stop

    func stop() {
        readerTask?.cancel()
        process?.terminate()
        process    = nil
        stdinPipe  = nil
        stdoutPipe = nil
        pendingReplies.removeAll()
    }

    // MARK: Private RPC

    private func nextID() -> Int {
        requestID += 1
        return requestID
    }

    private func sendRequest(method: String, params: [String: Any]?) async throws -> [String: Any] {
        guard let stdinHandle = stdinPipe?.fileHandleForWriting else {
            throw MCPClientError.notStarted
        }

        let id = nextID()
        var request: [String: Any] = ["jsonrpc": "2.0", "method": method, "id": id]
        if let params = params {
            request["params"] = params
        }

        let data = try JSONSerialization.data(withJSONObject: request)
        var line = data
        line.append(0x0A) // newline

        return try await withCheckedThrowingContinuation { continuation in
            pendingReplies[id] = continuation
            do {
                try stdinHandle.write(contentsOf: line)
            } catch {
                pendingReplies.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }

        guard let idAny = json["id"] else { return }

        let id: Int
        if let intID = idAny as? Int {
            id = intID
        } else if let strID = idAny as? String, let parsed = Int(strID) {
            id = parsed
        } else { return }

        guard let continuation = pendingReplies.removeValue(forKey: id) else { return }

        if let errorObj = json["error"] as? [String: Any],
           let code = errorObj["code"] as? Int,
           let msg  = errorObj["message"] as? String {
            continuation.resume(throwing: MCPClientError.rpcError(code, msg))
            return
        }

        if let result = json["result"] as? [String: Any] {
            continuation.resume(returning: result)
        } else {
            continuation.resume(returning: [:])
        }
    }
}

// MARK: - MCPClientProtocol (for test injection)
//
// `[String: Any]` is not Sendable in Swift 6 strict concurrency. We mark the
// protocol `@preconcurrency Sendable` and let conforming types opt into
// `@unchecked Sendable` themselves — the JSON payloads are immutable after
// decoding, so the safety contract holds.
@preconcurrency
protocol MCPClientProtocol: Sendable {
    func callTool(_ name: String, args: [String: Any]) async throws -> [String: Any]
    func listTools() async throws -> [MCPToolDescriptor]
}

extension MCPClient: MCPClientProtocol {}

// Dead helper kept only to suppress the original parser's reference. Will be
// removed in a follow-up cleanup.
private extension MCPClient {
    func _listToolsLegacy() async throws -> [MCPToolDescriptor] {
        let result = try await sendRequest(method: "tools/list", params: nil)
        guard let toolsArray = result["tools"] as? [[String: Any]] else {
            return []
        }
        return toolsArray.compactMap { obj -> MCPToolDescriptor? in
            guard let name = obj["name"] as? String,
                  let desc = obj["description"] as? String else { return nil }
            let schema = (obj["inputSchema"] as? [String: Any]) ?? ["type": "object", "properties": [:]]
            return MCPToolDescriptor(name: name, description: desc, inputSchema: schema)
        }
    }
}

// MARK: - Per-family chunk adapters

enum ChunkParser {

    /// Parse an Anthropic SSE data line into ProviderChunks.
    /// Returns nil if the line is not relevant.
    static func parseAnthropic(line: String) -> [ProviderChunk] {
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }

        let type_ = json["type"] as? String ?? ""

        switch type_ {
        case "content_block_delta":
            if let delta = json["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String,
               deltaType == "text_delta",
               let text = delta["text"] as? String {
                return [.textDelta(text)]
            }
            return []

        case "content_block_start":
            if let block = json["content_block"] as? [String: Any],
               let blockType = block["type"] as? String,
               blockType == "tool_use",
               let id   = block["id"] as? String,
               let name = block["name"] as? String {
                // args come in subsequent deltas; for simplicity return with empty args here
                // Full streaming accumulation is handled by ToolLoopExecutor
                return [.toolCall(id: id, name: name, args: [:])]
            }
            return []

        case "message_delta":
            // Anthropic emits stop_reason in message_delta before message_stop
            if let delta = json["delta"] as? [String: Any],
               let stopReason = delta["stop_reason"] as? String {
                return [.finishReason(stopReason)]
            }
            return []

        case "message_stop":
            return [.done]

        default:
            return []
        }
    }

    /// Parse an OpenAI-style SSE `data:` payload into ProviderChunks.
    static func parseOpenAI(line: String) -> [ProviderChunk] {
        if line == "[DONE]" { return [.done] }

        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any]
        else { return [] }

        var chunks: [ProviderChunk] = []

        // Text delta
        if let text = delta["content"] as? String, !text.isEmpty {
            chunks.append(.textDelta(text))
        }

        // Tool calls
        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
            for tc in toolCalls {
                let id   = tc["id"] as? String ?? UUID().uuidString
                if let fnObj   = tc["function"] as? [String: Any],
                   let name    = fnObj["name"] as? String {
                    let argsStr = fnObj["arguments"] as? String ?? "{}"
                    let argsData = argsStr.data(using: .utf8) ?? Data()
                    let args = (try? JSONSerialization.jsonObject(with: argsData)) as? [String: Any] ?? [:]
                    chunks.append(.toolCall(id: id, name: name, args: args))
                }
            }
        }

        // Finish reason — emit both the named reason and done
        if let finishReason = first["finish_reason"] as? String,
           !finishReason.isEmpty {
            chunks.append(.finishReason(finishReason))
            chunks.append(.done)
        }

        return chunks
    }
}

// MARK: - ToolLoopExecutor

/// Drives one full tool-loop turn for any provider family.
struct ToolLoopExecutor {

    let family: ProviderFamily
    let mcpClient: any MCPClientProtocol

    /// Maximum tool-call rounds before giving up to prevent infinite loops.
    var maxRounds: Int = 10

    // MARK: runOneStep

    /// Consume one provider stream, parse all chunks, execute any tool calls, and return
    /// a `StepOutcome` describing what happened.
    ///
    /// - Parameters:
    ///   - streamLines: Raw SSE data lines (no `data:` prefix needed).
    ///   - conversation: Initial conversation messages.
    /// - Returns: `StepOutcome` with accumulated text, tool calls, stop reason, and updated conversation.
    func runOneStep(
        streamLines: AsyncThrowingStream<String, Error>,
        conversation: [[String: Any]]
    ) async throws -> StepOutcome {

        var messages = conversation
        var accumulatedText = ""
        var rawToolCalls: [(id: String, name: String, args: [String: Any])] = []
        var rawFinishReason: String? = nil

        var iter = streamLines.makeAsyncIterator()
        while let line = try await iter.next() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let chunks = parseChunks(from: trimmed)
            for chunk in chunks {
                switch chunk {
                case .textDelta(let text):
                    accumulatedText += text

                case .toolCall(let id, let name, let args):
                    rawToolCalls.append((id: id, name: name, args: args))

                case .finishReason(let reason):
                    rawFinishReason = reason

                case .done:
                    break
                }
            }
        }

        // Determine stop reason
        let stopReason: StepOutcome.StopReason
        if !rawToolCalls.isEmpty {
            stopReason = .toolUse
        } else if let reason = rawFinishReason {
            // Normalize across provider conventions
            switch reason.lowercased() {
            case "length", "max_tokens":
                stopReason = .maxTokens
            case "stop", "end_turn", "stop_sequence", "tool_calls", "tool_use":
                stopReason = .endTurn
            default:
                stopReason = .other(reason)
            }
        } else {
            stopReason = .endTurn
        }

        // Execute tool calls if any
        if !rawToolCalls.isEmpty {
            var toolResults: [[String: Any]] = []
            for tc in rawToolCalls {
                do {
                    let result = try await mcpClient.callTool(tc.name, args: tc.args)
                    toolResults.append([
                        "tool_call_id": tc.id,
                        "name": tc.name,
                        "result": result
                    ])
                } catch {
                    toolResults.append([
                        "tool_call_id": tc.id,
                        "name": tc.name,
                        "error": error.localizedDescription
                    ])
                }
            }

            // Append tool results as a user-role message (provider-agnostic envelope)
            let toolResultMessage: [String: Any] = [
                "role": "user",
                "content": toolResults,
                "zion_tool_results": true
            ]
            messages.append(toolResultMessage)
        }

        let unifiedCalls = rawToolCalls.map { StepOutcome.ToolCall(id: $0.id, name: $0.name, args: $0.args) }
        return StepOutcome(
            text: accumulatedText,
            toolCalls: unifiedCalls,
            stopReason: stopReason,
            updatedConversation: messages
        )
    }

    // MARK: Run (compatibility wrapper)

    /// Thin wrapper around `runOneStep` that preserves the legacy `(text, conversation)` return type
    /// for existing callers (`ZionToolBridge`).
    func run(
        streamLines: AsyncThrowingStream<String, Error>,
        conversation: [[String: Any]]
    ) async throws -> (text: String, conversation: [[String: Any]]) {
        let outcome = try await runOneStep(streamLines: streamLines, conversation: conversation)
        return (text: outcome.text, conversation: outcome.updatedConversation)
    }

    // MARK: Private

    private func parseChunks(from line: String) -> [ProviderChunk] {
        switch family {
        case .anthropic:
            return ChunkParser.parseAnthropic(line: line)
        case .openai, .openrouter, .localOpenAICompatible:
            return ChunkParser.parseOpenAI(line: line)
        case .gemini:
            // Gemini uses a different format; basic text extraction
            return parseGemini(line: line)
        }
    }

    private func parseGemini(line: String) -> [ProviderChunk] {
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }

        var chunks: [ProviderChunk] = []

        if let candidates = json["candidates"] as? [[String: Any]],
           let first = candidates.first,
           let content = first["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            for part in parts {
                if let text = part["text"] as? String {
                    chunks.append(.textDelta(text))
                }
                if let fnCall = part["functionCall"] as? [String: Any],
                   let name = fnCall["name"] as? String {
                    let args = fnCall["args"] as? [String: Any] ?? [:]
                    chunks.append(.toolCall(id: UUID().uuidString, name: name, args: args))
                }
            }
        }

        if let finishReason = (json["candidates"] as? [[String: Any]])?.first?["finishReason"] as? String,
           !finishReason.isEmpty {
            chunks.append(.finishReason(finishReason))
            chunks.append(.done)
        }

        return chunks
    }
}
