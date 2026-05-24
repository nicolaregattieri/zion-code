import Foundation

enum SkillScope: String, Sendable, Codable {
    case user      // ~/.claude/skills/
    case project   // <repo>/.claude/skills/
}

struct Skill: Sendable, Identifiable, Equatable {
    let id: String           // slug from directory name
    let name: String         // from frontmatter `name`
    let description: String  // from frontmatter `description`
    let scope: SkillScope
    let path: URL            // path to SKILL.md
    let body: String         // markdown body (without frontmatter)
    let triggers: [String]   // optional `triggers` array from frontmatter
}
