import Foundation

/// Phase 5h — language-agnostic regex extractor for TypeScript /
/// JavaScript / Python. Returns line-based boundaries for the same
/// kinds the Swift scanner emits (function / class / interface /
/// method), so `ASTChunker.semanticChunks(...)` can treat them
/// uniformly.
///
/// Known limitations (~5–10% miss rate):
/// - Methods declared with shorthand object syntax `foo()` are missed.
/// - TypeScript declaration files (`.d.ts`) only surface top-level
///   `export interface / class / function`.
/// - Python decorators bump the boundary line by 1 (we anchor on the
///   `def` / `class` keyword line, not the decorator).
struct RegexSymbolScanner: Sendable {

    struct Hit: Equatable, Sendable {
        let line: Int   // 1-indexed
        let kind: String
    }

    /// Public entry. `language` MUST be a non-Swift, non-plain hit
    /// recognised by `forLanguage(_:)` — Swift is handled separately
    /// by `SwiftSymbolScanner`.
    func scan(source: String, language: SourceLanguage) -> [Hit] {
        guard let patterns = Self.patterns(for: language) else { return [] }
        var hits: [Hit] = []
        let lines = source.components(separatedBy: "\n")
        for (idx, raw) in lines.enumerated() {
            let line = idx + 1
            for (regex, kind) in patterns {
                if regex.firstMatch(
                    in: raw,
                    options: [],
                    range: NSRange(raw.startIndex..<raw.endIndex, in: raw)
                ) != nil {
                    hits.append(Hit(line: line, kind: kind))
                    break
                }
            }
        }
        return hits
    }

    // MARK: - Per-language patterns

    private static func patterns(for language: SourceLanguage) -> [(NSRegularExpression, String)]? {
        switch language {
        case .typescript, .javascript:
            return jsPatterns
        case .python:
            return pythonPatterns
        default:
            return nil
        }
    }

    private static let jsPatterns: [(NSRegularExpression, String)] = [
        (re(#"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s+(\w+)\s*[(<]"#), "function"),
        (re(#"^\s*(?:export\s+)?(?:default\s+)?class\s+(\w+)"#), "class"),
        (re(#"^\s*(?:export\s+)?interface\s+(\w+)"#), "interface"),
        (re(#"^\s*(?:public|private|protected)?\s*(?:static\s+)?(?:async\s+)?(\w+)\s*\([^)]*\)\s*[:{]"#), "method"),
    ]

    private static let pythonPatterns: [(NSRegularExpression, String)] = [
        (re(#"^\s*async\s+def\s+(\w+)\s*\("#), "function"),
        (re(#"^\s*def\s+(\w+)\s*\("#), "function"),
        (re(#"^\s*class\s+(\w+)\s*[(:]"#), "class"),
    ]

    private static func re(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }
}
