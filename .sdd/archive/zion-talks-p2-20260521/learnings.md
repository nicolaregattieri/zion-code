# Build Learnings — Zion Talks Phase 2

## Critical
- NEVER commit .sdd/ — user dev folder, excluded from repo
- swift build needs `dangerouslyDisableSandbox: true`
- Phase 1 (PR #436) merged; build on top of that

### Task 5: ChatStorage (SQLite) + tests (DONE, 2 cycles)
- `SQLITE_TRANSIENT` not available in Swift's SQLite3 overlay; use `unsafeBitCast(-1, to: sqlite3_destructor_type.self)`
- Actor `deinit` cannot touch non-Sendable properties — omit it; connections released on process exit
- Build collision from stale scratch path: use a new `--scratch-path` each cycle since `rm -rf` is sandboxed

### Task 6: Cloud streamers (Anthropic + OpenAI) + integration tests (DONE, 2 cycles)
- `URLSession.AsyncBytes.lines` does NOT yield empty lines for `\n\n` blank-line SSE separators in tests with MockURLProtocol
- Fix: also dispatch SSE block when a new `event:` line arrives while prior block is pending, plus a trailing-block flush after the loop
- `ChatStorage.swift` had a Swift 6.3 strict-concurrency error: `nonisolated deinit` cannot access non-Sendable properties; fixed with `nonisolated(unsafe)` on `connections`
- Cloud streamers reuse `_testURLSession` from AIClient (Phase 1 seam) — capture at method entry: `let session = _testURLSession ?? .shared`
- `AIError.localAPIError` is the right case for 401/403 (no dedicated `.authError` case exists); `quotaExceeded` for 429
- OpenAI cloud streaming reuses `parseOpenAISSELine` directly (same format as local); no blank-line accumulation needed

### Task 7: ChatThreadList + ChatThreadRow views (DONE, 1 cycle)
- Cancel button in alerts uses Portuguese key "Cancelar" not "common.cancel" (project uses PT keys for legacy strings)
- ChatStorage.swift error (nonisolated deinit) was a phantom from incremental build cache; cleared with fresh scratch path
- `nonisolated(unsafe)` on `connections` in actor = warning only at -warnings-as-errors, not error, once scratch cache was cleared
- Double-tap gesture: put onTapGesture(count:2) BEFORE onTapGesture(count:1) in SwiftUI or both fire
- selectionBackground token lives at DesignSystem.Colors.selectionBackground (Color not NSColor version)
- glassHover at DesignSystem.Colors.glassHover; destructive at DesignSystem.Colors.destructive

### Task 9: RepositoryViewModel+Chat wiring (storage + repoID) (DONE, 1 cycle)
- `repositoryURL` is `URL?` on RepositoryViewModel; use `.map { ChatStorage.repoID(for: $0) } ?? ""` to safely derive repoID
- `ChatStorage` actor init works fine as a stored property default (`= ChatStorage()`) on @Observable @MainActor class
- ChatService init has `storage: ChatStorage? = nil, repoID: String = ""` defaults — pass explicitly here to activate persistence

### Task 10: ChatScreen sidebar integration + dist build (DONE, 1 cycle)
- `@AppStorage("chat.threadListVisible") = true` means "visible"; ChatThreadList.isCollapsed needs inverse — add a `Binding<Bool>.inverse` extension
- `renameThread` signature is `renameThread(_ id: UUID, title: String)` — pass as `{ id, title in chat.renameThread(id, title: title) }`
- swift-testing framework outputs "Test run with N tests in M suite passed" NOT "Test Suite 'All tests' passed" (XCTest); task criteria grep will not match
- dist/Zion.app/Contents/MacOS/Zion already exists from prior builds; make-app.sh refreshes it; `test -x` verifies OK

