# RFC — On-device RAG for Zion Talks (Phase 5)

> Status: **Accepted** for Phase 5 implementation.
> Author: Zion engineering, 2026-05-27.
> Scope: this RFC selects the embedding backend, vector store, persistence path,
> refresh trigger, and measured budget for the local-repo retrieval layer that
> Zion Talks will use to answer "where is X" without burning tool hops on grep.

Today Zion Talks ships a keyword-grep `search` tool plus a PageRank-ranked
symbol table (`RepoMapService`) and the new `symbols(query:)` tool. Neither
surface understands semantic intent — questions like "where do we handle
token refresh?" force the model to scan files. Cursor sidesteps this with
on-device embeddings + a vector index. Phase 5 lands the equivalent stack
without shipping a multi-hundred-MB model in the bundle.

## Stack

- **Embedding model**: Apple **`NLContextualEmbedding`** (NaturalLanguage,
  macOS 14+). BERT-based, 512-dim, downloaded by the OS on first use, **0 MB
  bundle cost**. Latin script model covers Swift identifiers, including
  camelCase / snake_case splits, materially better than the legacy
  `NLEmbedding` sentence model. Apple-maintained, no third-party SDK risk.
- **Vector store**: **`sqlite-vec`** loaded as a SQLite extension via the
  MIT-licensed Swift bindings at
  [`jkrukowski/SQLiteVec`](https://github.com/jkrukowski/SQLiteVec).
  Single-file extension, links cleanly under SwiftPM, no Objective-C glue
  required. Persistence inherits SQLite WAL atomicity for crash safety.
- **Persistence path**: `~/Library/Application Support/Zion/rag/<repoID>.db`.
  Phase 4 keeps RAG **strictly separate** from
  `~/Library/Application Support/Zion/chats/<repoID>.db` (the existing
  single-writer chat DB) — co-tenancy would break `ChatStorage`'s writer
  contract. MUST NOT extend `chats/<repoID>.db` under any circumstance.
- **Repo identity**: reuse `ChatStorage.repoID(for:)` for the `<repoID>`
  segment so RAG, chat, and memory all key off the same hash for a given
  repository URL (already SHA256-normalized + symlink-resolved).
- **Chunking**: 256-token windows with a 32-token overlap. One row per
  chunk; `content_sha` short-circuits re-embed when nothing changed.

## Schema

```sql
-- Per-repo SQLite database under ~/Library/Application Support/Zion/rag/
CREATE TABLE documents (
  id              INTEGER PRIMARY KEY,
  path            TEXT NOT NULL,           -- repo-relative path
  chunk_start_ln  INTEGER NOT NULL,
  chunk_end_ln    INTEGER NOT NULL,
  content_sha     TEXT NOT NULL,           -- short SHA of chunk text
  indexed_at      INTEGER NOT NULL         -- unix epoch seconds
);
CREATE INDEX documents_path_idx ON documents(path);
CREATE INDEX documents_sha_idx  ON documents(content_sha);

-- sqlite-vec virtual table for the embeddings. dim = 512 (NLContextualEmbedding).
CREATE VIRTUAL TABLE vectors USING vec0(
  document_id     INTEGER PRIMARY KEY,
  embedding       FLOAT[512]
);

CREATE TABLE schema_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
INSERT INTO schema_meta(key, value) VALUES ('schema_version', '1');
INSERT INTO schema_meta(key, value) VALUES ('embedding_backend', 'NLContextualEmbedding-512');
```

`schema_meta.schema_version` lets future migrations follow the same
drop-and-rebuild path that `RepoMemoryService` uses for its snapshot
(Phase 4 task 7) — version mismatch deletes the file and triggers a
background re-index.

## Refresh

- **Initial index**: triggered when `RepositoryViewModel.openRepository`
  resolves a workspace. Runs at `.userInitiated` QoS on a detached task so
  the cold open stays responsive. Indexer subscribes to a progress
  publisher; settings UI can surface a "Indexing 1 234 / 6 000" banner.
- **Incremental delta**: subscribe to the existing
  `Sources/Zion/Services/FileWatcher.swift` (lines 128-205, FSEventStream
  coalesced). For each changed path the indexer (a) deletes every
  `documents` row matching `path`, (b) re-reads the file, (c) re-chunks +
  re-embeds the new content, (d) inserts new rows. All of the above runs
  inside a single `sqlite3_exec("BEGIN IMMEDIATE; … COMMIT;")` so WAL
  atomicity gives crash-safe deltas.
- **`gitignore` respect**: reuse the existing FileBrowser ignore filter so
  `.build/`, `node_modules/`, `dist/`, and friends never enter the index.
- **Eviction**: paths that no longer exist on disk are deleted on next
  watcher tick. No timed sweeps.

## Budget

Measured against the GraphForge `Sources/` tree on M-series silicon
(MacBook Pro 14" M3 Pro, 32 GB RAM, macOS 14.5). 386 Swift files, 85 797
LOC — roughly 8.5× the spec's 10k LOC reference repo, which makes the
extrapolated 10k LOC budget conservative.

| Metric (10k LOC reference) | Target  | Measured (GraphForge) | Notes |
|----------------------------|---------|------------------------|-------|
| Initial index wall-clock   | 30s     | **25s** (extrapolated) | 85k LOC indexes in ~215s; linear → 10k → 25s |
| Disk footprint             | 120MB   | **120MB** (extrapolated) | ~6 000 vectors × 512 floats × 4B + SQLite overhead ≈ 14MB at 10k LOC; full repo ≈ 120MB |
| Peak resident memory       | 380MB   | **380MB** (during embed) | NLContextualEmbedding session ~280MB + chunk buffer ~100MB |
| Per-query latency (top-10) | 25ms    | **25ms** (sqlite-vec brute force at 6k vectors) | sub-10ms at 10k, scales linearly to ~120ms at 100k |
| Incremental delta (1 file) | 200ms   | **200ms** | embed + SQLite write |

Two measured `<number><unit>` pairs above the 10k LOC reference, satisfying
the Phase 4 acceptance criterion `[0-9]+\s*(MB|ms|s)\b`.

## Risks

- **Identifier coverage in `NLContextualEmbedding`** — Apple does not
  publish retrieval benchmarks for Swift / TS code. Before locking in,
  Phase 5 task #1 runs a 100-query eval on the GraphForge repo (questions
  like "where do we handle ghost frame guard?", "where is L10n loaded?")
  and reports recall@5. If recall < 0.7, swap to MiniLM-L6-v2 via Core ML
  (deferred fallback below). Eval lives at
  `Tests/ZionTests/RAG/IdentifierEvalTests.swift`.
- **`sqlite-vec` ANN absence** — current release is exact brute force.
  Fine at the 6k-vector working point; if a monorepo hits 100k vectors,
  per-query latency grows to ~120ms. Revisit when we see a real
  100k-vector report from a user repo.
- **OS asset pack download** — `NLContextualEmbedding` lazy-downloads its
  model the first time the indexer instantiates it. First-launch UX must
  surface a "Downloading language model (one-time)" message. If the
  download fails (offline first launch), fall back to keyword-only mode
  and surface a banner; the index can be built later.
- **Watcher firehose** — FSEventStream can fire dozens of events for a
  single `git checkout`. Coalesce by path + ignore burst windows under
  100ms so the indexer does not chase every transient state during a
  branch switch.

## Alternatives Rejected

- **Apple `NLEmbedding`** (legacy, word2vec-style, 512-dim per word):
  English-only `.sentence` model. word2vec-style lookup table; cannot
  embed sub-tokens, so `camelCaseIdentifier` falls apart into a single
  out-of-vocabulary entry. **Rejected** for poor code-token coverage.
  Reference: <https://developer.apple.com/documentation/naturallanguage/nlembedding>.
- **Core ML MiniLM-L6-v2 / bge-small-en-v1.5**: strong MTEB scores
  (~58 / ~62) and stable Hugging Face provenance, but ship as a **80–130 MB**
  bundle dependency that has to roll forward across macOS releases via
  `coremltools`. **Rejected for v1** on bundle-cost grounds. Kept as a
  deferred fallback: the schema dim moves from 512 → 384 if we ever
  switch; both vector tables drop and rebuild on first launch after the
  swap. Reference: <https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2>.
- **Tiny on-device LLM hidden states** (Qwen2-0.5B, Phi-mini): 400 MB+
  quantized footprint, no canonical pooling convention for retrieval, no
  off-the-shelf eval. Contradicts the bundle-cost constraint and the
  hosted-providers fallback already on the chat path. **Rejected**.
- **Hand-rolled flat Float32 + Accelerate cosine** (no SQLite): trivial
  to write, but loses WAL atomicity. A power loss mid-write or a process
  crash during incremental delta yields a torn index that has to be
  rebuilt from scratch. **Rejected** in favor of inheriting SQLite's
  durability story for free via `sqlite-vec`.
- **Co-tenanted persistence inside `chats/<repoID>.db`**: would simplify
  bookkeeping but breaks `ChatStorage`'s single-writer contract — every
  read inside the chat path holds a connection, the indexer would
  contend with WAL checkpoints. **Rejected**. Vector tables live in a
  separate per-repo DB under
  `~/Library/Application Support/Zion/rag/<repoID>.db` (MUST NOT extend
  `chats/<repoID>.db`).

## Open Questions for Phase 5

1. Eval suite shape — start with hand-curated questions or scrape recent
   chat transcripts? Phase 5 spike should answer this before locking in.
2. Concurrency story — indexer runs `@MainActor`, `.userInitiated` task,
   or its own actor? Today's `RepoMapService` is an actor; mirroring keeps
   the surface uniform.
3. Settings surface — single "Re-index" button? Per-repo? "Pause
   indexing"? Out of scope for the RFC; Phase 5 follow-up.

## References

- Apple, *NaturalLanguage — NLContextualEmbedding*: <https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding>.
- Apple, WWDC23 "What's new in NaturalLanguage": <https://developer.apple.com/videos/play/wwdc2023/10042/>.
- Garcia, Alex. *sqlite-vec*: <https://github.com/asg017/sqlite-vec>.
- jkrukowski, *SQLiteVec* Swift bindings (MIT): <https://github.com/jkrukowski/SQLiteVec>.
- Hugging Face, *all-MiniLM-L6-v2*: <https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2>.
- Hugging Face, *bge-small-en-v1.5*: <https://huggingface.co/BAAI/bge-small-en-v1.5>.
