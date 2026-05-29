import Foundation

/// Phase 6.3 — payload the composer hands back to ChatService when a
/// paste-to-install detector hits. Either MCP JSON or a SKILL.md
/// markdown block.
enum PasteAutoInstall: Equatable {
    case mcpJSON(raw: String)
    case skillMarkdown(name: String, description: String, body: String, triggers: [String])
}

/// Heuristic classifier for clipboard payloads. Conservative — only
/// fires when the content matches one of the canonical shapes so a
/// normal text paste falls through to the default text insertion.
enum PasteAutoInstallDetector {

    static func detect(in raw: String) -> PasteAutoInstall? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let mcp = detectMCP(in: trimmed) { return mcp }
        if let skill = detectSkill(in: trimmed) { return skill }
        return nil
    }

    // MARK: - MCP JSON

    static func detectMCP(in trimmed: String) -> PasteAutoInstall? {
        guard trimmed.hasPrefix("{") else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let dict = any as? [String: Any] else { return nil }

        // Full Cursor / Claude Desktop shape.
        if dict["mcpServers"] is [String: Any] {
            return .mcpJSON(raw: trimmed)
        }
        // Single explicit server: {id, command, args}.
        if dict["command"] is String,
           dict["id"] is String {
            return .mcpJSON(raw: trimmed)
        }
        // Single named server: {"foo": {"command": "...", ...}}.
        if dict.count == 1,
           let first = dict.first,
           let inner = first.value as? [String: Any],
           inner["command"] is String {
            return .mcpJSON(raw: trimmed)
        }
        return nil
    }

    // MARK: - SKILL.md

    /// Parses a markdown payload with YAML-ish frontmatter (`---\nname:\ndescription:\n---\n<body>`).
    static func detectSkill(in trimmed: String) -> PasteAutoInstall? {
        guard trimmed.hasPrefix("---\n") || trimmed.hasPrefix("---\r\n") else { return nil }
        let withoutLeading = String(trimmed.dropFirst(4))
        guard let endRange = withoutLeading.range(of: "\n---\n") ?? withoutLeading.range(of: "\n---\r\n") else {
            return nil
        }
        let frontmatter = String(withoutLeading[..<endRange.lowerBound])
        let body = String(withoutLeading[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        var name = ""
        var description = ""
        var triggers: [String] = []
        var collectingTriggers = false
        for line in frontmatter.components(separatedBy: "\n") {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if collectingTriggers {
                if stripped.hasPrefix("- ") {
                    triggers.append(String(stripped.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                    continue
                } else if stripped.isEmpty {
                    continue
                } else {
                    collectingTriggers = false
                }
            }
            if let colon = stripped.firstIndex(of: ":") {
                let key = String(stripped[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(stripped[stripped.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                switch key {
                case "name": name = value
                case "description": description = value
                case "triggers": collectingTriggers = true
                default: break
                }
            }
        }
        guard !name.isEmpty, !description.isEmpty else { return nil }
        return .skillMarkdown(name: name, description: description, body: body, triggers: triggers)
    }
}
