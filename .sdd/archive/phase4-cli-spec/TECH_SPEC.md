# Tech Spec: Zion Talks Phase 4 — Subscription-backed CLI providers (claude + codex)

## Goal
Add two new AI providers (`claudeCLI`, `codexCLI`) that stream chat responses by spawning the user's installed `claude` (Claude Code CLI v2.1.x) and `codex` (Codex CLI v0.131.x) binaries as subprocesses with the repo as working directory. This unlocks the user's existing Claude Pro/Max and ChatGPT subscriptions (no API key, no metering), inherits the CLIs' built-in tool harness (Bash/Read/Edit/Grep/Glob/WebFetch), and gives Zion repo-context-aware responses out of the box.

## Constraints
- Language: Swift 5.10+
- Framework: SwiftUI + AppKit (macOS app target `Zion`)
- Test runner: XCTest via `swift test` (target `ZionTests`)
- Build: `./scripts/make-app.sh` (preferred); `swift build --scratch-path /tmp/zion-build-fresh` needs `dangerouslyDisableSandbox: true`
- Dependencies: Foundation `Process` + `Pipe` only — NO new SwiftPM dependencies
- Entitlements: existing Hardened Runtime, NO app-sandbox — subprocess spawning already permitted; DO NOT modify `Zion.entitlements`
- Boundaries:
  - Touch only files listed in Architecture. Do NOT modify `Zion.entitlements`, `AIClient+Anthropic.swift`, `AIClient+OpenAI.swift`, `AIClient+Local.swift`, `AIClient+Analysis.swift`, `AIClient+Review.swift`, `ChatStorage.swift`, `ChatContextBuilder.swift`, persistence schema, or any non-chat services.
  - Do NOT touch SwiftTerm fork, terminal stack, Recovery Vault, git workflows, mobile remote access code.
  - Do NOT commit anything under `.sdd/`.
  - All user-facing strings via `L10n(...)` in en/pt-BR/es (see `.claude/rules/localization.md`).
  - No hardcoded design literals — use `DesignSystem.Colors.*`, `DesignSystem.Spacing.*`, `DesignSystem.Typography.*`, `DesignSystem.Motion.*` per `.claude/rules/naming-conventions.md`.
  - One struct per file; file name matches struct name (`.claude/rules/folder-architecture.md`).
  - Each task touches ≤5 files. Total tasks ≤11.

## Reuse
- `Sources/Zion/Services/AIClient+Local.swift` — `AsyncThrowingStream<String, Error>` streaming pattern (see `streamLocalLLM` and `LocalStreamChunk` struct at lines 9–63). Copy this shape for `streamClaudeCLI` / `streamCodexCLI` so `ChatService.consumeStream` (existing) can route deltas without changes.
- `Sources/Zion/Services/AIClient+Helpers.swift` lines 547–575 — `AIError` enum. Add new cases here, don't create a parallel error type.
- `Sources/Zion/Services/AIClient.swift` — `AIClient.call(payload:provider:apiKey:maxTokens:lane:mode:)` dispatch (lines ~40–64). Add `.claudeCLI` / `.codexCLI` arms here.
- `Sources/Zion/Services/ChatService.swift` lines 236–268 — provider dispatch `switch`. Extend with `.claudeCLI` / `.codexCLI` arms following the `.anthropic` / `.openai` pattern (build stream → `consumeStream`).
- `Sources/Zion/Services/ChatService.swift` lines 313–325 — `consumeStream(...)` for text-delta consumption. Use as-is for text; tool events take a parallel path.
- `Sources/Zion/Services/AIProviderSupport.swift` line 22 — `configurableProviders` array. Append `.claudeCLI`, `.codexCLI`. Extend `dashboardURL(for:)` switch and `isConnected(...)` helper (CLI providers connected = installed AND authenticated, NOT via API key).
- `Sources/Zion/Services/AIClient.swift` `loadAPIKey` / `loadLocalConfig` precedent for UserDefaults caching — mirror for `CLIDiscoveryService` cache.
- `Sources/Zion/Services/GitHubClient.swift` lines 27–38 (which-style binary probing) and `GitClient.swift` lines 54–57 (`Process` + `currentDirectoryURL`) — copy the Process configuration idiom, including stderr capture pattern.
- `Sources/Zion/Models/AppEnums.swift` line 221 — `AIProvider` enum. Add `.claudeCLI`, `.codexCLI`. Update `label` (line ~223).
- `Sources/Zion/Models/ChatModels.swift` — `ChatMessage` struct (line 12), `ChatThread` (line 36). Add new `ToolEvent` struct in this file (one models domain per file rule), do NOT create `ToolEventModels.swift`.
- `Sources/Zion/Views/Chat/ChatScreen.swift` — `ChatMessageBubble(message:)` render loop (line 60). Inject tool-event chip rendering above the currently streaming assistant bubble.
- `Sources/Zion/Views/Chat/ChatThinkingIndicator.swift` — cold-start indicator (CLI ~3.8s spin-up). Reuse, do not create a new one.
- `Sources/Zion/Views/Settings/AISettingsTab.swift` + `Sources/Zion/Views/Settings/LocalLLMSettingsSection.swift` — section pattern for provider config (status pill + toggles + hint). Copy this layout for the new "Subscription CLIs" section. Use design tokens already in use.
- `Sources/Zion/Resources/{en,pt-BR,es}.lproj/Localizable.strings` — append new keys (use dot-notation per localization rule). Keep alphabetical proximity to existing `chat.*`, `settings.ai.*`, `ai.error.*` groupings.
- `Sources/Zion/Helpers/DiagnosticLogger.swift` — used by ChatService; reuse for CLI subprocess diagnostics. Source tag: `"CLIDiscovery"` / `"AIClientCLI"`.
- `Sources/Zion/Helpers/Constants.swift` — `Constants.Timing.*` for any timeout literals (cold-start timeout, auth probe timeout, SIGKILL grace).

## Acceptance Criteria

1. `swift build` succeeds with no warnings on the new code — `dangerouslyDisableSandbox swift build --scratch-path /tmp/zion-build-phase4 2>&1 | tee /tmp/phase4-build.log && grep -E "error:|warning:.*(CLIDiscoveryService|AIClient\+CLISubprocess|ChatToolEventBadge|claudeCLI|codexCLI)" /tmp/phase4-build.log; test $? -eq 1`
2. Full app build via repo script succeeds — `./scripts/make-app.sh && test -d dist/Zion.app`
3. All existing Phase 1+2+3 tests stay green — `swift test --filter "Chat|AIClient|AIProviderSupport|Anthropic" 2>&1 | tail -5 | grep -E "Test Suite 'All tests' passed"`
4. New `CLIDiscoveryServiceTests` pass — `swift test --filter CLIDiscoveryServiceTests 2>&1 | grep -E "Executed [0-9]+ tests, with 0 failures"`
5. New `ClaudeCLIStreamParserTests` pass — `swift test --filter ClaudeCLIStreamParserTests 2>&1 | grep -E "Executed [0-9]+ tests, with 0 failures"`
6. New `CodexCLIStreamParserTests` pass — `swift test --filter CodexCLIStreamParserTests 2>&1 | grep -E "Executed [0-9]+ tests, with 0 failures"`
7. New `AIClientCLIDispatchTests` pass — `swift test --filter AIClientCLIDispatchTests 2>&1 | grep -E "Executed [0-9]+ tests, with 0 failures"`
8. New `ChatServiceCLIIntegrationTests` pass — `swift test --filter ChatServiceCLIIntegrationTests 2>&1 | grep -E "Executed [0-9]+ tests, with 0 failures"`
9. `AIProvider` enum exposes both new cases as raw-decodable — `swift test --filter AIProviderCLICasesTests 2>&1 | grep -E "Executed [0-9]+ tests, with 0 failures"` (test asserts `.claudeCLI` and `.codexCLI` exist and round-trip through label)
10. All new L10n keys exist in en, pt-BR, es with identical key sets — `swift test --filter CLIProvidersLocalizationTests 2>&1 | grep -E "Executed [0-9]+ tests, with 0 failures"`
11. No raw `Color.` / hardcoded `cornerRadius:` / hardcoded `Font.` literals in new view files — `! grep -nE "(Color\.(white|black|gray|red|green|blue|orange|purple)|cornerRadius: *[0-9]|\.font\(\.(caption|footnote|body|title))" Sources/Zion/Views/Chat/ChatToolEventBadge.swift`
12. Every new user-facing string in Swift is wrapped in `L10n(...)` — `! grep -nE "Text\(\"[A-Z]" Sources/Zion/Views/Chat/ChatToolEventBadge.swift Sources/Zion/Views/Settings/AISettingsTab.swift | grep -v 'L10n\|//'`
13. Default `chat.cliAllowEdits` is OFF — `swift test --filter CLIAllowEditsDefaultTests 2>&1 | grep -E "Executed [0-9]+ tests, with 0 failures"`
14. Subprocess cancellation kills the child process group (no orphans) — `swift test --filter CLISubprocessCancellationTests 2>&1 | grep -E "Executed [0-9]+ tests, with 0 failures"`
15. CLI stream parser yields text deltas AND emits tool-use events as a distinct stream item — `swift test --filter ClaudeCLIStreamParserTests/testToolUseEventEmission 2>&1 | grep -E "Executed 1 test, with 0 failures"`

## Architecture

### Files to create
- `Sources/Zion/Services/CLIDiscoveryService.swift` — `actor CLIDiscoveryService` with `enum CLITool { case claude, codex }`, `struct CLIToolStatus { installed; path: URL?; version: String?; isAuthenticated: Bool? }`, `func status(for: CLITool, refresh: Bool = false) async -> CLIToolStatus`. Discovery probes `which <cli>` then `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, expands `~/.nvm/versions/node/*/bin` via `FileManager`. Version: `<cli> --version` parsed by regex. Auth: `claude -p "ping" --output-format json` with 10s timeout (`Constants.Timing.cliAuthProbeTimeout`); `codex` auth probe runs `codex exec --json -s read-only -C $TMPDIR <<< "ping"` with same timeout. Cache keyed `cli.discovery.<tool>.<binaryPath>.<version>` in UserDefaults with TTL `Constants.Timing.cliDiscoveryCacheTTL`. Injectable `ProcessRunner` typealias for test mocks.
- `Sources/Zion/Services/AIClient+CLISubprocess.swift` — extension on `AIClient`. Public API: `func streamClaudeCLI(payload: AIPromptPayload, cwd: URL, maxTokens: Int, allowEdits: Bool) async -> AsyncThrowingStream<CLIStreamEvent, Error>`, `func streamCodexCLI(payload: AIPromptPayload, cwd: URL, allowEdits: Bool) async -> AsyncThrowingStream<CLIStreamEvent, Error>`, plus non-streaming `callClaudeCLI` / `callCodexCLI` returning `String`. Internal static parsers: `static func parseClaudeJSONLLine(_ line: Data) -> CLIStreamEvent?`, `static func parseCodexJSONLLine(_ line: Data) -> CLIStreamEvent?`. Internal `enum CLIStreamEvent { case textDelta(String); case toolStart(id: String, name: String, description: String); case toolEnd(id: String, success: Bool); case done; case error(String) }`. Subprocess lifecycle uses Foundation `Process` + `Pipe` for stdin/stdout/stderr, `setpgid` via posix_spawn flags or `Process.launchPath`'s child-side `qualityOfService` is insufficient — instead set `process.environment["ZION_SUBPROCESS"] = "1"` and call `setpgid(process.processIdentifier, process.processIdentifier)` via a tiny `posix_spawnattr` setup (use `Darwin.posix_spawn` to spawn with `POSIX_SPAWN_SETPGROUP` if Foundation `Process` can't). Cancellation via `AsyncThrowingStream.onTermination`: `process.terminate()` (SIGTERM to PG), wait `Constants.Timing.cliSigkillGrace` (1s), then `kill(-pid, SIGKILL)`.
- `Sources/Zion/Views/Chat/ChatToolEventBadge.swift` — `struct ChatToolEventBadge: View`. Inputs: `let event: ToolEvent`. Capsule using `DesignSystem.Colors.glassHover` background, `DesignSystem.Spacing.smallCornerRadius`, `DesignSystem.Typography.caption` label, `DesignSystem.Motion.springSubtle` for enter/exit transitions, leading SF Symbol mapped from `event.toolName` (Bash→"terminal", Read→"doc.text", Edit→"pencil", Grep/Glob→"magnifyingglass", WebFetch→"globe", default→"hammer"), trailing `ProgressView()` when `.running`, checkmark/xmark when `.completed`/`.failed`. L10n: `chat.cli.tool.running` / `chat.cli.tool.completed` / `chat.cli.tool.failed` (all format with `%@` tool name).
- `Tests/ZionTests/CLIDiscoveryServiceTests.swift` — mock filesystem + mock `ProcessRunner`; covers: probe order honored, semver regex parses `"2.1.120"` and `"0.131.0"`, version parser rejects garbage, auth detection (claude permission_denials field), cache hit avoids re-probe, cache invalidated by stale TTL.
- `Tests/ZionTests/ClaudeCLIStreamParserTests.swift` — XCTest: parses `{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}` → `.textDelta("hello")`; parses `{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"git status"}}` → `.toolStart(id:"t1",name:"Bash",description:"git status")` (description = truncated 60-char preview); `{"type":"tool_result","tool_use_id":"t1","is_error":false}` → `.toolEnd(id:"t1",success:true)`; `{"type":"result",...}` → `.done`; malformed line returns nil; **`testToolUseEventEmission`** asserts tool event surfaces as distinct enum case (AC #15).
- `Tests/ZionTests/CodexCLIStreamParserTests.swift` — same shape for Codex event taxonomy (`msg.type` `agent_message`, `function_call_begin`, `function_call_end`, `task_complete`).
- `Tests/ZionTests/AIClientCLIDispatchTests.swift` — injects mock subprocess via test seam returning canned JSONL bytes; asserts `AIClient.call(provider: .claudeCLI, ...)` returns concatenated text; `.codexCLI` likewise.
- `Tests/ZionTests/ChatServiceCLIIntegrationTests.swift` — uses `ChatService` test-injection init with custom stream provider for CLI; asserts text deltas append to assistant message AND tool events populate `pendingToolEvents`; asserts events cleaned up after `Constants.Timing.toolEventCleanupDelay`.
- `Tests/ZionTests/CLISubprocessCancellationTests.swift` — spawns `/bin/sleep 60` via the subprocess helper, cancels the async task, asserts the child PID is no longer alive after `Constants.Timing.cliSigkillGrace + 0.5s` via `kill(pid, 0)`. AC #14.
- `Tests/ZionTests/AIProviderCLICasesTests.swift` — asserts `.claudeCLI` and `.codexCLI` exist, `label` is non-empty for each, round-trips through codable. AC #9.
- `Tests/ZionTests/CLIProvidersLocalizationTests.swift` — for every new key in the spec L10n list, asserts en/pt-BR/es bundles return non-empty + format-arg count matches. AC #10.
- `Tests/ZionTests/CLIAllowEditsDefaultTests.swift` — asserts `UserDefaults.standard.bool(forKey: "chat.cliAllowEdits")` defaults to `false` on a fresh suite. AC #13.

### Files to modify
- `Sources/Zion/Models/AppEnums.swift` — add `.claudeCLI`, `.codexCLI` cases to `AIProvider` (line 221) and corresponding `label` arms (line 223 area) using `L10n("settings.ai.provider.claudeCLI")` / `L10n("settings.ai.provider.codexCLI")`. Search the file for any other exhaustive switches on AIProvider and extend them; if found, list and patch each.
- `Sources/Zion/Services/AIClient.swift` — extend the `switch provider` block at lines ~40–64 inside `call(...)` with `.claudeCLI` and `.codexCLI` arms that call `callClaudeCLI(payload:cwd:maxTokens:)` / `callCodexCLI(payload:cwd:)` from the new extension. `cwd` is read from `payload.cwd` — add a new optional `cwd: URL?` field to `AIPromptPayload` (in `Sources/Zion/Models/AIModels.swift`) defaulting `nil`; if nil for CLI calls, throw `AIError.cliError(stderr: "missing cwd", exitCode: -1)`. Expose `let cliDiscovery = CLIDiscoveryService()` as a stored property on `AIClient`.
- `Sources/Zion/Models/AIModels.swift` — add optional `cwd: URL?` to `AIPromptPayload` (default nil). Ensure existing constructions remain source-compatible (parameter has default value).
- `Sources/Zion/Services/AIClient+Helpers.swift` — extend `AIError` (lines 547–575) with `.cliNotInstalled(CLITool)`, `.cliNotAuthenticated(CLITool)`, `.cliError(stderr: String, exitCode: Int32)`, `.cliVersionTooOld(required: String, found: String)`. Add `errorDescription` arms using new L10n keys (`ai.error.cli.notInstalled`, `ai.error.cli.notAuthenticated`, `ai.error.cli.execFailed`, `ai.error.cli.versionTooOld`).
- `Sources/Zion/Services/AIProviderSupport.swift` — append `.claudeCLI`, `.codexCLI` to `configurableProviders` (line 22). Extend `dashboardURL(for:)` switch (both → `URL(string: "https://docs.anthropic.com/.../claude-code")` / `https://github.com/openai/codex` respectively, or `nil`). Add new helper `isCLIConnected(provider: AIProvider, discovery: CLIDiscoveryService) async -> Bool`. Extend existing `isConnected(provider:loadKey:)` to special-case CLI providers (return false synchronously; async helper used by Settings UI).
- `Sources/Zion/Services/ChatService.swift` — extend `switch provider` at line 236 with `.claudeCLI` and `.codexCLI` arms. Add observable `var pendingToolEvents: [ToolEvent] = []`. Add `private func consumeCLIStream(_ stream: AsyncThrowingStream<CLIStreamEvent, Error>, assistantID: UUID, threadID: UUID) async` that routes `.textDelta` → existing `appendAssistantDelta`; `.toolStart` → append to `pendingToolEvents`; `.toolEnd` → mark `.completed`/`.failed`, schedule cleanup task after `Constants.Timing.toolEventCleanupDelay`. Read `@AppStorage("chat.cliAllowEdits")` via `UserDefaults.standard.bool(forKey:)` (per known-bugs.md: @AppStorage doesn't work in @Observable). Pass `payload.cwd = URL(fileURLWithPath: repoID)` only if `repoID` is a path; otherwise plumb a `repoURL: URL` constructor parameter.
- `Sources/Zion/Models/ChatModels.swift` — add `struct ToolEvent: Identifiable, Equatable { let id: UUID; let toolName: String; let description: String; var status: ToolEventStatus }` and `enum ToolEventStatus: String, Codable { case running, completed, failed }`. Do NOT persist tool events in Phase 4 (ephemeral state only).
- `Sources/Zion/Views/Chat/ChatScreen.swift` — render `pendingToolEvents` (from `ChatService`) as `VStack(spacing: DesignSystem.Spacing.xSmall)` of `ChatToolEventBadge(event:)` above the streaming bubble (the last assistant message where `isStreaming == true`). Use `.transition(.opacity.combined(with: .move(edge: .top)))` with the design system spring.
- `Sources/Zion/Views/Settings/AISettingsTab.swift` — add new section "Subscription CLIs" rendering one row per `CLITool` showing: status pill (green/amber/red via `DesignSystem.Colors.success/.warning/.error`), version label, install/auth hint with copy-to-clipboard button when missing, "Refresh" button. Add `Toggle(L10n("settings.ai.cli.allowEdits"), isOn: $allowEdits)` bound to `UserDefaults` via a small `@State` mirror refreshed on appear. NO API key field. Loads `CLIDiscoveryService` status via `.task { ... }`.
- `Sources/Zion/Resources/en.lproj/Localizable.strings` — append all new keys (see "L10n Keys" below). Group near existing `chat.*`, `settings.ai.*`, `ai.error.*` regions.
- `Sources/Zion/Resources/pt-BR.lproj/Localizable.strings` — same keys, pt-BR values.
- `Sources/Zion/Resources/es.lproj/Localizable.strings` — same keys, es values.
- `Sources/Zion/Helpers/Constants.swift` — add `Constants.Timing.cliAuthProbeTimeout = 10.0`, `Constants.Timing.cliSigkillGrace = 1.0`, `Constants.Timing.cliDiscoveryCacheTTL = 300.0` (5 min), `Constants.Timing.toolEventCleanupDelay = 3.0`. If file doesn't have a `Timing` namespace, follow whatever sibling pattern exists (verify with Grep before edit).

### Dependencies between files
- `CLIDiscoveryService.swift` depends on `Foundation` + `Constants.swift` + `AppEnums.swift` (re-uses no other types).
- `AIClient+CLISubprocess.swift` depends on `AIClient.swift`, `CLIDiscoveryService.swift`, `AIClient+Helpers.swift` (for `AIError`), `AIModels.swift` (for `AIPromptPayload`).
- `AIClient.swift` (modified) depends on `CLIDiscoveryService.swift` (stored property) and `AIClient+CLISubprocess.swift` (call dispatch).
- `AIProviderSupport.swift` depends on `CLIDiscoveryService.swift` (async helper) and modified `AppEnums.swift`.
- `ChatService.swift` depends on `AIClient+CLISubprocess.swift` (call site), modified `ChatModels.swift` (`ToolEvent`), `Constants.swift`.
- `ChatModels.swift` self-contained.
- `ChatScreen.swift` depends on `ChatService` (existing) and new `ChatToolEventBadge.swift`.
- `ChatToolEventBadge.swift` depends on modified `ChatModels.swift` (`ToolEvent`) and `DesignSystem.swift`.
- `AISettingsTab.swift` depends on `CLIDiscoveryService.swift` and modified `AIProviderSupport.swift`.
- All test files depend on their corresponding production files plus `XCTest`.

## Edge Cases

1. **Cold start (~3.8s for Claude CLI Node bootstrap)** — Reuse existing `ChatThinkingIndicator` and show it immediately when `isStreaming = true` is set, before the first delta arrives. Do NOT add a per-CLI timeout < cold-start time.
2. **Process inheritance / orphan Node children** — Foundation `Process` does NOT make the parent the new process group leader by default; killing the parent leaves Node children alive. Use `posix_spawn` with `POSIX_SPAWN_SETPGROUP` (set pgid = 0) OR set `setpgid` from the child via a tiny shell wrapper `/bin/sh -c 'exec setsid <cli> ...'`. Cancellation must `kill(-pid, SIGTERM)` (negative pid = process group), wait `Constants.Timing.cliSigkillGrace`, then `kill(-pid, SIGKILL)`. AC #14 enforces this.
3. **PATH inside `Zion.app` is minimal** — `which claude` from inside the app may fail even when the CLI is installed. `CLIDiscoveryService` must probe the explicit list (Homebrew Apple Silicon, Homebrew Intel, user-local, NVM glob expansion). Cache the resolved absolute path; subprocess spawns use that absolute path, NOT `claude` on PATH.
4. **Auth missing** — Surface `AIError.cliNotAuthenticated(.claude)` with `L10n("ai.error.cli.notAuthenticated")` body that instructs the user to run `claude auth` or `codex login` in their own Terminal. Do NOT attempt to launch interactive auth from Zion.
5. **Wrong version** — If `claude --version` returns < 2.1.0 or `codex --version` < 0.131.0, throw `.cliVersionTooOld(required:found:)`. Settings UI must render an upgrade hint.
6. **Stale UserDefaults cache when user upgrades CLI** — Cache invalidates on TTL (`Constants.Timing.cliDiscoveryCacheTTL = 300s`) AND on explicit Settings "Refresh" button click.
7. **Stream JSON line splits across buffer boundaries** — Use `FileHandle.bytes.lines` async sequence (Foundation already handles line buffering); never parse partial bytes. If a single line fails to decode, log and continue — do NOT abort the stream on one malformed event (matches the Local SSE parser's "return nil on garbage" pattern).
8. **stderr capture under heavy output** — Drain stderr concurrently with stdout via a separate `Task` reading `process.standardError.fileHandleForReading.readabilityHandler`; truncate captured stderr to last 2KB before stuffing into `AIError.cliError(stderr:exitCode:)` to avoid memory blowup.
9. **Cancellation during cold-start (before any output)** — `onTermination` may fire before the child has PID; guard with `process.isRunning` check before sending signals.
10. **CLAUDE.md auto-discovery (prompt-injection vector)** — A malicious repo could plant instructions in `CLAUDE.md` or `AGENTS.md` that the CLI obeys autonomously. Phase 4 ships with **default trust ON** and documents the risk in `ai.error.cli.execFailed` hint + Settings UI hint string `settings.ai.cli.allowEdits.hint` (warns about file edits). Per-repo trust toggle is Phase 5 (Out of Scope).
11. **Settings UI shown before discovery completes** — Render row in `.idle` state with spinner; do not block UI. Use `.task { await refresh() }` on appear.
12. **`AIPromptPayload.cwd == nil` reaching CLI path** — Defensive throw `AIError.cliError(stderr: "missing cwd", exitCode: -1)`; tests cover this (`AIClientCLIDispatchTests`).
13. **Tool event arrives after assistant message marked not-streaming** — Discard late events to avoid stale chips; ChatService checks `isStreaming` before appending to `pendingToolEvents`.
14. **Same tool event ID arrives twice** — Dedup by `event.id` in `pendingToolEvents` (upsert by id, not append).
15. **macOS sandbox** — Zion has NO app-sandbox; subprocess works. Verify no future PR adds the entitlement that would block this (out of scope for spec but mention in Builder Notes).
16. **Localization file diff hygiene** — Append new keys to the END of each `Localizable.strings` (one block per file) to keep diffs minimal and reviewable. Do not reorder existing keys.

## Out of Scope

- Warm process pool / persistent CLI process per chat thread (Phase 4.5).
- Hook discovery and customization beyond CLI defaults (Phase 5).
- Custom system prompt override via CLI args beyond a fixed Zion safety preamble (Phase 5).
- MCP server passthrough into the CLIs (Phase 5).
- Gemini CLI support (no official OAuth subscription CLI exists; revisit if Google ships one).
- Rendering Plan-mode UI / TodoWrite events in the chat surface beyond the basic tool-chip (Phase 5).
- Speculative-edit fast-apply pattern (Phase 5).
- Skills system / `.skills` discovery (Phase 5).
- DIY tool-calling harness for non-CLI providers (Anthropic / OpenAI direct API tool use) (Phase 6).
- Per-repo "Trust this repo's CLAUDE.md" toggle (Phase 5).
- Prompt-injection scanning of CLI auto-discovered context (`CLAUDE.md`, `AGENTS.md`) — `detectSuspiciousPromptPatterns` is not wired into the CLI path (future hardening).
- Persisting `ToolEvent` history to SQLite (Phase 4 ships ephemeral only).
- Streaming non-text content (images, file diffs as structured payloads) — text-only in Phase 4.
- Updating `Zion.entitlements`, SwiftTerm fork, Recovery Vault, mobile remote access code paths.
- Updating `dist/Zion.dmg` (only `dist/Zion.app` is required per build-workflow rule; DMG is a release-time step).

## Builder Notes

- **Read the rules before coding.** Mandatory: `.claude/rules/localization.md`, `.claude/rules/naming-conventions.md`, `.claude/rules/folder-architecture.md`, `.claude/rules/known-bugs.md` (especially the @AppStorage-in-@Observable rule), `.claude/rules/verification.md`, `.claude/rules/build-workflow.md`.
- **Build path:** Use `./scripts/make-app.sh` to validate end-to-end; `swift build` requires `dangerouslyDisableSandbox: true`. Use `swift build --scratch-path /tmp/zion-build-phase4` to avoid clobbering the main scratch dir between iterations.
- **Test path:** `swift test --filter <suite>` for fast loops. Full suite via `swift test`.
- **AsyncThrowingStream pattern:** Mirror `streamLocalLLM` in `AIClient+Local.swift` lines 119+ exactly — same `AsyncThrowingStream { continuation in ... continuation.onTermination = { ... } }` shape. The difference: yield `CLIStreamEvent` (not `String`) so tool events ride the same stream.
- **Process spawning with process group:** If `Process` won't give you `setpgid`, wrap the binary with `/bin/sh -c 'exec setsid <abs-path> <args>'` and pass args through. Verify on macOS that `setsid` exists at `/usr/bin/setsid` — if not, use the `posix_spawn` route in C interop.
- **stdin prompt delivery:** Always send the prompt via stdin (not `argv`) to avoid arg-length limits for long contexts. Close the stdin pipe immediately after writing so the CLI knows input is complete.
- **JSONL parsing:** Use `JSONSerialization.jsonObject(with:)` returning `[String: Any]` — keep the parser tolerant (return `nil` on shape mismatch, continue stream). Do NOT use `Codable` with strict schemas; CLI event shapes evolve.
- **L10n keys to add (all three languages):**
  - `settings.ai.provider.claudeCLI`
  - `settings.ai.provider.codexCLI`
  - `settings.ai.cli.subscription.title`
  - `settings.ai.cli.installed` (`%@` = version)
  - `settings.ai.cli.notInstalled`
  - `settings.ai.cli.notInstalled.claude.hint`
  - `settings.ai.cli.notInstalled.codex.hint`
  - `settings.ai.cli.notAuthenticated.claude.hint`
  - `settings.ai.cli.notAuthenticated.codex.hint`
  - `settings.ai.cli.allowEdits`
  - `settings.ai.cli.allowEdits.hint`
  - `settings.ai.cli.refresh`
  - `chat.cli.tool.running` (`%@` = tool name)
  - `chat.cli.tool.completed` (`%@` = tool name)
  - `chat.cli.tool.failed` (`%@` = tool name)
  - `ai.error.cli.notInstalled`
  - `ai.error.cli.notAuthenticated`
  - `ai.error.cli.versionTooOld`
  - `ai.error.cli.execFailed` (`%@` = stderr excerpt)
- **AppStorage trap:** `@AppStorage("chat.cliAllowEdits")` MUST NOT be used inside `@Observable` `ChatService`. Read via `UserDefaults.standard.bool(forKey:)` from a computed property; this is documented as RESOLVED in `.claude/rules/known-bugs.md`. In `AISettingsTab.swift` (a SwiftUI `View`), `@AppStorage` is fine.
- **Subprocess env:** Always set `process.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": NSHomeDirectory()]`. Don't inherit Zion's env wholesale (avoids polluting CLI with Node/Python tooling vars).
- **Claude CLI args (locked):** `["-p", "-", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-mode", (allowEdits ? "acceptEdits" : "plan"), "--max-budget-usd", "1.00", "--append-system-prompt", "<Zion safety preamble>"]`. Safety preamble lives as a `static let` constant near the call site; one-line, English-only (CLI doesn't localize).
- **Codex CLI args (locked):** `["exec", "--json", "-C", cwd.path, "-s", (allowEdits ? "workspace-write" : "read-only"), "-"]`.
- **Stream vs call:** Streaming variants for `ChatService.send`. Non-streaming `callClaudeCLI` / `callCodexCLI` for utility lanes (commit messages, review) via `AIClient.call`.
- **Settings UI:** Place new "Subscription CLIs" section BELOW the existing "Connected Providers" section and ABOVE any "Local LLM" / advanced sections. Follow the same row visual rhythm; reuse the status-pill component style from neighboring rows.
- **ChatScreen integration:** Render `pendingToolEvents` as a top-anchored VStack inside the assistant bubble container — same horizontal padding as the bubble, vertical spacing `DesignSystem.Spacing.xSmall`. Animate with `withAnimation(DesignSystem.Motion.springSubtle)`.
- **Cleanup on stream end:** When stream completes, defer-clear remaining `.running` tool events to `.completed` (or `.failed` if the stream threw) so chips don't hang.
- **Test execution speed:** `CLISubprocessCancellationTests` spawns real `/bin/sleep` — keep timeouts ≤ 3s total.
- **Commit hygiene:** One feature = one commit per `.claude/rules/git-control/RULE.md`. Split into commits like `feat(ai): CLI discovery service`, `feat(ai): Claude/Codex CLI subprocess transport`, `feat(chat): tool event chips`, `feat(settings): subscription CLI section`, `feat(l10n): CLI provider keys`. Each commit ≤ 5 files.
- **Branching:** `git fetch origin && git checkout -b feature/zion-talks-phase4-cli-providers origin/master`. Never branch from local stale `master`.
- **Mirror sync:** No `.claude/` or `docs/` edits expected in this spec; if the builder adds any, sync to `~/Documents/zion-code-docs/` per `.claude/rules/docs-mirror-sync.md`.
- **Don't touch `.sdd/`:** Per project memory, `.sdd/` files are local-only and never committed.
- **After every code change:** Re-run `./scripts/make-app.sh` and post `file:///Users/nicolaregattieri/Developer/GraphForge/dist/Zion.app/Contents/MacOS/Zion` for user testing (per memory).
