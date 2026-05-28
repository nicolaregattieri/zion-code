import Foundation

/// Phase 6 — `retrieve_more(query:k:)` mid-turn tool. Lets the model
/// ask for additional semantic context when the auto-injected chips
/// did not cover the question. Output mirrors `semantic_search` so the
/// model can reuse the same parser.
extension MCPConfigBuilder {

    static func retrieveMoreDescriptor() -> MCPToolDescriptor {
        MCPToolDescriptor(
            name: "retrieve_more",
            description: "Fetch additional semantic-search hits mid-turn when the auto-injected context did not cover the question. Use natural language; complements the auto-context chips already supplied with the user's message.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Natural-language follow-up query."
                    ] as [String: Any],
                    "k": [
                        "type": "integer",
                        "description": "Maximum hits to return (default 10, max 25).",
                        "minimum": 1,
                        "maximum": 25
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["query"]
            ]
        )
    }

    static func dispatchRetrieveMore(args: [String: Any]) async throws -> String {
        let query = (args["query"] as? String) ?? ""
        guard !query.isEmpty else { return "[error: missing query]" }
        let k = min(max((args["k"] as? Int) ?? Constants.RAG.maxResultsPerQuery, 1), 25)
        guard let service = RAGQueryServiceLocator.shared else {
            return L10n("rag.tool.notReady")
        }
        let hits = (try? await service.hybridSearch(query: query, limit: k)) ?? []
        if hits.isEmpty { return L10n("mention.code.empty") }
        return hits.map { hit in
            "\(hit.chunk.path):\(hit.chunk.startLine)-\(hit.chunk.endLine) — \(hit.chunk.kind) score=\(String(format: "%.4f", hit.score)) [\(hit.source.rawValue)]"
        }.joined(separator: "\n")
    }
}
