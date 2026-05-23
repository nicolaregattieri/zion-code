// ReActTextRunner.swift — Text-format ReAct fallback for local models that don't support tool_use.
//
// Mirrors the public surface of ToolLoopRunner for swap-compatibility.
// Uses a strict system prompt instructing THOUGHT/ACTION/OBSERVATION format.
//
// Note: the ACTION regex `({[^)]+})` is intentionally naive — it fails on nested braces.
// Local ReAct models are instructed to emit flat JSON only (no nested objects). v1 accepted limitation.
//
// Implemented as a `final class` (not an `actor`) mirroring ToolLoopRunner's concurrency contract.
// Internal state (textStreamFactory, mcpClient) is set once at init and never mutated.

import Foundation

// MARK: - TextStreamFactory

/// Injectable stream factory for ReAct. Returns a stream of text deltas (same shape as streamLocalLLM).
/// T6 — exposed for ReAct injection; `internal` so tests can substitute scripted streams.
typealias TextStreamFactory = @Sendable (
    [[String: Any]]  // conversation (messages array)
) async throws -> AsyncThrowingStream<String, Error>

// MARK: - ReActTextRunner

final class ReActTextRunner: @unchecked Sendable {

    // MARK: - Dependencies

    private let textStreamFactory: TextStreamFactory
    private let mcpClient: any MCPClientProtocol

    // MARK: - Init

    init(
        textStreamFactory: @escaping TextStreamFactory,
        mcpClient: any MCPClientProtocol
    ) {
        self.textStreamFactory = textStreamFactory
        self.mcpClient = mcpClient
    }

    // MARK: - Run

    /// Executes the ReAct text-format loop until ANSWER, maxSteps/2, 3 parse failures, or cancelled.
    ///
    /// - Parameters:
    ///   - provider:             The AI provider (must resolve to .reactTextFallback or .passthrough).
    ///   - model:                Optional model identifier string.
    ///   - conversation:         Initial conversation as raw message dictionaries.
    ///   - tools:                Tool descriptors available to the model.
    ///   - maxSteps:             Hard ceiling; ReAct loop caps at maxSteps/2 to control runaway.
    ///   - budgetCap:            Maximum cumulative cost in USD (0 = unlimited, placeholder for future).
    ///   - cancel:               CancellationToken polled at top of each iteration.
    ///   - onStep:               Callback fired on the MainActor after each completed step.
    /// - Returns: `LoopResult` summarising the run.
    func run(
        provider: AIProvider,
        model: String?,
        conversation initialConversation: [[String: Any]],
        tools: [MCPToolDescriptor],
        maxSteps: Int = 25,
        budgetCap: Double = 0,
        cancel: CancellationToken,
        onStep: @escaping @MainActor @Sendable (AgentStepEvent) -> Void
    ) async throws -> LoopResult {

        let halfMax = max(1, maxSteps / 2)
        var consecutiveParseFailures = 0
        var stepCount = 0

        // Prepend ReAct system prompt to conversation
        var conversation = Self.buildSystemPrompt(tools: tools) + initialConversation

        while true {
            // --- Guard conditions ---
            if await cancel.isCancelled {
                return LoopResult(
                    finalText: "",
                    stepsUsed: stepCount,
                    stopReason: .cancelled,
                    cumulativeTokens: 0,
                    cumulativeCostUSD: 0,
                    cancelled: true,
                    conversation: conversation
                )
            }
            if stepCount >= halfMax {
                return LoopResult(
                    finalText: "",
                    stepsUsed: stepCount,
                    stopReason: .maxStepsReached,
                    cumulativeTokens: 0,
                    cumulativeCostUSD: 0,
                    cancelled: false,
                    conversation: conversation
                )
            }

            // --- Stream and drain ---
            let stream = try await textStreamFactory(conversation)
            let fullText = try await Self.drainStream(stream)

            // --- Try ACTION ---
            if let (toolName, argsDict) = Self.parseAction(fullText) {
                consecutiveParseFailures = 0
                let toolResult: String
                do {
                    let resultDict = try await mcpClient.callTool(toolName, args: argsDict)
                    // Serialize result dict to compact JSON string for OBSERVATION
                    if let data = try? JSONSerialization.data(withJSONObject: resultDict, options: []),
                       let str = String(data: data, encoding: .utf8) {
                        toolResult = str
                    } else {
                        toolResult = "\(resultDict)"
                    }
                } catch {
                    toolResult = "error: \(error.localizedDescription)"
                }
                conversation.append(["role": "assistant", "content": fullText])
                conversation.append(["role": "user", "content": "OBSERVATION: \(toolResult)"])
                stepCount += 1

                // Fire step callback
                let stepEvent = AgentStepEvent(
                    toolEvent: ChatToolEvent(
                        id: UUID().uuidString,
                        name: toolName,
                        status: .completed,
                        argsPreview: String("\(argsDict)".prefix(60))
                    ),
                    stepIndex: stepCount,
                    cumulativeTokens: 0,
                    cumulativeCostUSD: 0
                )
                await onStep(stepEvent)
                continue
            }

            // --- Try ANSWER ---
            if let answer = Self.parseAnswer(fullText) {
                return LoopResult(
                    finalText: answer,
                    stepsUsed: stepCount,
                    stopReason: .endTurn,
                    cumulativeTokens: 0,
                    cumulativeCostUSD: 0,
                    cancelled: false,
                    conversation: conversation
                )
            }

            // --- Parse failure ---
            consecutiveParseFailures += 1
            if consecutiveParseFailures >= 3 {
                throw AIError.reactParseFailed
            }
            // Inject reflection prompt (does NOT count as a step)
            conversation.append(["role": "assistant", "content": fullText])
            conversation.append([
                "role": "user",
                "content": """
                Your last response did not match the required format. You MUST emit either:

                THOUGHT: ...
                ACTION: tool_name({"key":"value"})

                or

                THOUGHT: ...
                ANSWER: ...

                Reply only with the correct format.
                """
            ])
        }
    }

    // MARK: - System Prompt Builder

    static func buildSystemPrompt(tools: [MCPToolDescriptor]) -> [[String: Any]] {
        var toolsList = ""
        if tools.isEmpty {
            toolsList = "(no tools available)"
        } else {
            toolsList = tools.map { tool in
                var desc = "- \(tool.name): \(tool.description)"
                if let data = try? JSONSerialization.data(withJSONObject: tool.inputSchema, options: []),
                   let str = String(data: data, encoding: .utf8) {
                    desc += "\n  schema: \(str)"
                }
                return desc
            }.joined(separator: "\n")
        }

        let prompt = """
        You are a coding agent operating in ReAct mode. For every step, respond using EXACTLY this format:

        THOUGHT: <your reasoning>
        ACTION: <tool_name>({"key":"value"})

        After each ACTION, you will receive:

        OBSERVATION: <result>

        When you are done, respond with:

        THOUGHT: <final reasoning>
        ANSWER: <final answer to the user>

        Available tools:
        \(toolsList)

        Rules:
        - ACTION must be on its own line and match the format exactly: ACTION: tool_name({json})
        - JSON args MUST be valid JSON. No trailing commas. Quoted keys and string values.
        - Do NOT explain after ACTION — just emit it and wait for OBSERVATION.
        - One ACTION per turn.
        """
        return [["role": "system", "content": prompt]]
    }

    // MARK: - Parsers

    /// Extracts (toolName, argsDict) from text matching `ACTION: tool_name({"key":"value"})`.
    /// NOTE: regex `{[^)]+}` does not handle nested braces — intentional v1 limitation.
    static func parseAction(_ text: String) -> (tool: String, argsJSON: [String: Any])? {
        let pattern = #"ACTION:\s*(\w+)\((\{[^)]+\})\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let toolRange = Range(match.range(at: 1), in: text),
              let jsonRange = Range(match.range(at: 2), in: text) else { return nil }
        let toolName = String(text[toolRange])
        let jsonString = String(text[jsonRange])
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil  // JSON parse failure = parse failure, caller increments counter
        }
        return (toolName, json)
    }

    /// Extracts the answer text from `ANSWER: <text>` (captures to end of line, multiline).
    static func parseAnswer(_ text: String) -> String? {
        let pattern = #"ANSWER:\s*(.+)"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let answerRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[answerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Stream drain

    /// Collects all text chunks from the stream into a single String.
    static func drainStream(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var result = ""
        for try await chunk in stream {
            result += chunk
        }
        return result
    }
}
