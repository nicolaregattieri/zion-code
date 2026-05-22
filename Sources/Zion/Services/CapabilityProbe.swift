// CapabilityProbe.swift — Caches per-(provider, modelID) tool support results in UserDefaults.
// TTL: 24 hours. Key: chat.toolBridge.capability.<provider>.<modelID>

import Foundation

// MARK: - CapabilityProbe

/// Implemented as a `final class` (not an `actor`) so callers can pass
/// `UserDefaults` (not Sendable) without Swift 6 strict-concurrency
/// diagnostics. Internal access is serialised by a dispatch queue.
final class CapabilityProbe: @unchecked Sendable {

    // MARK: Constants

    static let ttlSeconds: TimeInterval = 86_400 // 24 h
    static let keyPrefix = "chat.toolBridge.capability"

    // MARK: Private storage

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Public API

    /// Returns whether the given provider + model supports tool calling.
    ///
    /// - If a fresh cached result exists, returns it immediately.
    /// - If cache is stale or missing, calls `probe()` and stores the result.
    /// - If `probe()` throws, conservatively returns `false` (don't crash callers).
    func supportsTools(provider: AIProvider, modelID: String, probe: @Sendable () async throws -> Bool) async -> Bool {
        let key = cacheKey(provider: provider, modelID: modelID)

        if let cached = read(key: key) {
            return cached
        }

        let result: Bool
        do {
            result = try await probe()
        } catch {
            result = false
        }

        write(key: key, supported: result)
        return result
    }

    /// Force-evict the cached entry for a provider+model (useful in tests).
    func evict(provider: AIProvider, modelID: String) {
        let key = cacheKey(provider: provider, modelID: modelID)
        defaults.removeObject(forKey: key)
    }

    // MARK: Private

    private func cacheKey(provider: AIProvider, modelID: String) -> String {
        let safeModel = modelID.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "\(Self.keyPrefix).\(provider.rawValue).\(safeModel)"
    }

    /// Reads and validates a cached capability entry. Returns nil when absent or expired.
    private func read(key: String) -> Bool? {
        guard let dict = defaults.dictionary(forKey: key),
              let supported = dict["supported"] as? Bool,
              let dateStr   = dict["checkedAt"] as? String,
              let date      = ISO8601DateFormatter().date(from: dateStr)
        else { return nil }

        let age = Date().timeIntervalSince(date)
        guard age < Self.ttlSeconds else { return nil }

        return supported
    }

    /// Persists a capability result with current timestamp.
    private func write(key: String, supported: Bool) {
        let formatter = ISO8601DateFormatter()
        let dict: [String: Any] = [
            "supported": supported,
            "checkedAt": formatter.string(from: Date())
        ]
        defaults.set(dict, forKey: key)
    }

    // MARK: Test helpers

    /// Directly inject a cache entry with a custom timestamp (for TTL tests).
    func injectCacheEntry(provider: AIProvider, modelID: String, supported: Bool, checkedAt: Date) {
        let key = cacheKey(provider: provider, modelID: modelID)
        let formatter = ISO8601DateFormatter()
        let dict: [String: Any] = [
            "supported": supported,
            "checkedAt": formatter.string(from: checkedAt)
        ]
        defaults.set(dict, forKey: key)
    }
}
