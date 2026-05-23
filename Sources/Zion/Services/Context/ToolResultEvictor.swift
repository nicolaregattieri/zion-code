import Foundation

/// Rewrites stale tool_result content blocks (older than currentStep-2) with an
/// [elided: N bytes — earlier round] marker when their length exceeds 4096 bytes.
/// Never evicts the latest tool result.
enum ToolResultEvictor {

    static let recentStepGuard = 2  // rounds preserved verbatim (most recent N results)
    static let minByteLengthToEvict = 4096

    /// Returns a new conversation with stale tool_result blocks elided in place.
    /// `currentStep` is the in-progress agentic-loop step index (1-based).
    static func evict(
        _ conversation: [[String: Any]],
        currentStep: Int
    ) -> [[String: Any]] {

        // First pass: count total tool_result occurrences.
        var totalResults = 0
        for msg in conversation {
            if let blocks = msg["content"] as? [[String: Any]] {
                for block in blocks where (block["type"] as? String) == "tool_result" {
                    totalResults += 1
                }
            }
        }

        // Evict all results except the most recent `recentStepGuard`.
        let evictUpTo = max(0, totalResults - Self.recentStepGuard)

        var seen = 0
        return conversation.map { msg -> [String: Any] in
            guard let blocks = msg["content"] as? [[String: Any]] else { return msg }
            let newBlocks: [[String: Any]] = blocks.map { block -> [String: Any] in
                guard (block["type"] as? String) == "tool_result" else { return block }
                seen += 1
                guard seen <= evictUpTo else { return block }  // recent ones survive
                let payload = (block["content"] as? String) ?? ""
                let bytes = payload.utf8.count
                guard bytes > Self.minByteLengthToEvict else { return block }
                var rewritten = block
                rewritten["content"] = "[elided: \(bytes) bytes \u{2014} earlier round]"
                rewritten["zion_evicted"] = true
                return rewritten
            }
            var newMsg = msg
            newMsg["content"] = newBlocks
            return newMsg
        }
    }
}
