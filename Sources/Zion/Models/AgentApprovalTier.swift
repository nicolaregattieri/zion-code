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

    /// L10n-aware display label for settings UI.
    var label: String {
        switch self {
        case .readOnly:       return L10n("chat.agent.tier.readOnly")
        case .workspaceWrite: return L10n("chat.agent.tier.workspaceWrite")
        case .fullAccess:     return L10n("chat.agent.tier.fullAccess")
        }
    }
}

// MARK: - UserDefaults persistence + TaskLocal override

extension AgentApprovalTier {
    private static let userDefaultsKey = "chat.agent.tier"

    /// Task-local override. When set (e.g. by PlanModeGate phase 1), `current` returns
    /// this value instead of the UserDefaults value, scoped to the current Swift Task.
    @TaskLocal static var overrideTier: AgentApprovalTier?

    /// The effective tier for the current task context.
    /// Returns `overrideTier` when set; otherwise falls back to the UserDefaults value.
    static var current: AgentApprovalTier {
        get {
            if let override = overrideTier { return override }
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
