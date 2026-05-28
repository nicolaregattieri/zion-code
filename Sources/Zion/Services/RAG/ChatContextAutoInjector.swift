import Foundation

/// Phase 6 — auto-context injector. Runs hybrid retrieval against the
/// active `RAGQueryService` for every chat turn that survives the
/// skip-heuristic, applies a per-provider token budget, and returns a
/// list of `RAGHit` rows the UI renders as inline chips before send.
///
/// User pinned mentions (already resolved via `MentionResolver`) take
/// precedence — any retrieval hit whose path overlaps a mentioned file
/// is dropped so the chat does not duplicate context.
struct ChatContextAutoInjector: Sendable {

    enum Tier: Sendable {
        case cheap   // local LLM, Haiku, 4o-mini
        case expensive // Opus, GPT-5-pro, Gemini Pro
    }

    /// Resolved auto-context payload. Empty when the heuristic skipped
    /// retrieval or no hits passed the budget.
    struct Payload: Sendable, Equatable {
        let hits: [RAGHit]
        let estimatedTokens: Int
        let truncated: Bool
        let skippedReason: SkipReason?

        static let empty = Payload(hits: [], estimatedTokens: 0, truncated: false, skippedReason: nil)
    }

    enum SkipReason: Sendable, Equatable {
        case shortMessage
        case metaPhrase
        case disabled
        case unavailable
    }

    private let service: @Sendable () -> RAGQueryService?

    init(service: @escaping @Sendable () -> RAGQueryService? = { RAGQueryServiceLocator.shared }) {
        self.service = service
    }

    /// Resolve auto-context for `message`. `mentionedPaths` is the list
    /// of paths already pinned via `@file` / `@code` / `@folder` so we
    /// can short-circuit duplicates.
    func resolve(
        message: String,
        tier: Tier,
        mentionedPaths: Set<String> = []
    ) async -> Payload {
        if !Constants.Feature.chatContextAutoEnabled {
            return Payload(hits: [], estimatedTokens: 0, truncated: false, skippedReason: .disabled)
        }
        if let skip = Self.skipReason(for: message) {
            return Payload(hits: [], estimatedTokens: 0, truncated: false, skippedReason: skip)
        }
        guard let svc = service() else {
            return Payload(hits: [], estimatedTokens: 0, truncated: false, skippedReason: .unavailable)
        }

        let raw = (try? await svc.hybridSearch(
            query: message,
            limit: Constants.RAG.maxResultsPerQuery
        )) ?? []

        let filtered = raw.filter { hit in
            !mentionedPaths.contains(where: { Self.pathMatches(hit.chunk.path, pinned: $0) })
        }

        let budget = Self.budget(for: tier)
        var picked: [RAGHit] = []
        var tokenSum = 0
        var truncated = false
        for hit in filtered {
            let chunkTokens = Self.estimateChunkTokens(hit.chunk)
            if tokenSum + chunkTokens > budget {
                truncated = true
                break
            }
            picked.append(hit)
            tokenSum += chunkTokens
            if picked.count >= Constants.RAG.autoMaxVisibleChips * 2 {
                truncated = true
                break
            }
        }

        return Payload(
            hits: picked,
            estimatedTokens: tokenSum,
            truncated: truncated || picked.count < filtered.count,
            skippedReason: nil
        )
    }

    /// Render the picked hits as a markdown block the provider receives
    /// alongside the user message. Matches the section header style
    /// used by `MentionResolver.buildSystemContext`.
    static func renderSystemBlock(_ payload: Payload) -> String {
        guard !payload.hits.isEmpty else { return "" }
        let lines: [String] = payload.hits.map { hit in
            "- `\(hit.chunk.path):\(hit.chunk.startLine)-\(hit.chunk.endLine)` — \(hit.chunk.kind) (\(hit.source.rawValue))"
        }
        return """
        ## auto-context (top \(payload.hits.count))
        \(lines.joined(separator: "\n"))
        """
    }

    // MARK: - Heuristics

    /// Phase 6 spec: skip retrieval on `< 8 token` messages or on the
    /// canonical meta-question regex. Both signals point at turns where
    /// the retrieved code chunks are pure noise (CodeRAG-Bench finding).
    static func skipReason(for message: String) -> SkipReason? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .shortMessage }
        // Meta-phrase check first: a long "why did you do X" must still
        // skip — those turns invariably degrade with retrieved code.
        if metaPhraseRegex.firstMatch(
            in: trimmed,
            options: [],
            range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        ) != nil {
            return .metaPhrase
        }
        let tokens = trimmed.count / 4
        if tokens < Constants.RAG.autoSkipTokenThreshold {
            return .shortMessage
        }
        return nil
    }

    private static let metaPhraseRegex: NSRegularExpression = {
        // Anchored start; case-insensitive. Captures the most common
        // meta turns where auto-context degrades responses.
        let pattern = #"^\s*(hi|hello|hey|olá|oi|thanks|thank you|valeu|ok|ok\.|okay|why|why\?|por que|why did you|why didn'?t you|explain that|undo|undo that|reverter|continue|continuar|go on|nope|sim|não|yes|no)\b"#
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    // MARK: - Budget

    static func budget(for tier: Tier) -> Int {
        switch tier {
        case .cheap: return Constants.RAG.autoBudgetTokensCheap
        case .expensive: return Constants.RAG.autoBudgetTokensExpensive
        }
    }

    static func estimateChunkTokens(_ chunk: RAGChunk) -> Int {
        // Phase 6 lacks per-chunk byte counts on the read path; assume
        // an average chunk weight of `chunkMaxTokens / 2` for budgeting
        // purposes. Closer-to-real token counting lands in Phase 7.
        Constants.RAG.chunkMaxTokens / 2
    }

    /// Treat a retrieval `path` as matching a `pinned` mention when the
    /// pinned argument is contained as a suffix or directory prefix.
    static func pathMatches(_ path: String, pinned: String) -> Bool {
        if path == pinned { return true }
        if path.hasSuffix(pinned) { return true }
        if path.hasPrefix(pinned + "/") { return true }
        return false
    }
}
