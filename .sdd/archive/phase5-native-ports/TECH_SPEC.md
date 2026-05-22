# Tech Spec: Zion Talks Phase 5 — ProseCompressor (caveman port, MIT) + ContextSandbox (FTS5 sandbox, independent reimpl)

## Goal
Ship two native Swift services for the Zion chat stack: (1) `ProseCompressor` — a deterministic regex-based prose shrinker ported verbatim from caveman (MIT, JuliusBrussee) with attribution, exposed via a user-toggled `CompactResponseMode` (4 levels: off/lite/full/ultra) that both prompts the model AND optionally post-processes assistant deltas; and (2) `ContextSandbox` — an independent SQLite FTS5 + BM25 + Reciprocal-Rank-Fusion store (design pattern inspired by context-mode, no licensed code reused) that absorbs >5KB tool outputs, exposes a `search_tool_output` meta-tool, and enforces progressive throttling so the model is forced to query large results instead of re-fetching them.

## Constraints
- Language: Swift 5.10+.
- Framework: SwiftUI + AppKit, Swift Concurrency (`actor`, `@MainActor`, `@Observable`), `@AppStorage`, system `SQLite3` framework.
- Test runner: XCTest via `swift test` (target `ZionTests`).
- Build: `./scripts/make-app.sh` (preferred). `swift build --scratch-path /tmp/zion-build-fresh` requires `dangerouslyDisableSandbox: true` on this machine.
- Dependencies: NO new SPM deps. Reuse system `SQLite3`, `Foundation`, `NSRegularExpression`. Phase 2 (`ChatStorage`) and Phase 3 (`ZionHarness`, `ZionTools`, `ChatToolEvent`) are **NOT YET MERGED** in the working tree (verified: `Sources/Zion/Services/ChatStorage.swift`, `ZionHarness.swift`, `ZionTools.swift` do not exist; `Models/ChatModels.swift` defines `ChatRole`, `ChatMessage`, `ChatThread` only — no `ChatToolEvent`). The builder MUST detect this state at task 1 and either base off the relevant feature branch or create the Phase 2/3 surface stubs needed for Phase 5 to compile and test. Surface this in the PR description.
- Licensing:
  - **ProseCompressor** is a verbatim algorithmic port of `caveman/src/mcp-servers/caveman-shrink/compress.js` (MIT, © Julius Brussee). Required: copy the MIT LICENSE text verbatim into `docs/THIRD_PARTY.md`, attribute by name + upstream URL.
  - **ContextSandbox** is an **independent reimplementation** using public-domain techniques (SQLite FTS5, BM25 weighting, Cormack et al. 2009 Reciprocal Rank Fusion with `k=60`). Pattern *inspiration* attributed to context-mode (https://github.com/mksglu/context-mode), but **NO verbatim code or schema is copied from that repo** — schema, tokenizer choice, public API, error types, throttling semantics are all original. ELv2 obligations do NOT carry over because no licensed material is reused. `docs/THIRD_PARTY.md` mentions context-mode as a reference inspiration only (no license text required, but a courtesy attribution line is included).
- Boundaries:
  - Phase 5 work on branch `feature/zion-talks-phase5-compact-sandbox` cut from latest `origin/master` (always `git fetch origin` first).
  - MUST NOT touch files outside the project root. MUST NOT commit `.sdd/`.
  - All user-facing strings via `L10n("dot.notation.key")` in en/pt-BR/es.
  - New SwiftUI views use `DesignSystem.Colors.*`, `DesignSystem.Spacing.*`, `DesignSystem.Typography.*` — no hardcoded colors, fonts, corner radii.
  - Each task touches ≤5 files. Total tasks ≤11.

## Reuse
- `Sources/Zion/Helpers/UserDefaultsKeys.swift` — extend the existing `enum UserDefaultsKeys { enum AI { ... } }` namespace with new compact + sandbox keys. NEVER sprinkle string literals.
- `Sources/Zion/Helpers/Constants.swift` — host all numeric tunables (`Constants.Limits.sandboxThresholdBytes = 5120`, `largeOutputThresholdBytes = 102_400`, `sandboxMaxChunkBytes = 4096`, `sandboxSearchLimit = 3`, `progressiveThrottleThreshold = 8`). Discoverable, central, follows existing project naming convention rule.
- `Sources/Zion/Services/ChatService.swift` — `@MainActor @Observable final class ChatService` already owns thread + send pipeline. Extend `send()` to: (a) append `CompactResponseMode.systemPromptAddendum(...)` to the system message when compact mode != .off, (b) call `harness.beginNewTurn()` at start of each user turn, (c) when post-process toggle is on AND stream completes, run final assistant text through `ProseCompressor.compress(...)`.
- `Sources/Zion/Models/ChatModels.swift` — currently defines `ChatRole`, `ChatMessage`, `ChatThread`. Phase 5 EXTENDS `ChatMessage` with an additive optional `sandboxedByteCount: Int?` (default nil) and adds `enum ChatToolEventKind` + `struct ChatToolEvent` (since Phase 3 has not landed). When Phase 3 merges first, deduplicate by extending instead of creating.
- `Sources/Zion/Views/Settings/AISettingsTab.swift` — existing `Form { Section { ... } }` + `@AppStorage` + `Picker`/`Toggle`/`Text(L10n(...))` pattern. Add a new "Compact & Sandbox" section inline; do NOT create a new tab.
- `Sources/Zion/Views/Chat/ChatComposer.swift` — existing composer; add a small `CompactPill` view to its toolbar row.
- `Sources/Zion/Views/Chat/ChatMessageBubble.swift` — existing message renderer; when message has `sandboxedByteCount != nil` (or Phase 3 `ChatToolEvent.sandboxedByteCount`), append a chip via the new `ChatToolEventBadge` view.
- `Sources/Zion/Resources/{en,pt-BR,es}.lproj/Localizable.strings` — every new user-facing string goes in all three.
- `Sources/Zion/Helpers/ZionResourceBundle.swift` (the `L10n("key", args...)` helper) — use as-is.
- `Tests/ZionTests/ChatLocalizationTests.swift` — pattern for verifying L10n keys exist in all 3 locales and that format markers (`%@`, `%d`) interpolate. Mirror for Phase 5 keys.
- `Tests/ZionTests/ChatServiceTests.swift`, `ChatModelsTests.swift`, `ChatContextBuilderTests.swift`, `ChatSlashCommandParserTests.swift` — patterns for Chat-tier unit tests (mock providers, in-memory state).
- SQLite idiom: `import SQLite3`, `OpaquePointer?` handle, `sqlite3_open_v2`, `sqlite3_prepare_v2` + `sqlite3_step` + `sqlite3_finalize`, `sqlite3_bind_*`, `sqlite3_column_*`. Mirror the pattern used by ChatStorage (Phase 2) once it lands; until then, the ContextSandbox file is the canonical example.

## Acceptance Criteria
1. `Sources/Zion/Services/ProseCompressor.swift` exposes `static func compress(_ text: String, level: CompactLevel) -> String` — `grep -E "static func compress\(" Sources/Zion/Services/ProseCompressor.swift | wc -l | tr -d ' '` returns `1`.
2. `ProseCompressor.compress(_:level: .off)` returns input unchanged for ANY input — `swift test --filter ProseCompressorTests/test_off_is_identity` passes.
3. Fenced code blocks (` ```...``` `), inline backticks, URLs (`https?://...`), filesystem paths (containing `/` or `\`), CONST_CASE tokens (`[A-Z_]{2,}`), dotted method calls (`foo.bar(...)`), bare function calls (`fn(...)`), and SemVer versions (`\d+\.\d+\.\d+`) are NEVER mutated at any level — `swift test --filter ProseCompressorTests/test_protected_ranges_preserved` passes.
4. `.lite` drops pleasantries/hedges/leaders but keeps articles + full sentences — `swift test --filter ProseCompressorTests/test_lite_drops_pleasantries_keeps_articles` passes.
5. `.full` drops articles (`a|an|the` before lowercase) AND everything `.lite` drops — `swift test --filter ProseCompressorTests/test_full_drops_articles` passes.
6. `.ultra` drops conjunctions (`and|but|or|so|because|since`) AND everything `.full` drops — `swift test --filter ProseCompressorTests/test_ultra_drops_conjunctions` passes.
7. After deletions, `ProseCompressor` capitalises the first letter following sentence terminators (`. ! ?`) — `swift test --filter ProseCompressorTests/test_cap_first_after_sentence_terminator` passes.
8. Protected-range splice is index-stable: sentinels are replaced in original-token order, no off-by-one — `swift test --filter ProseCompressorTests/test_splice_integrity` passes.
9. `Sources/Zion/Services/CompactResponseMode.swift` defines `enum CompactLevel: String, Codable, CaseIterable { case off, lite, full, ultra }` and `static func systemPromptAddendum(level: CompactLevel, locale: Locale) -> String` and `static func compress(_ assistantText: String, level: CompactLevel) -> String` — `grep -cE "enum CompactLevel|static func systemPromptAddendum|static func compress" Sources/Zion/Services/CompactResponseMode.swift | tr -d ' '` returns `3`.
10. `systemPromptAddendum(level: .off, locale: _)` returns `""` for every locale — `swift test --filter CompactResponseModeTests/test_off_returns_empty` passes.
11. Addendum for `.lite`/`.full`/`.ultra` is non-empty AND differs between levels AND between locales (en vs pt-BR vs es) — `swift test --filter CompactResponseModeTests/test_levels_and_locales_differ` passes.
12. Addendum text is sourced from L10n keys `compact.prompt.{lite,full,ultra}` (not hardcoded literals) — `grep -cE "L10n\\(\"compact\\.prompt" Sources/Zion/Services/CompactResponseMode.swift` returns `>= 3`.
13. `ChatService.send()` appends the addendum to the outgoing system message when `UserDefaults.standard.string(forKey: UserDefaultsKeys.AI.chatCompactLevel) != "off"`, omits when `"off"` — `swift test --filter ChatServiceTests/test_compact_addendum_applied_when_on` and `.../test_compact_addendum_omitted_when_off` pass.
14. When `chat.compactPostProcess == true` AND stream contains assistant text, ChatService runs the final text through `ProseCompressor.compress(_:level:)` before final commit — `swift test --filter ChatServiceTests/test_post_process_runs_when_enabled` passes.
15. Post-process is skipped when the assistant response trimmed starts with `{` or `[` (JSON heuristic) — `swift test --filter ChatServiceTests/test_post_process_skipped_for_json_output` passes.
16. `Sources/Zion/Services/ContextSandbox.swift` declares `actor ContextSandbox` with public `ingest`, `search`, `purge`, `stats`, and `static var isAvailable: Bool` — `grep -cE "actor ContextSandbox|func ingest|func search|func purge|func stats|isAvailable" Sources/Zion/Services/ContextSandbox.swift` returns `>= 6`.
17. ContextSandbox detects FTS5 at init via `PRAGMA compile_options` and sets `isAvailable = false` + throws `ContextSandboxError.fts5Unavailable` if missing — `swift test --filter ContextSandboxTests/test_fts5_required_check` passes (test forces failure by mocking via injectable open path).
18. Per-repo DB scoping: two `ContextSandbox` instances on different `repoURL`s write to different files under `~/Library/Application Support/Zion/sandbox/<repo-id>.db` — `swift test --filter ContextSandboxTests/test_per_repo_db_isolation` passes.
19. Per-thread row scoping: `search(query:)` only returns hits whose `thread_id` matches the actor's current thread — `swift test --filter ContextSandboxTests/test_per_thread_scoping` passes.
20. `ingest` returns input unchanged (`SandboxResult.truncated == false`) when `content.utf8.count < Constants.Limits.sandboxThresholdBytes` — `swift test --filter ContextSandboxTests/test_below_threshold_passthrough` passes.
21. `ingest` of a 50KB string returns `SandboxResult { truncated: true, summary: <= 1000 chars + footer, sourceID: > 0 }` and persists chunks to FTS5 — `swift test --filter ContextSandboxTests/test_above_threshold_indexed` passes.
22. Chunking splits by markdown headings if present, else into ≤`Constants.Limits.sandboxMaxChunkBytes` (4096) chunks; never produces a chunk > 4096 bytes — `swift test --filter ContextSandboxTests/test_chunk_strategy_caps_size` passes.
23. Schema includes both `chunks` (porter+unicode61+remove_diacritics) and `chunks_trigram` (trigram tokenizer) FTS5 virtual tables — `swift test --filter ContextSandboxTests/test_dual_fts_tables_created` passes (PRAGMA table_info / sqlite_master query).
24. `search("error_keyword")` returns hits ranked by BM25 with `title` weighted 5× content — `swift test --filter ContextSandboxTests/test_bm25_title_weight` passes (title-hit ranks above content-only hit).
25. `search` fuses porter-FTS results with trigram-FTS results via RRF `score = Σ 1/(60 + rank_i)` — `swift test --filter ContextSandboxTests/test_rrf_fusion` passes (substring-only match found via trigram path).
26. Diacritic-insensitive matching: `search("acao")` finds content `"ação"` — `swift test --filter ContextSandboxTests/test_unicode_diacritic_search` passes.
27. `purge()` removes all rows from `sources`, `chunks`, `chunks_trigram`; `stats()` afterwards reports `entryCount == 0`, `totalBytes == 0` — `swift test --filter ContextSandboxTests/test_purge_and_stats` passes.
28. `stats()` is cached for 5 seconds (second call within window returns same snapshot without re-querying) — `swift test --filter ContextSandboxTests/test_stats_cached_5s` passes.
29. `Sources/Zion/Services/ZionTools.swift` exports `search_tool_output(query: String, sourceID: Int?)` schema for BOTH OpenAI and Anthropic shapes — `grep -cE "search_tool_output" Sources/Zion/Services/ZionTools.swift` returns `>= 2`.
30. `Sources/Zion/Services/ZionHarness.swift` injects an optional `ContextSandbox?`, exposes `func beginNewTurn()` resetting `currentTurnCalls = 0`, and routes any tool result whose `utf8.count > Constants.Limits.sandboxThresholdBytes` through `sandbox.ingest` when sandbox enabled — `swift test --filter ZionHarnessSandboxTests/test_large_output_auto_ingested` passes.
31. `ZionHarness.execute` handles `search_tool_output` by delegating to `sandbox.search` and returning matched snippets formatted as plain text — `swift test --filter ZionHarnessSandboxTests/test_search_tool_output_returns_hits` passes.
32. Progressive throttle: calls 1-3 full results; calls 4-8 search limit reduced to 1; calls 9+ reject ALL tools except `search_tool_output` with localized error `tool.throttled.useSearch` — `swift test --filter ZionHarnessSandboxTests/test_progressive_throttle_tiers` passes.
33. Throttle counter resets on `beginNewTurn()` — `swift test --filter ZionHarnessSandboxTests/test_throttle_resets_on_new_turn` passes.
34. When `chat.sandboxEnabled == false`, ZionHarness returns raw tool output unchanged (passthrough) — `swift test --filter ZionHarnessSandboxTests/test_sandbox_disabled_passes_through` passes.
35. `Sources/Zion/Views/Chat/CompactPill.swift` defines a `struct CompactPill: View` that reads `@AppStorage(UserDefaultsKeys.AI.chatCompactLevel)` and cycles `.off → .lite → .full → .ultra → .off` on tap via an extracted helper `static func nextLevel(after: CompactLevel) -> CompactLevel` — `swift test --filter CompactPillTests/test_cycle_helper` passes (tests helper directly; UI not required in test).
36. `ChatComposer` renders `CompactPill` next to existing controls — `grep -c "CompactPill" Sources/Zion/Views/Chat/ChatComposer.swift` returns `>= 1`.
37. `Sources/Zion/Views/Chat/ChatToolEventBadge.swift` exists and, when its `event.sandboxedByteCount != nil`, renders a chip via L10n key `chat.tool.sandbox.indexed` — `grep -cE "ChatToolEventBadge|chat\\.tool\\.sandbox\\.indexed" Sources/Zion/Views/Chat/ChatToolEventBadge.swift` returns `>= 2`.
38. `AISettingsTab` exposes (a) Picker for compact level, (b) Toggle for post-process, (c) Toggle for sandbox enabled, (d) Stepper for intent threshold (bytes) 1024…102400 step 1024, (e) Stats label, (f) "Clear sandbox" button with `.confirmationDialog` — `grep -cE "settings\\.ai\\.compactLevel\\.title|settings\\.ai\\.compactLevel\\.postProcess|settings\\.ai\\.sandbox\\.enable|settings\\.ai\\.sandbox\\.intentThreshold|settings\\.ai\\.sandbox\\.stats|settings\\.ai\\.sandbox\\.purge" Sources/Zion/Views/Settings/AISettingsTab.swift` returns `>= 6`.
39. All Phase 5 L10n keys exist in `en.lproj`, `pt-BR.lproj`, `es.lproj` AND format-string args interpolate correctly — `swift test --filter ChatLocalizationTests/test_phase5_keys_in_all_locales` passes.
40. `docs/THIRD_PARTY.md` exists, contains a verbatim MIT LICENSE block for caveman with attribution to Julius Brussee + upstream URL, and a courtesy attribution line for context-mode marked as "design inspiration, no licensed code reused" — `grep -cE "caveman|Julius Brussee|MIT License|context-mode|design inspiration" docs/THIRD_PARTY.md` returns `>= 5`.
41. `Sources/Zion/Views/HelpSheet.swift` (or About panel) has a link/button to open `docs/THIRD_PARTY.md` — `grep -cE "THIRD_PARTY" Sources/Zion/Views/HelpSheet.swift` returns `>= 1`.
42. No hardcoded DesignSystem values in new SwiftUI views — for each new/modified view file, `git diff origin/master -- <file> | grep '^+' | grep -E "Color\\.|\\.font\\(\\.|cornerRadius:\\s*[0-9]+" | grep -v "DesignSystem\\." | wc -l` returns `0`.
43. Phase 1 test suites stay green — `swift test --filter "ChatServiceTests|ChatModelsTests|ChatContextBuilderTests|ChatSlashCommandParserTests|AIClientLocalDispatchTests|ChatLocalizationTests" 2>&1 | tail -5` shows no failures.
44. Full test suite green — `swift test 2>&1 | tail -5` contains the string `passed` and no `failed`.
45. App builds — `./scripts/make-app.sh 2>&1 | tail -3` shows no compiler errors and produces `dist/Zion.app`.

## Architecture

### Files to create
- `Sources/Zion/Services/ProseCompressor.swift` (~120 lines) — pure deterministic compressor. Public surface:
  - `enum ProseCompressor { static func compress(_ text: String, level: CompactLevel) -> String }`
  - Internal: `_sentinelize(_:)` builds `(scrubbed: String, originals: [String])` by replacing protected regex matches (in priority order: fenced → inline backticks → URL → path → CONST_CASE → dotted method call → bare function call → SemVer) with ` \u{1F}<index>\u{1F} ` sentinels; `_unsentinelize(_:originals:)` restores.
  - Internal `_applyDeletions(_:level:)` runs ordered `NSRegularExpression` replacements per level table (see Builder Notes).
  - Internal `_capFirstAfterTerminator(_:)` applies `([.!?])\s+([a-z])` → `$1 <uppercased $2>`.
  - Header comment: `// Adapted from caveman (MIT) by Julius Brussee — https://github.com/JuliusBrussee/caveman` + brief description of port scope.
- `Sources/Zion/Services/CompactResponseMode.swift` (~80 lines):
  - `enum CompactLevel: String, Codable, CaseIterable { case off, lite, full, ultra }` (raw values lowercase strings used by `@AppStorage`).
  - `static func systemPromptAddendum(level: CompactLevel, locale: Locale = .current) -> String` — `.off` → `""`; else dispatches to L10n key `compact.prompt.<level>` (Localizable.strings handles locale).
  - `static func compress(_ assistantText: String, level: CompactLevel) -> String` — thin wrapper around `ProseCompressor.compress`.
  - `static var current: CompactLevel { CompactLevel(rawValue: UserDefaults.standard.string(forKey: UserDefaultsKeys.AI.chatCompactLevel) ?? "off") ?? .off }`.
- `Sources/Zion/Services/ContextSandbox.swift` (~350 lines) — independent reimplementation. `actor ContextSandbox`:
  - Init: `init(repoURL: URL, threadID: String?, fileManager: FileManager = .default) throws`
  - State: opaque pointer SQLite handle, `currentThreadID: String?`, `private var statsCache: (snapshot: SandboxStats, timestamp: Date)?`.
  - `static var isAvailable: Bool { get }` — true iff a probe `sqlite3_open_v2(":memory:") + PRAGMA compile_options` finds `ENABLE_FTS5`.
  - DB path: `<Application Support>/Zion/sandbox/<repoID>.db` where repoID is derived from `repoURL.absoluteString.hash` hex string (provide static helper `static func repoID(for url: URL) -> String`).
  - Schema initialised under `BEGIN; ... COMMIT;` on first open (idempotent `CREATE IF NOT EXISTS`):
    ```sql
    CREATE TABLE IF NOT EXISTS sources (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      thread_id TEXT,
      label TEXT NOT NULL,
      tool_name TEXT NOT NULL,
      tool_call_id TEXT,
      intent TEXT,
      indexed_at REAL NOT NULL,
      bytes INTEGER NOT NULL DEFAULT 0
    );
    CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING fts5(
      title, content,
      source_id UNINDEXED,
      tokenize='porter unicode61 remove_diacritics 2'
    );
    CREATE VIRTUAL TABLE IF NOT EXISTS chunks_trigram USING fts5(
      title, content,
      source_id UNINDEXED,
      tokenize='trigram'
    );
    CREATE INDEX IF NOT EXISTS idx_sources_label ON sources(label);
    CREATE INDEX IF NOT EXISTS idx_sources_indexed_at ON sources(indexed_at);
    CREATE INDEX IF NOT EXISTS idx_sources_thread ON sources(thread_id);
    PRAGMA user_version = 1;
    ```
  - Public API:
    - `func ingest(toolName: String, toolCallID: String, content: String, intent: String?) async throws -> SandboxResult`
    - `func search(query: String, limit: Int = 3, sourceID: Int64? = nil) async throws -> [SandboxHit]`
    - `func purge() async throws`
    - `func stats() async throws -> SandboxStats`
  - Result types:
    - `struct SandboxResult { let summary: String; let sourceID: Int64; let bytes: Int; let truncated: Bool }`
    - `struct SandboxHit { let sourceID: Int64; let label: String; let snippet: String; let score: Double }`
    - `struct SandboxStats { let entryCount: Int; let totalBytes: Int }`
    - `enum ContextSandboxError: Error { case fts5Unavailable; case openFailed(String); case sqlError(String) }`
  - Chunking: pure helper `static func chunk(_ content: String, maxBytes: Int) -> [(title: String, body: String)]` — split on `^#{1,6}\s+...$` first; if no headings, slice every `maxBytes` UTF-8 bytes (respecting code-point boundaries via `String.Index` arithmetic). Each chunk's title is either the heading line or `"chunk \(i)"`.
  - Search: two FTS5 queries (`SELECT rowid, ... FROM chunks WHERE chunks MATCH ? ORDER BY bm25(chunks, 5.0, 1.0) LIMIT 50`) and same against `chunks_trigram`. Merge via RRF (k=60). Optional thread filter via JOIN on `sources.thread_id = currentThreadID`. Return top `limit`.
  - Public static helper `static func reciprocalRankFusion(rankings: [[Int64]], k: Int = 60) -> [(id: Int64, score: Double)]` extracted for unit-testability.
- `Sources/Zion/Services/ZionHarness.swift` (~250 lines) — Phase 3 surface as defined by SPEC READY. `actor ZionHarness` with public `execute(toolCall:) async -> ToolResult`, `func beginNewTurn()`, `func resetSession()`. Phase 5 adds: optional `let sandbox: ContextSandbox?` injected at init; `private var currentTurnCalls: Int = 0`; throttle tier logic in `execute`; auto-ingest large outputs; handler for `search_tool_output`. If Phase 3 already created this file, EXTEND additively; do not duplicate.
- `Sources/Zion/Services/ZionTools.swift` (~150 lines) — Phase 3 surface. Adds `search_tool_output` tool schema in both `toolSchemasJSON()` (OpenAI) and `anthropicToolSchemas()` (Anthropic) shapes. Description: `"Search past tool outputs in this chat that were auto-indexed because they exceeded the size threshold. Use this instead of re-running expensive tools when you need to recall earlier content."` Parameters: `query` (required string), `sourceID` (optional integer).
- `Sources/Zion/Views/Chat/CompactPill.swift` (~60 lines) — `struct CompactPill: View` reading `@AppStorage(UserDefaultsKeys.AI.chatCompactLevel)`, button label = localized current level, tap = cycle. Use `DesignSystem.Colors.accent`, `DesignSystem.Spacing.smallCornerRadius`, `DesignSystem.Typography.caption`.
- `Sources/Zion/Views/Chat/ChatToolEventBadge.swift` (~80 lines) — `struct ChatToolEventBadge: View` rendering either the standard tool-event chip OR (when `event.sandboxedByteCount != nil`) the "indexed" chip with text `L10n("chat.tool.sandbox.indexed", formattedBytes)`. Reused from Phase 3 if present.
- `docs/THIRD_PARTY.md` — verbatim MIT LICENSE for caveman + attribution line; courtesy attribution line for context-mode marked as "design inspiration, independent reimplementation, no licensed code reused". No ELv2 text needed.
- `Tests/ZionTests/ProseCompressorTests.swift` — AC 1-8.
- `Tests/ZionTests/CompactResponseModeTests.swift` — AC 9-12.
- `Tests/ZionTests/ContextSandboxTests.swift` — AC 16-28. Uses `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)` as repoURL; cleans up in `tearDown`.
- `Tests/ZionTests/ZionHarnessSandboxTests.swift` — AC 30-34.
- `Tests/ZionTests/CompactPillTests.swift` — AC 35 (pure cycle helper test).

### Files to modify
- `Sources/Zion/Helpers/UserDefaultsKeys.swift` — extend `enum AI` with:
  ```swift
  static let chatCompactLevel = "chat.compactLevel"        // CompactLevel raw, default "off"
  static let chatCompactPostProcess = "chat.compactPostProcess" // Bool, default false
  static let chatSandboxEnabled = "chat.sandboxEnabled"    // Bool, default true
  static let chatSandboxIntentThresholdBytes = "chat.sandbox.intentThresholdBytes" // Int, default 5120
  static let chatSandboxLargeOutputThresholdBytes = "chat.sandbox.largeOutputThresholdBytes" // Int, default 102_400
  ```
- `Sources/Zion/Helpers/Constants.swift` — add to `Constants.Limits` (or create the enum if absent):
  ```swift
  static let sandboxThresholdBytes = 5120
  static let sandboxLargeOutputBytes = 102_400
  static let sandboxMaxChunkBytes = 4096
  static let sandboxSearchLimit = 3
  static let sandboxSummaryPrefixChars = 1000
  static let progressiveThrottleThreshold = 8
  static let progressiveThrottleSoftTier = 3
  static let statsCacheTTLSeconds: TimeInterval = 5
  ```
- `Sources/Zion/Models/ChatModels.swift` — add `var sandboxedByteCount: Int? = nil` to `ChatMessage`; if Phase 3 has merged a `ChatToolEvent` type, extend that type instead with `var sandboxedByteCount: Int?` and `var sandboxSourceID: Int64?`. Add `enum ChatToolEventKind { case standard, sandboxIndexed }` if absent.
- `Sources/Zion/Services/ChatService.swift` — in `send()`:
  1. Read `UserDefaults.standard.string(forKey: UserDefaultsKeys.AI.chatCompactLevel)` → `CompactLevel`. If `!= .off`, append `CompactResponseMode.systemPromptAddendum(level:, locale: .current)` to the system message.
  2. Call `harness?.beginNewTurn()` at the start.
  3. After the stream completes, if `UserDefaults.standard.bool(forKey: UserDefaultsKeys.AI.chatCompactPostProcess)` AND assistant text trimmed does NOT start with `{` or `[`, call `ProseCompressor.compress(finalText, level: currentLevel)` and replace the final message body.
  4. Per-thread `ContextSandbox` cache: `private var sandboxCache: [String: ContextSandbox] = [:]` keyed by threadID; lazy `try?` init; passed to ZionHarness when constructing per-turn execution context.
- `Sources/Zion/Views/Chat/ChatComposer.swift` — render `CompactPill()` in the toolbar HStack next to existing provider menu / send button.
- `Sources/Zion/Views/Chat/ChatMessageBubble.swift` — when message has tool events whose `sandboxedByteCount != nil`, render `ChatToolEventBadge(event:)`.
- `Sources/Zion/Views/Settings/AISettingsTab.swift` — append a new `Section(L10n("settings.ai.compactSandbox.title"))` containing:
  - `Picker(L10n("settings.ai.compactLevel.title"), selection: $compactLevelRaw)` over `CompactLevel.allCases` with `Text(L10n("settings.ai.compactLevel.\\(case.rawValue)"))`.
  - `Text(L10n("settings.ai.compactLevel.hint")).font(DesignSystem.Typography.caption)`.
  - `Toggle(L10n("settings.ai.compactLevel.postProcess"), isOn: $compactPostProcess)` + hint.
  - `Toggle(L10n("settings.ai.sandbox.enable"), isOn: $sandboxEnabled)` + hint.
  - `Stepper(value: $sandboxIntentThreshold, in: 1024...102400, step: 1024)` with label rendering byte count via `ByteCountFormatter`.
  - Stats row: `Text(L10n("settings.ai.sandbox.stats", stats.entryCount, formattedBytes))`.
  - `Button(L10n("settings.ai.sandbox.purge"), role: .destructive) { showPurgeConfirm = true }` + `.confirmationDialog(L10n("settings.ai.sandbox.purge.confirm"), ...)` calling `await sandbox.purge()`.
- `Sources/Zion/Views/HelpSheet.swift` — add a button or link to `docs/THIRD_PARTY.md` (open via `NSWorkspace.shared.open(URL(fileURLWithPath:))` or a custom about-style sheet — choose pattern that exists already in the file).
- `Sources/Zion/Resources/en.lproj/Localizable.strings` — add all keys listed in **L10n keys** section.
- `Sources/Zion/Resources/pt-BR.lproj/Localizable.strings` — same keys, PT-BR values (natural, no em dashes).
- `Sources/Zion/Resources/es.lproj/Localizable.strings` — same keys, ES values.
- `Tests/ZionTests/ChatLocalizationTests.swift` — add `test_phase5_keys_in_all_locales` exercising every new key in en/pt-BR/es bundles + interpolation.
- `Tests/ZionTests/ChatServiceTests.swift` — extend with AC 13-15 (compact addendum applied/omitted, post-process toggle, JSON-skip heuristic).

### L10n keys (must exist in en + pt-BR + es)
- `settings.ai.compactSandbox.title`
- `settings.ai.compactLevel.title`
- `settings.ai.compactLevel.off`
- `settings.ai.compactLevel.lite`
- `settings.ai.compactLevel.full`
- `settings.ai.compactLevel.ultra`
- `settings.ai.compactLevel.hint`
- `settings.ai.compactLevel.postProcess`
- `settings.ai.compactLevel.postProcess.hint`
- `settings.ai.sandbox.title`
- `settings.ai.sandbox.enable`
- `settings.ai.sandbox.enable.hint`
- `settings.ai.sandbox.intentThreshold`
- `settings.ai.sandbox.stats` (format args: `%d` entries, `%@` size)
- `settings.ai.sandbox.purge`
- `settings.ai.sandbox.purge.confirm`
- `chat.composer.compactPill.off`
- `chat.composer.compactPill.lite`
- `chat.composer.compactPill.full`
- `chat.composer.compactPill.ultra`
- `chat.tool.sandbox.indexed` (format arg: `%@` size)
- `chat.tool.sandbox.searchHint`
- `tool.throttled.useSearch`
- `compact.prompt.lite`
- `compact.prompt.full`
- `compact.prompt.ultra`

(25 keys total. `compact.prompt.*` values ARE the locale-specific directives — `Localizable.strings` dispatches by locale, no per-language suffix needed.)

### Dependencies between files
- `ProseCompressor.swift` depends on `Foundation` (NSRegularExpression) only.
- `CompactResponseMode.swift` depends on `ProseCompressor.swift` (compress wrapper), `ZionResourceBundle` (L10n), `UserDefaultsKeys.swift`.
- `ContextSandbox.swift` depends on system `SQLite3`, `Foundation`, `Constants.swift`.
- `ZionHarness.swift` depends on `ContextSandbox.swift` (optional injection), `ZionTools.swift` (schema lookup), `Constants.swift`, `ZionResourceBundle` (throttle error message).
- `ChatService.swift` depends on `CompactResponseMode.swift`, `ProseCompressor.swift`, `ContextSandbox.swift` (cache + inject), `ZionHarness.swift`, `UserDefaultsKeys.swift`.
- `AISettingsTab.swift` depends on `CompactResponseMode.swift` (enum cases), `ContextSandbox.swift` (stats + purge), `UserDefaultsKeys.swift`, `Constants.swift`.
- `CompactPill.swift` depends on `CompactResponseMode.swift` (cycle helper) + `UserDefaultsKeys.swift`.
- `ChatComposer.swift` depends on `CompactPill.swift`.
- `ChatToolEventBadge.swift` depends on `ChatModels.swift` (new sandboxedByteCount field).
- `ChatMessageBubble.swift` depends on `ChatToolEventBadge.swift`.
- `HelpSheet.swift` depends on `docs/THIRD_PARTY.md` (file path / URL only, no compile dep).

## Edge Cases
1. **Phase 2 (`ChatStorage`) not merged.** `ContextSandbox` does NOT depend on it directly — it instantiates its own SQLite handle following the documented idiom. No blocker. Note in PR description.
2. **Phase 3 (`ZionHarness`/`ZionTools`/`ChatToolEvent`) not merged.** Task 1 must `ls Sources/Zion/Services/ZionHarness.swift Sources/Zion/Services/ZionTools.swift` and either create the Phase 3 surface stubs (matching the Phase 3 SPEC READY contract) sufficient for Phase 5 to compile + test, or rebase onto the Phase 3 branch. Mark the chosen approach in the PR description.
3. **FTS5 missing on host.** `ContextSandbox.isAvailable` returns false; `ChatService` does not pass a sandbox to `ZionHarness`; harness routes tool output unchanged. UI Settings shows the toggle disabled with hint `L10n("settings.ai.sandbox.unavailable")` — add this key too if executor encounters this path, default text "SQLite FTS5 unavailable on this system".
4. **Concurrent ingest on same actor.** `actor ContextSandbox` serializes by definition. Statements are prepared per-call (no caching) for Phase 5 simplicity.
5. **`ProseCompressor` mid-stream.** Phase 5 only post-processes at stream completion, NOT per delta. Per-delta is Phase 6+ (out of scope).
6. **`ProseCompressor` on assistant text containing JSON.** Skip if trimmed starts with `{` or `[`. AC 15 covers.
7. **`ProseCompressor` on Markdown headings.** Heading lines (`^#{1,6}\s+...`) are preserved as protected ranges — add as one more sentinelize regex (priority just after fenced code blocks).
8. **Sentinel character collision.** Use `U+001F` (Information Separator One, unit separator) as sentinel delimiter — never appears in human text or code. Format: `\u{1F}<index>\u{1F}`.
9. **NSRegularExpression performance.** Compile each pattern once at file load via `private static let _patterns: [Level: [NSRegularExpression]] = ...`. NEVER recompile per call.
10. **Diacritic-insensitive search.** `tokenize='porter unicode61 remove_diacritics 2'` handles this for FTS5. Trigram FTS5 tokenizer also strips diacritics by default. Test asserts `"acao"` finds `"ação"`.
11. **Empty / whitespace tool output to `ingest`.** Skip storage; return `SandboxResult(summary: "", sourceID: -1, bytes: 0, truncated: false)`.
12. **Threshold set to 0.** `>` comparison treats every output as ingest-eligible; harness still passes through for empty outputs (covered above).
13. **Stats cache invalidation.** `purge()` and `ingest()` clear `statsCache` so the next `stats()` re-queries.
14. **Per-thread scoping when threadID is nil.** Pass nil thread filter (search ALL rows in the repo DB). Documented in Builder Notes; settings UI shows the global stats.
15. **Progressive throttle counter timing.** Counter increments BEFORE tool execution; the 4th-8th calls execute with `searchLimit = 1`; the 9th call rejects with `tool.throttled.useSearch` unless it IS `search_tool_output`. Reset happens at `beginNewTurn()`, called by `ChatService.send()` at the very start.
16. **Subprocess env-strip and SSRF guard.** Out of scope (Phase 4 / Phase 6 prerequisites missing). Document in Out of Scope.
17. **`search_tool_output` called when sandbox empty.** Return localized message `chat.tool.sandbox.searchHint`. Do NOT error.
18. **SQLite file corruption / open failure.** Catch `sqlite3_open_v2` error, log via `DiagnosticLogger`, set `isAvailable = false` for the actor instance, fall back to passthrough. Do NOT crash ChatService.
19. **Schema migration.** `PRAGMA user_version = 1`. Future phases bump and migrate.
20. **Compact addendum + tool calling.** Include explicit line in each `compact.prompt.*` directive: "Tool call JSON must remain valid and unchanged. Only natural-language responses are compacted." See Builder Notes for verbatim text.
21. **Locale fallback in `systemPromptAddendum`.** L10n already falls back to base bundle (en) when no matching .lproj. No special-case code needed.

## Out of Scope
- MCP client implementation (Phase 6+).
- Wenyan classical-Chinese compression mode (Phase 7).
- Memory-file compression (`caveman-compress` equivalent) (Phase 7).
- Sensitive-path denylist for memory compression (Phase 7).
- Levenshtein typo correction in sandbox search (Phase 6).
- 24h TTL web-fetch cache (`ctx_fetch_and_index` pattern) — Phase 6 (when WebFetch tool ships).
- 14-day stale-DB cleanup at startup (Phase 6).
- Event-tier session snapshots (Phase 7).
- Subprocess env-strip denylist (gated on Phase 4 CLI providers).
- SSRF guard (`classifyIp` port) — gated on WebFetch tool.
- ML-based intent classification (NEVER — regex stays).
- Real-time streaming compression (compress per-delta) — Phase 6+.
- `cavecrew` subagents (investigator/builder/reviewer) — Phase 6.
- `caveman-stats` / `caveman-compress` slash commands — Zion has native chat stats.
- Embedding-based semantic search — FTS5 + trigram only in Phase 5.
- `ctx_insight` analytics dashboard.
- `ctx_execute` / `ctx_execute_file` multi-language code runner.
- Per-message sandbox UI viewer (click chip → see indexed content) — Phase 6.
- Migration of pre-existing large messages into the sandbox retroactively — only NEW tool calls are sandboxed.
- Live (`@Observable`) stats updates in Settings — single fetch per `.task` is enough in Phase 5.
- New SPM dependencies.

## Builder Notes
- **Branch hygiene:** `git fetch origin` then `git checkout -b feature/zion-talks-phase5-compact-sandbox origin/master`. NEVER push to master.
- **Phase 2/3 dependency check FIRST:** Task 1 runs:
  ```bash
  ls -1 Sources/Zion/Services/{ChatStorage,ZionHarness,ZionTools}.swift 2>&1
  grep -n "ChatToolEvent" Sources/Zion/Models/ChatModels.swift
  ```
  Report which exist. If Phase 3 surface is missing, create minimal stub matching its SPEC READY contract (just enough to compile + test Phase 5).
- **ProseCompressor regex tables (verbatim ported from caveman/src/mcp-servers/caveman-shrink/compress.js):**
  - Protected sentinelize order (apply in this order, capture each match, replace with `\u{1F}<idx>\u{1F}`):
    1. Fenced code: ` ```[\s\S]*?``` `
    2. Markdown headings: `^#{1,6}\s+.*$` (multiline)
    3. Inline backticks: `` `[^`]+` ``
    4. URLs: `https?://[^\s)]+`
    5. Filesystem paths: `\S*[/\\]\S+`
    6. CONST_CASE: `\b[A-Z_]{2,}\b`
    7. Dotted method call: `\w+\.\w+\([^)]*\)`
    8. Bare function call: `\w+\([^)]*\)`
    9. SemVer: `\b\d+\.\d+\.\d+\b`
  - Per-level deletions (apply in order on the scrubbed text):
    - **.lite, .full, .ultra (cumulative):**
      - Leaders: `(?im)^(I'll|I will|I can|I'd|you can|we will|we can|let me|let's)\s+` → `""`
      - Pleasantries: `(?i)\b(please|kindly|thanks?|sure|certainly|of course|happy to)\b` → `""`
      - Hedges: `(?i)\b(perhaps|maybe|might|could potentially|would like to|i think|it seems)\b` → `""`
    - **.full, .ultra (cumulative):**
      - Fillers: `(?i)\b(just|really|basically|actually|simply|quite|very|essentially|literally)\b` → `""`
      - Articles before lowercase: `\b(a|an|the)\s+(?=[a-z])` → `""`
    - **.ultra only:**
      - Conjunctions: `(?i)\b(and|but|or|so|because|since)\b` → `""`
    - **All levels (post-pass):**
      - Whitespace collapse: `[ \t]{2,}` → `" "`
  - Cap-first after sentence terminator: `([.!?])\s+([a-z])` — use a `NSRegularExpression` enumerate-matches loop, uppercase capture group 2 manually.
  - Splice originals back by iterating sentinel matches `\u{1F}(\d+)\u{1F}` and replacing each with `originals[Int(idx)]`.
- **Compact prompt directives (en, verbatim from caveman SKILL.md):**
  - `compact.prompt.lite` (en): `"Be concise. Drop pleasantries and filler words. Keep articles and full sentences. Professional but tight. Technical terms exact. Tool call JSON must remain valid and unchanged. Only natural-language responses are compacted."`
  - `compact.prompt.full` (en): `"Respond terse like smart caveman. Drop articles, pleasantries, filler. Fragments OK. Short synonyms ok. Technical terms exact. Code blocks unchanged. Tool call JSON must remain valid and unchanged. Only natural-language responses are compacted. Pattern: [thing] [action] [reason]. [next step]."`
  - `compact.prompt.ultra` (en): `"Caveman mode. Abbreviate prose words (DB, auth, config, req, res, fn, impl). Strip conjunctions. Arrows for causality (X then Y). One word when one word enough. Code symbols, function names, API names, error strings: never abbreviate. Tool call JSON must remain valid and unchanged."`
  - PT-BR and ES variants: translate the spirit naturally (these are model instructions; awkward translation will degrade compliance). No em dashes. Keep the "tool call JSON unchanged" sentence verbatim in meaning.
- **SQLite handle ownership pattern:**
  - Actor holds `private var db: OpaquePointer?`.
  - `init` opens via `sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)`.
  - Probe FTS5: `sqlite3_exec(db, "SELECT sqlite_compileoption_used('ENABLE_FTS5')", callback, ...)` — if not 1, throw `.fts5Unavailable`.
  - Statements prepared per-call (`sqlite3_prepare_v2` → `sqlite3_step` → `sqlite3_finalize` in `defer`). No caching in Phase 5.
  - Use parameterised statements (`?` bind markers + `sqlite3_bind_text` with `SQLITE_TRANSIENT`). NEVER string-concatenate user input.
- **Reciprocal Rank Fusion:** Pure helper `static func reciprocalRankFusion(rankings: [[Int64]], k: Int = 60) -> [(id: Int64, score: Double)]`. For each ranking, item at index `i` contributes `1.0 / Double(k + i + 1)` to its id's total. Sort by descending score. Cormack et al. 2009 standard. Extracted for direct unit-testability.
- **BM25 weights:** `bm25(chunks, 5.0, 1.0)` — first column (`title`) weighted 5×, second (`content`) weighted 1×. SQLite FTS5 reports lower BM25 as better, so wrap in `-bm25(...)` if normalising or simply `ORDER BY bm25(...) ASC LIMIT N`.
- **Trigram tokenizer** is built-in to FTS5 on modern macOS SQLite. Confirm at init via `PRAGMA compile_options` lookup (already covered by FTS5 probe).
- **`@AppStorage` in `@Observable` / `actor`:** Per known-bugs rule, `@AppStorage` does NOT work inside `@Observable` classes. Use direct `UserDefaults.standard.string(forKey:)` / `.bool(forKey:)` / `.integer(forKey:)` inside `ChatService.send()` and `ZionHarness.execute()`. SwiftUI views can keep `@AppStorage` (it works in views).
- **AppStorage defaults:**
  - `chat.compactLevel` → `"off"`
  - `chat.compactPostProcess` → `false`
  - `chat.sandboxEnabled` → `true`
  - `chat.sandbox.intentThresholdBytes` → `5120`
  - `chat.sandbox.largeOutputThresholdBytes` → `102400`
- **Settings UI defaults registration:** Add to the existing `UserDefaults.standard.register(defaults:)` call site if one exists; otherwise let the `@AppStorage` initial values in the view stand.
- **DesignSystem token usage:** All new SwiftUI views MUST use `DesignSystem.Colors.*`, `DesignSystem.Spacing.*`, `DesignSystem.Typography.*`. Mirror the pill/chip styling from existing Chat views.
- **L10n format markers:** `%@` for strings, `%d` for ints. Test via `ChatLocalizationTests` pattern.
- **Test runtime:** Full `swift test` takes ~60-90s on M-series. Each ContextSandbox test adds <1s. Don't set sub-30s test timeouts.
- **`swift build` / `swift test` sandbox:** Running these requires `dangerouslyDisableSandbox: true`. `./scripts/make-app.sh` runs unsandboxed already.
- **Attribution placement:** `docs/THIRD_PARTY.md` ships in the repo (not bundled in app binary). About panel link to `zioncode.dev` plus a button to `docs/THIRD_PARTY.md` is sufficient end-user-facing acknowledgement.
- **NEVER commit `.sdd/`:** stage `Sources/`, `Tests/`, `docs/THIRD_PARTY.md`, and `Sources/Zion/Resources/*.lproj/Localizable.strings` only. Do NOT `git add .`.
- **Build verification per task:** After edits, run `./scripts/make-app.sh 2>&1 | tail -20`. Don't proceed if compile breaks.
- **Don't break Phase 1 tests:** After each task, run the Phase 1 filter (see AC 43).
- **Task plan target (≤11 tasks, ≤5 files each):**
  1. Phase 2/3 surface check + create stubs OR rebase notes; extend `UserDefaultsKeys.swift` + `Constants.swift`.
  2. `ProseCompressor.swift` (sentinelize + per-level deletions + cap-first + splice) + `ProseCompressorTests.swift`.
  3. `CompactResponseMode.swift` (enum + addendum + compress wrapper) + `CompactResponseModeTests.swift` + L10n keys `compact.prompt.{lite,full,ultra}` in en/pt-BR/es.
  4. `ContextSandbox.swift` schema + ingest + chunking + stats + purge + `ContextSandboxTests.swift` (excluding search).
  5. `ContextSandbox.search` (porter + trigram + RRF) + tests including unicode + per-thread scoping + per-repo DB isolation.
  6. `ZionTools.swift` add `search_tool_output` schema (OpenAI + Anthropic) + schema test.
  7. `ZionHarness.swift` sandbox wrap + `beginNewTurn` + progressive throttle + `ZionHarnessSandboxTests.swift`.
  8. `ChatService.swift` wire compact addendum + post-process toggle + sandbox-per-thread cache + harness.beginNewTurn + ChatServiceTests extensions.
  9. `AISettingsTab.swift` Compact & Sandbox section (Picker + 2 Toggles + Stepper + Stats + Purge) + remaining settings L10n keys.
  10. `CompactPill.swift` + `ChatComposer.swift` integration + `ChatToolEventBadge.swift` + `ChatMessageBubble.swift` integration + `CompactPillTests.swift` + `ChatModels.swift` extension.
  11. `docs/THIRD_PARTY.md` + `HelpSheet.swift` link + `ChatLocalizationTests` `test_phase5_keys_in_all_locales` + full `swift test` + `./scripts/make-app.sh`.
- **Decision log:** After implementation, ask user whether to log "Native ProseCompressor (caveman port) + ContextSandbox (FTS5 sandbox, independent reimpl) over MCP client integration" in `docs/DECISIONS.md`.
- **Localization quality:** PT-BR + ES translations must read naturally for native speakers. The `compact.prompt.*` directives in particular are model instructions; awkward translation will hurt model compliance. Pull from existing PT-BR/ES copy in the .strings files for tone reference.
- **Independent reimplementation guarantee for ContextSandbox:** Do NOT copy any code, schema, identifiers, or text from the context-mode repo. Schema column names (`sources`, `chunks`, `chunks_trigram`), public API method names (`ingest`/`search`/`purge`/`stats`), error type names, throttle tier semantics (1-3 / 4-8 / 9+) are all original to Zion. The only shared concept is "FTS5 + BM25 + RRF over chunked tool output" which is a public-domain technique stack.
