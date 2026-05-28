## Project State

Phase 5 RAG ships end-to-end as Phase 5b: per-repo SQLite store (system sqlite3 + Accelerate cosine + FTS5 + BLOB embeddings, no SwiftPM dep — sidesteps the SQLiteVec amalgamation collision against ChatStorage), one-shot RAGIndexer over ignore-filtered repo files, RAGQueryService with vector / keyword / hybrid RRF (k=60), `semantic_search` MCP tool + `@code` mention resolver wired through MCPConfigBuilder, RAGSettingsSection UI scaffold with reindex affordance, and an A/B promotion gate (RAGBackendPromotion) for future Qodo upgrade. Recall@10 e2e test is wired but gated by `ZION_RAG_E2E=1`; golden fixture currently has 12 entries, expand to 100 in Phase 5c. Tree-sitter AST chunking remains XCTSkipped (grammars fail SPM 6.2); fixed-window fallback path ships for every language. FSEvents-driven incremental indexing is deferred to Phase 5c — today the user reindexes from Settings on demand.

## Phase 5 build summary
- Wave 1 (foundation): Constants.RAG, RAGChunk/RAGHit value types, 18 locale keys
- Wave 2 (store + chunker + embedder): RAGSchema, RAGStore via system SQLite, ASTChunker, EmbeddingProvider (NLContextualEmbedding + Qodo stub)
- Wave 3 (indexer + query): RAGIndexer one-shot, RAGQueryService with RRF
- Wave 4 (tool + mention + UI): semantic_search MCP tool, MentionResolver+CodeMention, RAGSettingsSection
- Wave 5 (eval): RAGBackendPromotion + 12-entry golden.json + RAGEvalTests harness

## Test coverage (all green)
- RAGLocalizationTests: 1
- RAGStoreTests: 6 (insert, count, delete, vectorSearch cosine, FTS5 keyword)
- RAGStoreIsolationTests: 2
- ASTChunkerTests: 14 (1 XCTSkip pending tree-sitter)
- ASTChunkerCoverageTests: 1
- EmbeddingProviderTests: skip-aware
- HybridQueryTests: 3 (RRF, sanitizer empty, sanitizer NL)
- ZionToolsSemanticSearchTests: 4
- RAGEvalTests: 4 (1 skip pending ZION_RAG_E2E=1)

## Known deferrals (Phase 5c)
1. FSEvents-driven incremental indexer + Progress publisher
2. Tree-sitter AST chunker (vendoring path TBD; SPM 6.2 incompatibility upstream)
3. RepositoryViewModel+Chat wiring of RAGQueryServiceLocator + chunkCount AppStorage publisher
4. Golden fixture expansion 12 → 100 entries
5. sqlite-vec runtime extension load (drop the brute-force cosine when ANN matures)

## Patterns
- Localization test pattern: use `Bundle.zionResources.path(forResource:ofType:inDirectory:forLocalization:)` + `NSDictionary(contentsOfFile:)`. See `ChatLocalizationTests.swift`.
- Phase keys go as a `// MARK: - Phase N` block appended at the end of each `.strings` file.
- `swift build` / `swift test` require sandbox disabled (`dangerouslyDisableSandbox: true`).
- `#filePath` in test files reliably locates `Tests/ZionTests/Fixtures/` without `Bundle.module`.
- Actor + `OpaquePointer` sqlite3 handle: cannot deinit-touch in Swift 6 strict concurrency — explicit `close()` method.
- Static `SQLITE_TRANSIENT` inside an actor must be referenced as `Self.SQLITE_TRANSIENT` from instance methods.
- Avoid SQLiteVec SwiftPM dep — its bundled amalgamation redefines `sqlite3_api_routines` and conflicts with system sqlite3 (which ChatStorage already links).
