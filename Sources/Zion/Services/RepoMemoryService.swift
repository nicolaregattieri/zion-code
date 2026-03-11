import CryptoKit
import Foundation

actor RepoMemoryService {
    private static let schemaVersion = 1
    private let fileManager: FileManager
    private let baseDirectory: URL

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.baseDirectory = appSupport.appendingPathComponent("Zion/RepoMemory", isDirectory: true)
        }
    }

    func loadSnapshot(for repositoryURL: URL) -> RepoMemorySnapshot? {
        let url = snapshotURL(for: repositoryURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.repoMemoryDecoder.decode(RepoMemorySnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: RepoMemorySnapshot, for repositoryURL: URL) throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
        let data = try JSONEncoder.repoMemoryEncoder.encode(snapshot)
        try data.write(to: snapshotURL(for: repositoryURL), options: .atomic)
    }

    func clearSnapshot(for repositoryURL: URL) throws {
        let url = snapshotURL(for: repositoryURL)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func refreshSnapshot(
        for repositoryURL: URL,
        worker: RepositoryWorker,
        activeBranch: String,
        headShortHash: String
    ) async throws -> RepoMemorySnapshot {
        let commitLog = try await worker.runAction(args: ["log", "--oneline", "-200"], in: repositoryURL)
        let branches = (try? await worker.runAction(args: ["for-each-ref", "--format=%(refname:short)", "refs/heads"], in: repositoryURL)) ?? ""
        let filePaths = Self.enumerateRepositoryFiles(at: repositoryURL, fileManager: fileManager)
        let sampledSource = Self.sampleSourceMarkers(from: filePaths, repositoryURL: repositoryURL)
        let remote = (try? await worker.runAction(args: ["remote", "get-url", "origin"], in: repositoryURL).clean) ?? ""
        let snapshot = Self.buildSnapshot(
            repositoryURL: repositoryURL,
            activeBranch: activeBranch,
            headShortHash: headShortHash,
            commitSubjects: Self.parseCommitSubjects(from: commitLog),
            branchNames: branches.split(separator: "\n").map(String.init),
            repositoryFiles: filePaths,
            sampledSource: sampledSource,
            remote: remote
        )
        try saveSnapshot(snapshot, for: repositoryURL)
        return snapshot
    }

    nonisolated func promptContext(
        for snapshot: RepoMemorySnapshot,
        focusFiles: [String],
        mode: AIMode
    ) -> String {
        Self.renderPromptContext(snapshot: snapshot, focusFiles: focusFiles, mode: mode)
    }

    private func snapshotURL(for repositoryURL: URL) -> URL {
        baseDirectory.appendingPathComponent("\(Self.repoFingerprint(for: repositoryURL)).json")
    }

    static func buildSnapshot(
        repositoryURL: URL,
        activeBranch: String,
        headShortHash: String,
        commitSubjects: [String],
        branchNames: [String],
        repositoryFiles: [String],
        sampledSource: [String],
        remote: String
    ) -> RepoMemorySnapshot {
        let sanitizedSubjects = commitSubjects
            .map(Self.sanitizedText(_:))
            .filter { !$0.isEmpty }
        let sanitizedFiles = repositoryFiles
            .map(Self.sanitizedRelativePath(_:))
            .filter { !$0.isEmpty }
        let sanitizedBranches = branchNames
            .map(Self.sanitizedText(_:))
            .filter { !$0.isEmpty }

        return RepoMemorySnapshot(
            schemaVersion: schemaVersion,
            repositoryID: "\(repoFingerprint(for: repositoryURL))-\(shortHash(remote))",
            generatedAt: Date(),
            activeBranch: sanitizedText(activeBranch),
            headShortHash: sanitizedText(headShortHash),
            commitStyle: buildCommitStyleProfile(from: sanitizedSubjects),
            moduleHints: deriveModules(from: sanitizedFiles, limit: 8),
            branchPatterns: deriveBranchPatterns(from: sanitizedBranches, limit: 6),
            conventions: deriveConventions(from: sanitizedFiles, sampledSource: sampledSource, subjects: sanitizedSubjects),
            testMappings: deriveTestMappings(from: sanitizedFiles),
            sensitiveAreas: deriveSensitiveAreas(from: sanitizedFiles)
        )
    }

    static func renderPromptContext(
        snapshot: RepoMemorySnapshot,
        focusFiles: [String],
        mode: AIMode
    ) -> String {
        let limits: (modules: Int, branches: Int, conventions: Int, focusFiles: Int) = switch mode {
        case .efficient: (3, 2, 3, 3)
        case .smart: (5, 3, 5, 5)
        case .bestQuality: (7, 5, 6, 6)
        }

        let sanitizedFocus = focusFiles
            .map(Self.sanitizedRelativePath(_:))
            .filter { !$0.isEmpty }
            .prefix(limits.focusFiles)

        var sections: [String] = []
        if !snapshot.activeBranch.isEmpty {
            sections.append("branch: \(snapshot.activeBranch)")
        }
        if snapshot.commitStyle.usesConventionalCommits {
            let types = snapshot.commitStyle.commonTypes.prefix(3).joined(separator: ", ")
            let scopes = snapshot.commitStyle.commonScopes.prefix(3).joined(separator: ", ")
            sections.append("commit style: conventional commits, common types \(types), common scopes \(scopes)")
        } else {
            sections.append("commit style: repo titles average \(snapshot.commitStyle.averageTitleLength) chars")
        }
        if !snapshot.moduleHints.isEmpty {
            sections.append("modules: \(snapshot.moduleHints.prefix(limits.modules).joined(separator: ", "))")
        }
        if !snapshot.branchPatterns.isEmpty {
            sections.append("branch patterns: \(snapshot.branchPatterns.prefix(limits.branches).joined(separator: ", "))")
        }
        if !snapshot.conventions.isEmpty {
            sections.append("conventions: \(snapshot.conventions.prefix(limits.conventions).joined(separator: ", "))")
        }
        if !snapshot.sensitiveAreas.isEmpty {
            sections.append("sensitive areas: \(snapshot.sensitiveAreas.prefix(3).joined(separator: ", "))")
        }
        if !sanitizedFocus.isEmpty {
            sections.append("focus files: \(sanitizedFocus.joined(separator: ", "))")
            let mappedTests = sanitizedFocus.compactMap { focus in
                snapshot.testMappings.first { focus.localizedCaseInsensitiveContains($0.key) }?.value.first
            }
            if !mappedTests.isEmpty {
                sections.append("likely tests: \(mappedTests.prefix(3).joined(separator: ", "))")
            }
        }

        return sections.joined(separator: "\n")
    }

    static func repoFingerprint(for repositoryURL: URL) -> String {
        shortHash(repositoryURL.standardizedFileURL.path)
    }

    static func parseCommitSubjects(from log: String) -> [String] {
        log.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            return parts.count == 2 ? String(parts[1]) : trimmed
        }
    }

    static func deriveModules(from repositoryFiles: [String], limit: Int) -> [String] {
        var modules: [String] = []
        var seen = Set<String>()

        for path in repositoryFiles {
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { continue }
            let candidates = [parts.dropFirst().first, parts.first]
                .compactMap { $0 }
                .map { String($0) }

            for candidate in candidates where seen.insert(candidate).inserted {
                modules.append(candidate)
                if modules.count == limit { return modules }
            }
        }

        return modules
    }

    static func deriveBranchPatterns(from branchNames: [String], limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for branch in branchNames {
            let token = branch.split(separator: "/").first.map(String.init) ??
                branch.split(separator: "-").first.map(String.init) ??
                branch
            guard !token.isEmpty else { continue }
            counts[token, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map(\.key)
            .prefix(limit)
            .map { $0 }
    }

    static func buildCommitStyleProfile(from commitSubjects: [String]) -> CommitStyleProfile {
        let regex = try? NSRegularExpression(pattern: #"^([a-z]+)(?:\(([^)]+)\))?:\s+"#)
        var typeCounts: [String: Int] = [:]
        var scopeCounts: [String: Int] = [:]
        var conventionalCount = 0

        for subject in commitSubjects {
            let nsRange = NSRange(subject.startIndex..., in: subject)
            guard let match = regex?.firstMatch(in: subject, range: nsRange) else { continue }
            conventionalCount += 1
            if let typeRange = Range(match.range(at: 1), in: subject) {
                typeCounts[String(subject[typeRange]), default: 0] += 1
            }
            if let scopeRange = Range(match.range(at: 2), in: subject), !scopeRange.isEmpty {
                scopeCounts[String(subject[scopeRange]), default: 0] += 1
            }
        }

        let averageLength = commitSubjects.isEmpty ? 0 : commitSubjects.map(\.count).reduce(0, +) / commitSubjects.count
        return CommitStyleProfile(
            usesConventionalCommits: conventionalCount >= max(1, commitSubjects.count / 2),
            commonTypes: topKeys(from: typeCounts, limit: 5),
            commonScopes: topKeys(from: scopeCounts, limit: 5),
            preferredVerbStyle: "imperative",
            averageTitleLength: averageLength
        )
    }

    static func deriveConventions(from repositoryFiles: [String], sampledSource: [String], subjects: [String]) -> [String] {
        var conventions: [String] = []
        if repositoryFiles.contains(where: { $0.contains("Resources/en.lproj/Localizable.strings") }) {
            conventions.append("localized strings are maintained in en, pt-BR, and es")
        }
        if sampledSource.contains(where: { $0.contains("L10n(") }) {
            conventions.append("user-facing strings use L10n")
        }
        if sampledSource.contains(where: { $0.contains("DesignSystem") }) {
            conventions.append("shared visual tokens come from DesignSystem")
        }
        if repositoryFiles.contains(where: { $0.contains("Tests/ZionTests") }) {
            conventions.append("unit tests live under Tests/ZionTests")
        }
        if sampledSource.contains(where: { $0.contains("@Observable") }) {
            conventions.append("observable state uses @Observable")
        }
        if sampledSource.contains(where: { $0.contains("RepositoryViewModel+") }) {
            conventions.append("view model behavior is split into extension files")
        }
        if subjects.contains(where: { $0.contains("feat(") || $0.contains("fix(") }) {
            conventions.append("commit titles often follow conventional commit formatting")
        }
        return Array(conventions.prefix(6))
    }

    static func deriveTestMappings(from repositoryFiles: [String]) -> [String: [String]] {
        let testFiles = repositoryFiles.filter {
            $0.localizedCaseInsensitiveContains("test") || $0.contains("/Tests/")
        }
        guard !testFiles.isEmpty else { return [:] }

        let moduleHints = deriveModules(from: repositoryFiles, limit: 12)
        var mappings: [String: [String]] = [:]
        for module in moduleHints {
            let matchedTests = testFiles.filter { $0.localizedCaseInsensitiveContains(module) }
            if !matchedTests.isEmpty {
                mappings[module] = Array(matchedTests.prefix(3))
            }
        }
        return mappings
    }

    static func deriveSensitiveAreas(from repositoryFiles: [String]) -> [String] {
        let keywords = ["auth", "security", "credential", "token", "remoteaccess", "payment", "keychain", "crypto"]
        let matches = repositoryFiles.filter { path in
            keywords.contains { path.lowercased().contains($0) }
        }
        return Array(deriveModules(from: matches, limit: 6).prefix(4))
    }

    private static func enumerateRepositoryFiles(at repositoryURL: URL, fileManager: FileManager) -> [String] {
        let ignoredDirectories = [".git", ".build", "node_modules", "dist", "DerivedData", ".swiftpm"]
        let allowedExtensions = Set(["swift", "md", "txt", "yml", "yaml", "json", "strings"])
        guard let enumerator = fileManager.enumerator(
            at: repositoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [String] = []
        while let url = enumerator.nextObject() as? URL, files.count < 2000 {
            let relative = url.path.replacingOccurrences(of: repositoryURL.path + "/", with: "")
            if ignoredDirectories.contains(where: { relative.hasPrefix($0 + "/") || relative == $0 }) {
                enumerator.skipDescendants()
                continue
            }
            if allowedExtensions.contains(url.pathExtension.lowercased()) {
                files.append(relative)
            }
        }
        return files.sorted()
    }

    private static func sampleSourceMarkers(from repositoryFiles: [String], repositoryURL: URL) -> [String] {
        let markerFiles = repositoryFiles.filter {
            $0.hasSuffix(".swift") || $0.hasSuffix(".md")
        }

        var samples: [String] = []
        for path in markerFiles.prefix(24) {
            let fileURL = repositoryURL.appendingPathComponent(path)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            samples.append(String(content.prefix(800)))
        }
        return samples
    }

    private static func sanitizedRelativePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let withoutHome = trimmed.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return String(withoutHome.prefix(160))
    }

    private static func sanitizedText(_ text: String) -> String {
        var sanitized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return "" }
        sanitized = sanitized.replacingOccurrences(
            of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            with: "[redacted-email]",
            options: [.regularExpression, .caseInsensitive]
        )
        sanitized = sanitized.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        sanitized = sanitized.replacingOccurrences(
            of: #"(sk-[A-Za-z0-9_\-]{20,}|AIza[0-9A-Za-z\-_]{20,}|ghp_[A-Za-z0-9]{20,})"#,
            with: "[redacted-secret]",
            options: [.regularExpression]
        )
        return String(sanitized.prefix(240))
    }

    private static func topKeys(from counts: [String: Int], limit: Int) -> [String] {
        counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map(\.key)
    }

    private static func shortHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}

private extension JSONEncoder {
    static var repoMemoryEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var repoMemoryDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
