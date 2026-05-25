import Foundation

/// User preference for whether Smart Auto may spawn the local LLM server when
/// a turn could be routed there but the server is not running.
///
/// Default is `.ask` — Zion MUST NOT start the local server without an explicit
/// user click. The banner produced by `LocalAutoStartPrompt` is the only
/// authorized path to flip the server on for an Auto-mode turn.
enum LocalAutoStartPolicy: String, Codable, Equatable, CaseIterable {
    /// Show a one-time banner per session asking the user. (default)
    case ask
    /// User opted in to always auto-start when needed.
    case always
    /// User opted out — Smart Auto will never start the local server.
    case never

    private static let defaultsKey = "chat.local.autoStartPolicy"

    static func current() -> LocalAutoStartPolicy {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let value = LocalAutoStartPolicy(rawValue: raw) else {
            return .ask
        }
        return value
    }

    static func set(_ policy: LocalAutoStartPolicy) {
        UserDefaults.standard.set(policy.rawValue, forKey: defaultsKey)
    }
}
