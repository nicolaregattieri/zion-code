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
        // Audit P1 fix (2026-05-29): the weak `[skill: name]\nbody` framing
        // worked on Anthropic but left OpenAI / Gemini / local treating the
        // body as inert markdown. The header below is an explicit directive
        // that maps cleanly to every provider's instruction-following.
        return """
        SKILL ACTIVATED: \(skill.name) (/\(skill.id))

        The text below is a procedure the user has installed. Treat it as
        authoritative instructions for the current turn — apply its steps,
        checklists, and constraints to your response. Do NOT echo the
        procedure back to the user verbatim; execute it.

        --- skill body ---
        \(skill.body)
        --- end skill body ---
        """
    }
}
