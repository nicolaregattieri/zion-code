import XCTest
@testable import Zion

final class ByteSafeTruncateTests: XCTestCase {

    // MARK: prefix

    func test_prefix_ascii_fast_path() {
        XCTAssertEqual(ByteSafeTruncate.prefix("hello world", maxBytes: 5), "hello")
    }

    func test_prefix_accented_char_boundary() {
        // é = 0xC3 0xA9 (2 bytes); "café" = c(1)+a(1)+f(1)+é(2) = 5 bytes total
        // maxBytes: 4 → fits "caf" (3 bytes) but not é (needs 2 more)
        XCTAssertEqual(ByteSafeTruncate.prefix("café", maxBytes: 4), "caf")
    }

    func test_prefix_emoji_boundary() {
        // 😀 = 4 bytes (U+1F600); "a😀b" → a(1) + 😀(4) + b(1)
        // maxBytes: 3 → only "a" fits (1 byte); 😀 needs 4 more bytes
        XCTAssertEqual(ByteSafeTruncate.prefix("a😀b", maxBytes: 3), "a")
    }

    func test_prefix_cjk_boundary() {
        // 中 = 3 bytes (U+4E2D); 文 = 3 bytes (U+6587)
        // maxBytes: 3 → "中" fits exactly, "文" would exceed
        XCTAssertEqual(ByteSafeTruncate.prefix("中文", maxBytes: 3), "中")
    }

    func test_prefix_zero_max_bytes() {
        XCTAssertEqual(ByteSafeTruncate.prefix("anything", maxBytes: 0), "")
    }

    func test_prefix_exact_fit() {
        // "hi" = 2 bytes, maxBytes = 2 → entire string returned
        XCTAssertEqual(ByteSafeTruncate.prefix("hi", maxBytes: 2), "hi")
    }

    // MARK: cap

    func test_cap_returns_original_when_under_limit() {
        XCTAssertEqual(ByteSafeTruncate.cap("hi", maxBytes: 100), "hi")
    }

    func test_cap_appends_marker_when_truncated() {
        // "hello world" = 11 bytes; maxBytes: 7
        // marker "…" = 3 bytes (UTF-8 0xE2 0x80 0xA6)
        // head budget = 7 - 3 = 4 bytes → "hell"
        // result = "hell…"
        let result = ByteSafeTruncate.cap("hello world", maxBytes: 7)
        XCTAssertEqual(result, "hell…")
        XCTAssertLessThanOrEqual(result.utf8.count, 7)
    }

    func test_cap_marker_included_in_byte_budget() {
        // Verify the result always fits within maxBytes
        let s = "This is a longer string with content"
        for limit in [5, 10, 20, 50] {
            let result = ByteSafeTruncate.cap(s, maxBytes: limit)
            XCTAssertLessThanOrEqual(result.utf8.count, limit,
                "cap exceeded maxBytes=\(limit): '\(result)' has \(result.utf8.count) bytes")
        }
    }

    func test_cap_emoji_truncation() {
        // "a😀b" = 6 bytes; maxBytes: 4
        // marker "…" = 3 bytes → head budget = 1 → "a"
        // result = "a…" = 4 bytes
        let result = ByteSafeTruncate.cap("a😀b", maxBytes: 4)
        XCTAssertEqual(result, "a…")
        XCTAssertLessThanOrEqual(result.utf8.count, 4)
    }
}
