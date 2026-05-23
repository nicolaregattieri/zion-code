// SwiftSymbolScanner.swift
// Regex-based Swift symbol extractor for RepoMap (Phase 12, Task 3).
//
// Known limitations (~5% miss rate):
// - Symbols inside block comments (/* ... */) or multi-line strings are detected.
// - Brace-depth heuristic is naive (no string/comment tracking), so braces inside
//   string literals or comments may shift depth. Acceptable for repomap hint use.
// - refs: [] is a v1 placeholder. TODO(P12.5): extract refs for richer PageRank.

import Foundation

// MARK: - Public Types

enum SymbolKind: String, Sendable, Codable, CaseIterable {
    case function
    case method
    case type            // typealias
    case enumCase
    case `struct`
    case `class`
    case `protocol`
    case `enum`
    case `extension`
    case variable
    case constant
}

struct ParsedSymbol: Sendable, Equatable {
    let name: String
    let kind: SymbolKind
    let line: Int      // 1-based
    let col: Int       // 1-based
    let refs: [String] // TODO(P12.5): always [] in v1; extract for PageRank in T5
}

enum ParserError: Error, Equatable {
    case unsupportedLanguage(extension: String)
    case readFailure(reason: String)
}

// MARK: - Scanner

struct SwiftSymbolScanner: Sendable {

    // MARK: Regex patterns (compiled once per kind)

    private struct Patterns {
        let funcPattern      = try! NSRegularExpression(pattern: #"(?:public|internal|private|fileprivate|open)?\s*(?:static\s+)?(?:final\s+)?func\s+(\w+)\s*[(<]"#)
        let structPattern    = try! NSRegularExpression(pattern: #"(?:public|internal|private|fileprivate|open)?\s*struct\s+(\w+)"#)
        let classPattern     = try! NSRegularExpression(pattern: #"(?:public|internal|private|fileprivate|open)?\s*(?:final\s+)?class\s+(\w+)"#)
        let protocolPattern  = try! NSRegularExpression(pattern: #"(?:public|internal|private|fileprivate|open)?\s*protocol\s+(\w+)"#)
        let enumPattern      = try! NSRegularExpression(pattern: #"(?:public|internal|private|fileprivate|open)?\s*(?:indirect\s+)?enum\s+(\w+)"#)
        let extensionPattern = try! NSRegularExpression(pattern: #"extension\s+(\w+(?:\.\w+)*)"#)
        let typealiasPattern = try! NSRegularExpression(pattern: #"typealias\s+(\w+)"#)
        let enumCasePattern  = try! NSRegularExpression(pattern: #"^\s*case\s+(\w+)(?:\s*[,(=]|\s*$)"#, options: .anchorsMatchLines)
        let varPattern       = try! NSRegularExpression(pattern: #"(?:public|internal|private|fileprivate|open)?\s*(?:static\s+)?var\s+(\w+)"#)
        let letPattern       = try! NSRegularExpression(pattern: #"(?:public|internal|private|fileprivate|open)?\s*(?:static\s+)?let\s+(\w+)"#)
    }

    private static let patterns = Patterns()

    // MARK: Public API

    /// Parse a Swift source file's contents into a list of symbols.
    /// Throws `.unsupportedLanguage` if the file extension is not `.swift`.
    func parse(file: URL, content: String) throws -> [ParsedSymbol] {
        guard file.pathExtension.lowercased() == "swift" else {
            throw ParserError.unsupportedLanguage(extension: file.pathExtension)
        }
        return parseSwift(content: content)
    }

    // MARK: Private

    private func parseSwift(content: String) -> [ParsedSymbol] {
        var symbols: [ParsedSymbol] = []
        let lines = content.components(separatedBy: "\n")
        var braceDepth = 0

        for (zeroIdx, line) in lines.enumerated() {
            let lineNumber = zeroIdx + 1
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            let p = Self.patterns

            // -- struct
            if let m = p.structPattern.firstMatch(in: line, range: range),
               let name = captureGroup(1, in: m, source: nsLine) {
                symbols.append(ParsedSymbol(name: name, kind: .struct, line: lineNumber, col: m.range.location + 1, refs: []))
            }
            // -- class
            else if let m = p.classPattern.firstMatch(in: line, range: range),
                    let name = captureGroup(1, in: m, source: nsLine) {
                symbols.append(ParsedSymbol(name: name, kind: .class, line: lineNumber, col: m.range.location + 1, refs: []))
            }
            // -- protocol
            else if let m = p.protocolPattern.firstMatch(in: line, range: range),
                    let name = captureGroup(1, in: m, source: nsLine) {
                symbols.append(ParsedSymbol(name: name, kind: .protocol, line: lineNumber, col: m.range.location + 1, refs: []))
            }
            // -- enum (before enumCase to avoid false positive on "enum case")
            else if let m = p.enumPattern.firstMatch(in: line, range: range),
                    let name = captureGroup(1, in: m, source: nsLine) {
                symbols.append(ParsedSymbol(name: name, kind: .enum, line: lineNumber, col: m.range.location + 1, refs: []))
            }
            // -- extension
            else if let m = p.extensionPattern.firstMatch(in: line, range: range),
                    let name = captureGroup(1, in: m, source: nsLine) {
                symbols.append(ParsedSymbol(name: name, kind: .extension, line: lineNumber, col: m.range.location + 1, refs: []))
            }
            // -- typealias
            else if let m = p.typealiasPattern.firstMatch(in: line, range: range),
                    let name = captureGroup(1, in: m, source: nsLine) {
                symbols.append(ParsedSymbol(name: name, kind: .type, line: lineNumber, col: m.range.location + 1, refs: []))
            }
            // -- func (function vs method based on braceDepth at time of declaration)
            else if let m = p.funcPattern.firstMatch(in: line, range: range),
                    let name = captureGroup(1, in: m, source: nsLine) {
                let kind: SymbolKind = braceDepth > 0 ? .method : .function
                symbols.append(ParsedSymbol(name: name, kind: kind, line: lineNumber, col: m.range.location + 1, refs: []))
            }
            // -- var
            else if let m = p.varPattern.firstMatch(in: line, range: range),
                    let name = captureGroup(1, in: m, source: nsLine) {
                symbols.append(ParsedSymbol(name: name, kind: .variable, line: lineNumber, col: m.range.location + 1, refs: []))
            }
            // -- let (constant)
            else if let m = p.letPattern.firstMatch(in: line, range: range),
                    let name = captureGroup(1, in: m, source: nsLine) {
                symbols.append(ParsedSymbol(name: name, kind: .constant, line: lineNumber, col: m.range.location + 1, refs: []))
            }

            // -- enum case (runs independently — not else-if, so it can match after an enum decl line)
            // Only scan for case if we're inside at least one brace scope
            if braceDepth > 0,
               let m = p.enumCasePattern.firstMatch(in: line, range: range),
               let name = captureGroup(1, in: m, source: nsLine) {
                // Avoid duplicating if the line already produced a symbol (e.g., `case` keyword in switch)
                if symbols.last?.line != lineNumber || symbols.last?.kind != .enumCase {
                    symbols.append(ParsedSymbol(name: name, kind: .enumCase, line: lineNumber, col: m.range.location + 1, refs: []))
                }
            }

            // Update brace depth AFTER processing the line so func declared on same line as `{` is still at depth N
            for ch in line {
                if ch == "{" { braceDepth += 1 }
                else if ch == "}" { braceDepth = max(0, braceDepth - 1) }
            }
        }

        return symbols
    }

    private func captureGroup(_ index: Int, in match: NSTextCheckingResult, source: NSString) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let r = match.range(at: index)
        guard r.location != NSNotFound else { return nil }
        return source.substring(with: r)
    }
}
