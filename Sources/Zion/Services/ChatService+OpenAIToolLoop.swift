import Foundation

/// Phase 6.7 — native OpenAI / local (OpenAI-compatible) tool loop.
/// Same shape as the Anthropic loop in ChatService+AnthropicToolLoop:
/// stream → tool_use → dispatch → tool_result → re-invoke until the
/// model stops calling tools or we hit `maxToolLoopRounds`.
@MainActor
extension ChatService {

    private static let openAIMaxToolLoopRounds: Int = 8

    func runOpenAICompatToolLoop(
        payload: AIPromptPayload,
        apiKey: String,
        modelID: String,
        maxTokens: Int,
        url: URL,
        authField: String?,
        authValue: String?,
        urlSession: URLSession,
        assistantID: UUID
    ) async throws {
        await MCPClientPool.shared.warmFromDisk()
        let toolDescriptors = await MCPConfigBuilder.allToolsIncludingUserServers(
            store: MCPRegistryStore()
        )
        await self.surfaceMCPWarmErrorsIfAny()
        await self.refreshMCPRoutingInstructions()
        let openAITools = ToolSchemaTranslator.translate(toolDescriptors, for: .openai)

        var additionalMessages: [[String: Any]] = []
        var round = 0

        while round < Self.openAIMaxToolLoopRounds {
            round += 1

            let bodyData = Self.buildOpenAIBody(
                payload: payload,
                modelID: modelID,
                maxTokens: maxTokens,
                tools: openAITools,
                additionalMessages: additionalMessages
            )
            let stream = await self.ai.streamOpenAICompatWithToolsBody(
                url: url,
                authField: authField,
                authValue: authValue,
                bodyData: bodyData,
                urlSession: urlSession
            )

            var assistantText: String = ""
            // OpenAI's tool_calls block on the assistant message carries an
            // ordered array — we accumulate id/name/args here and emit one
            // assistant message after the stream finishes.
            var toolCalls: [(id: String, name: String, args: [String: Any])] = []

            for try await event in stream {
                switch event {
                case .textDelta(let chunk):
                    assistantText += chunk
                    self.appendAssistantDelta(id: assistantID, delta: chunk)
                case .toolCallStart, .toolCallArgsDelta:
                    break
                case .toolCallComplete(let id, let name, let args):
                    toolCalls.append((id: id, name: name, args: args))
                case .done:
                    break
                }
            }

            if toolCalls.isEmpty {
                return
            }

            // Emit assistant turn carrying tool_calls so the next request
            // satisfies OpenAI's protocol: each `tool` message must follow
            // an assistant turn that contains the matching `tool_call_id`.
            let toolCallsBlocks: [[String: Any]] = toolCalls.map { call in
                let argsJSON = (try? JSONSerialization.data(withJSONObject: call.args)).flatMap {
                    String(data: $0, encoding: .utf8)
                } ?? "{}"
                return [
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": argsJSON
                    ] as [String: Any]
                ]
            }
            var assistantMsg: [String: Any] = [
                "role": "assistant",
                "tool_calls": toolCallsBlocks
            ]
            if !assistantText.isEmpty { assistantMsg["content"] = assistantText }
            additionalMessages.append(assistantMsg)

            // Dispatch each call and emit one `tool` role message per result.
            for call in toolCalls {
                let result: String
                // Encode args as Data so the dispatch boundary stays Sendable
                // under strict concurrency. dispatch(argsJSON:) decodes inside.
                let argsJSON = (try? JSONSerialization.data(withJSONObject: call.args)) ?? Data("{}".utf8)
                do {
                    result = try await MCPConfigBuilder.dispatch(name: call.name, argsJSON: argsJSON)
                } catch {
                    result = "[tool error: \(error.localizedDescription)]"
                }
                additionalMessages.append([
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": result
                ])
            }
        }

        self.appendAssistantDelta(
            id: assistantID,
            delta: "\n\n[tool loop capped at \(Self.openAIMaxToolLoopRounds) rounds]"
        )
    }

    /// Local provider wrapper — same OpenAI-compat shape, no auth, URL
    /// from `LocalLLMConfig`. Reuses `runOpenAICompatToolLoop`.
    func runLocalNativeToolLoop(
        payload: AIPromptPayload,
        assistantID: UUID
    ) async throws {
        let config = AIClient.loadLocalConfig() ?? LocalLLMConfig()
        let modelID = config.modelName.isEmpty ? LocalLLMConfig().modelName : config.modelName
        if config.autoStartEnabled, streamProvider == nil, !localSessionSuppressed {
            await ensureLocalServerRunning(config: config, assistantID: assistantID)
        }
        // `serverURL` already carries the `/v1` suffix; append the completions path.
        guard let url = URL(string: config.serverURL + "/chat/completions") else {
            self.appendAssistantDelta(id: assistantID, delta: "[local: invalid serverURL]")
            return
        }
        try await runOpenAICompatToolLoop(
            payload: payload,
            apiKey: "",
            modelID: modelID,
            maxTokens: 2048,
            url: url,
            authField: nil,
            authValue: nil,
            urlSession: URLSession.shared,
            assistantID: assistantID
        )
    }

    nonisolated static func buildOpenAIBody(
        payload: AIPromptPayload,
        modelID: String,
        maxTokens: Int,
        tools: [[String: Any]],
        additionalMessages: [[String: Any]]
    ) -> Data {
        var body = AIClient.openAIRequestBodyWithMessages(
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
