import Foundation

/// Phase 5 query layer. Sits on top of `RAGStore` + `EmbeddingProvider`
/// and exposes vector / keyword / hybrid (RRF) search. The hybrid path
/// is the default per the RAG RFC; toggleable via
/// `Constants.Feature.ragHybridEnabled` so dogfood can fall back to
/// vector-only without rebuilding.
actor RAGQueryService {

    private let store: RAGStore
    private let embedder: any EmbeddingProvider

    init(store: RAGStore, embedder: any EmbeddingProvider) {
        self.store = store
        self.embedder = embedder
    }

    /// Vector-only search. Embeds the query then asks `RAGStore` for
    /// the top-k by cosine. Returns `[]` if the embedder is not ready
    /// (e.g., Apple asset pack not downloaded yet).
    func vectorSearch(query: String, limit: Int) async throws -> [RAGHit] {
        guard await embedder.ready() else { return [] }
        let vectors = try await embedder.embed([query])
        guard let qv = vectors.first else { return [] }
        return try await store.vectorSearch(embedding: qv, limit: limit)
    }

    /// FTS5 keyword search. Sanitizes the query for FTS5 by quoting
    /// the entire input — sidesteps the operator parser so user text
    /// like `where is L10n loaded?` does not blow up.
    func keywordSearch(query: String, limit: Int) async throws -> [RAGHit] {
        let safe = Self.sanitizeFTSQuery(query)
        return try await store.keywordSearch(query: safe, limit: limit)
    }

    /// Hybrid retrieval — runs vector + keyword in parallel and merges
    /// via Reciprocal Rank Fusion with `k = Constants.RAG.rrfK = 60`.
    /// When `Constants.Feature.ragHybridEnabled == false`, falls back
    /// to vector-only.
    func hybridSearch(query: String, limit: Int) async throws -> [RAGHit] {
        if !Self.hybridFlag {
            return try await vectorSearch(query: query, limit: limit)
        }

        async let vectorTask = vectorSearch(query: query, limit: limit * 3)
        async let keywordTask = keywordSearch(query: query, limit: limit * 3)
        let (vectorHits, keywordHits) = try await (vectorTask, keywordTask)
        return Self.reciprocalRankFusion(
            vector: vectorHits,
            keyword: keywordHits,
            limit: limit,
            k: Double(Constants.RAG.rrfK)
        )
    }

    // MARK: - Helpers

    private static var hybridFlag: Bool {
        if let override = UserDefaults.standard.object(forKey: "rag.hybridEnabled") as? Bool {
            return override
        }
        return Constants.Feature.ragHybridEnabled
    }

    /// Merge two ranked result lists by Reciprocal Rank Fusion:
    /// `score(doc) = sum(1 / (k + rank_i))` across every list that
    /// contains the doc. Returns the top-`limit` distinct hits ordered
    /// by descending RRF score, source tagged `.hybrid`.
    static func reciprocalRankFusion(
        vector: [RAGHit],
        keyword: [RAGHit],
        limit: Int,
        k: Double
    ) -> [RAGHit] {
        var accumulator: [String: (score: Double, chunk: RAGChunk)] = [:]
        for (rank, hit) in vector.enumerated() {
            let key = hit.chunk.contentSHA
            let bump = 1.0 / (k + Double(rank + 1))
            accumulator[key, default: (0, hit.chunk)].score += bump
            accumulator[key]?.chunk = hit.chunk
        }
        for (rank, hit) in keyword.enumerated() {
            let key = hit.chunk.contentSHA
            let bump = 1.0 / (k + Double(rank + 1))
            accumulator[key, default: (0, hit.chunk)].score += bump
            accumulator[key]?.chunk = hit.chunk
        }
        return accumulator.values
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { RAGHit(chunk: $0.chunk, score: $0.score, source: .hybrid) }
    }

    /// FTS5 takes a structured query language (e.g., `"foo" AND "bar"`).
    /// User-typed natural language can include `?`, `:`, parentheses,
    /// or punctuation that FTS5 interprets as operators. Strategy: keep
    /// alphanumeric / whitespace, quote-wrap each surviving token, join
    /// with spaces (implicit OR).
    static func sanitizeFTSQuery(_ raw: String) -> String {
        let tokens = raw
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if tokens.isEmpty { return "\"\"" }
        return tokens.map { "\"\($0)\"" }.joined(separator: " ")
    }
}
