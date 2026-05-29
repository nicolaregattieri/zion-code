import Foundation

// MARK: - OpenAI Cloud Streaming

extension AIClient {

    /// Streams an OpenAI model and yields text deltas via SSE.
    ///
    /// - Parameters:
    ///   - payload: The prompt payload to send.
    ///   - apiKey: OpenAI API key.
    ///   - maxTokens: Maximum tokens for the response.
    ///   - modelID: Model identifier string (e.g. "gpt-4o").
    /// - Returns: An `AsyncThrowingStream` of text delta strings.
    func streamOpenAI(
        payload: AIPromptPayload,
        apiKey: String,
        maxTokens: Int,
        modelID: String
    ) -> AsyncThrowingStream<String, Error> {
        let session = _testURLSession ?? URLSession.shared
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "https://api.openai.com/v1/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.timeoutInterval = 60

                    var body = Self.openAIRequestBody(payload: payload, maxTokens: maxTokens, modelID: modelID)
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
                        continuation.finish(throwing: AIError.localAPIError("OpenAI auth error (\(http.statusCode))."))
                        return
                    case 429:
                        continuation.finish(throwing: AIError.rateLimited(retryAfter: Self.parseRetryAfter(from: http)))
                        return
                    default:
                        continuation.finish(throwing: AIError.localAPIError("OpenAI request failed (\(http.statusCode))."))
                        return
                    }

                    for try await line in asyncBytes.lines {
                        guard let chunk = Self.parseOpenAISSELine(Data(line.utf8)) else { continue }
                        if !chunk.text.isEmpty {
                            continuation.yield(chunk.text)
                        }
                        if chunk.done { break }
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
// MARK: - OpenAI Streaming with Tools

extension AIClient {

    /// Streams an OpenAI chat completions request with tool support.
    ///
    /// Parses SSE choices[0].delta events, accumulating tool_calls argument
    /// chunks per tool call index and emitting StreamEvents.
    func streamOpenAIWithTools(
        payload: AIPromptPayload,
        apiKey: String,
        tools: [[String: Any]],
        maxTokens: Int
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        return streamOpenAICompatWithTools(
            payload: payload,
            url: url,
            authHeader: ("Authorization", "Bearer \(apiKey)"),
            tools: tools,
            maxTokens: maxTokens,
            modelID: "gpt-4o",
            urlSession: _testURLSession ?? URLSession.shared
        )
    }

    // MARK: - Shared OpenAI-compat streaming core

    /// Internal helper used by both streamOpenAIWithTools and streamLocalWithTools.
    /// Sendable-friendly entry — caller passes a fully serialized body
    /// (`Data` is Sendable) so the native tool loop can re-invoke the
    /// stream with assistant + tool result messages appended without
    /// crossing `[[String: Any]]` across the actor barrier.
    func streamOpenAICompatWithToolsBody(
        url: URL,
        authField: String?,
        authValue: String?,
        bodyData: Data,
        urlSession: URLSession
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return streamOpenAICompatWithToolsImpl(
            url: url,
            authField: authField,
            authValue: authValue,
            bodyData: bodyData,
            urlSession: urlSession
        )
    }

    func streamOpenAICompatWithTools(
        payload: AIPromptPayload,
        url: URL,
        authHeader: (field: String, value: String)?,
        tools: [[String: Any]],
        maxTokens: Int,
        modelID: String,
        urlSession: URLSession
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        // Serialize tools and extract auth fields before Task boundary to avoid
        // non-Sendable [[String: Any]] and tuple captures in Swift 6 strict concurrency.
        let authField: String? = authHeader?.field
        let authValue: String? = authHeader?.value
        // Pre-build the request body so [[String: Any]] does not cross the Sendable boundary
        var preBody = Self.openAIRequestBody(payload: payload, maxTokens: maxTokens, modelID: modelID)
        preBody["stream"] = true
        if !tools.isEmpty {
            preBody["tools"] = tools
        }
        let bodyData = (try? JSONSerialization.data(withJSONObject: preBody)) ?? Data()
        return streamOpenAICompatWithToolsImpl(
            url: url,
            authField: authField,
            authValue: authValue,
            bodyData: bodyData,
            urlSession: urlSession
        )
    }

    private func streamOpenAICompatWithToolsImpl(
        url: URL,
        authField: String?,
        authValue: String?,
        bodyData: Data,
        urlSession: URLSession
    ) -> AsyncThrowingStream<StreamEvent, Error> {

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 60

                    if let field = authField, let value = authValue {
                        request.setValue(value, forHTTPHeaderField: field)
                    }

                    request.httpBody = bodyData

                    let (asyncBytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (asyncBytes, response) = try await urlSession.bytes(for: request)
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
                        continuation.finish(throwing: AIError.apiError("OpenAI-compat request failed (\(http.statusCode))."))
                        return
                    }

                    // Tool call accumulator keyed by tool call index
                    struct ToolAccumulator {
                        var id: String
                        var name: String
                        var argsBuffer: String
                    }
                    var toolAccumulators: [Int: ToolAccumulator] = [:]

                    for try await line in asyncBytes.lines {
                        guard let event = Self.parseOpenAIToolSSELine(line) else { continue }

                        switch event {
                        case let .textDelta(text):
                            if !text.isEmpty {
                                continuation.yield(.textDelta(text))
                            }

                        case let .toolCallChunk(index, id, name, argsChunk):
                            if var acc = toolAccumulators[index] {
                                // Continuation chunk — accumulate args
                                acc.argsBuffer += argsChunk
                                toolAccumulators[index] = acc
                                if !argsChunk.isEmpty {
                                    continuation.yield(.toolCallArgsDelta(id: acc.id, jsonChunk: argsChunk))
                                }
                            } else {
                                // First chunk for this tool call index — initialise
                                let startID = id ?? ""
                                let startName = name ?? ""
                                toolAccumulators[index] = ToolAccumulator(id: startID, name: startName, argsBuffer: argsChunk)
                                if !startID.isEmpty || !startName.isEmpty {
                                    continuation.yield(.toolCallStart(id: startID, name: startName))
                                }
                                if !argsChunk.isEmpty {
                                    continuation.yield(.toolCallArgsDelta(id: startID, jsonChunk: argsChunk))
                                }
                            }

                        case .finishToolCalls:
                            // Emit toolCallComplete for each accumulated tool call, in index order
                            for idx in toolAccumulators.keys.sorted() {
                                let acc = toolAccumulators[idx]!
                                let argsData = acc.argsBuffer.data(using: .utf8) ?? Data()
                                let args = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
                                continuation.yield(.toolCallComplete(id: acc.id, name: acc.name, arguments: args))
                            }
                            toolAccumulators.removeAll()

                        case .done:
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

    enum OpenAIToolSSEEvent {
        case textDelta(String)
        case toolCallChunk(index: Int, id: String?, name: String?, argsChunk: String)
        case finishToolCalls
        case done
    }

    /// Parses a single SSE data line from the OpenAI (or compat) streaming API.
    /// Returns nil for non-data lines and unrecognised payloads.
    static func parseOpenAIToolSSELine(_ line: String) -> OpenAIToolSSEEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "data: "
        guard trimmed.hasPrefix(prefix) else { return nil }

        let payload = String(trimmed.dropFirst(prefix.count))

        if payload == "[DONE]" { return .done }

        guard let jsonData = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first else { return nil }

        // Check finish_reason first
        if let finishReason = firstChoice["finish_reason"] as? String,
           finishReason == "tool_calls" {
            return .finishToolCalls
        }

        guard let delta = firstChoice["delta"] as? [String: Any] else { return nil }

        // Text content
        if let content = delta["content"] as? String {
            return .textDelta(content)
        }

        // Tool calls
        if let toolCalls = delta["tool_calls"] as? [[String: Any]],
           let firstToolCall = toolCalls.first {
            let index = firstToolCall["index"] as? Int ?? 0
            let id = firstToolCall["id"] as? String
            let name = (firstToolCall["function"] as? [String: Any])?["name"] as? String
            let argsChunk = (firstToolCall["function"] as? [String: Any])?["arguments"] as? String ?? ""
            return .toolCallChunk(index: index, id: id, name: name, argsChunk: argsChunk)
        }

        return nil
    }
}
