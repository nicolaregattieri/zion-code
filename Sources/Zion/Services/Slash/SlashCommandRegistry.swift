import Foundation

// MARK: - SlashItem

/// A single slash-command entry in the autocomplete popup.
struct SlashItem: @unchecked Sendable, Identifiable, Equatable {
    enum Source: Sendable, Equatable {
        case builtIn
        case projectSkill
        case userSkill
    }

    let id: String           // command name without slash, e.g. "diff"
    let name: String         // display name, e.g. "/diff"
    let argHint: String?     // e.g. "<path>" or "[n]"
    let description: String
    let source: Source
    let bodyLoader: (@Sendable () async -> String)? // for skills, returns SKILL.md body

    static func == (lhs: SlashItem, rhs: SlashItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.argHint == rhs.argHint &&
        lhs.description == rhs.description &&
        lhs.source == rhs.source
        // bodyLoader excluded intentionally — closures are not Equatable
    }
}

// MARK: - SlashCommandRegistry

@MainActor
final class SlashCommandRegistry: ObservableObject {
    private let skillIndex: SkillIndex

    init(skillIndex: SkillIndex) {
        self.skillIndex = skillIndex
    }

    /// All items: built-in first, then project skills, then user skills.
    var all: [SlashItem] {
        var out: [SlashItem] = BuiltInSlashCommands.all
        for skill in skillIndex.skills {
            let item = SlashItem(
                id: skill.id,
                name: "/" + skill.id,
                argHint: nil,
                description: skill.description,
                source: skill.scope == .project ? .projectSkill : .userSkill,
                bodyLoader: { skill.body }
            )
            out.append(item)
        }
        return out
    }

    /// Prefix-match against `name` (case-insensitive). Returns top `limit` results.
    func match(prefix: String, limit: Int = 6) -> [SlashItem] {
        let p = prefix.lowercased()
        return all
            .filter { $0.name.lowercased().hasPrefix(p) }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Shared accessor

extension SlashCommandRegistry {
    /// Lazily initialised shared registry. Reloads skill index once on first access.
    @MainActor static let shared: SlashCommandRegistry = {
        let skillIndex = SkillIndex()
        let registry = SlashCommandRegistry(skillIndex: skillIndex)
        Task { @MainActor in await skillIndex.reload() }
        return registry
    }()
}
