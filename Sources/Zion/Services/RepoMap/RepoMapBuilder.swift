import Foundation

// MARK: - RepoMapBuilder

/// Builds a Markdown outline of the repo sorted by PageRank relevance.
/// Personalization weights: focusFiles 50×, historyFiles 10×, mentionedIdentifiers 5×, default 1×.
/// Token budget enforced via bytes/4 heuristic.
struct RepoMapBuilder: Sendable {
    let db: SymbolDB

    init(db: SymbolDB) {
        self.db = db
    }

    // MARK: - Public API

    /// Build a Markdown outline of the repo, sorted by PageRank.
    /// - Parameters:
    ///   - focusFiles: files currently open/active — get 50× personalization weight
    ///   - historyFiles: recently touched files — get 10× weight
    ///   - mentionedIdentifiers: identifiers appearing in the prompt — files defining them get 5×
    ///   - tokenBudget: cap on output tokens (chars/4 heuristic, default 4000 tokens = 16000 chars)
    /// - Returns: Markdown string ready to inject into a prompt
    func markdown(
        focusFiles: [String] = [],
        historyFiles: [String] = [],
        mentionedIdentifiers: [String] = [],
        tokenBudget: Int = 4000
    ) async throws -> String {
        let charBudget = tokenBudget * 4

        // 1. Fetch all files.
        let fileRows = try await db.allFiles()

        guard !fileRows.isEmpty else {
            return "# Repo Map (top symbols by relevance)\n\n_(empty)_\n"
        }

        let allPaths = fileRows.map(\.path)

        // 2. Fetch symbols per file and build edge graph.
        var symbolsByFile: [String: [SymbolRow]] = [:]
        var edges: [String: Set<String>] = [:]

        for path in allPaths {
            let symbols = try await db.symbolsForFile(path)
            symbolsByFile[path] = symbols

            // Build edges: for each ref in a symbol, find which file defines it.
            // With T3 v1 refs being empty, this graph will be empty — PageRank
            // degenerates to personalization-only, which is acceptable.
            var destFiles: Set<String> = []
            for symbol in symbols {
                for ref in symbol.refs {
                    let defs = try await db.symbolsByName(ref)
                    for def in defs where def.file != path {
                        destFiles.insert(def.file)
                    }
                }
            }
            if !destFiles.isEmpty {
                edges[path] = destFiles
            }
        }

        // 3. Build personalization vector.
        var personalization: [String: Double] = [:]

        // All files start at weight 1 (default — set explicitly so absent paths get 1).
        for path in allPaths {
            personalization[path] = 1.0
        }

        // focusFiles → 50×
        for path in focusFiles where symbolsByFile[path] != nil {
            personalization[path] = 50.0
        }

        // historyFiles → 10× (only if not already boosted by focusFiles)
        for path in historyFiles where symbolsByFile[path] != nil {
            if (personalization[path] ?? 1.0) < 10.0 {
                personalization[path] = 10.0
            }
        }

        // mentionedIdentifiers → files containing a matching symbol get 5×
        for identifier in mentionedIdentifiers {
            let defs = try await db.symbolsByName(identifier)
            for def in defs {
                let current = personalization[def.file] ?? 1.0
                if current < 5.0 {
                    personalization[def.file] = 5.0
                }
            }
        }

        // 4. Run PageRanker.
        let scores = PageRanker.rank(
            nodes: allPaths,
            edges: edges,
            personalization: personalization
        )

        // 5. Sort files by score descending.
        let sortedPaths = allPaths.sorted { (a, b) in
            (scores[a] ?? 0) > (scores[b] ?? 0)
        }

        // 6. Greedy fill under charBudget.
        let header = "# Repo Map (top symbols by relevance)\n\n"
        var accumulated = header
        var accumulatedBytes = header.utf8.count

        for path in sortedPaths {
            let symbols = symbolsByFile[path] ?? []
            let section = formatSection(path: path, symbols: symbols)
            let sectionBytes = section.utf8.count

            if accumulatedBytes + sectionBytes <= charBudget {
                accumulated += section
                accumulatedBytes += sectionBytes
            }
            // Over budget: skip this file and try the next (smaller sections may still fit)
        }

        return accumulated
    }

    // MARK: - Private

    private func formatSection(path: String, symbols: [SymbolRow]) -> String {
        var lines = ["## \(path)"]
        for symbol in symbols {
            lines.append("- \(symbol.kind) \(symbol.name)")
        }
        lines.append("") // trailing newline between sections
        return lines.joined(separator: "\n") + "\n"
    }
}
