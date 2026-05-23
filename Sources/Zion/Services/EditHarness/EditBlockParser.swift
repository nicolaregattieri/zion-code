import Foundation

// MARK: - EditBlockParser

/// Consumes incremental text deltas and emits complete EditBlocks as each
/// `<<<<<<< SEARCH: <path> … ======= … >>>>>>> REPLACE` block closes.
/// Tolerant of partial-fence splits across deltas. 64 KB buffer cap with reset on overflow.
struct EditBlockParser {

    // MARK: - Constants

    private static let maxBuffer = 65_536   // 64 KB hard cap

    private static let openPrefix   = "<<<<<<< SEARCH:"
    private static let separator    = "======="
    private static let closeFence   = ">>>>>>> REPLACE"

    // MARK: - State

    private var buffer: String = ""

    // MARK: - Public API

    /// Feed a new delta. Returns every EditBlock whose closing fence arrived
    /// during this call. May return multiple blocks (back-to-back in one delta).
    /// Internal buffer retains only the unconsumed tail.
    mutating func feed(_ delta: String) -> [EditBlock] {
        buffer += delta

        // Enforce 64 KB cap — drop and continue
        if buffer.utf8.count > Self.maxBuffer {
            buffer = ""
            return []
        }

        return extractAllBlocks()
    }

    // MARK: - Extraction

    private mutating func extractAllBlocks() -> [EditBlock] {
        var results: [EditBlock] = []

        while let block = extractNextBlock() {
            results.append(block)
        }

        return results
    }

    /// Tries to extract one complete block from the current buffer.
    /// On success, advances buffer past the consumed block and returns the EditBlock.
    /// Returns nil when no complete block is available yet.
    private mutating func extractNextBlock() -> EditBlock? {
        // Find open fence
        guard let openRange = buffer.range(of: Self.openPrefix) else {
            // No open fence at all — keep buffer as-is (may be partial fence arriving)
            return nil
        }

        // The path is on the same line, after the prefix
        let afterPrefix = openRange.upperBound
        guard let openLineEnd = buffer[afterPrefix...].firstIndex(of: "\n") else {
            // Open fence line not yet complete
            return nil
        }

        let rawPath = String(buffer[afterPrefix..<openLineEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate: must have a non-empty path (rejects "<<<<<<< OOPS" which won't have ": path")
        // The open prefix includes "<<<<<<< SEARCH:" so rawPath is everything after the colon.
        // If the line doesn't have "SEARCH:" at all, openPrefix won't match, but we also
        // need to guard against an empty path (pure malformed line).
        guard !rawPath.isEmpty else {
            // Advance buffer past this malformed open line and keep looking
            let nextStart = buffer.index(after: openLineEnd)
            if nextStart <= buffer.endIndex {
                buffer = String(buffer[nextStart...])
            } else {
                buffer = ""
            }
            return nil
        }

        // Search content starts after the open line's newline
        let searchStart = buffer.index(after: openLineEnd)
        let bufferTail = buffer[searchStart...]

        // Find separator on its own line
        guard let sepRange = findFenceOnOwnLine(Self.separator, in: String(bufferTail), relativeTo: searchStart) else {
            return nil
        }

        // Find close fence on its own line, after separator
        let replaceStart = buffer.index(after: sepRange.upperBound)
        let afterSep = buffer[replaceStart...]
        guard let closeRange = findFenceOnOwnLine(Self.closeFence, in: String(afterSep), relativeTo: replaceStart) else {
            return nil
        }

        // Extract search and replace content
        let search  = String(buffer[searchStart..<sepRange.lowerBound])
        let replace = String(buffer[replaceStart..<closeRange.lowerBound])

        // Trim trailing newline from content sections (convention: fence is on own line so content ends with \n)
        let searchTrimmed  = search.hasSuffix("\n")  ? String(search.dropLast())  : search
        let replaceTrimmed = replace.hasSuffix("\n") ? String(replace.dropLast()) : replace

        let block = EditBlock(path: rawPath, search: searchTrimmed, replace: replaceTrimmed)

        // Advance buffer past the consumed block (past the close fence line's newline if present)
        let afterClose = closeRange.upperBound
        if afterClose < buffer.endIndex && buffer[afterClose] == "\n" {
            buffer = String(buffer[buffer.index(after: afterClose)...])
        } else {
            buffer = String(buffer[afterClose...])
        }

        return block
    }

    // MARK: - Helpers

    /// Finds `fence` appearing as its own line within `text` (which is a substring of buffer
    /// starting at `base`). Returns the range in the original buffer.
    private func findFenceOnOwnLine(
        _ fence: String,
        in text: String,
        relativeTo base: String.Index
    ) -> Range<String.Index>? {
        var searchFrom = text.startIndex

        while searchFrom < text.endIndex {
            guard let matchRange = text.range(of: fence, range: searchFrom..<text.endIndex) else {
                return nil
            }

            // Check that the fence starts at a line beginning
            let atLineStart = matchRange.lowerBound == text.startIndex
                || text[text.index(before: matchRange.lowerBound)] == "\n"

            // Check that the fence ends at a line end (or end of string)
            let atLineEnd = matchRange.upperBound == text.endIndex
                || text[matchRange.upperBound] == "\n"

            if atLineStart && atLineEnd {
                // Translate back to buffer indices
                let distance = text.distance(from: text.startIndex, to: matchRange.lowerBound)
                let bufLower = buffer.index(base, offsetBy: distance)
                let bufUpper = buffer.index(bufLower, offsetBy: fence.count)
                return bufLower..<bufUpper
            }

            // Advance past this non-matching occurrence
            searchFrom = matchRange.upperBound
        }

        return nil
    }
}
