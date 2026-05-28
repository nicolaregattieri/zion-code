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

    /// Raw chunk text. Optional because read-back from `RAGStore` does
    /// not rehydrate content unless explicitly requested — only the
    /// indexer-side write path carries it. Excluded from Codable
    /// equality so two chunks with the same identity but different
    /// transient content still compare equal.
    var content: String? = nil

    init(path: String, startLine: Int, endLine: Int, kind: String, contentSHA: String, fallback: Bool, content: String? = nil) {
        self.path = path
        self.startLine = startLine
        self.endLine = endLine
        self.kind = kind
        self.contentSHA = contentSHA
        self.fallback = fallback
        self.content = content
    }

    enum CodingKeys: String, CodingKey {
        case path, startLine, endLine, kind, contentSHA, fallback
    }

    static func == (lhs: RAGChunk, rhs: RAGChunk) -> Bool {
        lhs.path == rhs.path
            && lhs.startLine == rhs.startLine
            && lhs.endLine == rhs.endLine
            && lhs.kind == rhs.kind
            && lhs.contentSHA == rhs.contentSHA
            && lhs.fallback == rhs.fallback
    }
}
