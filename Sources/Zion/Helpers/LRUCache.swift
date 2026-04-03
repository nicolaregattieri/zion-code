import Foundation

/// A simple, generic LRU (Least Recently Used) cache.
/// Value-type semantics -- safe to use as a stored property on `@Observable` classes
/// when marked `@ObservationIgnored` (mutations won't trigger SwiftUI redraws).
struct LRUCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []
    private var keySet: Set<Key> = []
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    mutating func get(_ key: Key) -> Value? {
        storage[key]
    }

    mutating func set(_ key: Key, value: Value) {
        if keySet.contains(key) {
            order.removeAll { $0 == key }
        } else {
            keySet.insert(key)
        }
        order.append(key)
        storage[key] = value
        while order.count > capacity {
            let evicted = order.removeFirst()
            storage.removeValue(forKey: evicted)
            keySet.remove(evicted)
        }
    }

    mutating func clear() {
        storage.removeAll()
        order.removeAll()
        keySet.removeAll()
    }

    var count: Int { storage.count }
}
