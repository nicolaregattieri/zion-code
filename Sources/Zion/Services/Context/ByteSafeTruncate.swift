import Foundation

/// UTF-8-safe string truncation utilities.
///
/// Swift's `String.prefix(_:)` counts *characters* (Unicode extended grapheme clusters),
/// not bytes. When serialising strings into byte-budgeted network payloads, use these
/// helpers instead to avoid splitting emoji, accented characters, or CJK codepoints at
/// a non-grapheme boundary.
enum ByteSafeTruncate {

    /// Returns the longest prefix of `s` whose UTF-8 byte count is <= `maxBytes`.
    /// Never splits a grapheme cluster (emoji, accented char, CJK, etc.).
    /// Returns `""` when `maxBytes <= 0`.
    static func prefix(_ s: String, maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        var byteCount = 0
        var endIndex = s.startIndex
        for scalar in s.unicodeScalars {
            let scalarBytes = String(scalar).utf8.count
            if byteCount + scalarBytes > maxBytes { break }
            byteCount += scalarBytes
            endIndex = s.unicodeScalars.index(after: endIndex)
        }
        return String(s[..<endIndex])
    }

    /// Like `prefix(_:maxBytes:)` but appends `marker` when the string was truncated.
    /// The returned string's UTF-8 byte count is always <= `maxBytes` (marker included).
    /// If `maxBytes` is too small to even fit the marker, falls back to a bare prefix.
    /// Returns the original string unchanged when it already fits within `maxBytes`.
    static func cap(_ s: String, maxBytes: Int, marker: String = "…") -> String {
        let actual = s.utf8.count
        if actual <= maxBytes { return s }
        let markerBytes = marker.utf8.count
        guard maxBytes > markerBytes else { return prefix(s, maxBytes: maxBytes) }
        let head = prefix(s, maxBytes: maxBytes - markerBytes)
        return head + marker
    }
}
