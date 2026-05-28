import CryptoKit
import Foundation

/// Splits source files into indexable ``RAGChunk`` units.
///
/// ## Strategy
///
/// - **Grammar-backed** (future): walk the tree-sitter AST, emit at
///   function / class / struct / extension boundaries, merge siblings up to
///   ``Constants/RAG/chunkMaxTokens``.
/// - **Fixed-window** (current): slide a 256-token window with
///   ``Constants/RAG/chunkOverlapTokens`` overlap.  All chunks are tagged
///   `fallback: true`.
///
/// Tree-sitter grammar packages do not yet publish SPM 6.2-compatible
/// manifests (see Package.swift note).  The grammar path is stubbed so the
/// API is stable; it will be wired up without changing callers once upstream
/// grammars ship compatible manifests.
struct ASTChunker: Sendable {

    // MARK: - Public API

    /// Chunk a single file.
    ///
    /// - Parameters:
    ///   - file: Absolute URL of the source file.
    ///   - language: Language hint — determines whether a grammar walk is
    ///     attempted or the fixed-window path is used.
    /// - Returns: An ordered array of non-overlapping (content-wise) chunks.
    /// - Throws: File read errors or ``ASTChunkerError/fileTooLarge`` when the
    ///   file exceeds ``Constants/RAG/maxBytesPerFile``.
    func chunk(file: URL, language: SourceLanguage) throws -> [RAGChunk] {
        let data = try Data(contentsOf: file)
        guard data.count <= Constants.RAG.maxBytesPerFile else {
            throw ASTChunkerError.fileTooLarge(bytes: data.count)
        }
        guard let source = String(data: data, encoding: .utf8) else {
            throw ASTChunkerError.notUTF8
        }
        if source.isEmpty { return [] }
        if language.hasGrammar {
            // Grammar path — stub, falls through to fixed-window for now.
            return fixedWindowChunks(source: source, filePath: file.path)
        } else {
            return fixedWindowChunks(source: source, filePath: file.path)
        }
    }

    // MARK: - Fixed-window path

    /// Slide a 256-token window with `chunkOverlapTokens` overlap across the
    /// source text.  Token count is estimated as `chars / 4`.
    private func fixedWindowChunks(source: String, filePath: String) -> [RAGChunk] {
        let windowTokens = 256
        let overlapTokens = Constants.RAG.chunkOverlapTokens
        let charsPerToken = 4

        let windowChars = windowTokens * charsPerToken
        let overlapChars = overlapTokens * charsPerToken

        let lines = source.components(separatedBy: "\n")
        guard !lines.isEmpty else { return [] }

        var chunks: [RAGChunk] = []
        var startLine = 0      // 0-indexed
        let totalLines = lines.count

        while startLine < totalLines {
            // Accumulate lines until we hit the window character budget.
            var charCount = 0
            var endLine = startLine
            while endLine < totalLines {
                let lineLen = lines[endLine].count + 1 // +1 for newline
                if charCount + lineLen > windowChars && endLine > startLine {
                    break
                }
                charCount += lineLen
                endLine += 1
            }
            // endLine is exclusive; last included line index is endLine-1.
            let chunkLines = lines[startLine..<endLine]
            let content = chunkLines.joined(separator: "\n")

            chunks.append(RAGChunk(
                path: filePath,
                startLine: startLine + 1,   // 1-indexed
                endLine: endLine,            // endLine-1 + 1 = endLine (1-indexed)
                kind: "block",
                contentSHA: sha256(content),
                fallback: true
            ))

            if endLine >= totalLines { break }

            // Step forward by (window - overlap) characters worth of lines.
            let stepChars = windowChars - overlapChars
            var stepped = 0
            var nextStart = startLine
            while nextStart < endLine && stepped < stepChars {
                stepped += lines[nextStart].count + 1
                nextStart += 1
            }
            // Ensure forward progress.
            startLine = max(nextStart, startLine + 1)
        }

        return chunks
    }

    // MARK: - Helpers

    private func sha256(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors

enum ASTChunkerError: Error, CustomStringConvertible {
    case fileTooLarge(bytes: Int)
    case notUTF8

    var description: String {
        switch self {
        case .fileTooLarge(let bytes):
            return "File size \(bytes) bytes exceeds RAG limit of \(Constants.RAG.maxBytesPerFile) bytes"
        case .notUTF8:
            return "File is not valid UTF-8"
        }
    }
}
