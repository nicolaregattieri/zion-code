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
        // Phase 5e — Swift gets symbol-bounded chunks via the existing
        // SwiftSymbolScanner. Other languages still go through the
        // fixed-window fallback until tree-sitter grammars unblock.
        if language == .swift {
            if let semantic = semanticSwiftChunks(source: source, file: file) {
                return semantic
            }
        }
        return fixedWindowChunks(source: source, filePath: file.path)
    }

    // MARK: - Swift semantic path

    /// Use the regex-based `SwiftSymbolScanner` already shipped for
    /// RepoMap to bracket chunks at top-level symbol boundaries.
    /// Each chunk spans from one symbol's line to the line before the
    /// next symbol. Chunks that exceed `Constants.RAG.chunkMaxTokens`
    /// fall back to the fixed-window splitter for that range only.
    private func semanticSwiftChunks(source: String, file: URL) -> [RAGChunk]? {
        let scanner = SwiftSymbolScanner()
        let symbols = (try? scanner.parse(file: file, content: source)) ?? []
        let topLevel = symbols
            .filter { Self.isChunkBoundaryKind($0.kind) }
            .sorted { $0.line < $1.line }
        guard !topLevel.isEmpty else { return nil }

        let lines = source.components(separatedBy: "\n")
        let totalLines = lines.count
        var chunks: [RAGChunk] = []

        for (idx, sym) in topLevel.enumerated() {
            let startLine = sym.line // 1-indexed
            let nextStart = idx + 1 < topLevel.count ? topLevel[idx + 1].line : totalLines + 1
            let endLine = max(startLine, nextStart - 1)
            let startIdx = max(0, startLine - 1)
            let endIdx = min(totalLines, endLine)
            guard startIdx < endIdx else { continue }
            let chunkLines = lines[startIdx..<endIdx]
            let content = chunkLines.joined(separator: "\n")
            // Hard split if a single semantic chunk exceeds the cap.
            let approxTokens = content.count / 4
            if approxTokens > Constants.RAG.chunkMaxTokens {
                let windowed = fixedWindowChunks(source: content, filePath: file.path)
                let shifted = windowed.map { w in
                    RAGChunk(
                        path: w.path,
                        startLine: w.startLine + startIdx,
                        endLine: w.endLine + startIdx,
                        kind: sym.kind.rawValue,
                        contentSHA: w.contentSHA,
                        fallback: false,
                        content: w.content
                    )
                }
                chunks.append(contentsOf: shifted)
            } else {
                chunks.append(RAGChunk(
                    path: file.path,
                    startLine: startLine,
                    endLine: endLine,
                    kind: sym.kind.rawValue,
                    contentSHA: sha256(content),
                    fallback: false,
                    content: content
                ))
            }
        }
        return chunks.isEmpty ? nil : chunks
    }

    private static func isChunkBoundaryKind(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .function, .method, .struct, .class, .enum, .protocol, .extension:
            return true
        case .type, .enumCase, .variable, .constant:
            return false
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
