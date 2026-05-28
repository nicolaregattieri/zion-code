import Foundation

/// A single indexable unit of source code extracted from a file.
struct RAGChunk: Codable, Equatable {
    /// Relative file path within the repository.
    var path: String

    /// First line of the chunk (1-indexed, inclusive).
    var startLine: Int

    /// Last line of the chunk (1-indexed, inclusive).
    var endLine: Int

    /// Semantic kind of the chunk (e.g. "function", "class", "block").
    var kind: String

    /// SHA-256 hex digest of the chunk content — used for incremental re-indexing.
    var contentSHA: String

    /// When true this chunk was produced by the fallback line-splitter, not a
    /// semantic extractor. Consumers may weight it lower.
    var fallback: Bool
}
