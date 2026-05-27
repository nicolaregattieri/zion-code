// RepoMapService.swift
//
// Hand-rolled regex-based symbol scanner for Swift, TypeScript/JavaScript, Python, Go, and Rust.
// Builds a directed reference graph over discovered symbols and ranks entries via PageRank
// (damping 0.85, 30 iterations). Snapshot is persisted to:
//   ~/Library/Application Support/Zion/repo-map/<repoID>.json
//
// NOTE: Tree-sitter integration is deferred to a follow-up task. The current regex scanner
// covers the common declaration forms for each language but will miss dynamically constructed
// names, macro-generated symbols, and multi-line declarations. A tree-sitter migration will
// produce a complete, parse-tree-accurate symbol list.

import Foundation
import CryptoKit

// MARK: - RepoMapEntry

public struct RepoMapEntry: Identifiable, Equatable, Codable, Sendable {
    public var id: String { "\(path):\(name)" }
    public let path: String
    public let kind: String
    public let name: String
    public var score: Double
    public let snippet: String?

    public init(path: String, kind: String, name: String, score: Double = 1.0, snippet: String? = nil) {
        self.path = path
        self.kind = kind
        self.name = name
        self.score = score
        self.snippet = snippet
    }
}

// MARK: - RepoMapSnapshot

public struct RepoMapSnapshot: Codable, Sendable {
    public let repoID: String
    public let indexedAt: Date
    public var entries: [RepoMapEntry]
    /// symbol name → list of file paths that reference it
    public var references: [String: [String]]

    public init(repoID: String, indexedAt: Date, entries: [RepoMapEntry], references: [String: [String]]) {
        self.repoID = repoID
        self.indexedAt = indexedAt
        self.entries = entries
        self.references = references
    }
}

// MARK: - RepoMapService

public actor RepoMapService {

    // MARK: - State

    private var snapshots: [String: RepoMapSnapshot] = [:]

    // MARK: - Directory

    public static func sharedDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("Zion", isDirectory: true)
            .appendingPathComponent("repo-map", isDirectory: true)
    }

    // MARK: - repoID

    private static func repoID(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let data = Data(path.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Public API

    /// Build (or rebuild) the symbol map for the repo at `repoURL`.
    public func ensureMap(repoURL: URL) async throws {
        let repoID = Self.repoID(for: repoURL)
        let snapshot = try buildSnapshot(repoURL: repoURL, repoID: repoID)
        snapshots[repoID] = snapshot
        try persist(snapshot: snapshot)
    }

    /// Alias for `ensureMap` — forces a full re-index.
    public func refresh(repoURL: URL) async throws {
        try await ensureMap(repoURL: repoURL)
    }

    /// Phase 4 — top-N PageRank-ranked symbols mapped to `SymbolEntry`.
    /// Reads from already-computed snapshots; never recomputes PageRank,
    /// never touches the persisted snapshot file format.
    func topSymbols(limit: Int = 50) async -> [SymbolEntry] {
        let all = snapshots.values.flatMap { $0.entries }
        let sorted = all.sorted { $0.score > $1.score }
        return sorted.prefix(limit).map { entry in
            SymbolEntry(
                file: entry.path,
                line: 0,
                kind: entry.kind,
                score: entry.score
            )
        }
    }

    /// Returns top-N entries whose name or path contains `q`, ranked by PageRank score.
    public func query(_ q: String, limit: Int = 30) async -> [RepoMapEntry] {
        // Merge all snapshots — in practice callers should scope to a repo.
        // We search across all loaded snapshots.
        let all = snapshots.values.flatMap { $0.entries }
        let lower = q.lowercased()
        let matched = all.filter {
            $0.name.lowercased().contains(lower) || $0.path.lowercased().contains(lower)
        }
        let sorted = matched.sorted { $0.score > $1.score }
        return Array(sorted.prefix(limit))
    }

    // MARK: - Load Snapshot from Disk (lazy)

    private func loadSnapshotIfNeeded(repoID: String) throws -> RepoMapSnapshot? {
        if let cached = snapshots[repoID] { return cached }
        let file = snapshotURL(repoID: repoID)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        let snapshot = try JSONDecoder().decode(RepoMapSnapshot.self, from: data)
        snapshots[repoID] = snapshot
        return snapshot
    }

    // MARK: - Internal Build

    private func buildSnapshot(repoURL: URL, repoID: String) throws -> RepoMapSnapshot {
        let files = try listTrackedFiles(repoURL: repoURL)
        let supportedExtensions: Set<String> = ["swift", "ts", "tsx", "js", "py", "go", "rs"]

        var entries: [RepoMapEntry] = []
        var fileTexts: [String: String] = [:]  // path → content

        for filePath in files {
            let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }

            let fullURL = repoURL.appendingPathComponent(filePath)
            guard let content = try? String(contentsOf: fullURL, encoding: .utf8) else { continue }
            fileTexts[filePath] = content

            let symbols = parseSymbols(content: content, path: filePath, ext: ext)
            entries.append(contentsOf: symbols)
        }

        // Build reference graph: symbol name → [paths that mention it]
        var references: [String: [String]] = [:]
        let allSymbolNames = Set(entries.map { $0.name })

        for (filePath, content) in fileTexts {
            for symbolName in allSymbolNames {
                // simple substring search — fast enough for <10k-symbol repos
                if content.range(of: symbolName) != nil {
                    references[symbolName, default: []].append(filePath)
                }
            }
        }

        // Remove self-references (the file that defines it)
        for entry in entries {
            if var refs = references[entry.name] {
                refs.removeAll { $0 == entry.path }
                references[entry.name] = refs
            }
        }

        // PageRank
        let ranked = pageRank(entries: entries, references: references)

        return RepoMapSnapshot(
            repoID: repoID,
            indexedAt: Date(),
            entries: ranked,
            references: references
        )
    }

    // MARK: - git ls-files

    private func listTrackedFiles(repoURL: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["ls-files"]
        process.currentDirectoryURL = repoURL
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Symbol Scanner

    private func parseSymbols(content: String, path: String, ext: String) -> [RepoMapEntry] {
        var entries: [RepoMapEntry] = []
        let lines = content.components(separatedBy: "\n")

        for (lineIndex, line) in lines.enumerated() {
            guard let match = symbolMatch(line: line, ext: ext) else { continue }
            let snippet = snippetAround(lines: lines, index: lineIndex)
            entries.append(RepoMapEntry(
                path: path,
                kind: match.kind,
                name: match.name,
                score: 1.0,
                snippet: snippet
            ))
        }
        return entries
    }

    private struct SymbolMatch {
        let kind: String
        let name: String
    }

    private func symbolMatch(line: String, ext: String) -> SymbolMatch? {
        switch ext {
        case "swift":
            return matchSwift(line: line)
        case "ts", "tsx", "js":
            return matchTSJS(line: line)
        case "py":
            return matchPython(line: line)
        case "go":
            return matchGo(line: line)
        case "rs":
            return matchRust(line: line)
        default:
            return nil
        }
    }

    // Swift: `^(public|internal|private|open)? *(func|struct|class|actor|enum|protocol) +(\w+)`
    private func matchSwift(line: String) -> SymbolMatch? {
        let pattern = #"^[\s]*(public|internal|private|open|fileprivate)?\s*(func|struct|class|actor|enum|protocol)\s+(\w+)"#
        return matchPattern(pattern, in: line, kindGroup: 2, nameGroup: 3)
    }

    // TS/JS: `^(export +)?(class|function|interface|type|const|let) +(\w+)`
    private func matchTSJS(line: String) -> SymbolMatch? {
        let pattern = #"^[\s]*(export\s+)?(default\s+)?(class|function|interface|type|const|let)\s+(\w+)"#
        return matchPattern(pattern, in: line, kindGroup: 3, nameGroup: 4)
    }

    // Python: `^(def|class) +(\w+)`
    private func matchPython(line: String) -> SymbolMatch? {
        let pattern = #"^[\s]*(def|class)\s+(\w+)"#
        return matchPattern(pattern, in: line, kindGroup: 1, nameGroup: 2)
    }

    // Go: `^func +(\w+)` / `^type +(\w+)`
    private func matchGo(line: String) -> SymbolMatch? {
        if let m = matchPattern(#"^[\s]*(func)\s+(\w+)"#, in: line, kindGroup: 1, nameGroup: 2) { return m }
        if let m = matchPattern(#"^[\s]*(type)\s+(\w+)"#, in: line, kindGroup: 1, nameGroup: 2) { return m }
        return nil
    }

    // Rust: `^(pub +)?(fn|struct|enum|trait|mod) +(\w+)`
    private func matchRust(line: String) -> SymbolMatch? {
        let pattern = #"^[\s]*(pub\s+)?(pub\s*\(.*?\)\s+)?(fn|struct|enum|trait|mod)\s+(\w+)"#
        return matchPattern(pattern, in: line, kindGroup: 3, nameGroup: 4)
    }

    private func matchPattern(_ pattern: String, in line: String, kindGroup: Int, nameGroup: Int) -> SymbolMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else { return nil }

        func group(_ idx: Int) -> String? {
            guard idx < match.numberOfRanges else { return nil }
            let r = match.range(at: idx)
            guard r.location != NSNotFound else { return nil }
            return nsLine.substring(with: r)
        }

        guard let name = group(nameGroup), !name.isEmpty else { return nil }
        let kind = group(kindGroup) ?? "symbol"
        return SymbolMatch(kind: kind.trimmingCharacters(in: .whitespaces), name: name)
    }

    private func snippetAround(lines: [String], index: Int) -> String {
        let start = max(0, index - 1)
        let end = min(lines.count - 1, index + 1)
        return lines[start...end].joined(separator: "\n")
    }

    // MARK: - PageRank

    private func pageRank(entries: [RepoMapEntry], references: [String: [String]], damping: Double = 0.85, iterations: Int = 30) -> [RepoMapEntry] {
        guard !entries.isEmpty else { return entries }

        // Build node index: symbol name → indices in entries array (a symbol can appear in multiple files)
        var nameToIndices: [String: [Int]] = [:]
        for (idx, entry) in entries.enumerated() {
            nameToIndices[entry.name, default: []].append(idx)
        }

        let n = entries.count
        var scores = [Double](repeating: 1.0 / Double(n), count: n)

        // Build adjacency: for each entry index, which other entry indices does it receive links from?
        // A symbol `s` defined at entry index `i` gets a back-link from every file that references `s`.
        // We map each referencing file to all entry indices defined in that file.
        var fileToIndices: [String: [Int]] = [:]
        for (idx, entry) in entries.enumerated() {
            fileToIndices[entry.path, default: []].append(idx)
        }

        // inLinks[i] = list of entry indices that link to entry i
        var inLinks = [[Int]](repeating: [], count: n)
        for entry in entries {
            guard let refs = references[entry.name] else { continue }
            // entries defined by symbol `entry.name`
            guard let defIndices = nameToIndices[entry.name] else { continue }
            for refPath in refs {
                guard let srcIndices = fileToIndices[refPath] else { continue }
                for defIdx in defIndices {
                    for srcIdx in srcIndices where srcIdx != defIdx {
                        inLinks[defIdx].append(srcIdx)
                    }
                }
            }
        }

        // Compute out-degree for each entry (how many entries it links to)
        var outDegree = [Int](repeating: 0, count: n)
        for (_, linkers) in inLinks.enumerated() {
            for src in linkers {
                outDegree[src] += 1
            }
        }

        for _ in 0..<iterations {
            var newScores = [Double](repeating: (1.0 - damping) / Double(n), count: n)
            for idx in 0..<n {
                for src in inLinks[idx] {
                    let degree = outDegree[src]
                    if degree > 0 {
                        newScores[idx] += damping * scores[src] / Double(degree)
                    }
                }
            }
            scores = newScores
        }

        var updated = entries
        for idx in 0..<n {
            updated[idx].score = scores[idx]
        }
        return updated
    }

    // MARK: - Persistence

    private func snapshotURL(repoID: String) -> URL {
        Self.sharedDirectory().appendingPathComponent("\(repoID).json")
    }

    private func persist(snapshot: RepoMapSnapshot) throws {
        let dir = Self.sharedDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = snapshotURL(repoID: snapshot.repoID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}
