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

    /// Re-scan the underlying skill index so newly added / edited skills show
    /// up in the autocomplete without an app restart.
    func reloadSkills() async {
        await skillIndex.reload()
    }

    /// All items: project skills first, then user skills, then built-ins.
    /// Skills are the differentiator — surface them first; built-ins are always
    /// available so they can sit at the bottom.
    var all: [SlashItem] {
        var projectSkills: [SlashItem] = []
        var userSkills: [SlashItem] = []
        for skill in skillIndex.skills {
            let isProject = skill.scope == .project
            let item = SlashItem(
                id: skill.id,
                name: "/" + skill.id,
                argHint: nil,
                description: skill.description,
                source: isProject ? .projectSkill : .userSkill,
                bodyLoader: { skill.body }
            )
            if isProject {
                projectSkills.append(item)
            } else {
                userSkills.append(item)
            }
        }
        return projectSkills + userSkills + BuiltInSlashCommands.all
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
