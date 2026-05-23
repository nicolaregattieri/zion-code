import Foundation

// MARK: - CostBudget

/// Tracks per-provider daily spend in UserDefaults.
/// Keys: `cost.budget.<provider.rawValue>.<YYYY-MM-DD>`
final class CostBudget: @unchecked Sendable {

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = Calendar.current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    // MARK: - Key

    private func key(for provider: AIProvider, date: Date = Date()) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "cost.budget.%@.%04d-%02d-%02d", provider.rawValue, year, month, day)
    }

    // MARK: - Public API

    func record(provider: AIProvider, usd: Double) {
        let k = key(for: provider)
        let current = defaults.double(forKey: k)
        defaults.set(current + usd, forKey: k)
    }

    func spent(provider: AIProvider) -> Double {
        return defaults.double(forKey: key(for: provider))
    }

    func capExceeded(provider: AIProvider, cap: Double) -> Bool {
        guard cap > 0 else { return false }
        return spent(provider: provider) >= cap
    }
}
