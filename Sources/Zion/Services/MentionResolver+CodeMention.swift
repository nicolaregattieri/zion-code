import Foundation

/// Phase 5 — `@code <query>` resolver. Forwards to the active
/// `RAGQueryService` (looked up via `RAGQueryServiceLocator.shared`)
/// and formats the top hits into the volatile context block. Degrades
/// gracefully when the locator is unwired (empty repo, indexing in
/// flight, model assets missing) by returning the localized empty
/// fallback.
extension MentionResolver {

    func resolveCode(query: String) async -> (contents: String, bytes: Int) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let msg = L10n("mention.code.empty")
            return (msg, msg.utf8.count)
        }
        guard let service = RAGQueryServiceLocator.shared else {
            let msg = L10n("rag.tool.notReady")
            return (msg, msg.utf8.count)
        }
        let limit = Constants.RAG.maxResultsPerQuery
        do {
            let hits = try await service.hybridSearch(query: trimmed, limit: limit)
            if hits.isEmpty {
                let msg = L10n("mention.code.empty")
                return (msg, msg.utf8.count)
            }
            let body = hits.map { hit in
                "- `\(hit.chunk.path):\(hit.chunk.startLine)-\(hit.chunk.endLine)` — \(hit.chunk.kind) (\(hit.source.rawValue))"
            }.joined(separator: "\n")
            return (body, body.utf8.count)
        } catch {
            let msg = "[error: \(error.localizedDescription)]"
            return (msg, msg.utf8.count)
        }
    }
}
