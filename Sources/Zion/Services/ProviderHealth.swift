import Foundation

// MARK: - ProviderHealth

/// Tracks rate-limit windows and consecutive failure counts per AI provider.
actor ProviderHealth {

    // MARK: - Backoff schedule (seconds)
    private static let backoffSchedule: [TimeInterval] = [60, 120, 300, 600, 1800, 3600]

    // MARK: - State
    private var rateLimitedUntil: [AIProvider: Date] = [:]
    private var consecutiveFailures: [AIProvider: Int] = [:]

    // MARK: - Public API

    /// Mark a provider as rate-limited.
    /// - Parameter retryAfter: Explicit retry delay in seconds. When nil, uses exponential
    ///   backoff based on consecutive failure count.
    func markRateLimited(_ provider: AIProvider, retryAfter: TimeInterval?) {
        let count = consecutiveFailures[provider, default: 0]
        let delay: TimeInterval
        if let explicit = retryAfter {
            delay = explicit
        } else {
            let index = min(count, Self.backoffSchedule.count - 1)
            delay = Self.backoffSchedule[index]
        }
        rateLimitedUntil[provider] = Date().addingTimeInterval(delay)
        consecutiveFailures[provider] = count + 1
    }

    /// Mark a provider as healthy (clears rate-limit deadline and resets failure count).
    func markHealthy(_ provider: AIProvider) {
        rateLimitedUntil.removeValue(forKey: provider)
        consecutiveFailures.removeValue(forKey: provider)
    }

    /// Returns true when the provider has no active rate-limit deadline, or when the
    /// deadline has already passed relative to `now`.
    func isHealthy(_ provider: AIProvider, now: Date = Date()) -> Bool {
        guard let deadline = rateLimitedUntil[provider] else { return true }
        return now >= deadline
    }

    // MARK: - Test helpers (internal)

    /// Returns the current consecutive failure count. For testing only.
    func consecutiveFailureCount(for provider: AIProvider) -> Int {
        return consecutiveFailures[provider, default: 0]
    }

    /// Returns the rate-limit deadline. For testing only.
    func deadline(for provider: AIProvider) -> Date? {
        return rateLimitedUntil[provider]
    }
}
