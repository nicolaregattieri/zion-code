import Foundation

/// Source languages recognised by the RAG chunker.
///
/// Grammar-backed AST chunking is deferred (tree-sitter grammars do not yet
/// publish SPM 6.2-compatible manifests). All languages currently use the
/// fixed-window fallback path. The enum is kept as the public API contract so
/// AST support can be layered in later without changing callers.
enum SourceLanguage: String, CaseIterable, Sendable {
    case swift
    case typescript
    case python
    case javascript
    case json
    case markdown
    case plain

    /// Infer a language from a file extension.
    ///
    /// Returns `nil` when the extension is not recognised. Callers should fall
    /// back to `.plain` or skip the file entirely.
    static func forExtension(_ ext: String) -> SourceLanguage? {
        switch ext.lowercased() {
        case "swift":             return .swift
        case "ts", "tsx":         return .typescript
        case "py":                return .python
        case "js", "jsx", "mjs":  return .javascript
        case "json":              return .json
        case "md", "markdown":    return .markdown
        case "txt":               return .plain
        default:                  return nil
        }
    }

    /// True when a grammar-backed AST walk is available for this language.
    ///
    /// Currently always `false` — tree-sitter integration is deferred.
    var hasGrammar: Bool { false }
}
