import Foundation

// MARK: - Anthropic SSE Stream Parsing

extension AIClient {

    /// Parses a single Anthropic SSE event from a streaming response.
    ///
    /// SSE format:
    /// ```
    /// event: content_block_delta
    /// data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
    /// ```
    ///
    /// Rules:
    /// - `message_start`, `content_block_start`, `content_block_stop`, `message_delta` → nil (ignored)
    /// - `content_block_delta` with `delta.type == "text_delta"` → LocalStreamChunk(text:, done: false)
    /// - `content_block_delta` with other delta types → nil
    /// - `message_stop` → LocalStreamChunk(text: "", done: true)
    /// - Malformed JSON → nil (no throw)
    /// - Unknown event → nil
    static func parseAnthropicSSEEvent(eventName: String, data: Data) -> LocalStreamChunk? {
        switch eventName {
        case "message_start", "content_block_start", "content_block_stop", "message_delta":
            return nil

        case "message_stop":
            return LocalStreamChunk(text: "", done: true)

        case "content_block_delta":
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let delta = json["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String,
                  deltaType == "text_delta",
                  let text = delta["text"] as? String else {
                return nil
            }
            return LocalStreamChunk(text: text, done: false)

        default:
            return nil
        }
    }

    // MARK: - Anthropic Streaming

    /// Streams an Anthropic claude model and yields text deltas via SSE.
    ///
    /// - Parameters:
    ///   - payload: The prompt payload to send.
    ///   - apiKey: Anthropic API key.
    ///   - maxTokens: Maximum tokens for the response.
    ///   - modelID: Model identifier string (e.g. "claude-3-5-sonnet-20241022").
    /// - Returns: An `AsyncThrowingStream` of text delta strings.
    func streamAnthropic(
        payload: AIPromptPayload,
        apiKey: String,
        maxTokens: Int,
        modelID: String
    ) -> AsyncThrowingStream<String, Error> {
        let session = _testURLSession ?? URLSession.shared
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "https://api.anthropic.com/v1/messages")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.timeoutInterval = 60

                    var body = Self.anthropicRequestBody(payload: payload, maxTokens: maxTokens, modelID: modelID)
                    body["stream"] = true
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (asyncBytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIError.invalidResponse)
                        return
                    }

                    switch http.statusCode {
                    case 200:
                        break
                    case 401, 403:
                        continuation.finish(throwing: AIError.localAPIError("Anthropic auth error (\(http.statusCode))."))
                        return
                    case 429:
                        continuation.finish(throwing: AIError.quotaExceeded)
                        return
                    default:
                        continuation.finish(throwing: AIError.localAPIError("Anthropic request failed (\(http.statusCode))."))
                        return
                    }

                    // Accumulate SSE event/data pairs.
                    // Dispatch when we see a blank line OR when a new event: line arrives
                    // while a prior complete event+data pair is pending.
                    var currentEvent = ""
                    var currentData = ""
                    var done = false

                    func dispatch() -> Bool {
                        guard !currentEvent.isEmpty, !currentData.isEmpty,
                              let dataBytes = currentData.data(using: .utf8),
                              let chunk = Self.parseAnthropicSSEEvent(eventName: currentEvent, data: dataBytes) else {
                            return false
                        }
                        if !chunk.text.isEmpty {
                            continuation.yield(chunk.text)
                        }
                        return chunk.done
                    }

                    for try await line in asyncBytes.lines {
                        if line.hasPrefix("event: ") {
                            // If we have a pending block, dispatch it first
                            if !currentEvent.isEmpty && !currentData.isEmpty {
                                if dispatch() { done = true; break }
                            }
                            currentEvent = String(line.dropFirst("event: ".count))
                            currentData = ""
                        } else if line.hasPrefix("data: ") {
                            currentData = String(line.dropFirst("data: ".count))
                        } else if line.isEmpty {
                            // Blank line = explicit end of SSE event block
                            if dispatch() { done = true; break }
                            currentEvent = ""
                            currentData = ""
                        }
                    }

                    // Dispatch any trailing block not followed by a blank line
                    if !done && !currentEvent.isEmpty && !currentData.isEmpty {
                        _ = dispatch()
                    }

                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
