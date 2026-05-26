// EditTool.swift — zion_edit tool
// Duplicates the EditApplier ladder (exact, whitespaceNormalized, stripIndent, fuzzy).
// Cannot import Zion target — algorithm inlined here.

import Foundation

struct EditTool: Tool {
    /// Repo root used to resolve relative paths. Injected via main.swift or tests.
    let repoURL: URL

    var name: String { "zion_edit" }
    var description: String {
        "Apply a search/replace edit to a file inside the repository. " +
        "Tries exact match, then whitespace-normalized, strip-indent, and fuzzy (≥0.92) strategies."
    }

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Relative path to file inside the repository.")
                ]),
                "search": .object([
                    "type": .string("string"),
                    "description": .string("Text to search for.")
                ]),
                "replace": .object([
                    "type": .string("string"),
                    "description": .string("Replacement text.")
                ])
            ]),
            "required": .array([.string("path"), .string("search"), .string("replace")])
        ]
    }

    func call(args: [String: JSONValue]) throws -> JSONValue {
        let path    = try args.requireString("path")
        let search  = try args.requireString("search")
        let replace = try args.requireString("replace")

        // --- Path validation ---
        if path.hasPrefix("/") || path.contains("..") {
            let attempts: [JSONValue] = [
                .object(["strategy": .string("pathRejected"), "ok": .bool(false),
                         "note": .string("absolute path or traversal")])
            ]
            return makeContent([
                "applied": .bool(false),
                "attempts": .array(attempts)
            ])
        }

        let repoRoot = repoURL.standardizedFileURL.resolvingSymlinksInPath()
        let fileURL = repoRoot.appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let remainsInsideRepo = fileURL.path == repoRoot.path
            || fileURL.path.hasPrefix(repoRoot.path + "/")
        guard remainsInsideRepo else {
            let attempts: [JSONValue] = [
                .object(["strategy": .string("pathRejected"), "ok": .bool(false),
                         "note": .string("resolved path outside repository")])
            ]
            return makeContent([
                "applied": .bool(false),
                "attempts": .array(attempts)
            ])
        }

        // --- Read file ---
        guard let currentContents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            let attempts: [JSONValue] = [
                .object(["strategy": .string("readFile"), "ok": .bool(false),
                         "note": .string("cannot read file")])
            ]
            return makeContent([
                "applied": .bool(false),
                "attempts": .array(attempts)
            ])
        }

        var attempts: [JSONValue] = []

        // 1. Exact match
        if let result = applyExact(search: search, replace: replace, contents: currentContents) {
            attempts.append(.object(["strategy": .string("exact"), "ok": .bool(true)]))
            try result.write(to: fileURL, atomically: true, encoding: .utf8)
            return makeContent([
                "applied": .bool(true),
                "attempts": .array(attempts),
                "finalLength": .int(result.utf8.count)
            ])
        }
        attempts.append(.object(["strategy": .string("exact"), "ok": .bool(false)]))

        // 2. Whitespace-normalized match
        if let result = applyWhitespaceNormalized(search: search, replace: replace, contents: currentContents) {
            attempts.append(.object(["strategy": .string("whitespaceNormalized"), "ok": .bool(true)]))
            try result.write(to: fileURL, atomically: true, encoding: .utf8)
            return makeContent([
                "applied": .bool(true),
                "attempts": .array(attempts),
                "finalLength": .int(result.utf8.count)
            ])
        }
        attempts.append(.object(["strategy": .string("whitespaceNormalized"), "ok": .bool(false)]))

        // 3. Strip-common-indent match
        if let result = applyStripIndent(search: search, replace: replace, contents: currentContents) {
            attempts.append(.object(["strategy": .string("stripIndent"), "ok": .bool(true)]))
            try result.write(to: fileURL, atomically: true, encoding: .utf8)
            return makeContent([
                "applied": .bool(true),
                "attempts": .array(attempts),
                "finalLength": .int(result.utf8.count)
            ])
        }
        attempts.append(.object(["strategy": .string("stripIndent"), "ok": .bool(false)]))

        // 4. Fuzzy match (ratio >= 0.92)
        if let result = applyFuzzy(search: search, replace: replace, contents: currentContents) {
            attempts.append(.object(["strategy": .string("fuzzy"), "ok": .bool(true)]))
            try result.write(to: fileURL, atomically: true, encoding: .utf8)
            return makeContent([
                "applied": .bool(true),
                "attempts": .array(attempts),
                "finalLength": .int(result.utf8.count)
            ])
        }
        attempts.append(.object(["strategy": .string("fuzzy"), "ok": .bool(false)]))

        return makeContent([
            "applied": .bool(false),
            "attempts": .array(attempts)
        ])
    }

    // MARK: - Strategy implementations

    private func applyExact(search: String, replace: String, contents: String) -> String? {
        guard !search.isEmpty, let range = contents.range(of: search) else { return nil }
        return contents.replacingCharacters(in: range, with: replace)
    }

    private func applyWhitespaceNormalized(search: String, replace: String, contents: String) -> String? {
        guard !search.isEmpty else { return nil }

        func normalize(_ s: String) -> String {
            s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }

        let normalizedContents = normalize(contents)
        let normalizedSearch   = normalize(search)

        guard let normalizedRange = normalizedContents.range(of: normalizedSearch) else { return nil }

        let normalizedPrefixLen = normalizedContents[..<normalizedRange.lowerBound].count
        let normalizedSearchLen = normalizedSearch.count

        if let originalRange = mapNormalizedRangeBack(
            original: contents,
            normalizedPrefixLen: normalizedPrefixLen,
            normalizedMatchLen: normalizedSearchLen
        ) {
            return contents.replacingCharacters(in: originalRange, with: replace)
        }
        return nil
    }

    private func mapNormalizedRangeBack(
        original: String,
        normalizedPrefixLen: Int,
        normalizedMatchLen: Int
    ) -> Range<String.Index>? {
        var normalizedCount = 0
        var inWhitespace = false
        var startIdx: String.Index? = nil
        var endIdx: String.Index? = nil
        var idx = original.startIndex

        while idx < original.endIndex {
            let char = original[idx]
            let isWS = char.isWhitespace

            if isWS {
                if !inWhitespace {
                    inWhitespace = true
                    if normalizedCount == normalizedPrefixLen { startIdx = idx }
                    normalizedCount += 1
                    if normalizedCount == normalizedPrefixLen + normalizedMatchLen {
                        endIdx = original.index(after: idx)
                    }
                }
            } else {
                inWhitespace = false
                if normalizedCount == normalizedPrefixLen { startIdx = idx }
                normalizedCount += 1
                if normalizedCount == normalizedPrefixLen + normalizedMatchLen {
                    endIdx = original.index(after: idx)
                }
            }
            idx = original.index(after: idx)
        }

        if let s = startIdx, let e = endIdx, s <= e { return s..<e }
        return nil
    }

    private func applyStripIndent(search: String, replace: String, contents: String) -> String? {
        guard !search.isEmpty else { return nil }

        let searchLines    = search.components(separatedBy: "\n")
        let nonEmptyLines  = searchLines.filter { !$0.isEmpty }
        guard !nonEmptyLines.isEmpty else { return nil }

        let minIndent = nonEmptyLines.reduce(Int.max) { minSoFar, line in
            let leading = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            return Swift.min(minSoFar, leading)
        }
        guard minIndent > 0 else { return nil }

        let strippedSearch = searchLines.map { line -> String in
            line.count >= minIndent ? String(line.dropFirst(minIndent)) : line
        }.joined(separator: "\n")

        let fileLines    = contents.components(separatedBy: "\n")
        let strippedFile = fileLines.map { line -> String in
            line.count >= minIndent ? String(line.dropFirst(minIndent)) : line
        }.joined(separator: "\n")

        guard let range = strippedFile.range(of: strippedSearch) else { return nil }
        return strippedFile.replacingCharacters(in: range, with: replace)
    }

    private func applyFuzzy(search: String, replace: String, contents: String) -> String? {
        guard !search.isEmpty else { return nil }

        let searchChars  = Array(search)
        let contentChars = Array(contents)
        let windowSize   = searchChars.count

        guard windowSize <= contentChars.count else {
            return similarityRatio(searchChars, contentChars) >= 0.92 ? replace : nil
        }

        var bestRatio: Double = 0.0
        var bestRange: Range<String.Index>? = nil
        let limit = contentChars.count - windowSize

        for startOffset in 0...limit {
            let window = Array(contentChars[startOffset..<(startOffset + windowSize)])
            let ratio  = similarityRatio(searchChars, window)
            if ratio > bestRatio {
                bestRatio = ratio
                if ratio >= 0.92 {
                    let startIdx = contents.index(contents.startIndex, offsetBy: startOffset)
                    let endIdx   = contents.index(startIdx, offsetBy: windowSize)
                    bestRange = startIdx..<endIdx
                }
            }
        }

        if let range = bestRange, bestRatio >= 0.92 {
            return contents.replacingCharacters(in: range, with: replace)
        }
        return nil
    }

    private func similarityRatio(_ a: [Character], _ b: [Character]) -> Double {
        let distance = levenshtein(a, b)
        let maxLen   = max(a.count, b.count)
        guard maxLen > 0 else { return 1.0 }
        return 1.0 - Double(distance) / Double(maxLen)
    }

    private func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                curr[j] = a[i - 1] == b[j - 1]
                    ? prev[j - 1]
                    : 1 + Swift.min(prev[j], curr[j - 1], prev[j - 1])
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }
}
