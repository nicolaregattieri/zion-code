import Foundation

/// Phase 4 — `symbols(query:)` keyword navigation tool.
/// Non-semantic filter over the cached `RepoMemorySnapshot.topSymbols` /
/// `SymbolIndexer` table. Returns up to `Constants.Limits.symbolsToolLimit`
/// rows. Cheap, deterministic, complements `find_symbol` (exact) and
/// `repo_map` (overview); foundation for Phase 5 RAG.
extension MCPConfigBuilder {

    static func symbolsDescriptor() -> MCPToolDescriptor {
        MCPToolDescriptor(
            name: "symbols",
            description: "Keyword search over the cached top-ranked symbols snapshot. Returns up to 20 SymbolEntry rows {file, line, kind, score}. Use to navigate by approximate name without invoking the indexer.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Case-insensitive substring match against symbol names and paths."
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["query"]
            ]
        )
    }

    static func dispatchSymbols(args: [String: Any]) async throws -> String {
        let query = (args["query"] as? String) ?? ""
        guard !query.isEmpty else {
            return "[error: missing query]"
        }
        guard let indexer = SymbolIndexer.shared else {
            return "[error: SymbolIndexer not initialized — open a repo first]"
        }

        let limit = Constants.Limits.symbolsToolLimit

        // Reads only the cached top-ranked snapshot. MUST NOT call
        // RepoMapService.refresh() — verified by tests.
        let rows = try await indexer.symbolsByName(query, kind: nil)
        let lower = query.lowercased()
        let filtered = rows
            .filter { $0.name.lowercased().contains(lower) || $0.file.lowercased().contains(lower) }
            .prefix(limit)

        if filtered.isEmpty {
            return "No symbols matching '\(query)'."
        }
        return filtered
            .map { "\($0.file):\($0.line) — \($0.kind) \($0.name)" }
            .joined(separator: "\n")
    }
}
