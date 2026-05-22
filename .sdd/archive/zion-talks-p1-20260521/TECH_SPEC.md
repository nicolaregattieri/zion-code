# Tech Spec: Zion Talks (Phase 1)

## Goal
Add a repo-aware AI chat surface ("Zion Talks") inside the Zion macOS Git client. Phase 1 ships an in-memory chat thread per repository with streaming responses, git context auto-injection, and slash commands that expand to real git output before the message is sent to the AI provider.

## Constraints
- Language: Swift 5.10+ (Xcode toolchain shipped with Zion).
- Framework: SwiftUI + AppKit, native macOS only.
- Test runner: XCTest via `swift test` against the `ZionTests` target.
- Build verification: `swift build` (requires `dangerouslyDisableSandbox: true`) and `./scripts/make-app.sh`.
- Existing deps used: `AIClient` actor, `RepositoryWorker` actor, `AIPromptPayload`, `AIProvider`, `AIMode`, `AILimits`, `DesignSystem`, `L10n`, `Constants`. No new third-party deps.
- Boundaries (CAN touch): `Sources/Zion/Models/`, `Sources/Zion/Services/`, `Sources/Zion/ViewModel/`, `Sources/Zion/Views/Chat/`, `Sources/Zion/Views/Main/SidebarView.swift`, `Sources/Zion/Views/Main/ContentView.swift`, `Sources/Zion/Models/AppEnums.swift`, the three `Localizable.strings` files, `Tests/ZionTests/`.
- Boundaries (must NOT touch): `.sdd/`, any unrelated AIClient code paths, `SwiftTerm` fork, persistence layers, RemoteAccess/Mobile code, all existing FeatureSection consumers other than the navigation wiring.
- Chat must NOT modify any file in the user's working repository. Read-only git commands only (`status`, `log`, `show`, `diff`, `rev-parse`, file reads via `FileManager`).

## Reuse
The builder MUST use these existing pieces and MUST NOT reinvent them. All confirmed via Grep.

- `Sources/Zion/Services/AIClient.swift` — `actor AIClient`. Holds `AILimits` (lines 4-34), `AIPromptPayload` (line 44), `Self.makePromptPayload(...)` (Helpers line 176), `Self.renderUserMessage(from:)` (Helpers line 208). Use these instead of building prompts by hand.
- `Sources/Zion/Services/AIClient+Local.swift` — `func streamLocalLLM(payload:apiKey:maxTokens:modelID:) -> AsyncThrowingStream<String, Error>` (line 119). Use this for `.local` provider streaming.
- `Sources/Zion/Services/AIClient+Helpers.swift` — `func call(payload:provider:apiKey:maxTokens:lane:mode:)` (line 9). Use as the non-streaming fallback for `.openai`, `.gemini`, `.anthropic` in Phase 1 (no Anthropic SSE exists yet — see Edge Cases).
- `Sources/Zion/Services/RepositoryWorker.swift` + `RepositoryWorker+Execution.swift` — `actor RepositoryWorker` with `func runAction(args:in:mode:) throws -> String` (line 35) and `func runActionAllowingFailure(args:in:mode:)` (line 44). Use to execute every git command needed for context and slash-command expansion. NOTE: the actor type is `RepositoryWorker`, not `Worker` (the user request calls it "Worker"). Pass the existing per-repo worker through from `RepositoryViewModel`.
- `Sources/Zion/Models/AppEnums.swift` — `enum AIProvider` (line 220, cases: `.none, .anthropic, .openai, .gemini, .local`), `enum AIMode` at `Models/AIModels.swift` (line 3, cases: `.efficient, .smart, .bestQuality`), `enum FeatureSection` (line 247, full case list), `enum AppSection` (line 343, cases: `.code, .graph, .operations`). Read these before adding any case.
- `Sources/Zion/ViewModel/RepositoryViewModel.swift` — `@Observable @MainActor final class RepositoryViewModel` (line 9). Add chat via a `RepositoryViewModel+Chat.swift` extension following the existing `RepositoryViewModel+AI.swift` pattern.
- `Sources/Zion/DesignSystem/` — `DesignSystem.Colors.*`, `DesignSystem.Spacing.*`, `DesignSystem.Typography.*`, `DesignSystem.Motion.*`. Use exclusively for color/spacing/typography/timing tokens. No hardcoded `Color.*`, `Font.*`, `.padding(N)` literals in logic, or `cornerRadius:` values.
- `Sources/Zion/Helpers/Constants.swift` — `Constants.Timing.*`, `Constants.Limits.*`. Use for any non-AI timing/limit constant (debounce, max retries, etc.).
- `AILimits.maxDiffContentLength` (10_000) — use for `/diff` and `/commit` truncation. `AILimits.maxRepoContextLength` (1600) — use for the git context header budget. `AILimits.maxCommitLogLength` (3000) — use for `/log` truncation. For `/file` truncation a new constant `AILimits.maxFileContentPreviewLength = 8_000` MUST be added inside the existing `AILimits` enum (it does not exist yet — confirmed by Grep).
- `Sources/Zion/Views/Main/SidebarView.swift` — `@Binding var selectedSection: AppSection`, the `workspaceButton(for:)` helper (line 202) and the `ForEach(AppSection.allCases)` loop (line 194). Follow this exact pattern when adding the chat entry.
- `Sources/Zion/Views/Main/ContentView.swift` — the `selectedSection == .code / .graph / .operations` opacity/hitTesting overlay pattern (lines 564-593). Follow this pattern when wiring `ChatScreen`.
- `Sources/Zion/Resources/{en,pt-BR,es}.lproj/Localizable.strings` — append new keys to all three. Existing chat-related keys: none (confirmed by Grep `chat.`). Follow dot-notation per the localization rule (e.g. `chat.title`).
- `Sources/Zion/ViewModel/RepositoryViewModel+AI.swift` and sibling `+AI*.swift` files — pattern for AI-adjacent extensions; copy the file/class layout.
- `Tests/ZionTests/AIClientLocalDispatchTests.swift` — pattern for testing AIClient surfaces; mirror its test scaffolding style.

## Acceptance Criteria
1. Chat models compile cleanly with the existing target — `swift build` returns 0. — `swift build 2>&1 | tail -5` (expect "Build complete!", no errors)
2. App bundle builds with no warnings introduced by chat code. — `./scripts/make-app.sh 2>&1 | grep -E '(error:|warning:)' | grep -i chat | wc -l` (expect `0`)
3. `ChatModelsTests` passes: round-trip Identifiable/Equatable contract. — `swift test --filter ChatModelsTests 2>&1 | tail -3` (expect "Test Suite 'ChatModelsTests' passed")
4. `ChatSlashCommandParserTests` passes all 7 cases (diff, log, status, file+path, commit+sha, unknown rejected, missing-args rejected). — `swift test --filter ChatSlashCommandParserTests 2>&1 | tail -3`
5. `ChatContextBuilderTests` passes all 7 cases (header formatting, 5 expand-* commands, inline-slash ignored). — `swift test --filter ChatContextBuilderTests 2>&1 | tail -3`
6. `ChatServiceTests` passes all 4 cases (send appends both messages, stop cancels, newThread clears, streaming delta updates last message). — `swift test --filter ChatServiceTests 2>&1 | tail -3`
7. `ChatLocalizationTests` passes — every chat L10n key listed in section "L10n Keys" below is present in all three locale files. — `swift test --filter ChatLocalizationTests 2>&1 | tail -3`
8. New `AILimits.maxFileContentPreviewLength` constant is defined exactly once. — `grep -n "maxFileContentPreviewLength" Sources/Zion/Services/AIClient.swift | wc -l` (expect `1`)
9. `AppSection.chat` exists and is reachable from the sidebar. — `grep -n "case chat" Sources/Zion/Models/AppEnums.swift | wc -l` (expect at least `1`)
10. `FeatureSection.chat` (or `.zionTalks`) exists with icon `bubble.left.and.bubble.right` and `DesignSystem.Colors.brandPrimary` color. — `grep -n 'bubble.left.and.bubble.right' Sources/Zion/Models/AppEnums.swift` (expect 1 hit)
11. `ChatScreen.swift` exists at the spec path. — `test -f Sources/Zion/Views/Chat/ChatScreen.swift && echo OK`
12. No hardcoded color/font/spacing/corner-radius literals in chat views. — `grep -nE '(Color\.[a-z]+\.opacity|Font\.[a-z]+|cornerRadius:\s*[0-9])' Sources/Zion/Views/Chat/*.swift | wc -l` (expect `0`)
13. No user-facing string literal outside `L10n("…")` in chat views/services. — `grep -nE '"[A-Z][a-zA-Z ]{4,}"' Sources/Zion/Views/Chat/*.swift Sources/Zion/Services/ChatService.swift Sources/Zion/Services/ChatContextBuilder.swift | grep -v 'L10n("' | grep -v -E '^\s*//' | wc -l` (expect `0`)
14. Chat writes no files inside the user's repo. — `grep -nE '\.write|FileManager\.default\.create|removeItem' Sources/Zion/Services/ChatService.swift Sources/Zion/Services/ChatContextBuilder.swift Sources/Zion/Views/Chat/*.swift | wc -l` (expect `0`)
15. Spec validator passes. — `/Users/nicolaregattieri/.claude/plugins/cache/zion/zion-core/0.1.0/bin/zion-validate-spec .sdd/TECH_SPEC.md` (expect `VALID`)

## Architecture

### Files to create
- `Sources/Zion/Models/ChatModels.swift` — `enum ChatRole { case user, assistant }`, `struct ChatMessage: Identifiable, Equatable { let id: UUID; let role: ChatRole; var content: String; let timestamp: Date; var isStreaming: Bool }`, `struct ChatThread: Identifiable, Equatable { let id: UUID; var messages: [ChatMessage]; let createdAt: Date }`. One enum + two structs per file is acceptable here because they form a single domain group (follows `GitModels.swift` precedent).
- `Sources/Zion/Services/ChatService.swift` — `@MainActor @Observable final class ChatService`. Stores `var thread: ChatThread`, `var isStreaming: Bool`, `@ObservationIgnored private var activeTask: Task<Void, Never>?`, `@ObservationIgnored private let ai: AIClient`, `@ObservationIgnored private let worker: RepositoryWorker`. Methods: `func send(text:provider:apiKey:mode:contextBuilder:repoURL:branch:) async`, `func newThread()`, `func stop()`. Uses `AIClient.makePromptPayload` + `AIClient.renderUserMessage` to build the prompt; dispatches through `AIClient.streamLocalLLM` for `.local`, otherwise through `AIClient.call(...)` (non-streaming v1 fallback). Streaming appends a pending assistant `ChatMessage(isStreaming: true)` and updates its `content` per delta on the main actor.
- `Sources/Zion/Services/ChatContextBuilder.swift` — `struct ChatContextBuilder` with `let worker: RepositoryWorker`. Async methods: `func gitContextHeader(repoURL: URL, branch: String) async -> String` (formats `chat.contextHeader` localized template with repo name, branch, 7-char SHA, uncommitted count), `func expandSlashCommands(_ text: String, repoURL: URL) async -> String` (scans lines, replaces lines beginning with `/cmd[ args]` with an appended fenced block of the command output, truncated). Adds nested `enum SlashCommand: Equatable { case diff; case log; case status; case file(path: String); case commit(sha: String) }` and `static func parseSlashCommand(_ line: String) -> SlashCommand?` (pure, used by tests). Truncation uses existing `AILimits.maxDiffContentLength`, `AILimits.maxCommitLogLength`, and the new `AILimits.maxFileContentPreviewLength`.
- `Sources/Zion/ViewModel/RepositoryViewModel+Chat.swift` — extension on `RepositoryViewModel` exposing `var chatService: ChatService` (computed via a stored `@ObservationIgnored private var _chatService: ChatService?` created lazily once `repositoryURL` and the per-repo `worker` are available). Resets when `openRepository` switches to a new URL (hook via existing repo-switch path, do NOT call save-recents).
- `Sources/Zion/Views/Chat/ChatScreen.swift` — top-level SwiftUI `View`. Owns `@Bindable var chat: ChatService`, reads provider/apiKey/mode via existing `@AppStorage("ai.defaultProvider")` + the same access pattern already used by `RepositoryViewModel+AI.swift`. Renders `ChatEmptyState` when `thread.messages.isEmpty`, otherwise a `ScrollView` of `ChatMessageBubble` rows, followed by the `ChatComposer` pinned at the bottom.
- `Sources/Zion/Views/Chat/ChatMessageBubble.swift` — single `struct ChatMessageBubble: View`. User messages: right-aligned, brand-tinted background. Assistant messages: left-aligned, surface-tinted, renders markdown via `AttributedString(markdown:)` with a fenced-code-block fallback that uses `DesignSystem.Typography.codeMono`. Auto-scrolls owner via id.
- `Sources/Zion/Views/Chat/ChatComposer.swift` — `struct ChatComposer: View`. Holds the composer text via `@State`. Send button + `Cmd+Return` keyboard shortcut, stop button toggled by `chat.isStreaming`, new-chat (trash) button, provider mini-picker (read-only label + menu pulling from `AIProvider.allCases` filtered by `AIProviderSupport.isConfigured`). Hint text via `L10n("chat.composer.hint")`.
- `Sources/Zion/Views/Chat/ChatEmptyState.swift` — `struct ChatEmptyState: View`. Headline `L10n("chat.emptyState.headline")` + 3-4 tappable example cards (`chat.emptyState.example.history`, `.branch`, `.diff`). Tapping a card calls a closure that fills the composer text.
- `Tests/ZionTests/ChatModelsTests.swift` — round-trip equality, id uniqueness.
- `Tests/ZionTests/ChatSlashCommandParserTests.swift` — 7 cases listed in AC4.
- `Tests/ZionTests/ChatContextBuilderTests.swift` — 7 cases listed in AC5. Use a stub `RepositoryWorker` initializer (mirror `GitTestHelper.swift` pattern) backed by a temp git repo seeded with canned commits so `runAction(args: ["rev-parse", ...])` returns deterministic strings.
- `Tests/ZionTests/ChatServiceTests.swift` — 4 cases listed in AC6. Inject a fake streaming closure (replace `AIClient` with a protocol or use a test-only initializer that accepts an `AsyncStream<String>` source). Prefer initializer injection of a `streamProvider` closure to avoid widening `AIClient`'s public surface.
- `Tests/ZionTests/ChatLocalizationTests.swift` — load each `Localizable.strings`, assert every key listed in "L10n Keys" exists in all three.

### Files to modify
- `Sources/Zion/Services/AIClient.swift` — inside the `enum AILimits` block (lines 4-34) add `static let maxFileContentPreviewLength = 8_000`. Single-line addition.
- `Sources/Zion/Models/AppEnums.swift` — (a) add `chat` to `AppSection`'s case list (line 343) plus its `title`/`icon` branches. Use icon `bubble.left.and.bubble.right`. (b) add `chat` to `FeatureSection`'s case list (line 247), its `icon` returns `"bubble.left.and.bubble.right"`, its `color` returns `DesignSystem.Colors.brandPrimary`, its `titleKey` returns `"chat.title"`. Verify alphabetical/grouping order matches the existing convention before inserting.
- `Sources/Zion/Views/Main/SidebarView.swift` — the chat entry is rendered automatically through `ForEach(AppSection.allCases)` once `.chat` is added (line 194). Confirm: no extra hardcoded switch needs updating (Grep confirmed there are no `case .code:` switches in this file). If a per-case switch surfaces during implementation, extend it consistently.
- `Sources/Zion/Views/Main/ContentView.swift` — add a `ChatScreen(...)` overlay following the existing `.code / .graph / .operations` opacity+hitTesting pattern (lines 564-593). The screen reads its `ChatService` via `model.chatService`. Add no new state beyond what `RepositoryViewModel+Chat.swift` exposes.
- `Sources/Zion/Resources/en.lproj/Localizable.strings` — append the keys listed in "L10n Keys" with English values.
- `Sources/Zion/Resources/pt-BR.lproj/Localizable.strings` — append the same keys with Portuguese (pt-BR) values.
- `Sources/Zion/Resources/es.lproj/Localizable.strings` — append the same keys with Spanish values.

### Dependencies between files
- `ChatService` depends on: `ChatModels`, `AIClient` (+ Helpers + Local), `RepositoryWorker`, `ChatContextBuilder`, `AIPromptPayload`, `AIProvider`, `AIMode`, `AILimits`.
- `ChatContextBuilder` depends on: `RepositoryWorker`, `AILimits`, `L10n`.
- `ChatScreen` depends on: `ChatService`, `ChatMessageBubble`, `ChatComposer`, `ChatEmptyState`, `RepositoryViewModel` (read-only).
- `ChatMessageBubble` depends on: `ChatModels`, `DesignSystem`.
- `ChatComposer` depends on: `ChatService`, `AIProvider`, `AIProviderSupport`, `DesignSystem`, `L10n`.
- `ChatEmptyState` depends on: `DesignSystem`, `L10n`.
- `RepositoryViewModel+Chat` depends on: `RepositoryViewModel`, `ChatService`, `AIClient`, `RepositoryWorker`.
- `ContentView` (modify) depends on: `ChatScreen`, `AppSection`.
- `SidebarView` (modify) depends on: updated `AppSection`.
- `AppEnums` (modify) depends on: `DesignSystem.Colors`, `L10n`.
- Tests depend on the corresponding production files plus `GitTestHelper.swift` where a temp repo is needed.

## L10n Keys
All three locale files MUST contain identical keys. Recommended values (English shown; translate for pt-BR / es preserving the `%@` and `%d` positional tokens in the same order):
- `chat.title` — `"Zion Talks"`
- `chat.emptyState.headline` — `"Ask anything about this repo"`
- `chat.emptyState.example.history` — `"Why was this commit made?"`
- `chat.emptyState.example.branch` — `"Suggest a branch name for…"`
- `chat.emptyState.example.diff` — `"Explain my current changes"`
- `chat.composer.hint` — `"Type a message — use /diff, /log, /status, /file <path>, /commit <sha>"`
- `chat.composer.send` — `"Send"`
- `chat.composer.stop` — `"Stop"`
- `chat.composer.newChat` — `"New chat"`
- `chat.slash.diff.label` — `"Current diff vs HEAD"`
- `chat.slash.log.label` — `"Last 20 commits"`
- `chat.slash.status.label` — `"Working tree status"`
- `chat.slash.file.label` — `"File: %@"`
- `chat.slash.commit.label` — `"Commit %@"`
- `chat.error.aiNotConfigured` — `"Set up an AI provider in Settings to start chatting."`
- `chat.error.send.title` — `"Chat error"`
- `chat.contextHeader` — `"Repository context: %@ · branch %@ · HEAD %@ · %d uncommitted file(s)"`

## Edge Cases
1. **No AI provider configured** — `AIProvider` is `.none` or selected provider has no key. `ChatService.send` short-circuits, appends a non-streaming assistant message whose content is `L10n("chat.error.aiNotConfigured")`. No network call.
2. **No repository open** — `RepositoryViewModel.repositoryURL == nil`. `ChatScreen` renders `ChatEmptyState` only; composer is disabled. Slash commands are not parsed (no repo to query). Selecting `.chat` in the sidebar still works.
3. **User-supplied path for `/file` is outside the repo** — resolve against `repositoryURL`, then verify the resolved URL has the repo URL as prefix. If not, replace the expansion block with a localized warning line; do not read the file. No `..` traversal allowed.
4. **`/file <path>` for a file > `AILimits.maxFileContentPreviewLength`** — truncate by character count (UTF-8 safe, scalar-aligned) and append a `(truncated)` marker.
5. **Streaming task cancelled mid-stream by `stop()`** — the in-flight `AsyncThrowingStream` is consumed inside the active `Task`; cancellation cooperates by checking `Task.isCancelled` between deltas. The pending assistant message keeps the partial content and flips `isStreaming` to `false`.
6. **Provider doesn't support streaming (`.openai`, `.gemini`, `.anthropic` in Phase 1)** — fall back to `AIClient.call(...)`. After completion, atomically replace the pending message content with the full response and clear `isStreaming`. UI must render a single message bubble either way (no flicker).
7. **AIClient throws (network/auth/timeout)** — catch in `ChatService.send`, remove the pending message, append a system-style assistant message containing the localized error title plus the underlying error description. Do not crash.
8. **Repo switch while streaming** — `RepositoryViewModel+Chat` calls `chatService.stop()` and discards the existing `ChatService` instance when the underlying `repositoryURL` changes. The new repo gets a fresh in-memory thread.
9. **HEAD SHA short form on a detached HEAD or freshly initialized repo** — if `rev-parse --short=7 HEAD` fails, format the header with `HEAD ?` so the rest of the context still ships.
10. **Inline `/cmd` mention in URLs or prose** — slash-command detection is line-anchored (`^\s*/(diff|log|status|file|commit)(\s|$)`). A `/diff` inside `https://example.com/diff` does NOT trigger expansion. Test `testIgnoresInlineSlashes` enforces this.
11. **Git output is empty (clean tree for `/diff`)** — emit a localized "no changes" line inside the fenced block instead of a zero-length block.
12. **Empty composer text after slash expansion** — if the user submits only slash commands and they expand to non-empty text, send is allowed. If post-trim text is empty, send is a no-op.
13. **L10n key drift** — `ChatLocalizationTests` reads each `.strings` file and fails the build if a chat key is missing or value is empty in any locale.
14. **Markdown rendering failure** — if `AttributedString(markdown:)` throws, fall back to plain text rendering with the same typography token. Never crash the bubble view.

## Out of Scope
- Persistence of chat threads across app launches or repo close/reopen. History is intentionally ephemeral; document this in the empty state subtitle if it fits, otherwise leave undocumented.
- Multiple threads per repository (only one active thread; `newThread()` replaces it).
- Tool calling / function calling / agentic loops.
- File editing, file writes, or any mutation of the user's working tree from chat.
- `@file` mention autocompletion (use `/file <path>` instead).
- Export, share, copy-as-markdown, history search, jump-to-message.
- Token usage display, cost estimates, rate-limit UI.
- System prompt customization UI (system prompt remains hardcoded inside `ChatService`).
- Image / attachment input.
- Anthropic SSE streaming wiring (does NOT exist in `AIClient+Helpers.swift` today — Phase 1 falls back to non-streaming for `.anthropic`, `.openai`, `.gemini`). Adding it is a future phase.
- Voice / Whisper integration into chat.
- Mobile remote access surfacing of chat (mobile is unaffected).
- Changes to `AIProvider` enum cases, `AIMode` enum, or `AIClient` public method signatures.
- Any modification of `.sdd/` files (those belong to the SDD workflow, not the feature).

## Builder Notes
- Read these existing files BEFORE writing any line of code: `Sources/Zion/Services/AIClient.swift`, `Sources/Zion/Services/AIClient+Helpers.swift`, `Sources/Zion/Services/AIClient+Local.swift`, `Sources/Zion/ViewModel/RepositoryViewModel.swift`, `Sources/Zion/ViewModel/RepositoryViewModel+AI.swift`, `Sources/Zion/Views/Main/SidebarView.swift`, `Sources/Zion/Views/Main/ContentView.swift`, `Sources/Zion/Models/AppEnums.swift`, one `.lproj/Localizable.strings`.
- Real navigation in this app routes via `AppSection` (3 cases: `.code, .graph, .operations`) — NOT `FeatureSection`. The user request says "add `.chat` case OR `.zionTalks`" to FeatureSection; that addition is still needed (FeatureSection drives the help/onboarding map: `HelpSheet.swift`, `ZionMapContent.swift`, `ZionMapDetailPage.swift`) AND a new `.chat` case in `AppSection` is REQUIRED for the sidebar entry point. Do both.
- Pattern to follow for the `RepositoryViewModel+Chat.swift` extension: see `RepositoryViewModel+AI.swift`. Use `@ObservationIgnored` for the lazy `_chatService` storage (the `@Observable` migration table in `known-bugs.md` mandates this for implementation properties that should not trigger view updates).
- `@Observable` view models do NOT support `@AppStorage`. Read `ai.defaultProvider` via `UserDefaults.standard.string(forKey: "ai.defaultProvider").flatMap(AIProvider.init(rawValue:))`. The composer view itself MAY use `@AppStorage` because it is a SwiftUI view, not an `@Observable` class.
- `ChatService` is `@MainActor @Observable`. All state mutations must run on the main actor. Streaming deltas arrive from a background `AsyncThrowingStream` — bounce them via `await MainActor.run { … }` (or rely on actor isolation if the consuming `for try await` loop is started inside a `Task { @MainActor in … }`).
- For streaming, prefer `Task { @MainActor in for try await delta in stream { thread.messages[lastIndex].content += delta } }`. Store the `Task` in `activeTask` so `stop()` can cancel it.
- For non-streaming providers, wrap the `await ai.call(...)` in the same `Task`. On completion, set `content` once and flip `isStreaming = false` so UI stays consistent with the streaming code path.
- Slash expansion strategy: split user text by newline, scan each line. If `parseSlashCommand` returns non-nil, KEEP the original line in the message AND append a fenced block beneath it with the localized label and the truncated git output. Do NOT remove the user's original `/cmd` line — the user wrote it, they should see it.
- Git context header is prepended ONCE per send call, only to the first message of the thread within that send. Spec says "prepended to first user message of every send" — implement as: if `thread.messages.isEmpty` before appending the new user message, prepend the context block to the user message body; otherwise, do not re-inject (model already has it from history). Capture the result of `gitContextHeader(...)` from `ChatContextBuilder` and prepend in plain text (no markdown fences).
- Use `git diff HEAD` (NOT `--cached`) for `/diff`. Use `git log --oneline -20` for `/log`. Use `git status --porcelain` for `/status`. Use `git show --format=fuller --stat <sha>` for `/commit`. Use `FileManager.default` + `String(contentsOf:)` (UTF-8) for `/file`.
- `RepositoryWorker.runAction` is `throws` (NOT `async throws`). It is `actor`-isolated, so calling it requires `try await worker.runAction(args: …, in: url)`.
- The 7-character SHA: `rev-parse --short=7 HEAD`. Trim newline.
- The uncommitted file count: `status --porcelain | wc -l` is unsafe across `runAction`. Instead run `status --porcelain`, split on newline, count non-empty lines in Swift.
- L10n strings: append at the END of each file in a clearly demarcated `// MARK: Zion Talks (Chat)` block — easier code-review and consistent with how other feature blocks have been added recently. Wrap every user-visible string in `L10n("key")` or `L10n("key", arg1, arg2)`. NEVER hardcode a string in any of the three languages.
- DesignSystem token usage: bubbles use `DesignSystem.Colors.brandPrimary` (user) and the closest existing surface token (assistant) — confirm by reading `DesignSystem.swift` before picking. Spacing via `DesignSystem.Spacing.*`. Corner radius via `DesignSystem.Spacing.*CornerRadius`. Code font via `DesignSystem.Typography.codeMono` (or whatever monospaced token exists; confirm before use).
- Build verification: `./scripts/make-app.sh` MUST succeed with zero new warnings or errors. Then run `swift test --filter Chat` and confirm all chat tests pass. Then run `/Users/nicolaregattieri/.claude/plugins/cache/zion/zion-core/0.1.0/bin/zion-validate-spec .sdd/TECH_SPEC.md` and confirm `VALID`.
- Do NOT touch `.sdd/` files. This spec is the only `.sdd/` artifact you should be aware of, and you don't write to it either — the spec writer owns it.
- Do NOT commit anything from `.sdd/` if you do create a commit.
- The user's `localization.md` rule is non-negotiable: every single user-visible string in `Views/Chat/*` and any user-visible string emitted by `ChatService`/`ChatContextBuilder` MUST go through `L10n("…")`. The acceptance criterion (AC13) Grep enforces this.
- The user's `naming-conventions.md` rule is non-negotiable: extract any numeric literal that appears 3+ times. Slash-command labels go through `L10n`, not string constants.
- Test runner gotcha: `swift test` requires `dangerouslyDisableSandbox: true` per project constraints. Plan for that when running tests during implementation.
