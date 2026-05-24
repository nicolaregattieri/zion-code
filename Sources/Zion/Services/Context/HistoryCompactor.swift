import Foundation

/// Summarizes a span of stale conversation messages and replaces them with a single
/// system message. Preserves pinned @file/@selection blocks and the last 4 turns verbatim.
/// Falls back to plain truncation when the summarization call fails or no summarizer is configured.
actor HistoryCompactor {

    /// Summarizer signature — injectable for tests. Real impl wraps a cheap-model AIClient.call.
    /// Returns the summary text or nil on failure (so we fall back to plain truncation).
    typealias Summarizer = @Sendable ([[String: Any]]) async -> String?

    static let preservedTurns = 4  // last N user+assistant pairs survive verbatim
    static let elideTokenThreshold = 1000  // each elided turn assumed ~1000 tokens
    static let summaryMarkerPrefix = "[summary] "

    private let summarizer: Summarizer

    init(summarizer: @escaping Summarizer = HistoryCompactor.disabledSummarizer) {
        self.summarizer = summarizer
    }

    /// Default no-op summarizer (returns nil → triggers plain-truncation fallback).
    static let disabledSummarizer: Summarizer = { _ in nil }

    /// If the conversation exceeds tokenBudget, replace its stale middle with a single summary message.
    /// Pinned content (messages tagged "pinned": true) survive. Last 4 turns survive verbatim.
    nonisolated func compactIfNeeded(
        _ conversation: [[String: Any]],
        tokenBudget: Int
    ) async -> [[String: Any]] {

        let estimated = HistoryCompactor.estimate(conversation)
        if estimated <= tokenBudget { return conversation }

        // Index split: keep system/pinned at head, keep last N turns at tail, summarize middle.
        let (head, middle, tail) = HistoryCompactor.split(conversation, preservedTurns: HistoryCompactor.preservedTurns)

        if middle.isEmpty {
            // Already short on middle — nothing to compact.
            return conversation
        }

        // Attempt summarization. summarizer is a let constant — safe to call from nonisolated context.
        var summary: String? = await summarizer(middle)
        if summary == nil {
            // Fallback: plain elision marker
            summary = "[truncated \(middle.count) older turns]"
        }
        let summaryMsg: [String: Any] = [
            "role": "system",
            "content": HistoryCompactor.summaryMarkerPrefix + (summary ?? ""),
            "compactor_replacement": true
        ]
        return head + [summaryMsg] + tail
    }

    // MARK: - Private helpers

    /// Splits conversation into:
    /// - head: leading system messages + any pinned messages anywhere
    /// - middle: non-pinned, non-recent messages
    /// - tail: last 2*preservedTurns messages (user+assistant pairs)
    static func split(
        _ conversation: [[String: Any]],
        preservedTurns: Int
    ) -> (head: [[String: Any]], middle: [[String: Any]], tail: [[String: Any]]) {
        // First pass: pull all system and pinned messages into head.
        // Non-system, non-pinned messages go into the body (ordered).
        var head: [[String: Any]] = []
        var body: [[String: Any]] = []

        for msg in conversation {
            let role = (msg["role"] as? String) ?? ""
            let isPinned = (msg["pinned"] as? Bool) ?? false
            if role == "system" || isPinned {
                head.append(msg)
            } else {
                body.append(msg)
            }
        }

        let tailCount = min(preservedTurns * 2, body.count)
        let tail = Array(body.suffix(tailCount))
        let middle = Array(body.prefix(body.count - tailCount))
        return (head, middle, tail)
    }

    static func estimate(_ conversation: [[String: Any]]) -> Int {
        var total = 0
        for msg in conversation {
            if let s = msg["content"] as? String {
                total += TokenEstimator.estimate(s, kind: .code)
            } else if let blocks = msg["content"] as? [[String: Any]] {
                for block in blocks {
                    if let t = block["text"] as? String {
                        total += TokenEstimator.estimate(t, kind: .code)
                    } else if let c = block["content"] as? String {
                        total += TokenEstimator.estimate(c, kind: .code)
                    }
                }
            }
        }
        return total
    }
}
