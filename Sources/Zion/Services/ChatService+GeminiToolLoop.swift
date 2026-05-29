import Foundation

/// Phase 6.7 — native Gemini tool loop.
///
/// Gemini already exposes a step-friendly API (`streamGeminiWithTools`
/// returns `GeminiStepOutcome` with `updatedConversation`). We just need
/// to drive the loop: dispatch → append functionResponse part → re-step
/// with empty prompt + the carried history until `stopReason != .toolUse`.
@MainActor
extension ChatService {

    private static let geminiMaxToolLoopRounds: Int = 8

    func runGeminiToolLoop(
        payload: AIPromptPayload,
        apiKey: String,
        modelID: String,
        assistantID: UUID
    ) async throws {
        let toolDescriptors = await MCPConfigBuilder.allToolsIncludingUserServers(
            store: MCPRegistryStore()
        )
        let geminiTools = ToolSchemaTranslator.translate(toolDescriptors, for: .gemini)

        // First step: send the rendered user prompt with no history. Empty
        // string at the actor boundary is Sendable. We re-use renderUserMessage
        // via the existing API path: streamGeminiWithTools(prompt:) takes raw
        // text and wraps it as the user turn.
        let initialPrompt = AIClient.renderUserMessageForGemini(payload: payload)
        var history: [[String: Any]] = []
        var round = 0
        var lastText: String = ""

        while round < Self.geminiMaxToolLoopRounds {
            round += 1

            // On round 1 we still need the initial user prompt; subsequent
            // rounds carry only the appended functionResponse parts in history.
            var contents = history
            if round == 1, !initialPrompt.isEmpty {
                contents.append([
                    "role": "user",
                    "parts": [["text": initialPrompt]]
                ])
            }
            let bodyData = Self.buildGeminiBody(
                contents: contents,
                tools: geminiTools
            )
            let turn: GeminiModelTurn
            do {
                turn = try await self.ai.streamGeminiWithToolsBody(
                    bodyData: bodyData,
                    apiKey: apiKey,
                    model: modelID
                )
            } catch {
                throw error
            }

            // Stitch the model's turn onto our local history so the next
            // round (if any) sees it.
            history = contents + turn.modelTurnMessages

            // Stream new text into the assistant bubble. Gemini does not give
            // per-token deltas, so we surface the per-step accumulated text.
            if !turn.text.isEmpty && turn.text != lastText {
                let delta = String(turn.text.dropFirst(lastText.count))
                if !delta.isEmpty {
                    self.appendAssistantDelta(id: assistantID, delta: delta)
                }
                lastText = turn.text
            }

            switch turn.stopReason {
            case .endTurn, .maxTokens, .other:
                return
            case .toolUse:
                // Dispatch every tool call, append each result as a `user`
                // turn with a `functionResponse` part (Gemini protocol).
                for call in turn.toolCalls {
                    let result: String
                    let argsJSON = (try? JSONSerialization.data(withJSONObject: call.args)) ?? Data("{}".utf8)
                    do {
                        result = try await MCPConfigBuilder.dispatch(name: call.name, argsJSON: argsJSON)
                    } catch {
                        result = "[tool error: \(error.localizedDescription)]"
                    }
                    history.append([
                        "role": "user",
                        "parts": [[
                            "functionResponse": [
                                "name": call.name,
                                "response": ["result": result]
                            ] as [String: Any]
                        ]]
                    ])
                }
            }
        }

        self.appendAssistantDelta(
            id: assistantID,
            delta: "\n\n[tool loop capped at \(Self.geminiMaxToolLoopRounds) rounds]"
        )
    }

    nonisolated static func buildGeminiBody(
        contents: [[String: Any]],
        tools: [[String: Any]]
    ) -> Data {
        var body: [String: Any] = ["contents": contents]
        if !tools.isEmpty {
            body["tools"] = [["functionDeclarations": tools]]
        }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
}

// MARK: - Gemini prompt renderer

extension AIClient {
    /// Renders the user-facing prompt block for Gemini's `parts[].text`
    /// shape. Mirrors the body that `geminiRequestBody` builds for the
    /// non-streaming call so the model sees the same task instructions.
    nonisolated static func renderUserMessageForGemini(payload: AIPromptPayload) -> String {
        var out = ""
        if !payload.taskInstructions.isEmpty {
            out += "Task instructions:\n"
            out += payload.taskInstructions
            out += "\n\n"
        }
        for section in payload.untrustedSections {
            out += section.label + ":\n"
            out += section.content
            out += "\n\n"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
