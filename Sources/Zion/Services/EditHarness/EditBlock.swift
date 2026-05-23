import Foundation

/// A single search-and-replace edit operation targeting a file path.
struct EditBlock: Identifiable, Equatable, Codable {
    let id: UUID
    let path: String
    let search: String
    let replace: String
    var appliedAt: Date? = nil
    var failureReason: String? = nil
    var attemptStrategies: [String] = []

    init(
        id: UUID = UUID(),
        path: String,
        search: String,
        replace: String,
        appliedAt: Date? = nil,
        failureReason: String? = nil,
        attemptStrategies: [String] = []
    ) {
        self.id = id
        self.path = path
        self.search = search
        self.replace = replace
        self.appliedAt = appliedAt
        self.failureReason = failureReason
        self.attemptStrategies = attemptStrategies
    }
}

/// Records the outcome of a single application strategy attempt for an `EditBlock`.
struct EditAttemptLog: Codable, Equatable {
    let strategy: String
    let ok: Bool
    let note: String?

    init(strategy: String, ok: Bool, note: String? = nil) {
        self.strategy = strategy
        self.ok = ok
        self.note = note
    }
}
