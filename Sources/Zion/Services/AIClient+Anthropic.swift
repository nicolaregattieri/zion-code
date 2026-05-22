import Foundation

// MARK: - Anthropic Streaming with Tools

extension AIClient {

    /// Streams an Anthropic messages request with tool support.
    ///
    /// Parses SSE content_block_delta events, accumulating input_json_delta
    /// chunks per block index and emitting StreamEvents.
    func streamAnthropicWithTools(
        payload: AIPromptPayload,
        apiKey: String,
        tools: [[String: Any]],
        maxTokens: Int
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        // Pre-serialize tools before Task boundary to avoid non-Sendable [[String: Any]] capture
        var preBody = Self.anthropicRequestBody(payload: payload, maxTokens: maxTokens, modelID: "claude-3-5-sonnet-20241022")
        preBody["stream"] = true
        if !tools.isEmpty {
            preBody["tools"] = tools
        }
        let bodyData = (try? JSONSerialization.data(withJSONObject: preBody)) ?? Data()
        let session = _testURLSession ?? URLSession.shared

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "https://api.anthropic.com/v1/messages")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.timeoutInterval = 60

                    request.httpBody = bodyData
                    let (asyncBytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIError.invalidResponse)
                        return
                    }

                    switch http.statusCode {
                    case 200: break
                    case 401: continuation.finish(throwing: AIError.invalidKey); return
                    case 429: continuation.finish(throwing: AIError.quotaExceeded); return
                    case 503: continuation.finish(throwing: AIError.temporarilyUnavailable); return
                    default:
                        continuation.finish(throwing: AIError.apiError("Anthropic request failed (\(http.statusCode))."))
                        return
                    }

                    // Block state keyed by block index
                    struct BlockState {
                        var type: String        // "text" or "tool_use"
                        var name: String
                        var id: String
                        var argsBuffer: String
                    }
                    var blocks: [Int: BlockState] = [:]

                    for try await line in asyncBytes.lines {
                        guard let event = Self.parseAnthropicSSELine(line) else { continue }

                        switch event {
                        case let .contentBlockStart(index, blockType, id, name):
                            blocks[index] = BlockState(type: blockType, name: name, id: id, argsBuffer: "")
                            if blockType == "tool_use" {
                                continuation.yield(.toolCallStart(id: id, name: name))
                            }

                        case let .contentBlockDelta(index, deltaType, text, partialJSON):
                            if deltaType == "text_delta", let textVal = text, !textVal.isEmpty {
                                continuation.yield(.textDelta(textVal))
                            } else if deltaType == "input_json_delta", let chunk = partialJSON {
                                if var block = blocks[index] {
                                    block.argsBuffer += chunk
                                    blocks[index] = block
                                    continuation.yield(.toolCallArgsDelta(id: block.id, jsonChunk: chunk))
                                }
                            }

                        case let .contentBlockStop(index):
                            if let block = blocks[index], block.type == "tool_use" {
                                let argsData = block.argsBuffer.data(using: .utf8) ?? Data()
                                let args = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
                                continuation.yield(.toolCallComplete(id: block.id, name: block.name, arguments: args))
                                blocks.removeValue(forKey: index)
                            }

                        case .messageStop:
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        }
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - SSE Line Parser

    enum AnthropicSSEEvent {
        case contentBlockStart(index: Int, blockType: String, id: String, name: String)
        case contentBlockDelta(index: Int, deltaType: String, text: String?, partialJSON: String?)
        case contentBlockStop(index: Int)
        case messageStop
    }

    /// Parses a single SSE data line from the Anthropic streaming API.
    /// Returns nil for non-data lines and unrecognised event types.
    static func parseAnthropicSSELine(_ line: String) -> AnthropicSSEEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "data: "
        guard trimmed.hasPrefix(prefix) else { return nil }

        let payload = String(trimmed.dropFirst(prefix.count))
        guard let jsonData = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let type_ = json["type"] as? String else { return nil }

        switch type_ {
        case "content_block_start":
            guard let index = json["index"] as? Int,
                  let contentBlock = json["content_block"] as? [String: Any],
                  let blockType = contentBlock["type"] as? String else { return nil }
            let id = contentBlock["id"] as? String ?? ""
            let name = contentBlock["name"] as? String ?? ""
            return .contentBlockStart(index: index, blockType: blockType, id: id, name: name)

        case "content_block_delta":
            guard let index = json["index"] as? Int,
                  let delta = json["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else { return nil }
            let text = delta["text"] as? String
            let partialJSON = delta["partial_json"] as? String
            return .contentBlockDelta(index: index, deltaType: deltaType, text: text, partialJSON: partialJSON)

        case "content_block_stop":
            guard let index = json["index"] as? Int else { return nil }
            return .contentBlockStop(index: index)

        case "message_stop":
            return .messageStop

        default:
            return nil
        }
    }
}
