import Foundation

extension Constants {

    // MARK: - RAG (Retrieval-Augmented Generation) constants

    enum RAG {
        /// Maximum tokens per document chunk.
        static let chunkMaxTokens: Int = 512

        /// Overlap tokens between adjacent chunks to preserve context continuity.
        static let chunkOverlapTokens: Int = 32

        /// Embedding vector dimensionality (must match the embedded model output).
        static let embeddingDim: Int = 512

        /// Reciprocal Rank Fusion constant k (higher = less sensitive to rank differences).
        static let rrfK: Int = 60

        /// Maximum results returned per query before re-ranking.
        static let maxResultsPerQuery: Int = 10

        /// Minimum Recall@10 gate — index quality check threshold.
        static let recallAtTenGate: Double = 0.55

        /// Maximum file size (in bytes) eligible for indexing (1 MiB).
        static let maxBytesPerFile: Int = 1_048_576

        /// Number of chunks to embed in a single batch request.
        static let batchSize: Int = 32

        /// Chunk count at which a scale-tripwire warning is emitted.
        static let scaleTripwireChunks: Int = 50_000

        // MARK: - Phase 6 — Auto-context budgets per provider tier

        /// Token budget cap for auto-injected context per chat turn — cheap tier
        /// (local LLM / Haiku / 4o-mini). Lower bound to avoid blowing the
        /// context window on smaller models.
        static let autoBudgetTokensCheap: Int = 1500

        /// Token budget cap for auto-injected context per chat turn — expensive
        /// tier (Opus, GPT-5-pro, Gemini Pro). Higher headroom matches the
        /// larger window these models bill against.
        static let autoBudgetTokensExpensive: Int = 2500

        /// Skip auto-injection on messages shorter than this token estimate
        /// (chars / 4 heuristic). Most "hi", "thanks", "continue" turns fall
        /// below this threshold and would only inject noise.
        static let autoSkipTokenThreshold: Int = 8

        /// Skeleton-chip reveal delay — only show the loading skeleton if the
        /// retrieval has not returned within this window (UX cue: hides
        /// flicker on fast hits, shows progress on slow ones).
        static let autoSkeletonDelayMs: Int = 150

        /// Maximum chips to display before collapsing into a "+N more" pill.
        static let autoMaxVisibleChips: Int = 5
    }

    // MARK: - Feature flags (extending existing Feature namespace via nested extension)

    enum Feature_RAG {
        // NOTE: These are surfaced on Constants.Feature via the extension below.
    }
}

extension Constants.Feature {
    /// When true, the hybrid (vector + keyword) RAG pipeline is active.
    /// Override via UserDefaults key "rag.hybridEnabled".
    static var ragHybridEnabled: Bool {
        if let override = UserDefaults.standard.object(forKey: "rag.hybridEnabled") as? Bool {
            return override
        }
        return true
    }

    /// When true, Qodo-based RAG provider is active (off by default, experimental).
    static var ragQodoEnabled: Bool {
        if let override = UserDefaults.standard.object(forKey: "rag.qodoEnabled") as? Bool {
            return override
        }
        return false
    }

    /// Phase 6 — Auto-inject hybrid retrieval into every chat turn.
    /// Default true; UserDefaults key "chat.context.autoEnabled" overrides.
    static var chatContextAutoEnabled: Bool {
        if let override = UserDefaults.standard.object(forKey: "chat.context.autoEnabled") as? Bool {
            return override
        }
        return true
    }
}

extension Constants.Timing {
    /// P95 latency budget (milliseconds) for a hybrid RAG query end-to-end.
    static let ragHybridQueryP95Ms: Int = 50
}
