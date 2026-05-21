import Foundation

// MARK: - Local LLM SSE Stream Parsing

extension AIClient {

    // MARK: - Types

    struct LocalStreamChunk {
        let text: String
        let done: Bool
    }

    // MARK: - SSE Parser

    /// Parses a single SSE line from an OpenAI-compatible streaming response.
    ///
    /// Rules:
    /// - Returns nil for empty lines and SSE comment lines (starting with `:`)
    /// - Returns nil for lines not starting with `data: `
    /// - Returns chunk with done=true for the `[DONE]` sentinel
    /// - Decodes `choices[0].delta.content` as text
    /// - Non-null `choices[0].finish_reason` → done=true
    static func parseOpenAISSELine(_ line: Data) -> LocalStreamChunk? {
        guard let raw = String(data: line, encoding: .utf8) else { return nil }

        // Skip empty lines
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Skip SSE comment / keepalive lines
        guard !trimmed.hasPrefix(":") else { return nil }

        // Must start with "data: "
        let prefix = "data: "
        guard trimmed.hasPrefix(prefix) else { return nil }

        let payload = String(trimmed.dropFirst(prefix.count))

        // [DONE] sentinel
        if payload == "[DONE]" {
            return LocalStreamChunk(text: "", done: true)
        }

        // Decode JSON
        guard let jsonData = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            return nil
        }

        let delta = firstChoice["delta"] as? [String: Any]
        let text = delta?["content"] as? String ?? ""
        let finishReason = firstChoice["finish_reason"]
        let isDone: Bool
        if let reason = finishReason as? String, !reason.isEmpty {
            isDone = true
        } else {
            isDone = false
        }

        return LocalStreamChunk(text: text, done: isDone)
    }

    // MARK: - Model Discovery Parser

    /// Parses an OpenAI-compatible `/v1/models` JSON response into an array of model IDs.
    ///
    /// Expected shape: `{"object": "list", "data": [{"id": "model-name", ...}, ...]}`
    ///
    /// Throws `AIError.invalidResponse` if the JSON is malformed or the `data` key is missing.
    static func parseOpenAIModelsResponse(_ data: Data) throws -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw AIError.invalidResponse
        }
        return dataArray.compactMap { $0["id"] as? String }
    }

    // MARK: - Config Persistence

    /// Saves a LocalLLMConfig to UserDefaults as JSON.
    static func saveLocalConfig(_ config: LocalLLMConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: UserDefaultsKeys.AI.localConfig)
    }

    /// Loads a LocalLLMConfig from UserDefaults.
    ///
    /// Returns nil if nothing is stored. Logs a warning and returns defaults if the stored
    /// version is newer than the current known version (1).
    static func loadLocalConfig() -> LocalLLMConfig? {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.AI.localConfig) else {
            return nil
        }
        guard let config = try? JSONDecoder().decode(LocalLLMConfig.self, from: data) else {
            return nil
        }
        let currentVersion = 1
        if config.version > currentVersion {
            print("[AIClient] Warning: LocalLLMConfig version \(config.version) > current \(currentVersion); returning defaults")
            return LocalLLMConfig()
        }
        return config
    }

    // MARK: - Streaming

    /// Streams an OpenAI-compatible local LLM and yields text deltas.
    ///
    /// - Parameters:
    ///   - payload: The prompt payload to send.
    ///   - config: Local LLM configuration (serverURL, apiKey, requestTimeoutSeconds).
    ///   - maxTokens: Maximum tokens for the response.
    ///   - modelID: Model identifier string.
    ///   - urlSession: URLSession to use (injectable for testing; defaults to `.shared`).
    /// - Returns: An `AsyncThrowingStream` of text delta strings.
    func streamLocalLLM(
        payload: AIPromptPayload,
        config: LocalLLMConfig,
        maxTokens: Int,
        modelID: String,
        urlSession: URLSession = .shared
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let baseURL = URL(string: config.serverURL) else {
                        continuation.finish(throwing: AIError.invalidResponse)
                        return
                    }
                    let endpoint = baseURL.appendingPathComponent("chat/completions")
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = TimeInterval(config.requestTimeoutSeconds)

                    if !config.apiKey.isEmpty {
                        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                    }

                    // Build streaming body (openAIRequestBody + stream: true)
                    var body = Self.openAIRequestBody(payload: payload, maxTokens: maxTokens, modelID: modelID)
                    body["stream"] = true
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (asyncBytes, response) = try await urlSession.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIError.invalidResponse)
                        return
                    }

                    switch http.statusCode {
                    case 200:
                        break
                    case 404:
                        // 404 on /chat/completions typically means model name mismatch —
                        // the endpoint exists (probe passed) but the model wasn't found.
                        continuation.finish(throwing: AIError.localModelError)
                        return
                    case 500:
                        continuation.finish(throwing: AIError.localModelError)
                        return
                    default:
                        continuation.finish(throwing: AIError.localAPIError("Local LLM request failed (\(http.statusCode))."))
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
                } catch let urlError as URLError {
                    if urlError.code == .cannotConnectToHost || urlError.code == .networkConnectionLost {
                        continuation.finish(throwing: AIError.localConnectionFailed)
                    } else {
                        continuation.finish(throwing: urlError)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Awaits the full stream from a local LLM and returns assembled text.
    func callLocalLLM(
        payload: AIPromptPayload,
        config: LocalLLMConfig,
        maxTokens: Int,
        modelID: String,
        urlSession: URLSession = .shared
    ) async throws -> String {
        var result = ""
        for try await delta in streamLocalLLM(
            payload: payload,
            config: config,
            maxTokens: maxTokens,
            modelID: modelID,
            urlSession: urlSession
        ) {
            result += delta
        }
        return result
    }

    // MARK: - Health Probe

    /// Probes the local LLM server's `/models` endpoint.
    ///
    /// Returns true iff the server responds with HTTP 200.
    /// On success, persists the current timestamp to UserDefaults.
    static func probeHealth(config: LocalLLMConfig, urlSession: URLSession = .shared) async -> Bool {
        guard let baseURL = URL(string: config.serverURL) else { return false }
        let endpoint = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            let timestamp = Date().timeIntervalSince1970
            await MainActor.run {
                UserDefaults.standard.set(timestamp, forKey: UserDefaultsKeys.AI.localLastHealthyAt)
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Model Discovery

    /// Fetches available model IDs from the local LLM server's `/models` endpoint.
    static func discoverModels(config: LocalLLMConfig, urlSession: URLSession = .shared) async throws -> [String] {
        guard let baseURL = URL(string: config.serverURL) else {
            throw AIError.invalidResponse
        }
        let endpoint = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIError.invalidResponse
            }
            switch http.statusCode {
            case 200:
                return try parseOpenAIModelsResponse(data)
            case 404:
                throw AIError.localServerNotFound
            case 500:
                throw AIError.localModelError
            default:
                throw AIError.localConnectionFailed
            }
        } catch let error as AIError {
            throw error
        } catch let urlError as URLError {
            if urlError.code == .cannotConnectToHost || urlError.code == .networkConnectionLost {
                throw AIError.localConnectionFailed
            }
            throw urlError
        }
    }
}
