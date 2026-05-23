import Foundation

// MARK: - AgentApprovalTier

/// Controls how much autonomy the agentic loop is granted before pausing for user review.
enum AgentApprovalTier: String, CaseIterable, Codable {
    /// Agent may only read files; any write or shell action requires approval.
    case readOnly = "readOnly"
    /// Agent may read and write files inside the workspace; shell commands outside the repo require approval.
    case workspaceWrite = "workspaceWrite"
    /// Agent runs tools freely without per-action approval. User is notified after each step.
    case fullAccess = "fullAccess"
}

// MARK: - UserDefaults persistence

extension AgentApprovalTier {
    private static let userDefaultsKey = "chat.agent.tier"

    /// The current tier stored in UserDefaults. Defaults to `.readOnly` if no value has been saved.
    static var current: AgentApprovalTier {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let tier = AgentApprovalTier(rawValue: raw) else {
                return .readOnly
            }
            return tier
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }
}
