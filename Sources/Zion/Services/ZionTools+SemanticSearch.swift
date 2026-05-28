import Foundation

/// Phase 5 — `semantic_search(query:)` MCP tool. Routes through
/// `RAGQueryService.hybridSearch` when `Constants.Feature.ragHybridEnabled`
/// is true (default), falls back to vector-only otherwise. Returns
/// `rag.tool.notReady` localized hint when the active repo has no
/// indexed chunks (user must hit Reindex in Settings).
extension MCPConfigBuilder {

    static func semanticSearchDescriptor() -> MCPToolDescriptor {
        MCPToolDescriptor(
            name: "semantic_search",
            description: "Semantic search across the indexed code. Use natural language ('where is token expiry handled?'); complements 'symbols' (exact identifier) and 'search' (literal grep). Returns up to 10 chunks ranked by hybrid (vector + keyword) RRF.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Natural-language query."
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["query"]
            ]
        )
    }

    /// Per-call dispatch. The query service + repo URL come from the
    /// caller (chat session) — the harness loop wires them when the
    /// repo opens. For now we look up via a process-wide shared accessor
    /// that the view-model populates (mirrors `SymbolIndexer.shared`).
    static func dispatchSemanticSearch(args: [String: Any]) async throws -> String {
        let query = (args["query"] as? String) ?? ""
        guard !query.isEmpty else { return "[error: missing query]" }
        guard let service = RAGQueryServiceLocator.shared else {
            return L10n("rag.tool.notReady")
        }

        let limit = Constants.RAG.maxResultsPerQuery
        let hits: [RAGHit]
        do {
            hits = try await service.hybridSearch(query: query, limit: limit)
        } catch {
            return "[error: \(error.localizedDescription)]"
        }
        if hits.isEmpty { return L10n("mention.code.empty") }
        return hits.map { hit in
            "\(hit.chunk.path):\(hit.chunk.startLine)-\(hit.chunk.endLine) — \(hit.chunk.kind) score=\(String(format: "%.4f", hit.score)) [\(hit.source.rawValue)]"
        }.joined(separator: "\n")
    }
}

/// Process-wide accessor populated by `RepositoryViewModel+Chat` when
/// the active repo's `RAGIndexer` finishes opening. Mirrors the
/// `SymbolIndexer.shared` pattern used by `find_symbol` / `symbols`.
enum RAGQueryServiceLocator {
    nonisolated(unsafe) static var shared: RAGQueryService?
}
