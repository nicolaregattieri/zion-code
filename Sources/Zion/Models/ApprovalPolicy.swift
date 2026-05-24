import Foundation

// MARK: - ApprovalPolicy

/// Single source of truth for how much autonomy the AI loop is granted.
/// Replaces the legacy triple (PlanModeState + autoCommit + AgentApprovalTier).
enum ApprovalPolicy: String, Sendable, CaseIterable, Identifiable, Codable {
    case manual
    case autoSafe
    case auto
    case yolo

    static let storageKey = "chat.approvalPolicy"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual:   return L10n("chat.approvalPolicy.manual")
        case .autoSafe: return L10n("chat.approvalPolicy.autoSafe")
        case .auto:     return L10n("chat.approvalPolicy.auto")
        case .yolo:     return L10n("chat.approvalPolicy.yolo")
        }
    }

    var description: String {
        switch self {
        case .manual:   return L10n("chat.approvalPolicy.manual.description")
        case .autoSafe: return L10n("chat.approvalPolicy.autoSafe.description")
        case .auto:     return L10n("chat.approvalPolicy.auto.description")
        case .yolo:     return L10n("chat.approvalPolicy.yolo.description")
        }
    }

    // MARK: - Derived knobs (single source of truth for call sites)

    /// PlanModeState for the loop's plan-before-act behaviour.
    var planMode: PlanModeState {
        switch self {
        case .manual:                 return .planFirst
        case .autoSafe, .auto, .yolo: return .autoApply
        }
    }

    /// True when edit-harness blocks may apply without user confirmation.
    var autoCommit: Bool {
        switch self {
        case .manual:                 return false
        case .autoSafe, .auto, .yolo: return true
        }
    }

    /// Bash tier this policy uses.
    var bashTier: AgentApprovalTier {
        switch self {
        case .manual:    return .readOnly
        case .autoSafe:  return .workspaceWrite
        case .auto:      return .workspaceWrite
        case .yolo:      return .fullAccess
        }
    }

    /// True when destructive tool calls must surface a confirmation UI before running.
    var asksDestructive: Bool {
        switch self {
        case .manual, .autoSafe:  return true
        case .auto, .yolo:        return false
        }
    }

    // MARK: - Storage

    static var current: ApprovalPolicy {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return ApprovalPolicy(rawValue: raw) ?? Self.derivedFromLegacy()
    }

    static func set(_ policy: ApprovalPolicy) {
        UserDefaults.standard.set(policy.rawValue, forKey: storageKey)
    }

    // MARK: - Migration

    /// Reads legacy P11 keys and derives a policy. Used when chat.approvalPolicy
    /// has not been set yet (first launch post-update).
    static func derivedFromLegacy(
        defaults: UserDefaults = .standard
    ) -> ApprovalPolicy {
        let planModeRaw = defaults.string(forKey: "chat.plan.mode") ?? "planFirst"
        let autoCommit = defaults.object(forKey: "chat.editHarness.autoCommit") as? Bool ?? true
        let tierRaw = defaults.string(forKey: "chat.agent.tier") ?? "workspaceWrite"

        let isPlanFirst = (planModeRaw == "planFirst")

        if isPlanFirst && !autoCommit && tierRaw == "readOnly" {
            return .manual
        }
        if tierRaw == "fullAccess" && autoCommit {
            return .yolo
        }
        if !isPlanFirst && autoCommit && tierRaw == "workspaceWrite" {
            return .autoSafe
        }
        // Mixed signals: pick the safer of the two.
        return .autoSafe
    }

    /// Migrate once: if chat.approvalPolicy is unset, derive + persist + return true.
    @discardableResult
    static func migrateIfNeeded(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.string(forKey: storageKey) == nil else { return false }
        let derived = derivedFromLegacy(defaults: defaults)
        defaults.set(derived.rawValue, forKey: storageKey)
        return true
    }
}
