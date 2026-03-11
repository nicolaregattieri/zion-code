import Foundation

struct BridgeService {
    private let fileManager = FileManager.default

    private enum Path {
        static let root = ".bridge"
        static let manifest = ".bridge/manifest.json"
        static let guidance = ".bridge/guidance"
        static let rules = ".bridge/rules"
        static let skills = ".bridge/skills"
        static let commands = ".bridge/commands"
        static let hooks = ".bridge/hooks"
    }

    func loadState(repositoryURL: URL) -> BridgeProjectState {
        let root = repositoryURL.appendingPathComponent(Path.root)
        guard fileManager.fileExists(atPath: root.path) else {
            return .empty
        }

        let manifest = readManifest(repositoryURL: repositoryURL) ?? BridgeManifest()
        var warnings: [String] = []
        let items = applyManifestMetadata(
            to: readCanonicalItems(repositoryURL: repositoryURL, warnings: &warnings),
            manifest: manifest
        )
        return BridgeProjectState(
            exists: true,
            manifest: manifest,
            items: items.sorted(by: sortItems(_:_:)),
            warnings: warnings
        )
    }

    func initializePackage(repositoryURL: URL) throws -> BridgeProjectState {
        let state = BridgeProjectState(
            exists: true,
            manifest: BridgeManifest(),
            items: [],
            warnings: []
        )
        try writeCanonicalState(state, repositoryURL: repositoryURL)
        return loadState(repositoryURL: repositoryURL)
    }

    func importConfiguration(from target: BridgeTarget, repositoryURL: URL) throws -> BridgeProjectState {
        var warnings: [String] = []
        let importedItems = importItems(from: target, repositoryURL: repositoryURL, warnings: &warnings)
        let state = BridgeProjectState(
            exists: true,
            manifest: BridgeManifest(
                enabledTargets: BridgeTarget.allCases,
                lastImportedTarget: target,
                updatedAt: Date()
            ),
            items: importedItems.sorted(by: sortItems(_:_:)),
            warnings: warnings
        )
        try writeCanonicalState(state, repositoryURL: repositoryURL)
        return loadState(repositoryURL: repositoryURL)
    }

    func previewSync(to target: BridgeTarget, repositoryURL: URL) throws -> BridgeSyncPreview {
        let state = loadState(repositoryURL: repositoryURL)
        guard state.exists else {
            throw NSError(domain: "BridgeService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: L10n("bridge.error.packageMissing")
            ])
        }

        let renderedFiles = renderFiles(for: target, state: state)
        let operations = buildOperations(for: target, repositoryURL: repositoryURL, renderedFiles: renderedFiles)
        let warnings = renderWarnings(for: target, state: state)
        return BridgeSyncPreview(
            target: target,
            operations: operations.sorted(by: sortOperations(_:_:)),
            warnings: warnings
        )
    }

    func applySync(_ preview: BridgeSyncPreview, repositoryURL: URL) throws -> BridgeProjectState {
        for operation in preview.operations {
            let fileURL = repositoryURL.appendingPathComponent(operation.relativePath)
            switch operation.kind {
            case .create, .update:
                guard let content = operation.renderedContent else { continue }
                try ensureParentDirectory(for: fileURL)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
            case .remove:
                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                    removeEmptyParents(startingAt: fileURL.deletingLastPathComponent(), repositoryURL: repositoryURL)
                }
            case .noop:
                break
            }
        }

        var state = loadState(repositoryURL: repositoryURL)
        if !state.manifest.enabledTargets.contains(preview.target) {
            state.manifest.enabledTargets.append(preview.target)
        }
        state.manifest.updatedAt = Date()
        try writeManifest(manifestWithItemMetadata(from: state), repositoryURL: repositoryURL)
        return loadState(repositoryURL: repositoryURL)
    }

    func compatibility(for item: BridgeItem, target: BridgeTarget) -> BridgeCompatibility {
        if item.strategy == .claudeCommandMirror || item.strategy == .codexSkillMirror {
            return .native
        }

        switch target {
        case .claude:
            switch item.kind {
            case .guidance, .rule, .command: return .native
            case .skill: return .adapted
            case .hook: return .unsupported
            }
        case .codex:
            switch item.kind {
            case .guidance, .rule, .skill: return .native
            case .command: return .adapted
            case .hook: return .unsupported
            }
        case .gemini:
            switch item.kind {
            case .guidance, .rule, .command: return .native
            case .skill: return .adapted
            case .hook: return .unsupported
            }
        }
    }

    private func importItems(from target: BridgeTarget, repositoryURL: URL, warnings: inout [String]) -> [BridgeItem] {
        switch target {
        case .claude:
            return importClaude(repositoryURL: repositoryURL, warnings: &warnings)
        case .codex:
            return importCodex(repositoryURL: repositoryURL, warnings: &warnings)
        case .gemini:
            return importGemini(repositoryURL: repositoryURL, warnings: &warnings)
        }
    }

    private func importClaude(repositoryURL: URL, warnings: inout [String]) -> [BridgeItem] {
        var items: [BridgeItem] = []

        if let content = readTextIfExists(repositoryURL.appendingPathComponent("CLAUDE.md"))
            ?? readTextIfExists(repositoryURL.appendingPathComponent("claude.md")) {
            items.append(makeItem(kind: .guidance, fallbackSlug: "claude-context", title: "Claude Context", content: content, sourceHint: "CLAUDE.md"))
        }

        items.append(contentsOf: importMarkdownFiles(in: repositoryURL.appendingPathComponent(".claude/rules"), kind: .rule))
        items.append(contentsOf: importClaudeCommands(in: repositoryURL.appendingPathComponent(".claude/commands")))

        if items.isEmpty {
            warnings.append(L10n("bridge.warning.noClaudeConfig"))
        }

        return items
    }

    private func importCodex(repositoryURL: URL, warnings: inout [String]) -> [BridgeItem] {
        var items: [BridgeItem] = []

        if let content = readTextIfExists(repositoryURL.appendingPathComponent("AGENTS.md")) {
            items.append(
                makeItem(
                    kind: .guidance,
                    fallbackSlug: "codex-context",
                    title: "Codex Context",
                    content: reverseCodexMirrorTextForClaude(content),
                    sourceHint: "AGENTS.md"
                )
            )
        }

        items.append(
            contentsOf: importMarkdownFiles(
                in: repositoryURL.appendingPathComponent(".agents/rules"),
                kind: .rule,
                contentTransform: reverseCodexMirrorTextForClaude(_:)
            )
        )
        items.append(contentsOf: importCodexSkills(in: repositoryURL.appendingPathComponent(".agents/skills"), repositoryURL: repositoryURL))

        if items.isEmpty {
            warnings.append(L10n("bridge.warning.noCodexConfig"))
        }

        return items
    }

    private func importGemini(repositoryURL: URL, warnings: inout [String]) -> [BridgeItem] {
        var items: [BridgeItem] = []

        if let content = readTextIfExists(repositoryURL.appendingPathComponent("GEMINI.md")) {
            items.append(makeItem(kind: .guidance, fallbackSlug: "gemini-context", title: "Gemini Context", content: content, sourceHint: "GEMINI.md"))
        }

        items.append(contentsOf: importMarkdownFiles(in: repositoryURL.appendingPathComponent(".gemini/rules"), kind: .rule))
        items.append(contentsOf: importMarkdownFiles(in: repositoryURL.appendingPathComponent(".gemini/commands"), kind: .command))
        items.append(contentsOf: importSkillFolders(in: repositoryURL.appendingPathComponent(".gemini/skills")))

        if items.isEmpty {
            warnings.append(L10n("bridge.warning.noGeminiConfig"))
        }

        return items
    }

    private func importClaudeCommands(in directoryURL: URL) -> [BridgeItem] {
        guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let content = readTextIfExists(url) else { return nil }
                let slug = url.deletingPathExtension().lastPathComponent
                return makeItem(
                    kind: .command,
                    fallbackSlug: slug,
                    title: prettifyTitle(slug),
                    content: content,
                    sourceHint: url.lastPathComponent,
                    strategy: .claudeCommandMirror,
                    mirrorReferencePath: ".claude/commands/\(url.lastPathComponent)"
                )
            }
    }

    private func importMarkdownFiles(
        in directoryURL: URL,
        kind: BridgeItemKind,
        contentTransform: ((String) -> String)? = nil
    ) -> [BridgeItem] {
        guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let content = readTextIfExists(url) else { return nil }
                let normalizedContent = contentTransform?(content) ?? content
                return makeItem(
                    kind: kind,
                    fallbackSlug: url.deletingPathExtension().lastPathComponent,
                    title: prettifyTitle(url.deletingPathExtension().lastPathComponent),
                    content: normalizedContent,
                    sourceHint: url.lastPathComponent
                )
            }
    }

    private func importSkillFolders(in directoryURL: URL) -> [BridgeItem] {
        guard let skillDirs = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }

        return skillDirs
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { skillDir in
                let skillFile = skillDir.appendingPathComponent("SKILL.md")
                guard let content = readTextIfExists(skillFile) else { return nil }
                let metadata = extractSkillMetadata(from: content, fallback: skillDir.lastPathComponent)
                return BridgeItem(
                    kind: .skill,
                    slug: slugify(metadata.name),
                    title: metadata.name,
                    summary: metadata.description,
                    content: content,
                    sourceHint: relativePath(for: skillFile, repositoryURL: directoryURL.deletingLastPathComponent())
                )
            }
    }

    private func importCodexSkills(in directoryURL: URL, repositoryURL: URL) -> [BridgeItem] {
        guard let skillDirs = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }

        return skillDirs
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { skillDir in
                let skillFile = skillDir.appendingPathComponent("SKILL.md")
                guard let content = readTextIfExists(skillFile) else { return nil }
                let relativeSkillPath = relativePath(for: skillFile, repositoryURL: repositoryURL)

                if let referencePath = parseMirroredClaudeCommandReference(in: content),
                   let commandContent = readTextIfExists(repositoryURL.appendingPathComponent(referencePath)) {
                    let slug = URL(fileURLWithPath: referencePath).deletingPathExtension().lastPathComponent
                    let normalizedContent = normalizeCodexSkillForClaudeCommand(
                        content,
                        fallbackSlug: slug,
                        title: prettifyTitle(slug),
                        referencePath: referencePath
                    )
                    return makeItem(
                        kind: .command,
                        fallbackSlug: slug,
                        title: prettifyTitle(slug),
                        content: normalizedContent.isEmpty ? commandContent : normalizedContent,
                        sourceHint: relativeSkillPath,
                        strategy: normalizedContent.isEmpty ? .claudeCommandMirror : .codexSkillMirror,
                        mirrorReferencePath: referencePath
                    )
                }

                let metadata = extractSkillMetadata(from: content, fallback: skillDir.lastPathComponent)
                let slug = slugify(metadata.name)
                let mirroredClaudePath = ".claude/commands/\(slug).md"
                if fileManager.fileExists(atPath: repositoryURL.appendingPathComponent(mirroredClaudePath).path) {
                    let normalizedContent = normalizeCodexSkillForClaudeCommand(
                        content,
                        fallbackSlug: slug,
                        title: metadata.name,
                        referencePath: mirroredClaudePath
                    )

                    return makeItem(
                        kind: .command,
                        fallbackSlug: slug,
                        title: metadata.name,
                        content: normalizedContent,
                        sourceHint: relativeSkillPath,
                        strategy: .codexSkillMirror,
                        mirrorReferencePath: mirroredClaudePath
                    )
                }

                return BridgeItem(
                    kind: .skill,
                    slug: slug,
                    title: metadata.name,
                    summary: metadata.description,
                    content: content,
                    sourceHint: relativeSkillPath
                )
            }
    }

    private func readCanonicalItems(repositoryURL: URL, warnings: inout [String]) -> [BridgeItem] {
        let guidance = importMarkdownFiles(in: repositoryURL.appendingPathComponent(Path.guidance), kind: .guidance)
        let rules = importMarkdownFiles(in: repositoryURL.appendingPathComponent(Path.rules), kind: .rule)
        let commands = importMarkdownFiles(in: repositoryURL.appendingPathComponent(Path.commands), kind: .command)
        let hooks = importMarkdownFiles(in: repositoryURL.appendingPathComponent(Path.hooks), kind: .hook)
        let skills = importSkillFolders(in: repositoryURL.appendingPathComponent(Path.skills))
        let items = guidance + rules + commands + hooks + skills

        if items.isEmpty {
            warnings.append(L10n("bridge.warning.packageEmpty"))
        }

        return items
    }

    private func writeCanonicalState(_ state: BridgeProjectState, repositoryURL: URL) throws {
        let root = repositoryURL.appendingPathComponent(Path.root)
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }

        try createDirectory(root)
        try createDirectory(repositoryURL.appendingPathComponent(Path.guidance))
        try createDirectory(repositoryURL.appendingPathComponent(Path.rules))
        try createDirectory(repositoryURL.appendingPathComponent(Path.skills))
        try createDirectory(repositoryURL.appendingPathComponent(Path.commands))
        try createDirectory(repositoryURL.appendingPathComponent(Path.hooks))

        try writeManifest(manifestWithItemMetadata(from: state), repositoryURL: repositoryURL)

        for item in state.items {
            switch item.kind {
            case .skill:
                let skillDir = repositoryURL.appendingPathComponent(Path.skills).appendingPathComponent(item.slug)
                try createDirectory(skillDir)
                try item.content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            case .guidance:
                try item.content.write(
                    to: repositoryURL.appendingPathComponent(Path.guidance).appendingPathComponent("\(item.slug).md"),
                    atomically: true,
                    encoding: .utf8
                )
            case .rule:
                try item.content.write(
                    to: repositoryURL.appendingPathComponent(Path.rules).appendingPathComponent("\(item.slug).md"),
                    atomically: true,
                    encoding: .utf8
                )
            case .command:
                try item.content.write(
                    to: repositoryURL.appendingPathComponent(Path.commands).appendingPathComponent("\(item.slug).md"),
                    atomically: true,
                    encoding: .utf8
                )
            case .hook:
                try item.content.write(
                    to: repositoryURL.appendingPathComponent(Path.hooks).appendingPathComponent("\(item.slug).md"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        }
    }

    private func writeManifest(_ manifest: BridgeManifest, repositoryURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: repositoryURL.appendingPathComponent(Path.manifest))
    }

    private func readManifest(repositoryURL: URL) -> BridgeManifest? {
        let url = repositoryURL.appendingPathComponent(Path.manifest)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BridgeManifest.self, from: data)
    }

    private func manifestWithItemMetadata(from state: BridgeProjectState) -> BridgeManifest {
        var manifest = state.manifest
        manifest.itemMetadata = Dictionary(
            uniqueKeysWithValues: state.items.map { item in
                (
                    metadataKey(for: item),
                    BridgeItemMetadata(
                        strategy: item.strategy,
                        mirrorReferencePath: item.mirrorReferencePath,
                        sourceHint: item.sourceHint
                    )
                )
            }
        )
        return manifest
    }

    private func applyManifestMetadata(to items: [BridgeItem], manifest: BridgeManifest) -> [BridgeItem] {
        items.map { item in
            guard let metadata = manifest.itemMetadata[metadataKey(for: item)] else {
                return item
            }

            var updated = item
            updated.strategy = metadata.strategy
            updated.mirrorReferencePath = metadata.mirrorReferencePath
            updated.sourceHint = metadata.sourceHint ?? item.sourceHint
            return updated
        }
    }

    private func metadataKey(for item: BridgeItem) -> String {
        "\(item.kind.rawValue):\(item.slug)"
    }

    private func renderFiles(for target: BridgeTarget, state: BridgeProjectState) -> [String: (content: String, compatibility: BridgeCompatibility, detail: String)] {
        var files: [String: (String, BridgeCompatibility, String)] = [:]
        files[mainFilePath(for: target)] = (
            buildMainFile(for: target, state: state),
            .native,
            L10n("bridge.detail.mainFile")
        )

        for item in state.items {
            let compatibility = compatibility(for: item, target: target)
            guard compatibility != .unsupported else { continue }
            guard item.kind != .guidance else { continue }

            let mapping = targetPath(for: item, target: target)
            files[mapping.relativePath] = (mapping.content, compatibility, mapping.detail)
        }

        return files
    }

    private func buildOperations(
        for target: BridgeTarget,
        repositoryURL: URL,
        renderedFiles: [String: (content: String, compatibility: BridgeCompatibility, detail: String)]
    ) -> [BridgeSyncOperation] {
        var operations: [BridgeSyncOperation] = []
        let existingManagedFiles = listManagedTargetFiles(for: target, repositoryURL: repositoryURL)

        for (relativePath, payload) in renderedFiles {
            let fileURL = repositoryURL.appendingPathComponent(relativePath)
            let existingContent = readTextIfExists(fileURL)
            let kind: BridgeSyncOperationKind
            if existingContent == nil {
                kind = .create
            } else if contentMatches(existingContent, payload.content) {
                kind = .noop
            } else {
                kind = .update
            }

            operations.append(
                BridgeSyncOperation(
                    target: target,
                    relativePath: relativePath,
                    kind: kind,
                    compatibility: payload.compatibility,
                    detail: payload.detail,
                    renderedContent: payload.content
                )
            )
        }

        let plannedPaths = Set(renderedFiles.keys)
        for stalePath in existingManagedFiles where !plannedPaths.contains(stalePath) {
            operations.append(
                BridgeSyncOperation(
                    target: target,
                    relativePath: stalePath,
                    kind: .remove,
                    compatibility: .native,
                    detail: L10n("bridge.detail.removeStale"),
                    renderedContent: nil
                )
            )
        }

        return operations
    }

    private func renderWarnings(for target: BridgeTarget, state: BridgeProjectState) -> [String] {
        var warnings = state.warnings
        let unsupportedCount = state.items.filter { compatibility(for: $0, target: target) == .unsupported }.count
        let adaptedCount = state.items.filter { compatibility(for: $0, target: target) == .adapted }.count

        if adaptedCount > 0 {
            warnings.append(L10n("bridge.warning.adaptedCount", adaptedCount, target.label))
        }
        if unsupportedCount > 0 {
            warnings.append(L10n("bridge.warning.unsupportedCount", unsupportedCount, target.label))
        }

        return warnings
    }

    private func buildMainFile(for target: BridgeTarget, state: BridgeProjectState) -> String {
        switch target {
        case .claude:
            return buildClaudeMainFile(state: state)
        case .codex:
            return buildCodexMainFile(state: state)
        case .gemini:
            return buildGeminiMainFile(state: state)
        }
    }

    private func targetPath(for item: BridgeItem, target: BridgeTarget) -> (relativePath: String, content: String, detail: String) {
        switch target {
        case .claude:
            switch item.kind {
            case .rule:
                return (".claude/rules/\(item.slug).md", item.content, L10n("bridge.detail.rule"))
            case .command:
                return (".claude/commands/\(item.slug).md", item.content, L10n("bridge.detail.command"))
            case .skill:
                return (".claude/commands/\(item.slug).md", item.content, L10n("bridge.detail.skillAsCommand"))
            case .guidance, .hook:
                return ("CLAUDE.md", item.content, L10n("bridge.detail.mainFile"))
            }
        case .codex:
            switch item.kind {
            case .rule:
                return (".agents/rules/\(item.slug).md", item.content, L10n("bridge.detail.rule"))
            case .skill:
                return (".agents/skills/\(item.slug)/SKILL.md", item.content, L10n("bridge.detail.skill"))
            case .command:
                let content = item.strategy == .claudeCommandMirror
                    ? buildClaudeMirroredCodexSkill(for: item)
                    : wrapPortableCommandAsSkill(item)
                return (".agents/skills/\(item.slug)/SKILL.md", content, L10n("bridge.detail.commandAsSkill"))
            case .guidance, .hook:
                return ("AGENTS.md", item.content, L10n("bridge.detail.mainFile"))
            }
        case .gemini:
            switch item.kind {
            case .rule:
                return (".gemini/rules/\(item.slug).md", item.content, L10n("bridge.detail.rule"))
            case .command:
                return (".gemini/commands/\(item.slug).md", item.content, L10n("bridge.detail.command"))
            case .skill:
                return (".gemini/skills/\(item.slug)/SKILL.md", item.content, L10n("bridge.detail.skill"))
            case .guidance, .hook:
                return ("GEMINI.md", item.content, L10n("bridge.detail.mainFile"))
            }
        }
    }

    private func mainFilePath(for target: BridgeTarget) -> String {
        switch target {
        case .claude: return "CLAUDE.md"
        case .codex: return "AGENTS.md"
        case .gemini: return "GEMINI.md"
        }
    }

    private func listManagedTargetFiles(for target: BridgeTarget, repositoryURL: URL) -> Set<String> {
        var paths: Set<String> = [mainFilePath(for: target)]

        switch target {
        case .claude:
            paths.formUnion(listFiles(in: repositoryURL.appendingPathComponent(".claude/rules"), repositoryURL: repositoryURL))
            paths.formUnion(listFiles(in: repositoryURL.appendingPathComponent(".claude/commands"), repositoryURL: repositoryURL))
        case .codex:
            paths.formUnion(listFiles(in: repositoryURL.appendingPathComponent(".agents/rules"), repositoryURL: repositoryURL))
            paths.formUnion(listFiles(in: repositoryURL.appendingPathComponent(".agents/skills"), repositoryURL: repositoryURL))
        case .gemini:
            paths.formUnion(listFiles(in: repositoryURL.appendingPathComponent(".gemini/rules"), repositoryURL: repositoryURL))
            paths.formUnion(listFiles(in: repositoryURL.appendingPathComponent(".gemini/commands"), repositoryURL: repositoryURL))
            paths.formUnion(listFiles(in: repositoryURL.appendingPathComponent(".gemini/skills"), repositoryURL: repositoryURL))
        }

        return paths.filter { fileManager.fileExists(atPath: repositoryURL.appendingPathComponent($0).path) }
    }

    private func listFiles(in directoryURL: URL, repositoryURL: URL) -> Set<String> {
        guard let subpaths = try? fileManager.subpathsOfDirectory(atPath: directoryURL.path) else {
            return []
        }

        return Set(
            subpaths
                .filter { !$0.hasSuffix("/") }
                .map { directoryURL.appendingPathComponent($0).path }
                .filter { fileManager.fileExists(atPath: $0) }
                .map { relativePath(for: URL(fileURLWithPath: $0), repositoryURL: repositoryURL) }
        )
    }

    private func buildClaudeMainFile(state: BridgeProjectState) -> String {
        buildCommandDrivenMainFile(
            heading: "# CLAUDE",
            guidance: state.items(of: .guidance),
            rules: state.items(of: .rule),
            skills: state.items(of: .skill),
            commands: state.items(of: .command)
        )
    }

    private func buildGeminiMainFile(state: BridgeProjectState) -> String {
        buildCommandDrivenMainFile(
            heading: "# GEMINI",
            guidance: state.items(of: .guidance),
            rules: state.items(of: .rule),
            skills: state.items(of: .skill),
            commands: state.items(of: .command)
        )
    }

    private func buildCodexMainFile(state: BridgeProjectState) -> String {
        let guidance = state.items(of: .guidance).map {
            $0.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let rules = state.items(of: .rule)
        let codexSkills = state.items.filter { item in
            switch item.kind {
            case .skill:
                return true
            case .command:
                return true
            default:
                return false
            }
        }

        var sections: [String] = [
            "# AGENTS",
            "",
            "Generated from Zion Bridge for active Codex usage.",
            "Active paths: `AGENTS.md`, `.agents/rules/*.md`, and `.agents/skills/*/SKILL.md`."
        ]

        if let primaryGuidance = guidance.first, !primaryGuidance.isEmpty {
            sections.append("")
            sections.append(primaryGuidance)
        }

        if !codexSkills.isEmpty {
            sections.append("")
            sections.append("## \(L10n("bridge.kind.skill"))")
            sections.append("")
            sections.append("### Available skills")
            sections.append(
                codexSkills
                    .sorted(by: sortItems(_:_:))
                    .map { "- \($0.slug): \($0.summary) (file: .agents/skills/\($0.slug)/SKILL.md)" }
                    .joined(separator: "\n")
            )
        }

        if !rules.isEmpty {
            sections.append("")
            sections.append("## \(L10n("bridge.kind.rule"))")
            sections.append(rules.sorted(by: sortItems(_:_:)).map { "- \($0.title)" }.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func buildCommandDrivenMainFile(
        heading: String,
        guidance: [BridgeItem],
        rules: [BridgeItem],
        skills: [BridgeItem],
        commands: [BridgeItem]
    ) -> String {
        var sections: [String] = [
            heading,
            "",
            L10n("bridge.generated.header")
        ]

        if let primaryGuidance = guidance.first?.content.trimmingCharacters(in: .whitespacesAndNewlines),
           !primaryGuidance.isEmpty {
            sections.append("")
            sections.append(primaryGuidance)
        }

        if !rules.isEmpty {
            sections.append("")
            sections.append("## \(L10n("bridge.kind.rule"))")
            sections.append(rules.sorted(by: sortItems(_:_:)).map { "- \($0.title)" }.joined(separator: "\n"))
        }

        if !skills.isEmpty {
            sections.append("")
            sections.append("## \(L10n("bridge.kind.skill"))")
            sections.append(skills.sorted(by: sortItems(_:_:)).map { "- \($0.title)" }.joined(separator: "\n"))
        }

        if !commands.isEmpty {
            sections.append("")
            sections.append("## \(L10n("bridge.kind.command"))")
            sections.append(commands.sorted(by: sortItems(_:_:)).map { "- \($0.title)" }.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func buildClaudeMirroredCodexSkill(for item: BridgeItem) -> String {
        let referencePath = item.mirrorReferencePath ?? ".claude/commands/\(item.slug).md"
        let description = codexMirroredSkillDescription(for: item.slug, fallback: item.summary)

        return """
        ---
        name: \(item.slug)
        description: \(description)
        ---

        Repo-local Codex skill generated from `\(referencePath)`.

        Workflow:
        1. Read `\(referencePath)` and follow it as the reference procedure.
        2. Treat `.claude/*` as immutable governance input unless the user explicitly asks to edit it.
        3. Prefer mirrored project rules in `.agents/rules/*.md` when the same rule exists there.
        4. Create or edit project files outside `.claude/`.
        """
    }

    private func reverseCodexMirrorTextForClaude(_ content: String) -> String {
        content
            .replacingOccurrences(of: ".agents/rules", with: ".claude/rules")
            .replacingOccurrences(of: ".agents/skills/", with: ".claude/commands/")
            .replacingOccurrences(of: "/SKILL.md", with: ".md")
            .replacingOccurrences(of: "AGENTS.md", with: "CLAUDE.md")
            .replacingOccurrences(of: "Codex", with: "Claude")
    }

    private func normalizeCodexSkillForClaudeCommand(
        _ content: String,
        fallbackSlug: String,
        title: String,
        referencePath: String
    ) -> String {
        var normalized = stripFrontmatter(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = dropLeadingHeading(from: normalized, matchingSlug: fallbackSlug, title: title)
        normalized = dropLeadingParagraph(
            from: normalized,
            matching: [
                "Mirror and execute the workflow defined for Claude command parity using Codex skills.",
                "Mirror and execute the workflow defined for Claude command parity using Claude skills.",
                "Repo-local Codex skill generated from `\(referencePath)`."
            ]
        )
        normalized = dropLeadingLiteralSection("## Workflow", from: normalized)
        normalized = dropGeneratedCodexWrapperWorkflow(from: normalized, referencePath: referencePath)
        normalized = reverseCodexMirrorTextForClaude(normalized)
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripFrontmatter(from content: String) -> String {
        guard content.hasPrefix("---\n") else {
            return content
        }

        guard let range = content.range(of: "\n---\n") else {
            return content
        }

        return String(content[range.upperBound...])
    }

    private func dropLeadingHeading(from content: String, matchingSlug: String, title: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }

        guard let firstLine = lines.first else {
            return content
        }

        let trimmedFirstLine = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedFirstLine.hasPrefix("# ") else {
            return content
        }

        let heading = trimmedFirstLine.replacingOccurrences(of: "# ", with: "")
        let normalizedHeading = slugify(heading)
        guard normalizedHeading == matchingSlug || normalizedHeading == slugify(title) else {
            return content
        }

        lines.removeFirst()
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }

        return lines.joined(separator: "\n")
    }

    private func dropLeadingParagraph(from content: String, matching candidates: [String]) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        for candidate in candidates where trimmed.hasPrefix(candidate) {
            let suffix = trimmed.dropFirst(candidate.count)
            return suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func dropLeadingLiteralSection(_ heading: String, from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(heading) else {
            return trimmed
        }

        let suffix = trimmed.dropFirst(heading.count)
        return suffix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dropGeneratedCodexWrapperWorkflow(from content: String, referencePath: String) -> String {
        let wrapper = [
            "Workflow:",
            "1. Read `\(referencePath)` and follow it as the reference procedure.",
            "2. Treat `.claude/*` as immutable governance input unless the user explicitly asks to edit it.",
            "3. Prefer mirrored project rules in `.agents/rules/*.md` when the same rule exists there.",
            "4. Create or edit project files outside `.claude/`."
        ].joined(separator: "\n")

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(wrapper) else {
            return trimmed
        }

        let suffix = trimmed.dropFirst(wrapper.count)
        return suffix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func wrapPortableCommandAsSkill(_ item: BridgeItem) -> String {
        """
        ---
        name: \(item.slug)
        description: \(item.summary)
        ---

        # \(item.title)

        \(item.content.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    private func makeItem(
        kind: BridgeItemKind,
        fallbackSlug: String,
        title: String,
        content: String,
        sourceHint: String?,
        strategy: BridgeItemStrategy = .portable,
        mirrorReferencePath: String? = nil
    ) -> BridgeItem {
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = extractSummary(from: normalizedContent)
        return BridgeItem(
            kind: kind,
            slug: slugify(fallbackSlug),
            title: title,
            summary: summary,
            content: normalizedContent + "\n",
            sourceHint: sourceHint,
            strategy: strategy,
            mirrorReferencePath: mirrorReferencePath
        )
    }

    private func extractSummary(from content: String) -> String {
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#") || trimmed == "---" { continue }
            return String(trimmed.prefix(120))
        }
        return L10n("bridge.summary.default")
    }

    private func extractSkillMetadata(from content: String, fallback: String) -> (name: String, description: String) {
        let lines = content.components(separatedBy: .newlines)
        var insideFrontmatter = false
        var name: String?
        var description: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                insideFrontmatter.toggle()
                continue
            }
            guard insideFrontmatter else { continue }

            if trimmed.hasPrefix("name:") {
                name = trimmed.replacingOccurrences(of: "name:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("description:") {
                description = trimmed.replacingOccurrences(of: "description:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return (
            name: sanitizedMetadataValue(name) ?? prettifyTitle(fallback),
            description: sanitizedMetadataValue(description) ?? extractSummary(from: content)
        )
    }

    private func sanitizedMetadataValue(_ value: String?) -> String? {
        guard var value else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return value.isEmpty ? nil : value
    }

    private func ensureParentDirectory(for fileURL: URL) throws {
        try createDirectory(fileURL.deletingLastPathComponent())
    }

    private func createDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func removeEmptyParents(startingAt directoryURL: URL, repositoryURL: URL) {
        guard directoryURL.path.hasPrefix(repositoryURL.path) else { return }
        guard directoryURL.path != repositoryURL.path else { return }

        if let contents = try? fileManager.contentsOfDirectory(atPath: directoryURL.path), contents.isEmpty {
            try? fileManager.removeItem(at: directoryURL)
            removeEmptyParents(startingAt: directoryURL.deletingLastPathComponent(), repositoryURL: repositoryURL)
        }
    }

    private func readTextIfExists(_ url: URL) -> String? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func relativePath(for url: URL, repositoryURL: URL) -> String {
        let normalizedURL = url.resolvingSymlinksInPath().standardizedFileURL.path
        let normalizedRepository = repositoryURL.resolvingSymlinksInPath().standardizedFileURL.path

        if normalizedURL.hasPrefix(normalizedRepository + "/") {
            return String(normalizedURL.dropFirst(normalizedRepository.count + 1))
        }

        if url.path.hasPrefix(repositoryURL.path + "/") {
            return String(url.path.dropFirst(repositoryURL.path.count + 1))
        }

        return url.lastPathComponent
    }

    private func contentMatches(_ existingContent: String?, _ renderedContent: String) -> Bool {
        guard let existingContent else {
            return false
        }

        return existingContent.trimmingCharacters(in: .whitespacesAndNewlines)
            == renderedContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func prettifyTitle(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func parseMirroredClaudeCommandReference(in content: String) -> String? {
        firstCapturedMatch(in: content, pattern: #"Repo-local Codex skill generated from `([^`]+)`\."#)
            ?? firstCapturedMatch(in: content, pattern: #"Read `([^`]+)` and follow it as the reference procedure\."#)
    }

    private func firstCapturedMatch(in content: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              match.numberOfRanges > 1,
              let capturedRange = Range(match.range(at: 1), in: content) else {
            return nil
        }

        return String(content[capturedRange])
    }

    private func codexMirroredSkillDescription(for slug: String, fallback: String) -> String {
        let descriptions: [String: String] = [
            "analyze-design": "Use when the user wants a structured design brief from text, screenshots, URLs, or Figma input.",
            "approve-to-library": "Use when the user wants to promote a workspace component into the theme library.",
            "build-component": "Use when the user wants an end-to-end Shopify section build with validation and preview.",
            "catalog": "Use when the user wants to browse or search the component registry.",
            "cleanup": "Use when the user wants to remove generated workspace files for a component.",
            "compose-page": "Use when the user wants to compose a full page from sections or visual inputs.",
            "compose-section": "Use when the user wants to build or update a Shopify section from text, screenshots, URLs, Figma, or Jira input.",
            "evaluate-section": "Use when the user wants a quality review of a section in workspace or theme code.",
            "generate-style-guide": "Use when the user wants to generate or refresh the living style guide page.",
            "oraculo": "Use when the user wants tool-level diagnosis, friction analysis, or governance changes rather than section work.",
            "push-to-shopify": "Use when the user wants to assemble the theme library and push it to Shopify.",
            "qa-visual-check": "Use when the user wants browser-based QA against a reference design or recent fix.",
            "setup-design-system": "Use when the user wants to initialize a new project or brand design system.",
            "stress-test-tool": "Use when the user wants to stress-test the build workflow and log tool friction.",
            "token-compress": "Use when the user wants token-efficiency analysis for governance files.",
            "update-figma-page": "Use when the user wants to update an existing page composition after Figma changes.",
            "update-tokens": "Use when the user wants to add or change design-system tokens without rebuilding from scratch."
        ]

        return descriptions[slug] ?? fallback
    }

    private func slugify(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let pieces = folded.split { !$0.isLetter && !$0.isNumber }
        let slug = pieces.map(String.init).filter { !$0.isEmpty }.joined(separator: "-")
        return slug.isEmpty ? "item" : slug
    }

    private func sortItems(_ lhs: BridgeItem, _ rhs: BridgeItem) -> Bool {
        if lhs.kind.rawValue == rhs.kind.rawValue {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }

    private func sortOperations(_ lhs: BridgeSyncOperation, _ rhs: BridgeSyncOperation) -> Bool {
        if lhs.kind.rawValue == rhs.kind.rawValue {
            return lhs.relativePath < rhs.relativePath
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}
