import Foundation

extension BridgeService {

    // MARK: - Artifact Discovery

    func discoverArtifacts(
        for target: BridgeTarget,
        repositoryURL: URL,
        warnings: inout [String]
    ) -> [BridgeArtifact] {
        var artifacts: [BridgeArtifact] = []

        switch target {
        case .claude:
            if let content = readTextIfExists(repositoryURL.appendingPathComponent("CLAUDE.md")) {
                artifacts.append(makeArtifact(target: .claude, relativePath: "CLAUDE.md", kind: .guidance, fallbackTitle: "Claude Context", content: content))
            }
            artifacts.append(contentsOf: markdownArtifacts(in: repositoryURL, basePath: ".claude/rules", target: .claude, kind: .rule))
            artifacts.append(contentsOf: markdownArtifacts(in: repositoryURL, basePath: ".claude/commands", target: .claude, kind: .command))

        case .codex:
            if let content = readTextIfExists(repositoryURL.appendingPathComponent("AGENTS.md")) {
                artifacts.append(makeArtifact(target: .codex, relativePath: "AGENTS.md", kind: .guidance, fallbackTitle: "Codex Context", content: content))
            }
            artifacts.append(contentsOf: markdownArtifacts(in: repositoryURL, basePath: ".agents/rules", target: .codex, kind: .rule))
            artifacts.append(contentsOf: skillArtifacts(in: repositoryURL, basePath: ".agents/skills", target: .codex))

        case .gemini:
            if let content = readTextIfExists(repositoryURL.appendingPathComponent("GEMINI.md")) {
                artifacts.append(makeArtifact(target: .gemini, relativePath: "GEMINI.md", kind: .guidance, fallbackTitle: "Gemini Context", content: content))
            }
            artifacts.append(contentsOf: markdownArtifacts(in: repositoryURL, basePath: ".gemini/rules", target: .gemini, kind: .rule))
            artifacts.append(contentsOf: markdownArtifacts(in: repositoryURL, basePath: ".gemini/commands", target: .gemini, kind: .command))
            artifacts.append(contentsOf: skillArtifacts(in: repositoryURL, basePath: ".gemini/skills", target: .gemini))

        case .cursor:
            artifacts.append(contentsOf: cursorArtifacts(in: repositoryURL))
        }

        if artifacts.isEmpty {
            warnings.append(L10n("bridge.warning.noSourceFiles", target.label))
        }

        return artifacts
    }

    // MARK: - Markdown Artifact Finder

    func markdownArtifacts(
        in repositoryURL: URL,
        basePath: String,
        target: BridgeTarget,
        kind: BridgeArtifactKind
    ) -> [BridgeArtifact] {
        let directoryURL = repositoryURL.appendingPathComponent(basePath)
        guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let content = readTextIfExists(url) else { return nil }
                let relativePath = basePath + "/" + url.lastPathComponent
                return makeArtifact(
                    target: target,
                    relativePath: relativePath,
                    kind: kind,
                    fallbackTitle: prettifyTitle(url.deletingPathExtension().lastPathComponent),
                    content: content
                )
            }
    }

    // MARK: - Skill Artifact Finder

    func skillArtifacts(
        in repositoryURL: URL,
        basePath: String,
        target: BridgeTarget
    ) -> [BridgeArtifact] {
        let directoryURL = repositoryURL.appendingPathComponent(basePath)
        guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }

        return urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { skillDirectory in
                let skillURL = skillDirectory.appendingPathComponent("SKILL.md")
                guard let content = readTextIfExists(skillURL) else { return nil }
                let relativePath = basePath + "/" + skillDirectory.lastPathComponent + "/SKILL.md"
                return makeArtifact(
                    target: target,
                    relativePath: relativePath,
                    kind: .skill,
                    fallbackTitle: extractSkillMetadata(from: content, fallback: skillDirectory.lastPathComponent).name,
                    content: content
                )
            }
    }

    // MARK: - Cursor Artifact Finder

    func cursorArtifacts(in repositoryURL: URL) -> [BridgeArtifact] {
        let directoryURL = repositoryURL.appendingPathComponent(".cursor/rules")
        guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "mdc" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let content = readTextIfExists(url) else { return nil }
                let slug = url.deletingPathExtension().lastPathComponent
                let kind: BridgeArtifactKind = slug == "project-context" ? .guidance : .rule
                return makeArtifact(
                    target: .cursor,
                    relativePath: ".cursor/rules/" + url.lastPathComponent,
                    kind: kind,
                    fallbackTitle: prettifyTitle(slug),
                    content: content
                )
            }
    }

    // MARK: - makeArtifact Helper

    func makeArtifact(
        target: BridgeTarget,
        relativePath: String,
        kind: BridgeArtifactKind,
        fallbackTitle: String,
        content: String
    ) -> BridgeArtifact {
        let metadata = extractSkillMetadata(from: content, fallback: fallbackTitle)
        let embeddedHome = embeddedHome(in: content)
        return BridgeArtifact(
            sourceTarget: target,
            relativePath: relativePath,
            kind: kind,
            slug: slugify(metadata.name),
            title: metadata.name,
            summary: metadata.description,
            content: content,
            homeTarget: embeddedHome?.target ?? target,
            homeRelativePath: embeddedHome?.relativePath ?? relativePath
        )
    }
}
