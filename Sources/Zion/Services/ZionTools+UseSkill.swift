import Foundation

/// Phase 6.5 — `use_skill(id)` tool. Lets the model activate an
/// installed skill without the user typing `/<id>` literally.
/// Returns the skill body as the tool_result so the model can apply
/// its instructions in the same conversation.
extension MCPConfigBuilder {

    static func dispatchUseSkill(args: [String: Any]) async throws -> String {
        guard let rawID = args["id"] as? String else {
            return "[use_skill: missing 'id' argument]"
        }
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !id.isEmpty else {
            return "[use_skill: empty id]"
        }
        let skills = await MainActor.run { SkillIndex.shared.skills }
        guard let skill = skills.first(where: { $0.id == id }) else {
            let known = skills.map { "/\($0.id)" }.joined(separator: ", ")
            return "[use_skill: no skill named '\(id)']\nInstalled: \(known.isEmpty ? "(none)" : known)"
        }
        return "[skill: \(skill.name)]\n\(skill.body)"
    }
}
