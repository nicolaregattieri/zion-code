import Foundation

// MARK: - SymbolEntry

/// A single symbol extracted from a repository's codebase for memory and context ranking.
struct SymbolEntry: Codable, Equatable {
    /// Relative path to the file containing this symbol.
    let file: String
    /// 1-based line number where the symbol is defined.
    let line: Int
    /// Symbol kind (e.g. "function", "class", "struct", "enum").
    let kind: String
    /// Relevance score used to rank symbols for context injection.
    let score: Double
}
