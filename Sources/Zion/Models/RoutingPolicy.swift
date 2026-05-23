import Foundation

/// Defines the ordered provider fallback chain for each AI task lane.
///
/// Chains are stored as `[String: [String]]` (lane rawValue → [provider rawValue])
/// so JSON round-tripping works without custom CodingKeys.
struct RoutingPolicy: Codable, Equatable {
    var chains: [String: [String]]

    init(chains: [String: [String]] = [:]) {
        self.chains = chains
    }

    // MARK: - Default Policy

    static let defaultPolicy: RoutingPolicy = {
        var c: [String: [String]] = [:]
        c[AITaskLane.cheapSummary.rawValue]  = [AIProvider.local.rawValue, AIProvider.claudeCLI.rawValue, AIProvider.anthropic.rawValue, AIProvider.openai.rawValue]
        c[AITaskLane.general.rawValue]       = [AIProvider.claudeCLI.rawValue, AIProvider.anthropic.rawValue, AIProvider.openai.rawValue, AIProvider.local.rawValue]
        c[AITaskLane.reasoning.rawValue]     = [AIProvider.claudeCLI.rawValue, AIProvider.anthropic.rawValue, AIProvider.openai.rawValue]
        c[AITaskLane.review.rawValue]        = [AIProvider.claudeCLI.rawValue, AIProvider.anthropic.rawValue]
        c[AITaskLane.transcription.rawValue] = [AIProvider.openai.rawValue]
        return RoutingPolicy(chains: c)
    }()

    // MARK: - Chain Resolution

    /// Returns the provider chain for a lane, falling back to the default chain when missing.
    func chain(for lane: AITaskLane) -> [AIProvider] {
        let rawValues = chains[lane.rawValue] ?? RoutingPolicy.defaultPolicy.chains[lane.rawValue] ?? []
        return rawValues.compactMap { AIProvider(rawValue: $0) }
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "chat.routing.policy.v1"

    static func load() -> RoutingPolicy {
        guard
            let data = UserDefaults.standard.data(forKey: userDefaultsKey),
            let policy = try? JSONDecoder().decode(RoutingPolicy.self, from: data)
        else {
            return .defaultPolicy
        }
        return policy
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: RoutingPolicy.userDefaultsKey)
    }
}
