import Foundation

// MARK: - ProviderSwitchEvent

struct ProviderSwitchEvent: Identifiable, Equatable {
    let id: UUID
    let from: AIProvider
    let to: AIProvider
    /// Localized at the call site.
    let reason: String
    let at: Date

    init(id: UUID = UUID(), from: AIProvider, to: AIProvider, reason: String, at: Date = Date()) {
        self.id = id
        self.from = from
        self.to = to
        self.reason = reason
        self.at = at
    }
}

// MARK: - Codable

extension ProviderSwitchEvent: Codable {

    private enum CodingKeys: String, CodingKey {
        case id, from, to, reason, at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id     = try container.decode(UUID.self, forKey: .id)
        let fromRaw = try container.decode(String.self, forKey: .from)
        let toRaw   = try container.decode(String.self, forKey: .to)
        guard let fromProvider = AIProvider(rawValue: fromRaw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .from,
                in: container,
                debugDescription: "Unknown AIProvider rawValue: \(fromRaw)"
            )
        }
        guard let toProvider = AIProvider(rawValue: toRaw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .to,
                in: container,
                debugDescription: "Unknown AIProvider rawValue: \(toRaw)"
            )
        }
        from   = fromProvider
        to     = toProvider
        reason = try container.decode(String.self, forKey: .reason)
        at     = try container.decode(Date.self,   forKey: .at)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id,          forKey: .id)
        try container.encode(from.rawValue, forKey: .from)
        try container.encode(to.rawValue,   forKey: .to)
        try container.encode(reason,      forKey: .reason)
        try container.encode(at,          forKey: .at)
    }
}
