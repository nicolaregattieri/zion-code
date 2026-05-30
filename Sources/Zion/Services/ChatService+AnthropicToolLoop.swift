import Foundation

/// Phase 6.6 — native Anthropic tool-use loop.
///
/// `dispatchStreamThrowing.case .anthropic` historically called the
/// tool-less `streamAnthropic`, so the model never saw the MCP toolbox.
/// This loop swaps in `streamAnthropicWithTools` + a tool_use → dispatch
/// → tool_result resume cycle so user-installed MCPs and built-in tools
/// become callable inside the chat.
///
/// Gated behind `chat.nativeToolLoop.enabled` (default OFF) until the
/// behavior is validated across providers. When OFF, the legacy
/// tool-less stream path is used.
@MainActor
extension ChatService {

    nonisolated static let nativeToolLoopFlagKey = "chat.nativeToolLoop.enabled"

    nonisolated static var nativeToolLoopEnabled: Bool {
        UserDefaults.standard.bool(forKey: nativeToolLoopFlagKey)
    }

    /// Hard cap on tool-use rounds per assistant turn. Anthropic chains
    /// can in theory loop indefinitely; bound it so a misbehaving model
    /// or pool cannot stall the UI.
    private static let maxToolLoopRounds: Int = 8

    /// Runs the Anthropic tool-use loop until the model stops calling
    /// tools or we hit `maxToolLoopRounds`. Drives token append into
    /// the assistant bubble via the existing setters, dispatches tool
    /// calls via `MCPConfigBuilder.dispatch`, carries tool_use / tool_result
    /// blocks across rounds so the model picks up its own context.
    func runAnthropicToolLoop(
        payload: AIPromptPayload,
        apiKey: String,
        modelID: String,
        maxTokens: Int,
        assistantID: UUID,
        threadID: UUID,
        provider: AIProvider
    ) async throws {
        await MCPClientPool.shared.warmFromDisk()
        let toolDescriptors = await MCPConfigBuilder.allToolsIncludingUserServers(
            store: MCPRegistryStore()
        )
        await self.surfaceMCPWarmErrorsIfAny()
        await self.refreshMCPRoutingInstructions()
        let anthropicTools = ToolSchemaTranslator.translate(toolDescriptors, for: .anthropic)

        var additionalMessages: [[String: Any]] = []
        var round = 0

        while round < Self.maxToolLoopRounds {
            round += 1

            // Serialize the full request body locally — Data is Sendable
            // and the actor entry point accepts it as-is, sidestepping the
            // [[String: Any]] cross-actor barrier under strict concurrency.
            let bodyData = Self.buildAnthropicBody(
                payload: payload,
                modelID: modelID,
                maxTokens: maxTokens,
                tools: anthropicTools,
                additionalMessages: additionalMessages
            )
            let stream = await self.ai.streamAnthropicWithToolsBody(
                bodyData: bodyData,
                apiKey: apiKey
            )

            var assistantContentBlocks: [[String: Any]] = []
            var pendingTextThisRound: String = ""
            var pendingToolCalls: [(id: String, name: String, args: [String: Any])] = []

            for try await event in stream {
                switch event {
                case .textDelta(let chunk):
                    pendingTextThisRound += chunk
                    self.appendAssistantDelta(id: assistantID, delta: chunk)

                case .toolCallStart:
                    // Flush any accumulated text into an assistant text block
                    // BEFORE the tool_use block lands, so the assistant message
                    // we hand back to Anthropic preserves order.
                    if !pendingTextThisRound.isEmpty {
                        assistantContentBlocks.append([
                            "type": "text",
                            "text": pendingTextThisRound
                        ])
                        pendingTextThisRound = ""
                    }

                case .toolCallArgsDelta:
                    break

                case .toolCallComplete(let id, let name, let args):
                    pendingToolCalls.append((id: id, name: name, args: args))
                    assistantContentBlocks.append([
                        "type": "tool_use",
                        "id": id,
                        "name": name,
                        "input": args
                    ])

                case .done:
                    break
                }
            }

            if !pendingTextThisRound.isEmpty {
                assistantContentBlocks.append([
                    "type": "text",
                    "text": pendingTextThisRound
                ])
            }

            if pendingToolCalls.isEmpty {
                // Model finished — no tools to run, exit loop.
                return
            }

            // Append the assistant turn (with tool_use blocks) so the next
            // request carries the conversation forward.
            additionalMessages.append([
                "role": "assistant",
                "content": assistantContentBlocks
            ])

            // Dispatch each tool call and assemble a single user message
            // carrying all tool_result blocks (Anthropic protocol).
            var toolResultBlocks: [[String: Any]] = []
            for call in pendingToolCalls {
                let result: String
                let isError: Bool
                let argsJSON = (try? JSONSerialization.data(withJSONObject: call.args)) ?? Data("{}".utf8)
                do {
                    result = try await MCPConfigBuilder.dispatch(name: call.name, argsJSON: argsJSON)
                    isError = false
                } catch {
                    result = "[tool error: \(error.localizedDescription)]"
                    isError = true
                }
                var block: [String: Any] = [
                    "type": "tool_result",
                    "tool_use_id": call.id,
                    "content": result
                ]
                if isError { block["is_error"] = true }
                toolResultBlocks.append(block)
            }
            additionalMessages.append([
                "role": "user",
                "content": toolResultBlocks
            ])
            // Loop: re-invoke stream with the extended message list.
        }

        // Hit the round cap — surface a soft notice so the user knows
        // we bailed out of the loop. The assistant bubble already has
        // whatever text the model wrote across rounds.
        self.appendAssistantDelta(
            id: assistantID,
            delta: "\n\n[tool loop capped at \(Self.maxToolLoopRounds) rounds]"
        )
    }

    nonisolated static func buildAnthropicBody(
        payload: AIPromptPayload,
        modelID: String,
        maxTokens: Int,
        tools: [[String: Any]],
        additionalMessages: [[String: Any]]
    ) -> Data {
        var body = AIClient.anthropicRequestBodyWithMessages(
            payload: payload,
            maxTokens: maxTokens,
            modelID: modelID,
            additionalMessages: additionalMessages
        )
        body["stream"] = true
        if !tools.isEmpty { body["tools"] = tools }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
}
