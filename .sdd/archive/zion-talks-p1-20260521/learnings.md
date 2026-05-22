# Build Learnings — Zion Talks (Phase 1)

## Critical
- **NEVER commit .sdd/ files** — user dev folder excluded from repo. Stage only source/test files explicitly.
- swift build needs `dangerouslyDisableSandbox: true` for module cache.

### Task 2: AILimits + AppEnums additions (DONE, 1 cycle)
- Adding a case to `FeatureSection` breaks exhaustive switches in HelpSheet.swift, ZionMapContent.swift, and RepositoryViewModel+Git.swift.
- Adding a case to `AppSection` breaks the switch in RepositoryViewModel+Git.swift (`loadDeferredDataForSection`).
- A linter (likely SwiftFormat or similar) automatically added `.chat: return []` and `.chat: break` to ZionMapContent.swift and RepositoryViewModel+Git.swift before the build completed — verify these files are already updated before manually editing.
- For `FeatureSection.titleKey`, the switch returns a string key via `L10n(...)` directly (not just a key), matching the pattern of other cases that call `L10n(...)` in some places but return raw strings in others. Task spec said `L10n("chat.title")` for titleKey — used that directly.
- `HelpSheet.swift` featureKeys switch needed a manual `.chat: return []` arm added.

### Task 3: L10n keys + ChatLocalizationTests (DONE, 1 cycle)
- Append new locale keys at end of each .strings file (after last existing key).
- `FeatureSection.chat` already handled in `ZionMapContent.swift` and `AppSection.chat` in `RepositoryViewModel+Git.swift` — both added by task #2.
- Build errors shown during first `swift test` run were stale cache; `swift build` alone confirmed clean build.
- Test pattern mirrors `LocalLLMLocalizationTests.swift` exactly: `Bundle.zionResources`, `NSDictionary(contentsOfFile:)`, loop locales then keys.
- Added bonus test `testContextHeaderContainsPositionalTokens` to verify 3x %@ + 1x %d in all locales.

### Task 4: ChatContextBuilder + slash parser + tests (DONE, 2 cycles)
- `RepositoryWorker.runAction(args:in:)` is sync (throws), not async — lives in `RepositoryWorker+Execution.swift`.
- `git diff` only shows changes to tracked files; untracked new files do NOT appear. Test for `/diff` must modify an existing tracked file (e.g., overwrite README.md), not create a new file.
- Line-anchored regex `^\s*/(diff|log|status|file|commit)(\s+(.+))?\s*$` correctly rejects inline slashes in URLs.
- Safe path resolution for `/file`: use `.standardizedFileURL` and check `resolvedURL.path.hasPrefix(repoStandardized.path + "/")`.
- `AILimits` enum is internal — accessible from test target via `@testable import Zion`.
- `GitTestHelper.makeTempRepo()` creates a repo with one commit ("Initial commit") on whatever branch git defaults to (main or master).

### Task 8: ChatEmptyState view (DONE, 1 cycle)
- `DesignSystem.Spacing` has `sectionGap` (20), `standard` (8), `cardPadding` (12), `mediumCornerRadius` (10).
- `DesignSystem.Typography` has `sectionTitle` (13 bold) for headline; `bodyMedium` (11 medium) for card labels.
- `DesignSystem.Colors.glassBackground` + `glassBorder` for card tiles; `textPrimary`/`textSecondary` for text.
- Use `ClipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius))` — never `cornerRadius:` literal.
- Grep check `cornerRadius:\s*[0-9]` catches hardcoded radius — ensure all use token references.
- `ForEach(examples, id: \.self)` works cleanly since example strings are unique.

### Task 5: ChatService + tests (DONE, 1 cycle)
- `@MainActor @Observable` class works cleanly — `@ObservationIgnored` required for `Task`, `AIClient`, `RepositoryWorker`, `ChatContextBuilder`, and `streamProvider` closure.
- Test init injects `streamProvider: (LocalLLMConfig, AIPromptPayload, Int, String) -> AsyncThrowingStream<String, Error>` — avoids any real network call.
- `send()` calls `await task.value` at the end so the test `await service.send(...)` call blocks until streaming finishes — no extra sleeps needed in happy-path tests.
- `stop()` test: fire-and-forget `send()` via a separate `Task`, `sleep(50ms)`, call `stop()`, finish the held continuation, `await sendTask.value`. Pattern works reliably.
- `AIClient.streamLocalLLM` is an actor method — calling from `@MainActor` context needs `await ai.streamLocalLLM(...)`.
- `AIClient.makePromptPayload` is a static method — call as `AIClient.makePromptPayload(task:taskInstructions:untrustedSections:)`.
- Git context header injected only on first user message (filter by `.user` role). Slash commands expanded on every message.

### Task 6: ChatMessageBubble view (DONE, 1 cycle)
- `DesignSystem.Colors` has no `surface*` tokens — use `glassElevated` (white 0.06) for assistant bubble background.
- `DesignSystem.Opacity` tokens (muted: 0.5, dim: 0.3) are the right lever for tinted bubble backgrounds instead of inline `.opacity(...)`.
- `AttributedString(markdown:)` initializer throws — must wrap in `try?` with plain Text fallback.
- `.inlineOnlyPreservingWhitespace` interpreted syntax avoids block-level markdown breaking the bubble layout.
- Streaming dot uses `DesignSystem.Motion.glowPulse` animation (easeInOut 1.5s, repeatForever) — no custom duration literals needed.
- `mkdir -p Sources/Zion/Views/Chat` required before writing the file.

### Task 9: ChatScreen view (DONE, 1 cycle)
- `AIClient.loadAPIKey(for: provider)` returns `String?` — use `?? ""` at call site.
- `onChange(of:)` two-arg form (Swift 5.9+) used without closure arg — value captured implicitly.
- Empty repoURL: show only `ChatEmptyState` (no composer rendered). Composer area guarded by `if repoURL != nil`.
- `ChatEmptyState.onPickPrompt` sets `composerText` — user can then send manually; do not auto-send.
- Scroll-to-last fires on both `.count` change AND `.last?.content` change to follow streaming tokens.
- `composerText` captured before clearing so `Task { await send(...) }` uses original value.

### Task 7: ChatComposer view (DONE, 1 cycle)
- `UserDefaultsKeys.AI.provider` = `"zion.aiProvider"` — the task spec's `"ai.defaultProvider"` refers to this key.
- `@AppStorage` on a raw String + computed `Binding<AIProvider>` is the correct pattern (avoids @AppStorage in @Observable pitfall; ChatComposer is a View).
- `AIProviderSupport.configurableProviders` is the filtered list to use for the Menu (excludes `.none`).
- Glass input style: `.fill(DesignSystem.Colors.glassHover)` + `.stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)` with `elementCornerRadius`.
- `TextField(..., axis: .vertical)` + `.lineLimit(1...5)` for multiline growth without TextEditor.
- `.keyboardShortcut(.return, modifiers: .command)` on the send Button delivers Cmd+Return shortcut cleanly.

### Task 10: RepositoryViewModel+Chat (DONE, 2 cycles)
- `private` stored properties on `@Observable` classes are inaccessible from extension files in OTHER Swift files — use internal (no modifier) instead. `fileprivate` would also fail across files.
- Hook point for repo-switch reset: `cancelRepositoryBackgroundActivityForSwitch()` in RepositoryViewModel+SnapshotHelpers.swift — called at the top of `openRepository` before URL is reassigned.
- `worker` and `aiClient` are `let` properties on `RepositoryViewModel` — shared singleton worker, not per-repo instance. ChatService init receives the shared worker directly.
- `ChatContextBuilder` init takes `worker: RepositoryWorker` as only argument (memberwise).

### Task 11: Sidebar + ContentView wiring + dist build (DONE, 1 cycle)
- SidebarView uses `ForEach(AppSection.allCases)` — `.chat` renders automatically, no switch arm needed.
- ContentView `workspaceHost` ZStack: add ChatScreen inside the `if model.hasGitWorkspace` block after OperationsScreen, following the same `.frame/.opacity/.allowsHitTesting` pattern.
- `model.currentBranch` is non-optional `String` — the `?? ""` guard in the task spec is safe but redundant (only a warning).
- `LocalStreamingIntegrationTests.testServerNotFoundError` fails pre-existing (requires live local LLM server) — not a regression from these changes.
- Never use `git stash` to verify pre-existing failures — it removes your current changes and requires a manual `git stash pop` to recover.
