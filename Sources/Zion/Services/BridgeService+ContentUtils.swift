import CryptoKit
import Foundation

extension BridgeService {

    // MARK: - Embedded Home

    func embeddedHome(in content: String) -> (target: BridgeTarget, relativePath: String)? {
        let pattern = #"<!--\s*Zion Bridge:\s*home=([a-z]+):(.*?)\s*-->"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range) else { return nil }
        guard
            let targetRange = Range(match.range(at: 1), in: content),
            let pathRange = Range(match.range(at: 2), in: content),
            let target = BridgeTarget(rawValue: String(content[targetRange]))
        else {
            return nil
        }

        return (target, String(content[pathRange]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Mirror Source Extraction

    func extractMirrorSource(from body: String) -> String? {
        guard let range = body.range(of: "\n## Mirror Source\n") else { return nil }
        let content = body[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content + "\n"
    }

    // MARK: - Bridge Marker Removal

    func removingBridgeMarkers(from body: String) -> String {
        body.replacingOccurrences(
            of: #"(?m)^<!--\s*Zion Bridge:\s*home=.*?-->\n?"#,
            with: "",
            options: .regularExpression
        )
    }

    // MARK: - Frontmatter Stripping

    func stripFrontmatter(from body: String) -> String {
        let pattern = #"(?s)\A---\n.*?\n---\n?"#
        return body.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    // MARK: - Leading Heading Stripping

    func stripLeadingHeading(from body: String, matching title: String) -> String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstContent = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return body
        }

        if firstContent.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("# \(title)") == .orderedSame {
            var mutable = lines
            if let index = mutable.firstIndex(of: firstContent) {
                mutable.remove(at: index)
            }
            return mutable.joined(separator: "\n")
        }
        return body
    }

    // MARK: - Path Reference Normalization

    func normalizePathReferences(in body: String, destination: BridgeTarget) -> String {
        switch destination {
        case .claude:
            return body
                .replacingOccurrences(of: ".agents/skills/", with: ".claude/commands/")
                .replacingOccurrences(of: "/SKILL.md", with: ".md")
                .replacingOccurrences(of: "AGENTS.md", with: "CLAUDE.md")
                .replacingOccurrences(of: ".agents/rules/", with: ".claude/rules/")
        case .codex:
            return body
                .replacingOccurrences(of: "CLAUDE.md", with: "AGENTS.md")
                .replacingOccurrences(of: ".claude/rules/", with: ".agents/rules/")
        case .gemini:
            return body
                .replacingOccurrences(of: "CLAUDE.md", with: "GEMINI.md")
                .replacingOccurrences(of: "AGENTS.md", with: "GEMINI.md")
        case .cursor:
            return body
                .replacingOccurrences(of: "CLAUDE.md", with: ".cursor/rules/project-context.mdc")
                .replacingOccurrences(of: "AGENTS.md", with: ".cursor/rules/project-context.mdc")
        }
    }

    // MARK: - Normalized Markdown

    func normalizedMarkdown(_ body: String) -> String {
        body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    // MARK: - Preview Text

    func previewText(from body: String) -> String {
        let compact = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > 220 else { return compact }

        let searchEnd = compact.index(compact.startIndex, offsetBy: 220)
        let searchRange = compact.startIndex..<searchEnd
        if let lastNewline = compact.range(of: "\n", options: .backwards, range: searchRange)?.lowerBound {
            return String(compact[..<lastNewline]) + "\n" + L10n("bridge.preview.truncated")
        }

        return String(compact[..<searchEnd]) + "\n" + L10n("bridge.preview.truncated")
    }

    // MARK: - Normalize Comparison

    func normalizeComparison(_ body: String) -> String {
        body.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Matrix Merge

    func merge(records newRecords: [BridgeMirrorRecord], into matrix: inout BridgeMirrorMatrix) {
        var records = matrix.records.filter { existing in
            !newRecords.contains(where: {
                $0.sourceTarget == existing.sourceTarget &&
                    $0.destinationTarget == existing.destinationTarget &&
                    $0.sourceRelativePath == existing.sourceRelativePath
            })
        }
        records.append(contentsOf: newRecords)
        matrix.records = records.sorted {
            if $0.sourceTarget == $1.sourceTarget {
                if $0.destinationTarget == $1.destinationTarget {
                    return $0.sourceRelativePath < $1.sourceRelativePath
                }
                return $0.destinationTarget.rawValue < $1.destinationTarget.rawValue
            }
            return $0.sourceTarget.rawValue < $1.sourceTarget.rawValue
        }
    }

    // MARK: - SHA Helpers

    func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - String Processing Utilities

    func extractSkillMetadata(from content: String, fallback: String) -> (name: String, description: String) {
        let frontmatterPattern = #"(?s)\A---\n(.*?)\n---"#
        guard let regex = try? NSRegularExpression(pattern: frontmatterPattern, options: []) else {
            return (fallback, "")
        }
        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              let blockRange = Range(match.range(at: 1), in: content) else {
            return (fallback, "")
        }

        var name = fallback
        var description = ""
        for line in content[blockRange].split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "name":
                name = parts[1]
            case "description":
                description = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            default:
                break
            }
        }

        return (name, description)
    }

    func yamlEscaped(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    func slugify(_ value: String) -> String {
        let lowered = value.lowercased()
        let components = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return components.filter { !$0.isEmpty }.joined(separator: "-")
    }

    func prettifyTitle(_ slug: String) -> String {
        slug
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
