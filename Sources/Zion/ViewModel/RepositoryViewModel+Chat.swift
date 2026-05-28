import Foundation

extension RepositoryViewModel {

    // MARK: - ChatService lifecycle

    /// Lazily creates and returns the ChatService for the current repository.
    /// Backed by `_chatService`; reset on every repo switch via `resetChatService()`.
    var chatService: ChatService {
        if let existing = _chatService { return existing }
        let builder = ChatContextBuilder(worker: worker)
        let url = repositoryURL ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let harness = ZionHarness(worker: worker, repoURL: url)
        let repoID = repositoryURL.map { ChatStorage.repoID(for: $0) } ?? ""

        // P12: Bootstrap SymbolIndexer + MentionResolver for the active repo.
        // SymbolIndexer.shared is read by repo_map / find_symbol MCP tools and
        // by the composer's @file/@symbol autocomplete.
        Self.bootstrapSmartContext(for: url)
        // Phase 5c: Bootstrap RAG layer alongside SymbolIndexer so the
        // semantic_search MCP tool + @code mention have a live query
        // service for the active repo. No-op when ragHybridEnabled is
        // false. Cold index is fire-and-forget.
        if Constants.Feature.ragHybridEnabled {
            Self.bootstrapRAG(for: url)
        }
        let resolver = MentionResolver(
            toolClient: FileSystemMentionToolClient(repoURL: url)
        )

        let svc = ChatService(
            ai: aiClient,
            worker: worker,
            contextBuilder: builder,
            harness: harness,
            storage: chatStorage,
            repoID: repoID,
            mentionResolver: resolver
        )
        _chatService = svc
        return svc
    }

    /// One-shot Smart Context bootstrap: opens the per-repo symbol DB and kicks
    /// off a cold scan in the background. Safe to call repeatedly — re-uses an
    /// existing shared indexer when the repoURL matches.
    private static func bootstrapSmartContext(for url: URL) {
        let dbDir = url.appendingPathComponent(".zion", isDirectory: true)
        let dbPath = dbDir.appendingPathComponent("symbols.sqlite")
        do {
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            let db = try SymbolDB(path: dbPath)
            let indexer = SymbolIndexer(db: db, repoURL: url)
            SymbolIndexer.shared = indexer
            Task.detached(priority: .utility) {
                _ = try? await indexer.bootstrap()
            }
        } catch {
            // Indexer optional; repo_map / find_symbol return their own
            // "[error: not initialized]" markers if SymbolIndexer.shared is nil.
        }
    }

    /// Phase 5c — one-shot RAG bootstrap. Instantiates `RAGStore`,
    /// `RAGIndexer`, `RAGQueryService` for the given repo and assigns
    /// the query service to `RAGQueryServiceLocator.shared` so the
    /// semantic_search MCP tool + @code mention can reach it. Cold
    /// indexing runs detached so the chat surface boots immediately;
    /// the locator returns hits once the first batch lands.
    private static func bootstrapRAG(for url: URL) {
        do {
            let store = try RAGStore(repoURL: url)
            let embedder = NLContextualEmbeddingProvider()
            let service = RAGQueryService(store: store, embedder: embedder)
            RAGQueryServiceLocator.shared = service
            // Cold index detached. Failures are non-fatal — chat keeps
            // working via the other tools. Index runs at `.utility`
            // QoS so it does not steal cycles from active streaming.
            let indexer = RAGIndexer(store: store, embedder: embedder)
            Task.detached(priority: .utility) {
                _ = try? await indexer.index(repoURL: url)
            }
        } catch {
            // RAG is optional; semantic_search / @code surface their
            // own localized "not ready" messages when the locator is
            // nil.
        }
    }

    /// Stops any in-flight streaming and discards the current ChatService instance.
    /// Called by `cancelRepositoryBackgroundActivityForSwitch()` on every repo switch.
    func resetChatService() {
        _chatService?.stop()
        _chatService = nil
        // Phase 5c — drop the per-repo RAG locator so the next
        // openRepository can bootstrap fresh.
        RAGQueryServiceLocator.shared = nil
    }
}
