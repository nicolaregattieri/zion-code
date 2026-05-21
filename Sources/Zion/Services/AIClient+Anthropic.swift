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
}
