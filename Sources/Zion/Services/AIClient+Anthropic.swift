import Foundation

// MARK: - Retry-After Header Parsing

extension AIClient {

    /// Parses the value of the `Retry-After` response header into a `TimeInterval`.
    ///
    /// Supports two formats per RFC 7231:
    /// - Integer string (e.g. "60") → seconds as `Double`.
    /// - HTTP-date string (e.g. "Wed, 21 Oct 2015 07:28:00 GMT") → seconds from now.
    ///
    /// Returns nil when the header is absent or unparseable.
    static func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // Integer form
        if let seconds = Double(trimmed) {
            return seconds
        }

        // HTTP-date form (RFC 7231 §7.1.3)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",   // preferred (IMF-fixdate)
            "EEEE, dd-MMM-yy HH:mm:ss zzz",     // RFC 850 (obsolete)
            "EEE MMM d HH:mm:ss yyyy",           // ANSI C asctime
        ]
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                let delta = date.timeIntervalSinceNow
                return delta > 0 ? delta : 0
            }
        }

        return nil
    }
}

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

                    let (asyncBytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (asyncBytes, response) = try await session.bytes(for: request)
                    } catch let urlError as URLError {
                        continuation.finish(throwing: AIError.networkFailure(underlying: urlError.localizedDescription))
                        return
                    }

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
                        continuation.finish(throwing: AIError.rateLimited(retryAfter: Self.parseRetryAfter(from: http)))
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
        maxTokens: Int,
        modelID: String = "claude-3-5-sonnet-20241022",
        additionalMessages: [[String: Any]] = []
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        // Pre-serialize tools before Task boundary to avoid non-Sendable [[String: Any]] capture
        var preBody = Self.anthropicRequestBodyWithMessages(
            payload: payload,
            maxTokens: maxTokens,
            modelID: modelID,
            additionalMessages: additionalMessages
        )
        preBody["stream"] = true
        if !tools.isEmpty {
            preBody["tools"] = tools
        }
        let bodyData = (try? JSONSerialization.data(withJSONObject: preBody)) ?? Data()
        return streamAnthropicWithTools(bodyData: bodyData, apiKey: apiKey)
    }

    /// Sendable-friendly entry point: caller hands over a fully-serialized
    /// JSON body (`Data` is Sendable), we drive the HTTP request and SSE
    /// parsing. Used by `ChatService.runAnthropicToolLoop` which needs to
    /// cross the actor boundary with `tools` + `additionalMessages` arrays
    /// that strict-concurrency cannot prove safe at the call site.
    func streamAnthropicWithToolsBody(
        bodyData: Data,
        apiKey: String
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return streamAnthropicWithTools(bodyData: bodyData, apiKey: apiKey)
    }

    private func streamAnthropicWithTools(
        bodyData: Data,
        apiKey: String
    ) -> AsyncThrowingStream<StreamEvent, Error> {
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
                    let (asyncBytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (asyncBytes, response) = try await session.bytes(for: request)
                    } catch let urlError as URLError {
                        continuation.finish(throwing: AIError.networkFailure(underlying: urlError.localizedDescription))
                        return
                    }

                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIError.invalidResponse)
                        return
                    }

                    switch http.statusCode {
                    case 200: break
                    case 401: continuation.finish(throwing: AIError.invalidKey); return
                    case 429: continuation.finish(throwing: AIError.rateLimited(retryAfter: Self.parseRetryAfter(from: http))); return
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
