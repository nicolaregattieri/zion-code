import Foundation

/// Indicates which retrieval pipeline produced a RAGHit.
enum RAGSource: String, Codable, Equatable {
    /// Pure vector (embedding) similarity search.
    case vector
    /// Pure keyword (BM25 / FTS) search.
    case keyword
    /// Hybrid re-ranked result combining vector and keyword scores.
    case hybrid
}

/// A single search result returned by the RAG pipeline.
struct RAGHit: Codable, Equatable {
    /// The source chunk that matched the query.
    var chunk: RAGChunk

    /// Relevance score in [0, 1] (higher = more relevant).
    var score: Double

    /// Which retrieval pipeline produced this hit.
    var source: RAGSource
}
