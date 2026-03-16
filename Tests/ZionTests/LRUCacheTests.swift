import XCTest
@testable import Zion

final class LRUCacheTests: XCTestCase {

    func testGetReturnsNilForMissingKey() {
        var cache = LRUCache<String, Int>(capacity: 5)
        XCTAssertNil(cache.get("missing"))
    }

    func testSetAndGet() {
        var cache = LRUCache<String, Int>(capacity: 5)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        XCTAssertEqual(cache.get("a"), 1)
        XCTAssertEqual(cache.get("b"), 2)
        XCTAssertEqual(cache.count, 2)
    }

    func testEvictsOldestWhenCapacityExceeded() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.set("c", value: 3)
        cache.set("d", value: 4)

        XCTAssertNil(cache.get("a"), "Oldest entry should be evicted")
        XCTAssertEqual(cache.get("b"), 2)
        XCTAssertEqual(cache.get("d"), 4)
        XCTAssertEqual(cache.count, 3)
    }

    func testOverwriteMovesKeyToEnd() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.set("c", value: 3)

        // Overwrite "a" so it becomes most recent
        cache.set("a", value: 10)

        // Now "b" is the oldest, adding "d" should evict "b"
        cache.set("d", value: 4)

        XCTAssertNil(cache.get("b"), "b should be evicted after a was refreshed")
        XCTAssertEqual(cache.get("a"), 10)
        XCTAssertEqual(cache.get("c"), 3)
        XCTAssertEqual(cache.get("d"), 4)
    }

    func testClearRemovesAll() {
        var cache = LRUCache<String, Int>(capacity: 5)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.clear()

        XCTAssertNil(cache.get("a"))
        XCTAssertNil(cache.get("b"))
        XCTAssertEqual(cache.count, 0)
    }

    func testCapacityOfOne() {
        var cache = LRUCache<String, String>(capacity: 1)
        cache.set("first", value: "A")
        XCTAssertEqual(cache.get("first"), "A")

        cache.set("second", value: "B")
        XCTAssertNil(cache.get("first"))
        XCTAssertEqual(cache.get("second"), "B")
        XCTAssertEqual(cache.count, 1)
    }

    func testNoDuplicateKeysInOrder() {
        var cache = LRUCache<Int, String>(capacity: 3)
        cache.set(1, value: "a")
        cache.set(1, value: "b")
        cache.set(1, value: "c")

        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.get(1), "c")
    }
}
