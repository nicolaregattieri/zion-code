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
}

extension Constants.Timing {
    /// P95 latency budget (milliseconds) for a hybrid RAG query end-to-end.
    static let ragHybridQueryP95Ms: Int = 50
}
