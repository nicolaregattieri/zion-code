import CryptoKit
import Foundation

struct BridgeService {
    private let fileManager: FileManager
    private let cacheStore: BridgeCacheStore

    init(
        fileManager: FileManager = .default,
        cacheStore: BridgeCacheStore = BridgeCacheStore()
    ) {
        self.fileManager = fileManager
        self.cacheStore = cacheStore
    }

    func loadState(repositoryURL: URL) -> BridgeProjectState {
        let detections = BridgeTarget.allCases.map { target in
            detection(for: target, repositoryURL: repositoryURL)
        }
        let warnings: [String] = detections.contains(where: \.isDetected) ? [] : [L10n("bridge.warning.noTargets")]
        return BridgeProjectState(detections: detections, warnings: warnings)
    }

    func analyze(
        from source: BridgeTarget,
        to destination: BridgeTarget,
        repositoryURL: URL
    ) throws -> BridgeMigrationAnalysis {
        guard source != destination else {
            throw NSError(domain: "BridgeService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: L10n("bridge.error.sameTarget")
            ])
        }

        let matrix = cacheStore.loadMatrix(for: repositoryURL)
        var warnings: [String] = []
        let artifacts = discoverArtifacts(for: source, repositoryURL: repositoryURL, warnings: &warnings)
        let rows = buildRows(
            for: artifacts,
            source: source,
            destination: destination,
            repositoryURL: repositoryURL,
            matrix: matrix
        )

        if artifacts.isEmpty {
            warnings.append(L10n("bridge.warning.noSourceFiles", source.label))
        }

        return BridgeMigrationAnalysis(
            sourceTarget: source,
            destinationTarget: destination,
            rows: rows,
            warnings: Array(NSOrderedSet(array: warnings)) as? [String] ?? warnings,
            generatedAt: Date()
        )
    }

    func apply(
        _ analysis: BridgeMigrationAnalysis,
        repositoryURL: URL,
        selectedRowIDs: Set<String>? = nil
    ) throws -> BridgeMigrationAnalysis {
        let rowsToApply = analysis.rows.filter { row in
            guard row.isSyncable else { return false }
            guard let selectedRowIDs else { return true }
            return selectedRowIDs.contains(row.id)
        }

        for row in rowsToApply {
            guard let destinationRelativePath = row.destinationRelativePath else { continue }
            guard let renderedContent = row.renderedContent else { continue }

            let destinationURL = repositoryURL.appendingPathComponent(destinationRelativePath)
            try ensureParentDirectory(for: destinationURL)
            try renderedContent.write(to: destinationURL, atomically: true, encoding: .utf8)
        }

        var matrix = cacheStore.loadMatrix(for: repositoryURL)
        let refreshedRecords = rowsToApply.compactMap { row -> BridgeMirrorRecord? in
            guard let destinationRelativePath = row.destinationRelativePath else { return nil }
            guard row.mappingKind != .manualReview, row.mappingKind != .unsupported else { return nil }

            let sourceHash = sha256(row.sourceArtifact.content)
            let destinationContent = row.renderedContent ?? row.destinationPreview
            return BridgeMirrorRecord(
                sourceTarget: analysis.sourceTarget,
                destinationTarget: analysis.destinationTarget,
                sourceRelativePath: row.sourceArtifact.relativePath,
                destinationRelativePath: destinationRelativePath,
                mappingKind: row.mappingKind,
                confidence: row.confidence,
                sourceHash: sourceHash,
                destinationHash: sha256(destinationContent),
                updatedAt: Date()
            )
        }

        merge(records: refreshedRecords, into: &matrix)
        try cacheStore.saveMatrix(matrix, for: repositoryURL)

        return try analyze(from: analysis.sourceTarget, to: analysis.destinationTarget, repositoryURL: repositoryURL)
    }

    private func buildRows(
        for artifacts: [BridgeArtifact],
        source: BridgeTarget,
        destination: BridgeTarget,
        repositoryURL: URL,
        matrix: BridgeMirrorMatrix
    ) -> [BridgeMappingRow] {
        let existingDestinationFiles = destinationFiles(for: destination, repositoryURL: repositoryURL)
        var rows: [BridgeMappingRow] = artifacts.map { artifact in
            row(
                for: artifact,
                source: source,
                destination: destination,
                repositoryURL: repositoryURL,
                matrix: matrix,
                existingDestinationFiles: existingDestinationFiles
            )
        }

        let grouped = Dictionary(grouping: rows.filter { $0.destinationRelativePath != nil }, by: \.destinationRelativePath!)
        let duplicatePaths = Set(grouped.filter { $0.value.count > 1 }.keys)

        rows = rows.map { row in
            guard let destinationRelativePath = row.destinationRelativePath, duplicatePaths.contains(destinationRelativePath) else {
                return row
            }

            return BridgeMappingRow(
                sourceArtifact: row.sourceArtifact,
                destinationTarget: row.destinationTarget,
                destinationRelativePath: row.destinationRelativePath,
                mappingKind: .manualReview,
                action: .manualReview,
                confidence: .low,
                reason: L10n("bridge.reason.multipleCandidates"),
                sourcePreview: row.sourcePreview,
                destinationPreview: row.destinationPreview,
                renderedContent: nil
            )
        }

        return rows.sorted(by: sortRows(_:_:))
    }

    private func row(
        for artifact: BridgeArtifact,
        source: BridgeTarget,
        destination: BridgeTarget,
        repositoryURL: URL,
        matrix: BridgeMirrorMatrix,
        existingDestinationFiles: Set<String>
    ) -> BridgeMappingRow {
        let resolved = resolveDestination(
            for: artifact,
            destination: destination,
            repositoryURL: repositoryURL,
            matrix: matrix,
            existingDestinationFiles: existingDestinationFiles
        )

        guard let destinationRelativePath = resolved.relativePath else {
            return BridgeMappingRow(
                sourceArtifact: artifact,
                destinationTarget: destination,
                destinationRelativePath: nil,
                mappingKind: resolved.mappingKind,
                action: .unsupported,
                confidence: resolved.confidence,
                reason: resolved.reason,
                sourcePreview: previewText(from: cleanedSourceBody(for: artifact, destination: destination)),
                destinationPreview: "",
                renderedContent: nil
            )
        }

        let destinationURL = repositoryURL.appendingPathComponent(destinationRelativePath)
        let existingContent = readTextIfExists(destinationURL) ?? ""
        let renderedContent = renderDestinationContent(
            for: artifact,
            destination: destination,
            destinationRelativePath: destinationRelativePath
        )

        let action: BridgeSyncActionKind
        if existingContent.isEmpty {
            action = .create
        } else if normalizeComparison(existingContent) == normalizeComparison(renderedContent) {
            action = .noop
        } else {
            action = .update
        }

        return BridgeMappingRow(
            sourceArtifact: artifact,
            destinationTarget: destination,
            destinationRelativePath: destinationRelativePath,
            mappingKind: resolved.mappingKind,
            action: resolved.mappingKind == .manualReview ? .manualReview : action,
            confidence: resolved.confidence,
            reason: resolved.reason,
            sourcePreview: previewText(from: cleanedSourceBody(for: artifact, destination: destination)),
            destinationPreview: previewText(from: existingContent.isEmpty ? renderedContent : existingContent),
            renderedContent: resolved.mappingKind == .manualReview ? nil : renderedContent
        )
    }

    private func resolveDestination(
        for artifact: BridgeArtifact,
        destination: BridgeTarget,
        repositoryURL: URL,
        matrix: BridgeMirrorMatrix,
        existingDestinationFiles: Set<String>
    ) -> (relativePath: String?, mappingKind: BridgeMappingKind, confidence: BridgeConfidence, reason: String) {
        if let cached = matrix.records.first(where: {
            $0.sourceTarget == artifact.sourceTarget &&
                $0.destinationTarget == destination &&
                $0.sourceRelativePath == artifact.relativePath
        }) {
            return (
                cached.destinationRelativePath,
                .knownMirror,
                .high,
                L10n("bridge.reason.cached")
            )
        }

        if artifact.homeTarget == destination {
            return (
                artifact.homeRelativePath,
                .knownMirror,
                .high,
                L10n("bridge.reason.home")
            )
        }

        guard let inferred = inferredDestinationPath(for: artifact, destination: destination) else {
            return (
                nil,
                .unsupported,
                .low,
                L10n("bridge.reason.unsupported")
            )
        }

        if existingDestinationFiles.contains(inferred) {
            return (
                inferred,
                .inferredMirror,
                .medium,
                L10n("bridge.reason.pathMatch")
            )
        }

        return (
            inferred,
            .newImport,
            .medium,
            L10n("bridge.reason.newImport")
        )
    }

    private func detection(for target: BridgeTarget, repositoryURL: URL) -> BridgeToolDetection {
        let paths = discoveryRoots(for: target)
        let hitPaths = paths.filter { fileManager.fileExists(atPath: repositoryURL.appendingPathComponent($0).path) }
        return BridgeToolDetection(
            target: target,
            isDetected: !hitPaths.isEmpty,
            detail: hitPaths.isEmpty ? L10n("bridge.detect.none") : hitPaths.joined(separator: ", ")
        )
    }

    private func discoverArtifacts(
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

    private func markdownArtifacts(
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

    private func skillArtifacts(
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

    private func cursorArtifacts(in repositoryURL: URL) -> [BridgeArtifact] {
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

    private func makeArtifact(
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

    private func renderDestinationContent(
        for artifact: BridgeArtifact,
        destination: BridgeTarget,
        destinationRelativePath: String
    ) -> String {
        switch destination {
        case .claude:
            switch artifact.kind {
            case .guidance:
                return normalizedMarkdown(cleanedSourceBody(for: artifact, destination: destination))
            case .rule, .command, .skill:
                return normalizedMarkdown(cleanedSourceBody(for: artifact, destination: destination))
            }

        case .codex:
            switch artifact.kind {
            case .guidance:
                return normalizedMarkdown(cleanedSourceBody(for: artifact, destination: destination))
            case .rule:
                return normalizedMarkdown(cleanedSourceBody(for: artifact, destination: destination))
            case .command, .skill:
                return renderSkillWrapper(
                    name: artifact.slug,
                    description: artifact.summary,
                    source: artifact,
                    body: cleanedSourceBody(for: artifact, destination: destination),
                    destinationRelativePath: destinationRelativePath
                )
            }

        case .gemini:
            switch artifact.kind {
            case .guidance, .rule, .command:
                return normalizedMarkdown(cleanedSourceBody(for: artifact, destination: destination))
            case .skill:
                return renderGenericSkillBundle(
                    name: artifact.slug,
                    description: artifact.summary,
                    source: artifact,
                    body: cleanedSourceBody(for: artifact, destination: destination),
                    destinationRelativePath: destinationRelativePath
                )
            }

        case .cursor:
            return renderCursorRule(
                title: artifact.title,
                description: artifact.summary,
                source: artifact,
                body: cleanedSourceBody(for: artifact, destination: destination),
                destinationRelativePath: destinationRelativePath
            )
        }
    }

    private func cleanedSourceBody(for artifact: BridgeArtifact, destination: BridgeTarget) -> String {
        var body = artifact.content
        body = removingBridgeMarkers(from: body)
        body = stripFrontmatter(from: body)
        body = extractMirrorSource(from: body) ?? body
        body = normalizePathReferences(in: body, destination: destination)
        body = stripLeadingHeading(from: body, matching: artifact.title)
        return body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func inferredDestinationPath(for artifact: BridgeArtifact, destination: BridgeTarget) -> String? {
        switch destination {
        case .claude:
            switch artifact.kind {
            case .guidance:
                return "CLAUDE.md"
            case .rule:
                return ".claude/rules/\(artifact.slug).md"
            case .command, .skill:
                return ".claude/commands/\(artifact.slug).md"
            }

        case .codex:
            switch artifact.kind {
            case .guidance:
                return "AGENTS.md"
            case .rule:
                return ".agents/rules/\(artifact.slug).md"
            case .command, .skill:
                return ".agents/skills/\(artifact.slug)/SKILL.md"
            }

        case .gemini:
            switch artifact.kind {
            case .guidance:
                return "GEMINI.md"
            case .rule:
                return ".gemini/rules/\(artifact.slug).md"
            case .command:
                return ".gemini/commands/\(artifact.slug).md"
            case .skill:
                return ".gemini/skills/\(artifact.slug)/SKILL.md"
            }

        case .cursor:
            switch artifact.kind {
            case .guidance:
                return ".cursor/rules/project-context.mdc"
            case .rule, .command, .skill:
                return ".cursor/rules/\(artifact.slug).mdc"
            }
        }
    }

    private func renderSkillWrapper(
        name: String,
        description: String,
        source: BridgeArtifact,
        body: String,
        destinationRelativePath: String
    ) -> String {
        let summary = description.isEmpty ? "Mirror of \(source.relativePath)." : description
        let marker = bridgeMarker(for: source, destinationRelativePath: destinationRelativePath)

        return """
        ---
        name: \(name)
        description: \(yamlEscaped(summary))
        ---

        \(marker)

        # \(name)

        Use this skill when the task matches the mirrored workflow.

        ## Workflow
        1. Use the mirror source below as the main instruction body.
        2. Keep repo-specific file paths in native \(source.homeTarget.label) shape when syncing back.

        ## Mirror Source
        \(body.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    private func renderGenericSkillBundle(
        name: String,
        description: String,
        source: BridgeArtifact,
        body: String,
        destinationRelativePath: String
    ) -> String {
        let marker = bridgeMarker(for: source, destinationRelativePath: destinationRelativePath)
        let summary = description.isEmpty ? "Portable mirror of \(source.relativePath)." : description
        return """
        ---
        name: \(name)
        description: \(yamlEscaped(summary))
        ---

        \(marker)

        # \(name)

        ## Mirror Source
        \(body.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    private func renderCursorRule(
        title: String,
        description: String,
        source: BridgeArtifact,
        body: String,
        destinationRelativePath: String
    ) -> String {
        let marker = bridgeMarker(for: source, destinationRelativePath: destinationRelativePath)
        let summary = yamlEscaped(description.isEmpty ? "Mirror of \(source.relativePath)." : description)
        return """
        ---
        description: \(summary)
        globs:
        alwaysApply: false
        ---

        \(marker)

        # \(title)

        ## Mirror Source
        \(body.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    private func bridgeMarker(for source: BridgeArtifact, destinationRelativePath: String) -> String {
        guard !(source.homeTarget == source.sourceTarget && source.homeRelativePath == destinationRelativePath) else {
            return ""
        }
        return "<!-- Zion Bridge: home=\(source.homeTarget.rawValue):\(source.homeRelativePath) -->"
    }

    private func embeddedHome(in content: String) -> (target: BridgeTarget, relativePath: String)? {
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

    private func extractMirrorSource(from body: String) -> String? {
        guard let range = body.range(of: "\n## Mirror Source\n") else { return nil }
        let content = body[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content + "\n"
    }

    private func removingBridgeMarkers(from body: String) -> String {
        body.replacingOccurrences(
            of: #"(?m)^<!--\s*Zion Bridge:\s*home=.*?-->\n?"#,
            with: "",
            options: .regularExpression
        )
    }

    private func stripFrontmatter(from body: String) -> String {
        let pattern = #"(?s)\A---\n.*?\n---\n?"#
        return body.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private func stripLeadingHeading(from body: String, matching title: String) -> String {
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

    private func normalizePathReferences(in body: String, destination: BridgeTarget) -> String {
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

    private func normalizedMarkdown(_ body: String) -> String {
        body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func previewText(from body: String) -> String {
        let compact = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > 220 else { return compact }
        let index = compact.index(compact.startIndex, offsetBy: 220)
        return String(compact[..<index]) + "..."
    }

    private func normalizeComparison(_ body: String) -> String {
        body.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func merge(records newRecords: [BridgeMirrorRecord], into matrix: inout BridgeMirrorMatrix) {
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

    private func destinationFiles(for target: BridgeTarget, repositoryURL: URL) -> Set<String> {
        var paths: Set<String> = []
        for root in discoveryRoots(for: target) {
            let url = repositoryURL.appendingPathComponent(root)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
                    for case let child as URL in enumerator {
                        var childIsDirectory: ObjCBool = false
                        if fileManager.fileExists(atPath: child.path, isDirectory: &childIsDirectory), !childIsDirectory.boolValue {
                            paths.insert(child.path.replacingOccurrences(of: repositoryURL.path + "/", with: ""))
                        }
                    }
                }
            } else {
                paths.insert(root)
            }
        }
        return paths
    }

    private func discoveryRoots(for target: BridgeTarget) -> [String] {
        switch target {
        case .claude:
            return ["CLAUDE.md", ".claude/rules", ".claude/commands"]
        case .codex:
            return ["AGENTS.md", ".agents/rules", ".agents/skills"]
        case .gemini:
            return ["GEMINI.md", ".gemini/rules", ".gemini/commands", ".gemini/skills"]
        case .cursor:
            return [".cursor/rules"]
        }
    }

    private func ensureParentDirectory(for url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func readTextIfExists(_ url: URL) -> String? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func extractSkillMetadata(from content: String, fallback: String) -> (name: String, description: String) {
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

    private func yamlEscaped(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func slugify(_ value: String) -> String {
        let lowered = value.lowercased()
        let components = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return components.filter { !$0.isEmpty }.joined(separator: "-")
    }

    private func prettifyTitle(_ slug: String) -> String {
        slug
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func sortRows(_ lhs: BridgeMappingRow, _ rhs: BridgeMappingRow) -> Bool {
        if lhs.action == rhs.action {
            return lhs.sourceArtifact.relativePath < rhs.sourceArtifact.relativePath
        }

        func rank(_ action: BridgeSyncActionKind) -> Int {
            switch action {
            case .update: return 0
            case .create: return 1
            case .noop: return 2
            case .manualReview: return 3
            case .unsupported: return 4
            }
        }

        return rank(lhs.action) < rank(rhs.action)
    }
}
