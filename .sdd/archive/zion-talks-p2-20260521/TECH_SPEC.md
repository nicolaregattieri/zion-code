# Tech Spec: Zion Talks Phase 2 — Cloud Streaming, SQLite Persistence, Multi-Thread

## Goal
Extend the Phase 1 in-repo chat with (a) SSE streaming for Anthropic and OpenAI providers, (b) per-repo SQLite persistence of threads and messages, and (c) multi-thread management UI inside `ChatScreen`. Phase 1 behavior (slash commands, local streaming, ChatContextBuilder, AppSection.chat entry, L10n) is preserved verbatim.

## Constraints
- Language: Swift 5.10+
- Framework: SwiftUI + AppKit (macOS 14+)
- Test runner: XCTest via `swift test` (target `ZionTests`)
- Build: `./scripts/make-app.sh` (debug `swift build` requires `dangerouslyDisableSandbox: true`)
- Dependencies: existing only. Use `import SQLite3` (system C library) for persistence — **do not add a Swift Package dependency**. No new third-party deps.
- Boundaries:
  - MUST NOT modify `.sdd/` from product code (plugin dev folder, user memory rule).
  - MUST NOT alter `AIClient.call()` switch dispatch or signatures of Phase 1 APIs (`ChatContextBuilder`, `parseOpenAISSELine`, `LocalStreamChunk`, `streamLocalLLM`, `ChatScreen` public surface).
  - MUST NOT touch Gemini provider beyond ensuring it still routes via non-streaming `AIClient.call()` (Gemini streaming = Phase 3).
  - MUST NOT introduce tool-calling, @file mentions autocomplete, click-to-open paths, suggestion-apply UI, system-prompt customization, history search, export, or token usage display (all Phase 3).
  - Persistence path is fixed: `~/Library/Application Support/Zion/chats/<repo-id>.db` where `<repo-id>` is the first 16 hex chars of `SHA256(repoURL.path)`.
  - DB I/O must run off the main thread (ChatStorage is an `actor`).
  - All user-facing strings via `L10n("dot.notation.key")`, added to **all three** locale files (`en`, `pt-BR`, `es`).
  - No hardcoded colors, fonts, spacing, corner radius, or timing literals — use `DesignSystem.*` tokens and `Constants.Timing.*`.

## Reuse
- `Sources/Zion/Services/AIClient+Local.swift` — defines `struct LocalStreamChunk { let text: String; let done: Bool }` and `static func parseOpenAISSELine(_ line: Data) -> LocalStreamChunk?` plus `func streamLocalLLM(payload:baseURL:modelID:) -> AsyncThrowingStream<String, Error>`. The OpenAI cloud streamer MUST reuse `parseOpenAISSELine` unchanged (OpenAI Chat Completions SSE shape is identical to the local server). The Anthropic streamer MUST emit `LocalStreamChunk` from a new sibling parser so the consumer loop in `ChatService` does not branch per provider.
- `Sources/Zion/Services/AIClient.swift` — `actor AIClient`. Phase 1 `streamLocalLLM` is an actor method returning `AsyncThrowingStream<String, Error>`. The two new methods (`streamAnthropic`, `streamOpenAI`) MUST follow the same actor-method + `AsyncThrowingStream<String, Error>` signature and the same URLSession bytes-task SSE loop pattern used in `streamLocalLLM` (see lines ~119–200 of `AIClient+Local.swift`).
- `Sources/Zion/Services/ChatService.swift` — `@MainActor @Observable final class ChatService`. Reuse the existing send pipeline: `Task { @MainActor in ... }` continuation already used at line ~83. Add streaming dispatch in `send(...)` based on `aiSettings.provider` instead of touching `AIClient.call()`.
- `Sources/Zion/Services/ChatContextBuilder.swift` — slash command parser and repo context builder. Used unchanged from Phase 2 threads.
- `Sources/Zion/Models/ChatModels.swift` — existing `ChatThread` and `ChatMessage` types. Extend in place; do not introduce a parallel model.
- `Sources/Zion/ViewModel/RepositoryViewModel+Chat.swift` — Phase 1 lazy-creates `ChatService`. Extend the lazy init to also construct + inject a shared `ChatStorage` and the per-repo `repoID`.
- `Sources/Zion/DesignSystem/DesignSystem.swift` — tokens: `DesignSystem.Colors.selectionBackground` (line 162 / theme overrides 557–625), `DesignSystem.Colors.hoverBackground`, `DesignSystem.Spacing.*CornerRadius`, `DesignSystem.Typography.*`, `DesignSystem.Motion.*`. All new view code MUST consume these — never raw `Color`, `Font`, or numeric corner radius literals.
- `Sources/Zion/Helpers/Constants.swift` — `Constants.Timing.*` for the streaming debounce interval. Add a new `Constants.Timing.chatPersistenceDebounce` (500 ms) rather than inlining.
- `Sources/Zion/Resources/{en,pt-BR,es}.lproj/Localizable.strings` — Phase 1 `chat.*` keys already live here (en line 2415+). Add new keys at the bottom of the chat section in **all three** files.
- `Tests/ZionTests/ChatServiceTests.swift`, `ChatContextBuilderTests.swift`, `ChatLocalizationTests.swift`, `ChatModelsTests.swift`, `ChatSlashCommandParserTests.swift` — existing chat test patterns (XCTest, async/await, no third-party mocking). New tests follow the same shape: `final class ...Tests: XCTestCase`, `@MainActor` where touching `ChatService`.

## Acceptance Criteria
1. `swift build` succeeds with no warnings introduced — `swift build 2>&1 | tee /tmp/zion-build.log && ! grep -E "warning:|error:" /tmp/zion-build.log | grep -v "^$"`
2. Full test suite passes — `swift test 2>&1 | tail -20 | grep -E "Test Suite 'All tests' passed"`
3. New Anthropic SSE parser unit test passes — `swift test --filter AnthropicStreamParserTests`
4. New OpenAI cloud SSE parser test passes — `swift test --filter OpenAIStreamParserTests`
5. ChatStorage roundtrip + cascade + repo isolation tests pass — `swift test --filter ChatStorageTests`
6. ChatService multi-thread tests pass — `swift test --filter ChatServiceMultiThreadTests`
7. Cloud streaming integration tests (URLProtocol mock) pass — `swift test --filter ChatStreamingCloudIntegrationTests`
8. Persistence DB created at expected path after first send — `test -f "$HOME/Library/Application Support/Zion/chats/$(echo -n "$PWD" | shasum -a 256 | cut -c1-16).db"` (manual smoke after `./scripts/make-app.sh` launch)
9. New L10n keys exist in all three locales — `for L in en pt-BR es; do for K in chat.thread.list.title chat.thread.new chat.thread.delete chat.thread.rename chat.thread.untitled chat.thread.confirmDelete chat.thread.lastUpdatedAt chat.thread.empty chat.thread.sidebar.toggle chat.persistence.error; do grep -q "\"$K\"" "Sources/Zion/Resources/$L.lproj/Localizable.strings" || { echo "MISSING $K in $L"; exit 1; }; done; done; echo OK`
10. `.sdd/` is not modified by product code — `git diff --name-only | grep -v "^\\.sdd/" | xargs -I{} test -f {} && ! git diff --name-only HEAD -- .sdd/ | grep -qE "^\\.sdd/(?!archive)"` (manual review: builder commits must not stage anything under `.sdd/` other than archive metadata).
11. `./scripts/make-app.sh` produces a launchable bundle — `./scripts/make-app.sh && test -x dist/Zion.app/Contents/MacOS/Zion`
12. Spec validator passes — `zion-validate-spec .sdd/TECH_SPEC.md` outputs `VALID`.

## Architecture

### Files to create
- `Sources/Zion/Services/AIClient+Anthropic.swift` — actor extension on `AIClient`. Adds `func streamAnthropic(payload: AIRequestPayload, apiKey: String, maxTokens: Int, modelID: String) -> AsyncThrowingStream<String, Error>` and `static func parseAnthropicSSEEvent(eventName: String, data: Data) -> LocalStreamChunk?`. SSE event types handled: `message_start` (no-op), `content_block_start` (no-op), `content_block_delta` → extract `delta.text` when `delta.type == "text_delta"`, `content_block_stop` (no-op), `message_delta` (no-op), `message_stop` → emit `LocalStreamChunk(text: "", done: true)`. Endpoint: `POST https://api.anthropic.com/v1/messages` with headers `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`, body `{"model": modelID, "max_tokens": maxTokens, "stream": true, "messages": [...]}`.
- `Sources/Zion/Services/AIClient+OpenAI.swift` — actor extension on `AIClient`. Adds `func streamOpenAI(payload: AIRequestPayload, apiKey: String, maxTokens: Int, modelID: String) -> AsyncThrowingStream<String, Error>`. Endpoint: `POST https://api.openai.com/v1/chat/completions` with `Authorization: Bearer <apiKey>`, body `{"model": modelID, "max_tokens": maxTokens, "stream": true, "messages": [...]}`. Reuses `AIClient.parseOpenAISSELine` (defined in `AIClient+Local.swift`).
- `Sources/Zion/Services/ChatStorage.swift` — `actor ChatStorage`. Owns one `OpaquePointer?` `sqlite3` connection per repo DB file, lazily opened. Public surface:
  - `init() {}` (no-args; per-repo DBs opened on demand)
  - `func loadThreads(repoID: String) async throws -> [ChatThread]`
  - `func saveThread(_ thread: ChatThread, repoID: String) async throws` (upsert by id)
  - `func loadMessages(threadID: UUID, repoID: String) async throws -> [ChatMessage]`
  - `func appendMessage(_ message: ChatMessage, threadID: UUID, repoID: String) async throws`
  - `func updateMessage(_ message: ChatMessage, repoID: String) async throws` (for streaming-delta content + final flip of `is_streaming` to 0)
  - `func deleteThread(_ id: UUID, repoID: String) async throws`
  - `func renameThread(_ id: UUID, title: String, repoID: String) async throws`
  - private `func connection(for repoID: String) throws -> OpaquePointer` (lazy open, run schema migration with `PRAGMA foreign_keys = ON;` + `CREATE TABLE IF NOT EXISTS` for both tables + `CREATE INDEX IF NOT EXISTS idx_messages_thread_created ON messages(thread_id, created_at)`)
  - Schema:
    ```
    CREATE TABLE IF NOT EXISTS threads (
      id TEXT PRIMARY KEY,
      repo_id TEXT NOT NULL,
      title TEXT NOT NULL,
      created_at REAL NOT NULL,
      updated_at REAL NOT NULL
    );
    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at REAL NOT NULL,
      is_streaming INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_messages_thread_created ON messages(thread_id, created_at);
    ```
  - DB path: `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Zion/chats/<repoID>.db")` with parent dir created via `FileManager.createDirectory(at:withIntermediateDirectories: true)`.
  - On any `sqlite3_open_v2` / `sqlite3_prepare_v2` / `sqlite3_step` failure: throw `ChatStorageError.sqlite(code:Int32, message:String)` and let the caller log + degrade. Never crash, never block.
- `Sources/Zion/Views/Chat/ChatThreadList.swift` — `struct ChatThreadList: View`. Inputs (bindable): `threads: [ChatThread]`, `activeThreadID: UUID`, callbacks `onSelect: (UUID) -> Void`, `onNew: () -> Void`, `onDelete: (UUID) -> Void`, `onRename: (UUID, String) -> Void`. Layout: header row with `+ New thread` button (uses `L10n("chat.thread.new")`) + collapse toggle (`L10n("chat.thread.sidebar.toggle")`), then `ScrollView { LazyVStack { ForEach(threads) { ChatThreadRow(...) } } }`. Empty state shows `L10n("chat.thread.empty")`. Width: 200 pt fixed.
- `Sources/Zion/Views/Chat/ChatThreadRow.swift` — `struct ChatThreadRow: View`. Single row: title `Text` swapping to a `TextField` while in rename mode (local `@State var renaming: Bool`, commit on submit / cancel on Escape), relative date subtitle using `RelativeDateTimeFormatter`, trash button visible only on hover (`@State var isHovered: Bool`). Selected row background = `DesignSystem.Colors.selectionBackground`. Confirm delete with native `Alert` keyed by `L10n("chat.thread.confirmDelete")`. Double-click title → enter rename mode. Context menu offers Rename + Delete.
- `Tests/ZionTests/AnthropicStreamParserTests.swift` — XCTest for `AIClient.parseAnthropicSSEEvent`. Cases: `content_block_delta` with `text_delta` → extract text; non-text delta (e.g. `input_json_delta`) → nil; `message_stop` → `done: true`; malformed JSON → nil (no throw); unknown event name → nil.
- `Tests/ZionTests/OpenAIStreamParserTests.swift` — verify `AIClient.parseOpenAISSELine` handles cloud OpenAI variant: `data: {"choices":[{"delta":{"content":"hi"}}]}` → text "hi"; `data: [DONE]` → `done: true`; payload without `delta.content` → empty text; `finish_reason: "stop"` chunk → `done: true`.
- `Tests/ZionTests/ChatStorageTests.swift` — tmp directory override (inject base URL into `ChatStorage` init for tests, see Builder Notes). Cases: schema creation on first open; insert + load thread roundtrip preserves all fields; insert N messages then `loadMessages` returns them ordered by `created_at`; `deleteThread` cascades and `loadMessages` returns empty; two different `repoID` values produce independent DBs (write to A, read from B returns empty).
- `Tests/ZionTests/ChatServiceMultiThreadTests.swift` — `@MainActor`. Cases: `createThread` appends and sets `activeThreadID` to the new id; `selectThread(id)` swaps active and `thread` (computed) reflects the selected one; `deleteThread(active)` removes it and selects the next-most-recent (or creates a fresh one if none remain); `renameThread` mutates title + persists; init with seeded `ChatStorage` (temp DB) loads previously persisted threads + messages.
- `Tests/ZionTests/ChatStreamingCloudIntegrationTests.swift` — register a `URLProtocol` subclass on a custom `URLSessionConfiguration`, inject via a `URLSession` parameter into the streaming methods (see Builder Notes for the seam). For Anthropic: feed canned SSE bytes (`event: content_block_delta\ndata: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hello"}}\n\nevent: message_stop\ndata: {}\n\n`) and assert the assembled stream concatenates to `"hello"`. For OpenAI: feed `data: {"choices":[{"delta":{"content":"hi"}}]}\n\ndata: [DONE]\n\n` and assert `"hi"`.

### Files to modify
- `Sources/Zion/Models/ChatModels.swift` — add stored properties to `ChatThread`: `var repoID: String` and `var title: String`. Update memberwise init + `Codable`/`Equatable` (auto-synth where possible). Add `static func defaultTitle(date: Date = Date()) -> String` returning `String(format: L10n("chat.thread.untitled"), DateFormatter.chatThreadShort.string(from: date))`. Add a small `DateFormatter.chatThreadShort` (cached static) producing `YYYY-MM-dd HH:mm`. **Keep** the `ChatModels.swift` multi-struct file exception — do not split.
- `Sources/Zion/Services/ChatService.swift` — Phase 2 changes:
  - Replace single `var thread: ChatThread` with `var threads: [ChatThread] = []` and `var activeThreadID: UUID = UUID()`. Add computed `var thread: ChatThread { get { threads.first { $0.id == activeThreadID } ?? <fallback new> } set { ... } }` so existing call sites compile.
  - Inject `let storage: ChatStorage` and `let repoID: String` in init.
  - `init` kicks off `Task { @MainActor in await reloadFromStorage() }` (non-blocking). If `loadThreads` throws → log + create one in-memory thread + set a non-fatal `lastPersistenceError` string surfaced via existing `errorMessage` channel + L10n key `chat.persistence.error`.
  - Add `func createThread()`, `func deleteThread(_ id: UUID)`, `func renameThread(_ id: UUID, to title: String)`, `func selectThread(_ id: UUID)`. Each mutates `threads` then `Task { try? await storage.<op> }` (fire-and-forget; failure → log only).
  - In `send(...)`: after appending the user message, if the active thread title still equals a `defaultTitle(...)` value, derive new title from first 60 chars of the user message (rstrip + ellipsize) and call `renameThread`.
  - Provider dispatch: switch on `aiSettings.provider`:
    - `.local` → existing `streamLocalLLM` path
    - `.openai` → new `streamOpenAI` path
    - `.anthropic` → new `streamAnthropic` path
    - `.gemini`, `.none` → existing non-streaming `aiClient.call(...)` path (unchanged)
  - Streaming consumer loop: on every delta, append text to the in-progress assistant message in `threads[activeIndex].messages` (last). Throttle persistence via a debounced `Task` keyed by message id — flush via `storage.updateMessage(...)` at most once per `Constants.Timing.chatPersistenceDebounce` (500 ms) AND once final on stream completion (with `is_streaming = 0`).
- `Sources/Zion/Services/AIClient.swift` — no signature changes to `call(...)`. Only addition: if `streamLocalLLM` currently lives as an extension method and the new streamers need a shared `URLSession` injection point for tests, add an internal `var urlSessionForStreaming: URLSession = .shared` stored on the actor (default `.shared`) consumed by all three streamers. Test bundle can replace it via a new internal `func _setStreamingSession(_ session: URLSession)` (test-only, `internal`).
- `Sources/Zion/Views/Chat/ChatScreen.swift` — wrap the existing chat column in an `HStack` (or `HSplitView`) with `ChatThreadList` on the left (200 pt), main chat content on the right. Visibility of the sidebar is bound to `@AppStorage("chat.threadListVisible") private var threadListVisible: Bool = true`. A toolbar/header toggle button calls back to set this. Pass `chatService.threads`, `chatService.activeThreadID`, and the four callbacks (`onSelect`, `onNew`, `onDelete`, `onRename`) into `ChatThreadList`. Do not change the existing composer / message list internals — only the outer container.
- `Sources/Zion/ViewModel/RepositoryViewModel+Chat.swift` — when lazily constructing `ChatService`, also compute `let repoID = ChatStorage.repoID(for: repositoryURL)` (new static helper on `ChatStorage` doing SHA256 + first 16 hex chars) and pass an app-level shared `ChatStorage()` (store as `@ObservationIgnored private(set) var chatStorage = ChatStorage()` on the view model). Pass both into `ChatService.init`.
- `Sources/Zion/Helpers/Constants.swift` — add `static let chatPersistenceDebounce: TimeInterval = 0.5` under `Constants.Timing`.
- `Sources/Zion/Resources/en.lproj/Localizable.strings` — append the 10 new keys listed under L10n KEYS.
- `Sources/Zion/Resources/pt-BR.lproj/Localizable.strings` — same 10 keys with pt-BR copy.
- `Sources/Zion/Resources/es.lproj/Localizable.strings` — same 10 keys with es copy.

### Dependencies between files
- `ChatService` depends on `ChatStorage`, `AIClient`, `ChatContextBuilder`, `ChatModels`, `Constants`.
- `ChatStorage` depends on `ChatModels` and the system `SQLite3` library (`import SQLite3`).
- `AIClient+Anthropic` and `AIClient+OpenAI` depend on `AIClient` (extend the actor), `AIClient+Local` (reuse `LocalStreamChunk` + `parseOpenAISSELine`).
- `ChatScreen` depends on `ChatThreadList`, existing `ChatComposer`, `ChatMessageBubble`, `ChatEmptyState`, `ChatService`.
- `ChatThreadList` depends on `ChatThreadRow`, `ChatModels`, `DesignSystem`.
- `ChatThreadRow` depends on `ChatModels`, `DesignSystem`.
- `RepositoryViewModel+Chat` depends on `ChatService`, `ChatStorage`.
- All test files depend on the production files they exercise + XCTest only.

## Edge Cases
1. **SQLite open fails** (disk full, sandbox denial, permission error) — `ChatStorage` throws, `ChatService` logs via `DiagnosticLogger`, sets `errorMessage = L10n("chat.persistence.error")` once, and continues in volatile-memory mode for the session. Subsequent sends do not retry persistence within the session.
2. **Schema migration on existing DB** — schema uses `CREATE TABLE IF NOT EXISTS` + `CREATE INDEX IF NOT EXISTS`; no destructive ALTERs in Phase 2. If a future migration is needed, gate on `user_version` PRAGMA (out of scope here, but do not block its introduction).
3. **Streaming connection drops mid-message** — the `AsyncThrowingStream` rethrows; the consumer in `ChatService.send` catches, flips `is_streaming = 0`, persists whatever partial content arrived, surfaces `errorMessage` via existing `chat.error.send.title`. Partial message remains in the thread (not deleted).
4. **Anthropic / OpenAI auth missing or invalid** — provider returns 401/403. The streaming method throws on the first non-2xx response; `ChatService` surfaces via the same path as Phase 1 errors. No retry.
5. **User deletes the active thread** — `deleteThread(active)` removes it, selects the next thread by `updated_at` desc, and if none remain calls `createThread()` to ensure UI always has a target. Streaming task on the deleted thread is cancelled.
6. **Rename to empty string** — trim whitespace; if result is empty, revert to the previous title (no-op).
7. **Two repos with colliding 16-hex SHA prefix** — astronomically unlikely (~2^64). Document acceptance; do not engineer collision handling.
8. **Repo opened with `silent: true` (mobile bootstrap)** — `ChatService` is lazy; persistence only initializes on first `send` or first thread-list view. Mobile silent boot does not touch chat DBs.
9. **Streaming debounce vs stream end** — the final `done: true` event MUST trigger an immediate (non-debounced) `updateMessage` with `is_streaming = 0`. The debounced task must be cancelled on stream completion so it cannot overwrite the final state.
10. **NSColor / SwiftUI compositing** — `ChatThreadRow` is pure SwiftUI (no NSTextView), so the NSTextView color rules in `known-bugs.md` do not apply. Continue to use `DesignSystem.Colors.*` swiftui tokens only.
11. **Active thread state after restart** — on `reloadFromStorage`, if any thread exists, select the one with the most recent `updated_at`. If none, `createThread()`.
12. **Large message bodies** — SQLite TEXT has no practical size limit for Phase 2 sizes (< 1 MB typical). No chunking required.

## Out of Scope
- Tool calling / function calling (Phase 3).
- `@file` mentions autocomplete (Phase 3).
- Click-to-open file paths from assistant messages (Phase 3).
- Apply-suggestion / one-click code-action buttons (Phase 3).
- System-prompt customization UI (Phase 3).
- Cross-thread history search (Phase 3).
- Export thread as Markdown / JSON (Phase 3).
- Token usage / cost display (Phase 3).
- Gemini streaming (Phase 3).
- DB migrations beyond first-create schema (no `user_version` bumps in Phase 2).
- Sharing chat DBs across repos, cloud sync, encryption-at-rest.
- Changing `AIClient.call()` dispatch, the existing local-streaming path, slash-command parser, or the Phase 1 `ChatScreen` composer/message bubble internals.
- Modifying `.sdd/` from product code at any time.

## Builder Notes
- **Repo-id helper**: implement `static func ChatStorage.repoID(for url: URL) -> String` as `SHA256(url.path).hexEncodedString().prefix(16)`. Use `CryptoKit.SHA256` (already available via Foundation on macOS 14). No new deps.
- **DB path override for tests**: `ChatStorage.init(baseDirectory: URL? = nil)` — when `nil`, resolve `~/Library/Application Support/Zion/chats/`. Tests pass a `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)` to keep the user DB untouched.
- **URLSession seam for cloud streaming tests**: add internal `func _setStreamingSession(_ session: URLSession)` on `AIClient` (test-only, marked `internal`, no `@testable` tricks needed because `Zion` target is already `@testable import Zion` per existing tests — confirm in `Package.swift`). Tests register a `URLProtocol` subclass with canned SSE bytes and inject the session before invoking `streamAnthropic` / `streamOpenAI`.
- **Streaming consumer pattern**: mirror lines ~170–200 of `AIClient+Local.swift` (`URLSession.bytes(for:)` + `for try await line in bytes.lines` + per-line parse + yield `delta.text`). For Anthropic SSE specifically, accumulate `event: <name>` and the next `data: <json>` line into a pair, parse via `parseAnthropicSSEEvent(eventName:data:)`, and yield the resulting `LocalStreamChunk.text` (skip empty text). On `done: true`, finish the stream.
- **Persistence debounce**: store a `[UUID: Task<Void, Never>]` map keyed by message id on `ChatService`. On each delta, cancel any pending task for that id and schedule a new `Task.sleep(nanoseconds: 500_000_000)` then `await storage.updateMessage(...)`. On stream completion, cancel any pending and call `updateMessage` immediately with `is_streaming = 0`.
- **Title derivation**: `let trimmed = userMessage.content.trimmingCharacters(in: .whitespacesAndNewlines); let cut = trimmed.prefix(60); let title = cut.count < trimmed.count ? "\(cut)…" : String(cut)`.
- **Sidebar visibility persistence**: use `@AppStorage("chat.threadListVisible")` directly in `ChatScreen` (this is a View, not an `@Observable` class, so the @AppStorage rule from `known-bugs.md` does not apply).
- **Localization**: every new visible string goes through `L10n("dot.notation.key")`. Add all 10 keys to **all three** locale files in the SAME commit; verify with the AC #9 shell loop before declaring done.
- **DesignSystem tokens**: thread row selected background = `DesignSystem.Colors.selectionBackground`; hover = `DesignSystem.Colors.hoverBackground`; row corner radius = `DesignSystem.Spacing.smallCornerRadius` (or the project's nearest equivalent — verify via grep before picking); typography = `DesignSystem.Typography.body` for title, `DesignSystem.Typography.caption` for relative date. **Grep first**, do not invent token names.
- **Branch + commit hygiene**: `git fetch origin && git checkout -b feature/chat-phase2 origin/master`. Split commits by wave; never bundle persistence + views + cloud streaming into one commit. Use `feat(chat): ...` scope per project convention.
- **Build verification**: after each wave run `swift build` (use `dangerouslyDisableSandbox: true` in the bash tool) + `swift test --filter <newSuite>`. After final wave run `./scripts/make-app.sh` and confirm `dist/Zion.app/Contents/MacOS/Zion` is launchable.
- **Do NOT** modify `.sdd/` from product code or commits — that folder is the SDD planner's own scratch space and the user has a memory rule excluding it from product diffs.
- **Sparkle / release / dist**: no version bump in this spec. Release notes / version bumps are a separate workflow (`docs/RELEASE.md`).
- **Test bundle**: tests live under `Tests/ZionTests/`. Confirm `Package.swift` already grants `@testable import Zion` (it does for existing Chat tests). Reuse that.
- **Known bug awareness**: this feature does not touch SwiftTerm, NSTextView, or alt-buffer terminals — the `known-bugs.md` SwiftTerm sections are not in play. Do not "improve" unrelated terminal code while in chat files.
- **Plan budget**: builder should produce ≤11 tasks across 5 waves: (W1) ChatModels + ChatStorage + L10n + Constants; (W2) AIClient+Anthropic + AIClient+OpenAI + parser tests; (W3) ChatService multi-thread + persistence wiring + ChatService tests; (W4) ChatThreadList + ChatThreadRow + ChatScreen rewire + RepositoryViewModel+Chat; (W5) cloud streaming integration tests + `make-app.sh` smoke.
