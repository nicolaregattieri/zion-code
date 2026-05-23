// SymbolIndexer.swift
// Orchestrator actor for symbol indexing. Cold-scans a repo on bootstrap,
// debounces FSEvent-driven incremental reparses, and exposes autocomplete APIs.
//
// Phase 12, Task 4.
//
// Singleton: SymbolIndexer.shared is set by ChatService / RepositoryViewModel on repo open (P12.5).
// TODO(P12.5): wire SymbolIndexer.shared in RepositoryViewModel.openRepository()

import Foundation
import CryptoKit

// MARK: - SymbolIndexer

actor SymbolIndexer {

    // MARK: - Constants

    static let maxColdScanFiles = 5_000
    static let debounceMs: Int = 200

    /// Directories skipped during cold scan (heuristic .gitignore equivalent).
    private static let skippedPathComponents: [String] = [
        "/.build/", "/.git/", "/node_modules/", "/Pods/", "/dist/", "/DerivedData/"
    ]

    // MARK: - State

    private let db: SymbolDB
    private let scanner: SwiftSymbolScanner
    private let repoURL: URL
    private var pendingReparseFiles: Set<String> = []
    private var debounceTask: Task<Void, Never>?

    /// Optional spy injected by tests. Called immediately before each parse invocation.
    private let parserSpy: (@Sendable (URL) -> Void)?

    // MARK: - Init

    init(
        db: SymbolDB,
        scanner: SwiftSymbolScanner = SwiftSymbolScanner(),
        repoURL: URL,
        parserSpy: (@Sendable (URL) -> Void)? = nil
    ) {
        self.db = db
        self.scanner = scanner
        self.repoURL = repoURL
        self.parserSpy = parserSpy
    }

    // MARK: - Public API

    /// Cold-scans the repo. Walks the file tree, parses .swift files, populates SymbolDB.
    /// Cap: 5000 files. Returns count of files scanned.
    @discardableResult
    func bootstrap() async throws -> Int {
        let files = collectFiles()
        let toScan = Array(files.prefix(Self.maxColdScanFiles))
        for url in toScan {
            await parseAndUpsert(url)
        }
        return toScan.count
    }

    /// Notify the indexer that a file changed on disk.
    /// Batched with a 200 ms debounce before reparse.
    func fileDidChange(_ url: URL) {
        pendingReparseFiles.insert(url.standardizedFileURL.path)
        // Restart debounce timer
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.debounceMs) * 1_000_000)
            // Only flush if not cancelled
            guard !Task.isCancelled else { return }
            await self?.flushPending()
        }
    }

    /// Force an immediate flush of all pending reparses (test hook + bootstrap finalization).
    func flushPending() async {
        let files = pendingReparseFiles
        pendingReparseFiles.removeAll()
        for path in files {
            await parseAndUpsert(URL(fileURLWithPath: path))
        }
    }

    /// Returns up to `limit` file path suggestions whose path contains `prefix` (case-insensitive).
    /// Used for @file autocomplete in T8.
    func fileSuggestions(prefix: String, limit: Int = 6) async -> [String] {
        let allFiles = (try? await db.allFiles()) ?? []
        let lower = prefix.lowercased()
        return Array(
            allFiles
                .compactMap { row in row.path.lowercased().contains(lower) ? row.path : nil }
                .prefix(limit)
        )
    }

    /// Returns up to `limit` symbol name suggestions whose name starts with `prefix` (case-insensitive).
    /// Used for @symbol autocomplete (future).
    ///
    /// TODO(P12.5 optimization): add `symbolsLikeName(prefix:limit:)` SQL query to SymbolDB
    ///   to avoid scanning all files in memory. Current v1 is correct but O(symbols).
    func symbolSuggestions(prefix: String, limit: Int = 6) async -> [String] {
        let allFiles = (try? await db.allFiles()) ?? []
        let lower = prefix.lowercased()
        var seen = Set<String>()
        var results: [String] = []
        for file in allFiles {
            guard let rows = try? await db.symbolsForFile(file.path) else { continue }
            for row in rows {
                if row.name.lowercased().hasPrefix(lower), !seen.contains(row.name) {
                    results.append(row.name)
                    seen.insert(row.name)
                    if results.count >= limit { return results }
                }
            }
        }
        return results
    }

    // MARK: - Private

    private func parseAndUpsert(_ url: URL) async {
        // Normalize URL to resolve symlinks (e.g. /var → /private/var on macOS)
        let url = url.standardizedFileURL

        // Read file
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return
        }

        // Compute SHA-256 content hash
        let hash = SHA256.hash(data: data)
            .compactMap { String(format: "%02x", $0) }
            .joined()

        // Skip if content is unchanged
        if let existing = try? await db.contentHashFor(url.path), existing == hash {
            return
        }

        // Notify spy BEFORE parse (test hook)
        parserSpy?(url)

        // Parse symbols
        let symbols: [ParsedSymbol]
        do {
            symbols = try scanner.parse(file: url, content: content)
        } catch {
            // Non-Swift or parse error — skip silently
            return
        }

        // Persist file record
        try? await db.insertFile(path: url.path, contentHash: hash)

        // Persist symbols
        let rows = symbols.map { sym -> SymbolRow in
            let refsJSON: String
            if let data = try? JSONEncoder().encode(sym.refs),
               let str = String(data: data, encoding: .utf8) {
                refsJSON = str
            } else {
                refsJSON = "[]"
            }
            return SymbolRow(
                file: url.path,
                kind: sym.kind.rawValue,
                name: sym.name,
                line: sym.line,
                col: sym.col,
                refsJSON: refsJSON
            )
        }
        try? await db.upsertSymbols(rows, file: url.path)
    }

    /// Collects all .swift files under repoURL, excluding noise directories.
    private func collectFiles() -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: repoURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let path = url.path
            // Skip standard noise directories
            let isNoise = Self.skippedPathComponents.contains { path.contains($0) }
            if isNoise { continue }
            guard url.pathExtension.lowercased() == "swift" else { continue }
            result.append(url)
        }
        return result
    }
}

// MARK: - Singleton

extension SymbolIndexer {
    /// Set by ChatService / RepositoryViewModel on repo open (P12.5).
    nonisolated(unsafe) static var shared: SymbolIndexer?
}

// MARK: - MCP Tool helpers

extension SymbolIndexer {

    /// Find symbols by exact name, optionally filtered by kind.
    /// Bridges `SymbolDB.symbolsByName` for use in MCP tool dispatch without
    /// exposing the private `db` property.
    func symbolsByName(_ name: String, kind: String? = nil) async throws -> [SymbolRow] {
        try await db.symbolsByName(name, kind: kind)
    }

    /// Build a Markdown repo map and return it as a String.
    /// Constructs `RepoMapBuilder` internally so callers need not hold a `SymbolDB` reference.
    func buildRepoMap(focusFiles: [String] = [], tokenBudget: Int = 4000) async throws -> String {
        let builder = RepoMapBuilder(db: db)
        return try await builder.markdown(focusFiles: focusFiles, tokenBudget: tokenBudget)
    }
}
