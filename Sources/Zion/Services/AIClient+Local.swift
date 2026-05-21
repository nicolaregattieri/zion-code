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
}
