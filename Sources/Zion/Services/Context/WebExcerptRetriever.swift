import Foundation

/// Retrieves the most relevant excerpts of an HTML payload against a query prompt.
/// Used by FileSystemMentionToolClient when a @web fetch exceeds 32 KB after stripping.
///
/// Ranking algorithm: BM25-lite (term-frequency × inverse-document-frequency).
/// We considered routing through PageRanker (graph PageRank) but BM25 is more appropriate
/// for chunk-vs-query relevance ranking. PageRanker requires a link graph, not a query string.
enum WebExcerptRetriever {

    static let directInjectThresholdBytes = 32 * 1024
    static let maxExcerptBytes = 32 * 1024

    /// Returns excerpts of `html` ranked by relevance to `query`, capped at maxExcerptBytes.
    /// If the stripped text is <= directInjectThresholdBytes, returns the stripped text unchanged.
    static func excerpt(html: String, query: String, maxBytes: Int = maxExcerptBytes) -> String {
        let stripped = stripHTML(html)
        if stripped.utf8.count <= directInjectThresholdBytes {
            return stripped
        }
        let chunks = chunkByHeadings(stripped)
        let ranked = rankByQuery(chunks, query: query)
        return assemble(ranked, capBytes: maxBytes)
    }

    // MARK: - Stripping

    /// Strips HTML tags + collapses whitespace. Best-effort readability extraction.
    static func stripHTML(_ html: String) -> String {
        var out = html
        // Drop script / style / noscript blocks first
        for tag in ["script", "style", "noscript"] {
            let pattern = "<\(tag)[^>]*>.*?</\(tag)>"
            if let rx = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) {
                let range = NSRange(out.startIndex..., in: out)
                out = rx.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "")
            }
        }
        // Drop all remaining tags
        if let rx = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(out.startIndex..., in: out)
            out = rx.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: " ")
        }
        // Collapse whitespace
        if let rx = try? NSRegularExpression(pattern: "\\s+", options: []) {
            let range = NSRange(out.startIndex..., in: out)
            out = rx.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: " ")
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Chunking

    /// Splits text into ~1000-byte chunks on sentence boundaries.
    static func chunkByHeadings(_ text: String) -> [String] {
        let target = 1000
        var chunks: [String] = []
        var current = ""
        for sentence in text.split(separator: ".", omittingEmptySubsequences: true) {
            let s = String(sentence).trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            if current.utf8.count + s.utf8.count > target {
                if !current.isEmpty { chunks.append(current.trimmingCharacters(in: .whitespaces)) }
                current = s + "."
            } else {
                current += (current.isEmpty ? "" : " ") + s + "."
            }
        }
        if !current.isEmpty { chunks.append(current.trimmingCharacters(in: .whitespaces)) }
        return chunks
    }

    // MARK: - Ranking (BM25-lite)

    static func rankByQuery(_ chunks: [String], query: String) -> [(chunk: String, score: Double)] {
        let qTerms = tokenize(query.lowercased())
        guard !qTerms.isEmpty else {
            // No query: return in original order with uniform score
            return chunks.map { ($0, 1.0) }
        }
        let tokenizedChunks = chunks.map { tokenize($0.lowercased()) }
        let N = Double(chunks.count)
        // Document frequency per query term
        var df: [String: Int] = [:]
        for chunkTokens in tokenizedChunks {
            for term in Set(chunkTokens) where qTerms.contains(term) {
                df[term, default: 0] += 1
            }
        }
        let avgLen = tokenizedChunks.map { Double($0.count) }.reduce(0, +) / max(1, N)
        let k1 = 1.5
        let b = 0.75

        var ranked: [(chunk: String, score: Double)] = []
        for (idx, tokens) in tokenizedChunks.enumerated() {
            var score = 0.0
            let len = Double(tokens.count)
            for term in qTerms {
                let tf = Double(tokens.filter { $0 == term }.count)
                guard tf > 0 else { continue }
                let dfT = Double(df[term] ?? 1)
                let idf = log(max(1.0, (N - dfT + 0.5) / (dfT + 0.5) + 1))
                score += idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * len / avgLen))
            }
            ranked.append((chunks[idx], score))
        }
        return ranked.sorted { $0.score > $1.score }
    }

    static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { String($0) }
    }

    // MARK: - Assembly

    /// Assembles ranked chunks up to capBytes total.
    static func assemble(_ ranked: [(chunk: String, score: Double)], capBytes: Int) -> String {
        var out = ""
        var bytes = 0
        for (chunk, _) in ranked {
            let chunkBytes = chunk.utf8.count
            let separator = out.isEmpty ? "" : "\n\n"
            let addBytes = separator.utf8.count + chunkBytes
            if bytes + addBytes > capBytes { continue }
            out += separator + chunk
            bytes += addBytes
        }
        return out
    }
}
