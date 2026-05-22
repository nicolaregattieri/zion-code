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

                    let (asyncBytes, response) = try await session.bytes(for: request)

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
                        continuation.finish(throwing: AIError.quotaExceeded)
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
