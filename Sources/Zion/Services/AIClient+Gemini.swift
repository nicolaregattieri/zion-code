import Foundation

// MARK: - Gemini Types

/// Stop reason for a Gemini streaming step.
enum GeminiStopReason: Equatable {
    case toolUse
    case endTurn
    case maxTokens
    case other(String)

    static func == (lhs: GeminiStopReason, rhs: GeminiStopReason) -> Bool {
        switch (lhs, rhs) {
        case (.toolUse, .toolUse): return true
        case (.endTurn, .endTurn): return true
        case (.maxTokens, .maxTokens): return true
        case (.other(let a), .other(let b)): return a == b
        default: return false
        }
    }
}

/// A single function/tool call emitted by Gemini in a response.
struct GeminiToolCall: @unchecked Sendable {
    /// Synthetic unique ID (Gemini has no native call ID).
    let id: String
    let name: String
    let args: [String: Any]
}

/// Outcome of one Gemini streaming step.
/// T3 will unify StepOutcome across providers — this is the Gemini-local shape until then.
// T3 will unify StepOutcome
struct GeminiStepOutcome: @unchecked Sendable {
    let text: String
    let toolCalls: [GeminiToolCall]
    let stopReason: GeminiStopReason
    /// Full updated conversation history including the model's response appended.
    let updatedConversation: [[String: Any]]
}

// MARK: - AIClient+Gemini

extension AIClient {

    // MARK: - Public API

    /// Streams a single Gemini step with optional tool declarations.
    ///
    /// - Parameters:
    ///   - prompt: User text prompt.
    ///   - tools: Optional array of tool definitions matching Gemini's `functionDeclarations` schema.
    ///   - apiKey: Gemini API key.
    ///   - model: Model identifier (e.g. "gemini-1.5-pro").
    ///   - history: Prior conversation turns (`contents` array). Pass `[]` for a fresh conversation.
    /// - Returns: A `GeminiStepOutcome` with the accumulated text, tool calls, stop reason, and updated history.
    func streamGeminiWithTools(
        prompt: String,
        tools: [[String: Any]] = [],
        apiKey: String,
        model: String,
        history: [[String: Any]] = []
    ) async throws -> GeminiStepOutcome {
        guard let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):streamGenerateContent?alt=sse&key=\(apiKey)")
        else { throw AIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let userTurn: [String: Any] = [
            "role": "user",
            "parts": [["text": prompt]]
        ]
        var conversation = history
        conversation.append(userTurn)

        var body: [String: Any] = ["contents": conversation]
        if !tools.isEmpty {
            body["tools"] = [["functionDeclarations": tools]]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let session = _testURLSession ?? URLSession.shared
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw AIError.networkFailure(underlying: urlError.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        if http.statusCode == 400 || http.statusCode == 401 { throw AIError.invalidKey }
        if http.statusCode == 503 { throw AIError.temporarilyUnavailable }
        if http.statusCode == 429 { throw AIError.rateLimited(retryAfter: Self.parseRetryAfter(from: http)) }
        guard http.statusCode == 200 else {
            throw AIError.apiError("Gemini streaming request failed (\(http.statusCode)).")
        }

        let sseText = String(data: data, encoding: .utf8) ?? ""
        let outcome = Self.parseGeminiSSE(sseText, history: conversation)
        return outcome
    }

    // MARK: - Non-streaming (existing) Gemini call

    func callGemini(payload: AIPromptPayload, apiKey: String, maxTokens: Int, modelID: String) async throws -> String {
        guard let encodedModel = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent")
        else { throw AIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 30

        let body = Self.geminiRequestBody(payload: payload, maxTokens: maxTokens, modelID: modelID)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let session = _testURLSession ?? URLSession.shared
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw AIError.networkFailure(underlying: urlError.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }

        if http.statusCode == 400 || http.statusCode == 401 { throw AIError.invalidKey }
        if http.statusCode == 503 { throw AIError.temporarilyUnavailable }
        if http.statusCode == 429 { throw AIError.rateLimited(retryAfter: Self.parseRetryAfter(from: http)) }
        guard http.statusCode == 200 else {
            throw AIError.apiError("Gemini request failed (\(http.statusCode)).")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw AIError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tool Result Envelope

    /// Builds the `functionResponse` user turn to append after executing a tool call.
    ///
    /// ```json
    /// { "role": "user", "parts": [{ "functionResponse": { "name": "...", "response": { "content": "..." } } }] }
    /// ```
    static func geminiFunctionResponseTurn(name: String, content: String) -> [String: Any] {
        [
            "role": "user",
            "parts": [
                [
                    "functionResponse": [
                        "name": name,
                        "response": ["content": content]
                    ]
                ]
            ]
        ]
    }

    // MARK: - Context Caching (stub)

    /// TODO(P14): Wire explicit Gemini context caching API.
    ///
    /// Gemini supports explicit context caching via `models.cachedContents.create(...)` followed
    /// by reusing the `cacheId` in subsequent `generateContent` requests via `cachedContent: "name"`.
    /// This method is a placeholder — full implementation is deferred to Phase 14 when the stable
    /// context pipeline is complete and we have enough token volume to benefit from cache billing.
    ///
    /// - Parameters:
    ///   - payload: The prompt payload whose `stableContext` should be cached.
    ///   - apiKey: Gemini API key.
    ///   - model: Model identifier (e.g. "gemini-1.5-pro").
    /// - Returns: `nil` always until the implementation is wired.
    func enableGeminiContextCaching(payload: AIPromptPayload, apiKey: String, model: String) -> String? {
        // TODO(P14): call `POST /v1beta/cachedContents` with payload.stableContext,
        // store the returned cache name (e.g. "cachedContents/xyz"), and pass it as
        // `cachedContent: "cachedContents/xyz"` in subsequent generateContent requests.
        return nil
    }

    // MARK: - SSE Parser (internal for testing)

    /// Parses Gemini SSE response text into a `GeminiStepOutcome`.
    /// Exposed as `internal` so unit tests can exercise it without network.
    static func parseGeminiSSE(_ sseText: String, history: [[String: Any]]) -> GeminiStepOutcome {
        var accumulatedText = ""
        var toolCalls: [GeminiToolCall] = []
        var rawFinishReason = ""

        let lines = sseText.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let jsonString = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !jsonString.isEmpty,
                  let jsonData = jsonString.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any]
            else { continue }

            // Extract finish reason
            if let candidates = json["candidates"] as? [[String: Any]],
               let first = candidates.first {
                if let reason = first["finishReason"] as? String {
                    rawFinishReason = reason
                }
                if let content = first["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]] {
                    for part in parts {
                        if let text = part["text"] as? String {
                            accumulatedText += text
                        } else if let fc = part["functionCall"] as? [String: Any],
                                  let name = fc["name"] as? String {
                            let args = fc["args"] as? [String: Any] ?? [:]
                            let syntheticID = "gem-\(UUID().uuidString.lowercased().prefix(8))"
                            toolCalls.append(GeminiToolCall(id: syntheticID, name: name, args: args))
                        }
                    }
                }
            }
        }

        // Determine stop reason
        let stopReason: GeminiStopReason
        if !toolCalls.isEmpty {
            stopReason = .toolUse
        } else if rawFinishReason == "STOP" || rawFinishReason.isEmpty {
            stopReason = .endTurn
        } else if rawFinishReason == "MAX_TOKENS" {
            stopReason = .maxTokens
        } else {
            stopReason = .other(rawFinishReason)
        }

        // Build updated conversation: append model response
        var modelParts: [[String: Any]] = []
        if !accumulatedText.isEmpty {
            modelParts.append(["text": accumulatedText])
        }
        for call in toolCalls {
            modelParts.append([
                "functionCall": [
                    "name": call.name,
                    "args": call.args
                ]
            ])
        }
        var updatedConversation = history
        if !modelParts.isEmpty {
            updatedConversation.append([
                "role": "model",
                "parts": modelParts
            ])
        }

        return GeminiStepOutcome(
            text: accumulatedText,
            toolCalls: toolCalls,
            stopReason: stopReason,
            updatedConversation: updatedConversation
        )
    }
}
