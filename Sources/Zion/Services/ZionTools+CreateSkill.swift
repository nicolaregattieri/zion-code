import Foundation

/// Phase 6.3 — `create_skill(name:description:body:scope:)` MCP tool.
/// Writes a SKILL.md to `~/.claude/skills/<slug>/SKILL.md` (user) or
/// `<repo>/.claude/skills/<slug>/SKILL.md` (project) so the model can
/// turn natural-language "create a skill that does X" requests into a
/// real reusable skill without the user editing files by hand. Matches
/// the SKILL.md shape `SkillIndex.scan` already consumes.
extension MCPConfigBuilder {

    static func createSkillDescriptor() -> MCPToolDescriptor {
        MCPToolDescriptor(
            name: "create_skill",
            description: "Create a new Zion skill (SKILL.md with YAML frontmatter + markdown body). Use when the user asks to 'create a skill that …' or wants to make a repeatable workflow available across chat sessions. Project-scope = inside this repo's .claude/skills/; user-scope = ~/.claude/skills/ (default).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Human-readable skill name; also used to derive the slug directory."
                    ] as [String: Any],
                    "description": [
                        "type": "string",
                        "description": "One-line description shown in the skill picker."
                    ] as [String: Any],
                    "body": [
                        "type": "string",
                        "description": "Markdown body of the skill (instructions, prompts, examples)."
                    ] as [String: Any],
                    "scope": [
                        "type": "string",
                        "enum": ["user", "project"],
                        "description": "Where to save. user (default) = ~/.claude/skills; project = <repo>/.claude/skills."
                    ] as [String: Any],
                    "triggers": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Optional phrases that should auto-activate this skill."
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["name", "description", "body"]
            ]
        )
    }

    static func dispatchCreateSkill(args: [String: Any]) async throws -> String {
        let name = (args["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let description = (args["description"] as? String) ?? ""
        let body = (args["body"] as? String) ?? ""
        guard !name.isEmpty else { return "[error: missing name]" }
        guard !description.isEmpty else { return "[error: missing description]" }
        guard !body.isEmpty else { return "[error: missing body]" }

        let scopeRaw = (args["scope"] as? String) ?? "user"
        let triggers = (args["triggers"] as? [String]) ?? []

        let slug = Self.slugify(name)
        guard !slug.isEmpty else { return "[error: name produces empty slug]" }

        let baseDir: URL
        if scopeRaw == "project" {
            guard let repoURL = RAGIndexerLocator.repoURL else {
                return "[error: no active repo for project-scope skill]"
            }
            baseDir = repoURL
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            baseDir = home
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
        }
        let skillDir = baseDir.appendingPathComponent(slug, isDirectory: true)
        let skillFile = skillDir.appendingPathComponent("SKILL.md")

        do {
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
            let content = Self.renderSkillMarkdown(
                name: name,
                description: description,
                body: body,
                triggers: triggers
            )
            if FileManager.default.fileExists(atPath: skillFile.path) {
                return "[error: skill already exists at \(skillFile.path) — pick a different name]"
            }
            try content.write(to: skillFile, atomically: true, encoding: .utf8)
        } catch {
            return "[error: \(error.localizedDescription)]"
        }

        return "Created skill `\(slug)` at \(skillFile.path)"
    }

    static func renderSkillMarkdown(
        name: String,
        description: String,
        body: String,
        triggers: [String]
    ) -> String {
        var lines: [String] = ["---"]
        lines.append("name: \(name)")
        lines.append("description: \(description)")
        if !triggers.isEmpty {
            lines.append("triggers:")
            for t in triggers {
                lines.append("  - \(t)")
            }
        }
        lines.append("---")
        lines.append("")
        lines.append(body)
        if !body.hasSuffix("\n") {
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func slugify(_ raw: String) -> String {
        let lower = raw.lowercased()
        let allowed = lower.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return "-"
        }
        let collapsed = String(allowed)
            .components(separatedBy: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return collapsed
    }
}
