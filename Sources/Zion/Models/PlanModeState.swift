import Foundation

// MARK: - PlanModeState

enum PlanModeState: String, Codable, CaseIterable, Equatable {
    case planFirst
    case autoApply

    private static let defaultsKey = "chat.plan.mode"

    static func current() -> PlanModeState {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let value = PlanModeState(rawValue: raw) else {
            return .planFirst
        }
        return value
    }

    static func set(_ state: PlanModeState) {
        UserDefaults.standard.set(state.rawValue, forKey: defaultsKey)
    }
}
