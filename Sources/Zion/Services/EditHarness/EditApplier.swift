import Foundation

// MARK: - Strategy Enum

enum EditStrategy: String, Codable {
    case exact
    case whitespaceNormalized
    case stripIndent
    case fuzzy
    case reflection
    case wholeFileRewrite
}

// MARK: - Result Types

struct EditApplyResult: Equatable {
    var applied: Bool
    var finalContents: String?
    var attempts: [EditAttemptLog]
    var failureReason: String?
}

// MARK: - Callback Types

typealias ReflectionCallback = @Sendable (_ fileContents: String, _ failedSearch: String) async -> EditBlock?
typealias WholeFileCallback = @Sendable (_ fileContents: String, _ originalBlock: EditBlock) async -> String?

// MARK: - Actor

actor EditApplier {

    func apply(
        _ block: EditBlock,
        to currentContents: String,
        reflection: ReflectionCallback?,
        wholeFileRewrite: WholeFileCallback?
    ) async -> EditApplyResult {
        var attempts: [EditAttemptLog] = []

        // Path validation
        if block.path.hasPrefix("/") || block.path.contains("..") {
            attempts.append(EditAttemptLog(strategy: "pathRejected", ok: false, note: "absolute or traversal"))
            return EditApplyResult(applied: false, finalContents: nil, attempts: attempts, failureReason: "invalid_path")
        }

        // 1. Exact match
        if let result = applyExact(block: block, contents: currentContents) {
            attempts.append(EditAttemptLog(strategy: EditStrategy.exact.rawValue, ok: true))
            return EditApplyResult(applied: true, finalContents: result, attempts: attempts, failureReason: nil)
        } else {
            attempts.append(EditAttemptLog(strategy: EditStrategy.exact.rawValue, ok: false))
        }

        // 2. Whitespace-normalized match
        if let result = applyWhitespaceNormalized(block: block, contents: currentContents) {
            attempts.append(EditAttemptLog(strategy: EditStrategy.whitespaceNormalized.rawValue, ok: true))
            return EditApplyResult(applied: true, finalContents: result, attempts: attempts, failureReason: nil)
        } else {
            attempts.append(EditAttemptLog(strategy: EditStrategy.whitespaceNormalized.rawValue, ok: false))
        }

        // 3. Strip-common-indent match
        if let result = applyStripIndent(block: block, contents: currentContents) {
            attempts.append(EditAttemptLog(strategy: EditStrategy.stripIndent.rawValue, ok: true))
            return EditApplyResult(applied: true, finalContents: result, attempts: attempts, failureReason: nil)
        } else {
            attempts.append(EditAttemptLog(strategy: EditStrategy.stripIndent.rawValue, ok: false))
        }

        // 4. Fuzzy match (ratio >= 0.92)
        if let result = applyFuzzy(block: block, contents: currentContents) {
            attempts.append(EditAttemptLog(strategy: EditStrategy.fuzzy.rawValue, ok: true))
            return EditApplyResult(applied: true, finalContents: result, attempts: attempts, failureReason: nil)
        } else {
            attempts.append(EditAttemptLog(strategy: EditStrategy.fuzzy.rawValue, ok: false))
        }

        // 5. Reflection
        if let reflectionCB = reflection {
            let corrected = await reflectionCB(currentContents, block.search)
            if let correctedBlock = corrected, let result = applyExact(block: correctedBlock, contents: currentContents) {
                attempts.append(EditAttemptLog(strategy: EditStrategy.reflection.rawValue, ok: true))
                return EditApplyResult(applied: true, finalContents: result, attempts: attempts, failureReason: nil)
            } else {
                attempts.append(EditAttemptLog(strategy: EditStrategy.reflection.rawValue, ok: false, note: "reflection returned no usable block"))
            }
        }

        // 6. Whole-file rewrite
        if let rewriteCB = wholeFileRewrite {
            let newContents = await rewriteCB(currentContents, block)
            if let newContents = newContents, isValidRewrite(newContents: newContents, originalContents: currentContents) {
                attempts.append(EditAttemptLog(strategy: EditStrategy.wholeFileRewrite.rawValue, ok: true))
                return EditApplyResult(applied: true, finalContents: newContents, attempts: attempts, failureReason: nil)
            } else {
                attempts.append(EditAttemptLog(strategy: EditStrategy.wholeFileRewrite.rawValue, ok: false, note: "rewrite rejected: lazy placeholder or too short"))
            }
        }

        return EditApplyResult(applied: false, finalContents: nil, attempts: attempts, failureReason: "all_strategies_failed")
    }

    // MARK: - Strategy Implementations

    private func applyExact(block: EditBlock, contents: String) -> String? {
        guard !block.search.isEmpty, let range = contents.range(of: block.search) else { return nil }
        return contents.replacingCharacters(in: range, with: block.replace)
    }

    private func applyWhitespaceNormalized(block: EditBlock, contents: String) -> String? {
        guard !block.search.isEmpty else { return nil }

        func normalize(_ s: String) -> String {
            s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }

        let normalizedContents = normalize(contents)
        let normalizedSearch = normalize(block.search)

        guard let normalizedRange = normalizedContents.range(of: normalizedSearch) else { return nil }

        // Map the normalized range back to the original string via character counts
        // We use a line-by-line approach: find which original section matches.
        // Simpler robust approach: find the original range by scanning.
        let normalizedPrefix = String(normalizedContents[..<normalizedRange.lowerBound])
        let normalizedPrefixLen = normalizedPrefix.count
        let normalizedSearchLen = normalizedSearch.count

        // Walk original string to accumulate "normalized offset"
        if let originalRange = mapNormalizedRangeBack(
            original: contents,
            normalizedPrefixLen: normalizedPrefixLen,
            normalizedMatchLen: normalizedSearchLen
        ) {
            return contents.replacingCharacters(in: originalRange, with: block.replace)
        }
        return nil
    }

    /// Maps a range in the normalized version back to the original string.
    private func mapNormalizedRangeBack(original: String, normalizedPrefixLen: Int, normalizedMatchLen: Int) -> Range<String.Index>? {
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
                    // Transition to whitespace: this collapses to one space in normalized
                    inWhitespace = true
                    if normalizedCount == normalizedPrefixLen { startIdx = idx }
                    normalizedCount += 1
                    if normalizedCount == normalizedPrefixLen + normalizedMatchLen { endIdx = original.index(after: idx) }
                }
                // Skip subsequent whitespace chars (they're collapsed in normalized)
            } else {
                inWhitespace = false
                if normalizedCount == normalizedPrefixLen { startIdx = idx }
                normalizedCount += 1
                if normalizedCount == normalizedPrefixLen + normalizedMatchLen { endIdx = original.index(after: idx) }
            }

            idx = original.index(after: idx)
        }

        if let s = startIdx, let e = endIdx, s <= e {
            return s..<e
        }
        return nil
    }

    private func applyStripIndent(block: EditBlock, contents: String) -> String? {
        guard !block.search.isEmpty else { return nil }

        let searchLines = block.search.components(separatedBy: "\n")
        let nonEmptyLines = searchLines.filter { !$0.isEmpty }
        guard !nonEmptyLines.isEmpty else { return nil }

        // Find minimum common leading whitespace
        let minIndent = nonEmptyLines.reduce(Int.max) { minSoFar, line in
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            return Swift.min(minSoFar, leadingSpaces)
        }

        guard minIndent > 0 else { return nil }

        // Strip minIndent chars from each line of search
        let strippedSearch = searchLines.map { line -> String in
            if line.count >= minIndent {
                return String(line.dropFirst(minIndent))
            }
            return line
        }.joined(separator: "\n")

        // Also strip same indent from file lines (try matching stripped search in stripped file)
        let fileLines = contents.components(separatedBy: "\n")
        let strippedFile = fileLines.map { line -> String in
            if line.count >= minIndent {
                return String(line.dropFirst(minIndent))
            }
            return line
        }.joined(separator: "\n")

        // Try exact match of strippedSearch in strippedFile
        guard let range = strippedFile.range(of: strippedSearch) else { return nil }
        return strippedFile.replacingCharacters(in: range, with: block.replace)
    }

    private func applyFuzzy(block: EditBlock, contents: String) -> String? {
        guard !block.search.isEmpty else { return nil }

        let searchChars = Array(block.search)
        let contentChars = Array(contents)
        let windowSize = searchChars.count

        guard windowSize <= contentChars.count else {
            // Search longer than file — try full file similarity
            let ratio = similarityRatio(searchChars, contentChars)
            if ratio >= 0.92 {
                return block.replace
            }
            return nil
        }

        var bestRatio: Double = 0.0
        var bestRange: Range<String.Index>? = nil

        let limit = contentChars.count - windowSize
        for startOffset in 0...limit {
            let window = Array(contentChars[startOffset..<(startOffset + windowSize)])
            let ratio = similarityRatio(searchChars, window)
            if ratio > bestRatio {
                bestRatio = ratio
                if ratio >= 0.92 {
                    let startIdx = contents.index(contents.startIndex, offsetBy: startOffset)
                    let endIdx = contents.index(startIdx, offsetBy: windowSize)
                    bestRange = startIdx..<endIdx
                }
            }
        }

        if let range = bestRange, bestRatio >= 0.92 {
            return contents.replacingCharacters(in: range, with: block.replace)
        }
        return nil
    }

    /// Levenshtein-derived similarity ratio: 1 - distance / max(len(a), len(b))
    private func similarityRatio(_ a: [Character], _ b: [Character]) -> Double {
        let distance = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
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
                if a[i - 1] == b[j - 1] {
                    curr[j] = prev[j - 1]
                } else {
                    curr[j] = 1 + Swift.min(prev[j], curr[j - 1], prev[j - 1])
                }
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }

    private func isValidRewrite(newContents: String, originalContents: String) -> Bool {
        // Reject lazy placeholders
        if newContents.contains("// rest of code") { return false }
        let trimmed = newContents.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("…") || trimmed.hasSuffix("...") { return false }
        // Reject if shorter than half of original
        if !originalContents.isEmpty && newContents.count < originalContents.count / 2 { return false }
        return true
    }
}
