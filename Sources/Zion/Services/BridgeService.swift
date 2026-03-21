import CryptoKit
import Foundation

struct BridgeService {
    let fileManager: FileManager
    let cacheStore: BridgeCacheStore

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
            guard let content = row.effectiveContent else { continue }

            let destinationURL = repositoryURL.appendingPathComponent(destinationRelativePath)
            try ensureParentDirectory(for: destinationURL)
            try content.write(to: destinationURL, atomically: true, encoding: .utf8)
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

    // MARK: - Row Building

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
                renderedContent: nil,
                transformedContent: nil,
                validationWarnings: [],
                compatibilityScore: nil
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
                renderedContent: nil,
                transformedContent: nil,
                validationWarnings: [],
                compatibilityScore: nil
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

        let warnings = validateRenderedContent(
            renderedContent,
            destination: destination,
            artifact: artifact,
            destinationRelativePath: destinationRelativePath
        )

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
            renderedContent: resolved.mappingKind == .manualReview ? nil : renderedContent,
            transformedContent: nil,
            validationWarnings: warnings,
            compatibilityScore: nil
        )
    }

    // MARK: - Resolution Logic

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
        var hitDetails: [String] = []
        for path in paths {
            let url = repositoryURL.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let count = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?
                    .filter { !$0.lastPathComponent.hasPrefix(".") }.count ?? 0
                hitDetails.append(count > 0 ? path : "\(path) (\(L10n("bridge.detect.empty.folder")))")
            } else {
                hitDetails.append(path)
            }
        }
        return BridgeToolDetection(
            target: target,
            isDetected: !hitDetails.isEmpty,
            detail: hitDetails.isEmpty ? L10n("bridge.detect.none") : hitDetails.joined(separator: ", ")
        )
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

    // MARK: - Content Rendering

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

    // MARK: - Content Validation (Phase 1B)

    private func validateRenderedContent(
        _ content: String,
        destination: BridgeTarget,
        artifact: BridgeArtifact,
        destinationRelativePath: String
    ) -> [String] {
        var warnings: [String] = []

        switch destination {
        case .cursor:
            // Check YAML frontmatter is valid
            if !content.hasPrefix("---\n") {
                warnings.append(L10n("bridge.validation.cursor.noFrontmatter"))
            }
            // Check .mdc extension
            if !destinationRelativePath.hasSuffix(".mdc") {
                warnings.append(L10n("bridge.validation.cursor.wrongExtension"))
            }
            // Check for unsupported directives (Claude XML tags)
            if content.contains("<tool_use>") || content.contains("<result>") || content.contains("<anthr") {
                warnings.append(L10n("bridge.validation.cursor.unsupportedDirectives"))
            }

        case .claude:
            // Check markdown structure
            if content.contains("---\n") && content.contains("alwaysApply:") {
                warnings.append(L10n("bridge.validation.claude.cursorSyntax"))
            }
            // Check for Codex-specific syntax
            if content.contains("## Workflow\n1. Use the mirror source") {
                warnings.append(L10n("bridge.validation.claude.codexSyntax"))
            }

        case .codex:
            // Check AGENTS.md structure for guidance files
            if artifact.kind == .skill {
                if !content.contains("---\nname:") {
                    warnings.append(L10n("bridge.validation.codex.missingSkillFrontmatter"))
                }
            }

        case .gemini:
            // Check for Claude-specific XML directives
            if content.contains("<tool_use>") || content.contains("</tool_use>") {
                warnings.append(L10n("bridge.validation.gemini.claudeDirectives"))
            }
        }

        // Universal checks
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append(L10n("bridge.validation.emptyContent"))
        }

        return warnings
    }

    // MARK: - Round-Trip Safety (Phase 1D)

    func computeDestinationDiff(
        existingContent: String,
        newContent: String
    ) -> (linesAdded: Int, linesRemoved: Int, destinationOnlyLines: [String]) {
        let existingLines = Set(existingContent.components(separatedBy: .newlines))
        let newLines = Set(newContent.components(separatedBy: .newlines))

        let removed = existingLines.subtracting(newLines)
        let added = newLines.subtracting(existingLines)
        let destinationOnly = Array(existingLines.subtracting(newLines))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return (linesAdded: added.count, linesRemoved: removed.count, destinationOnlyLines: destinationOnly)
    }

    // MARK: - File Helpers

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

    func readTextIfExists(_ url: URL) -> String? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Sorting

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
