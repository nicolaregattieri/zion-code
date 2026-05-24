import Foundation

// MARK: - SkillIndex

@MainActor
final class SkillIndex: ObservableObject {
    // MARK: - Shared accessor (used by ChatService.send skill injection)
    @MainActor static let shared = SkillIndex()

    private(set) var skills: [Skill] = []
    private let userRoot: URL
    private let projectRoot: URL?

    init(
        userRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills"),
        projectRoot: URL? = nil
    ) {
        self.userRoot = userRoot
        self.projectRoot = projectRoot
    }

    // MARK: - Reload

    func reload() async {
        var loaded: [Skill] = []
        let projectSkills = await scan(root: projectRoot, scope: .project)
        let userSkills = await scan(root: userRoot, scope: .user)

        // Merge: project shadows user (same id wins to project)
        var seen = Set<String>()
        for skill in projectSkills {
            loaded.append(skill)
            seen.insert(skill.id)
        }
        for skill in userSkills where !seen.contains(skill.id) {
            loaded.append(skill)
        }
        self.skills = loaded.sorted { $0.id < $1.id }
    }

    // MARK: - Frontmatter Parser (public test hook)

    /// Parses YAML-style frontmatter from a SKILL.md file.
    /// Returns `(frontmatter dict, body string)`.
    /// If no `---` boundaries are found, returns `([:], fullContent)`.
    static func parseFrontmatter(content: String) -> (frontmatter: [String: String], body: String) {
        let lines = content.components(separatedBy: "\n")
        guard lines.count >= 2 else {
            return ([:], content)
        }

        // First line must be exactly "---" (trimming trailing whitespace)
        guard lines[0].trimmingCharacters(in: .whitespaces) == "---" else {
            return ([:], content)
        }

        // Find closing "---"
        var closingIndex: Int? = nil
        for i in 1 ..< lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = i
                break
            }
        }

        guard let closeIdx = closingIndex else {
            // Malformed — no closing delimiter
            return ([:], content)
        }

        // Parse frontmatter lines between the two "---" markers
        var frontmatter: [String: String] = [:]
        for i in 1 ..< closeIdx {
            let line = lines[i]
            guard let colonRange = line.range(of: ":") else { continue }
            let key = String(line[line.startIndex ..< colonRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[colonRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            // Handle triggers list: `[foo, bar]` → strip brackets, split by comma
            if key == "triggers" {
                let stripped = rawValue
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .trimmingCharacters(in: .whitespaces)
                frontmatter[key] = stripped
            } else {
                frontmatter[key] = rawValue
            }
        }

        // Body: everything after the closing "---" line (drop leading blank line if present)
        let afterClose = lines[(closeIdx + 1)...]
        var bodyLines = Array(afterClose)
        // Drop one leading blank line if present
        if bodyLines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            bodyLines.removeFirst()
        }
        let body = bodyLines.joined(separator: "\n")

        return (frontmatter, body)
    }

    // MARK: - Private scan

    private func scan(root: URL?, scope: SkillScope) async -> [Skill] {
        guard let root else { return [] }
        var result: [Skill] = []

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for entry in entries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let skillFile = entry.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFile.path) else { continue }

            guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else {
                print("[SkillIndex] Failed to read \(skillFile.path)")
                continue
            }

            let (fm2, body) = SkillIndex.parseFrontmatter(content: content)
            let slug = entry.lastPathComponent
            let name = fm2["name"] ?? slug
            let description = fm2["description"] ?? ""
            let triggers: [String]
            if let raw = fm2["triggers"] {
                triggers = raw.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            } else {
                triggers = []
            }

            let skill = Skill(
                id: slug,
                name: name,
                description: description,
                scope: scope,
                path: skillFile,
                body: body,
                triggers: triggers
            )
            result.append(skill)
        }

        return result
    }
}

// MARK: - Scaffold

extension SkillIndex {
    enum ScaffoldError: Error {
        case invalidName
        case directoryExists
        case writeFailed
    }

    /// Writes a starter SKILL.md to <root>/<slug>/SKILL.md.
    /// Returns the URL of the new file. Throws if the directory already exists.
    @discardableResult
    nonisolated func scaffold(
        name: String,
        description: String,
        scope: SkillScope,
        rootOverride: URL? = nil
    ) throws -> URL {
        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !slug.isEmpty else { throw ScaffoldError.invalidName }

        let root: URL = rootOverride ?? {
            if scope == .user {
                return FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude/skills")
            } else {
                return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(".claude/skills")
            }
        }()

        let dir = root.appendingPathComponent(slug, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: dir.path) else {
            throw ScaffoldError.directoryExists
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let file = dir.appendingPathComponent("SKILL.md")
        let body = """
        ---
        name: \(slug)
        description: \(description.replacingOccurrences(of: "\n", with: " "))
        ---

        # \(name)

        Describe what this skill does, when to invoke it, and any constraints.

        ## Usage

        Invoke this skill in chat with `/\(slug)`.

        ## Steps

        1. ...
        2. ...

        """

        do {
            try body.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            throw ScaffoldError.writeFailed
        }
        return file
    }
}
