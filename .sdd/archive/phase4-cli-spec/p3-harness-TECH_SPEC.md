# Tech Spec: Zion Talks Phase 3 — ZionHarness (Native Tool Calling + Intent Classifier Fallback)

## Goal
Give the in-app Chat assistant autonomous read/write/exec access to the active repo by introducing `ZionHarness` (a Swift tool-calling layer that drives OpenAI-`tools` and Anthropic `tool_use` providers) plus a regex-based `IntentClassifier` fallback for models without tool-calling support. Result: the model stops asking the user to paste `/diff` output and instead invokes read/edit/bash/grep/glob tools itself.

## Constraints
- Language: Swift 5.10+
- Framework: SwiftUI + AppKit, Swift Concurrency (`@MainActor`, `actor`, `AsyncThrowingStream`), `@Observable`
- Test runner: XCTest via `swift test` (target `ZionTests`)
- Build: `./scripts/make-app.sh` (preferred); `swift build --scratch-path /tmp/zion-build-fresh` requires `dangerouslyDisableSandbox: true`
- Dependencies: NO new SPM deps. Reuse Foundation, URLSession, existing `RepositoryWorker`, existing `AIClient` streaming stack.
- Boundaries:
  - Phase 3 rebases onto Phase 2 (PR #437). Phase 2 ships `AIClient+Anthropic.swift` and `AIClient+OpenAI.swift`. If Phase 2 is not merged at build start, Phase 3 creates those files. The task list assumes they exist; the executor must check and create-or-modify accordingly.
  - MUST NOT touch CLI subprocess providers (Phase 4), Task-list/Skills/Plan-Mode (Phase 5), Compaction (Phase 6), MCP, Gemini streaming.
  - MUST NOT modify any file outside the project root. MUST NOT commit `.sdd/`.
  - Path-safety, read-before-edit, prefer-edit-over-create, bash allowlist: enforced in the harness (Swift), NOT in the prompt.

## Reuse
- `Sources/Zion/Services/AIClient+Local.swift` (`streamLocalLLM`, `LocalStreamChunk`, `parseOpenAISSELine`) — copy the URLSession.bytes + AsyncThrowingStream pattern for new `streamLocalWithTools`.
- `Sources/Zion/Services/AIClient+Helpers.swift` — `makePromptPayload`, `renderUserMessage`, `openAIRequestBody`, retry/backoff harness, `AIError` enum (extend with new cases).
- `Sources/Zion/Services/AIClient.swift` — `_testURLSession` seam for injecting `URLProtocol` fakes in tool-streaming tests.
- `Sources/Zion/Services/ChatService.swift` — existing `@MainActor @Observable final class ChatService` with `send()`, `stop()`, `newThread()`. Extend, do not rewrite.
- `Sources/Zion/Services/ChatContextBuilder.swift` — slash-command expansion (`/diff`, `/log`, `/status`, `/file`, `/commit`). IntentClassifier produces the same canonical commands; call into this builder for output formatting consistency.
- `Sources/Zion/Services/RepositoryWorker.swift` + `RepositoryWorker+Execution.swift` — `runAction(args:in:) async throws -> String`. ZionHarness uses `worker` for git/swift/ls/cat/pwd/echo execution.
- `Sources/Zion/Models/ChatModels.swift` — `ChatRole`, `ChatMessage`, `ChatThread`. Extend `ChatMessage` (additive fields, default nil → backwards compatible).
- `Sources/Zion/Models/AppEnums.swift` (line 220) — `enum AIProvider: String, CaseIterable, Identifiable { case none, anthropic, openai, gemini, local }`. Add `var supportsToolCalling: Bool` here.
- `Sources/Zion/Services/AIProviderSupport.swift` — existing capability helper; add `localModelSupportsTools(_ name: String) -> Bool` here (regex whitelist).
- `Sources/Zion/Models/LocalLLMConfig.swift` — read `modelName` to decide local tool support.
- `Sources/Zion/Views/Chat/ChatMessageBubble.swift` — extend bubble to render new `AutoInjectionChip` + `ToolEventBadge` subviews. Do not duplicate bubble logic.
- `Sources/Zion/Views/Settings/AISettingsTab.swift` — add "AI Harness" section using existing `@AppStorage` + `Toggle` + `Form` pattern in this file.
- `Sources/Zion/ViewModel/RepositoryViewModel+Chat.swift` (lines 5-19) — `var chatService: ChatService { ChatService(ai:worker:contextBuilder:) }`. Wire `ZionHarness` into ChatService init.
- DesignSystem tokens (`DesignSystem.Colors.*`, `DesignSystem.Spacing.*`, `DesignSystem.Typography.*`) for badges/chips. No hardcoded values.
- `L10n("key")` + `Sources/Zion/Resources/{en,pt-BR,es}.lproj/Localizable.strings` — every user-facing string in all 3 locales.
- `Tests/ZionTests/AIClientLocalDispatchTests.swift` and `LocalSSEStreamParserTests.swift` — pattern for URL-protocol fake injection + SSE chunk feeding. Mirror for tool-call deltas.
- `Tests/ZionTests/ChatServiceTests.swift` — pattern for testing ChatService with mock AIClient.

## Acceptance Criteria
1. `Sources/Zion/Services/ZionTools.swift` defines tool schemas and exports `toolSchemasJSON()` (OpenAI shape) and `anthropicToolSchemas()` (Anthropic shape) — `grep -E "static func toolSchemasJSON|static func anthropicToolSchemas" Sources/Zion/Services/ZionTools.swift | wc -l` returns `2`.
2. Tool schema for `edit` matches Anthropic `text_editor_20250728` `str_replace` command shape (oldText/newText pairs) — `grep -E "oldText|newText" Sources/Zion/Services/ZionTools.swift | wc -l` is `>= 4`.
3. `ZionHarness` rejects `edit` on a path that was never `view`d in the session — `swift test --filter ZionHarnessTests/test_edit_rejected_without_prior_read` passes.
4. `ZionHarness` rejects `write` on an existing path — `swift test --filter ZionHarnessTests/test_write_rejected_when_file_exists` passes.
5. `ZionHarness` rejects bash commands outside the allowlist regex `^(git|swift|ls|pwd|cat|echo)\s` — `swift test --filter ZionHarnessTests/test_bash_allowlist_enforced` passes.
6. `ZionHarness` rejects file paths outside `repoURL` (including `..` traversal and symlink escape) — `swift test --filter ZionHarnessTests/test_path_outside_repo_rejected` passes.
7. `FileMutationQueue` serializes concurrent edits to the same path; concurrent edits to different paths run in parallel — `swift test --filter ZionHarnessTests/test_file_mutation_queue_serializes` passes.
8. `AIProvider.supportsToolCalling` returns `true` for `.anthropic` and `.openai`, `false` for `.gemini`, `.none`; `.local` consults `AIProviderSupport.localModelSupportsTools(modelName)` — `swift test --filter AIProviderSupportTests/test_supportsToolCalling` passes.
9. `AIProviderSupport.localModelSupportsTools("qwen3-coder")` returns `true`; `localModelSupportsTools("phi-2")` returns `false` — `swift test --filter AIProviderSupportLocalTests/test_localModelSupportsTools_whitelist` passes.
10. `IntentClassifier.classify` returns the expected intent for canonical EN + PT-BR phrasings and `nil` for ambiguous input — `swift test --filter IntentClassifierTests` passes (>= 12 assertions covering all 6 intents).
11. Tool-streaming protocol parsers handle Anthropic `content_block_delta` with `input_json_delta` (accumulate partial JSON), OpenAI `tool_calls` deltas, and OpenAI-compat (Ollama/MLX/vLLM/llama.cpp) `tool_calls` — `swift test --filter ToolStreamingProtocolTests` passes.
12. `ChatService` end-to-end tool loop: tool_call → harness.execute → tool_result → continue stream → final assistant text — `swift test --filter ChatServiceToolLoopTests/test_full_tool_loop` passes.
13. `ChatService` enforces max 10 hops per turn; on the 11th hop it appends a `max_hops_exceeded` tool result and forces a final response — `swift test --filter ChatServiceToolLoopTests/test_max_hops_enforced` passes.
14. When `provider.supportsToolCalling == false` and `IntentClassifier.classify` returns a hit, ChatService auto-injects the git command output into the user prompt and records `autoInjectedIntent` on the message — `swift test --filter ChatServiceToolLoopTests/test_auto_injection_when_no_tools` passes.
15. Settings toggle `chat.toolsEnabled` (default `true`) disables tool loop entirely; toggle `chat.allowEdits` (default `false`) rejects edit/write tools with explicit error; toggle `chat.autoInject` (default `true`) gates the intent classifier — `swift test --filter ChatServiceToolLoopTests/test_settings_toggles_respected` passes.
16. Read-before-edit session state is per-`ChatThread` and resets on `newThread()` — `swift test --filter ZionHarnessTests/test_session_reset_on_new_thread` passes.
17. All new L10n keys exist in `en.lproj`, `pt-BR.lproj`, `es.lproj` — `swift test --filter ChatLocalizationTests/test_phase3_keys_in_all_locales` passes.
18. No hardcoded colors / spacing / fonts in new SwiftUI views — `grep -nE "Color\.|\.font\(\.|cornerRadius:\s*[0-9]+|\.padding\(\s*[0-9]+" Sources/Zion/Views/Chat/ToolEventBadge.swift Sources/Zion/Views/Chat/AutoInjectionChip.swift | grep -v "DesignSystem\." | wc -l` returns `0` (SwiftUI inline `.padding(8)` and `.frame()` literals exempt per project rule — exclude with the grep below).
19. Full test suite green — `swift test 2>&1 | tail -5` shows `Test Suite 'All tests' passed`.
20. App builds — `./scripts/make-app.sh 2>&1 | tail -3` shows no compiler errors and produces `dist/Zion.app`.

## Architecture

### Files to create
- `Sources/Zion/Services/ZionTools.swift` — `struct ZionTools` with stable tool schema definitions and two exporters: `toolSchemasJSON()` (OpenAI `{type:"function", function:{name,description,parameters:JSONSchema}}` array) and `anthropicToolSchemas()` (Anthropic `{name,description,input_schema}` array). Defines the 6 tools: `read`, `edit`, `write`, `bash`, `grep`, `glob`. Edit tool schema mirrors Anthropic `text_editor_20250728` `str_replace` semantics (array of `{oldText,newText}` pairs).
- `Sources/Zion/Services/ZionHarness.swift` — `actor ZionHarness { let worker: RepositoryWorker; let repoURL: URL; private var sessionReadFiles: Set<URL>; private let mutationQueue: FileMutationQueue; func execute(toolCall: ToolCall) async -> ToolResult; func resetSession() }`. Hosts `struct ToolCall`, `struct ToolResult`, `enum HarnessError`. Also defines private nested `actor FileMutationQueue` keyed by absolute path. All hard rules (read-before-edit, prefer-edit, path-safety, bash allowlist) live here.
- `Sources/Zion/Services/IntentClassifier.swift` — `enum HarnessIntent { case lastCommit, currentChanges, recentHistory, status, fileContent(path: String), commitDetails(sha: String) }` + `static func classify(_ text: String) -> HarnessIntent?`. Regex/keyword EN+PT-BR. Returns `nil` unless high confidence.
- `Sources/Zion/Views/Chat/ToolEventBadge.swift` — `struct ToolEventBadge: View` ephemeral capsule above streaming bubble. Shows SF Symbol + tool name + truncated args preview. Uses `DesignSystem.Colors.*`, `DesignSystem.Spacing.*`, `DesignSystem.Typography.*`.
- `Sources/Zion/Views/Chat/AutoInjectionChip.swift` — `struct AutoInjectionChip: View` small chip below user bubble. Label like `L10n("chat.harness.autoIncluded", "git show HEAD")`.
- `Tests/ZionTests/ZionToolsTests.swift` — schema JSON shape validation; OpenAI vs Anthropic envelope difference; required-field presence.
- `Tests/ZionTests/ZionHarnessTests.swift` — read-before-edit, file-exists rejection, outside-repo rejection (including `..` and symlink escape), bash allowlist (positive + negative), FileMutationQueue serialization, session reset, settings toggle (allowEdits off rejects edit/write).
- `Tests/ZionTests/IntentClassifierTests.swift` — each of 6 intents: positive EN, positive PT-BR, negative/ambiguous returns nil.
- `Tests/ZionTests/ToolStreamingProtocolTests.swift` — feed canned Anthropic SSE `content_block_delta`+`input_json_delta` chunks, OpenAI `tool_calls` deltas, Ollama-compat `tool_calls`; assert `StreamEvent` sequence.
- `Tests/ZionTests/ChatServiceToolLoopTests.swift` — full loop, max-hops, auto-injection fallback, settings toggles.

### Files to modify
- `Sources/Zion/Models/AppEnums.swift` — add `extension AIProvider { var supportsToolCalling: Bool { ... } }` after the enum at line 220. Returns `true` for `.anthropic`/`.openai`, `false` for `.gemini`/`.none`. For `.local`: returns `true` only if `AIProviderSupport.localModelSupportsTools(loadedModelName)`.
- `Sources/Zion/Services/AIProviderSupport.swift` — add `static func localModelSupportsTools(_ name: String) -> Bool` with regex whitelist: `qwen3-coder`, `qwen2\\.5-coder`, `llama-3\\.[3-9]`, `mistral-large`, `deepseek-v3`, `gpt-oss`, `glm-4`. Case-insensitive.
- `Sources/Zion/Models/ChatModels.swift` — extend `struct ChatMessage` with `var autoInjectedIntent: String? = nil` and `var toolEvents: [ChatToolEvent]? = nil`. Add `struct ChatToolEvent: Identifiable, Equatable { let id: String; let name: String; var status: ToolEventStatus; let argsPreview: String }` and `enum ToolEventStatus { case pending, running, completed, failed }`. Default-nil keeps existing call sites and tests green.
- `Sources/Zion/Services/AIClient+Helpers.swift` — add `AIError` cases: `toolExecutionFailed(String)`, `maxToolHopsExceeded`, `toolCallingNotSupported`. Add localized descriptions via `L10n`.
- `Sources/Zion/Services/AIClient+Anthropic.swift` — IF EXISTS (Phase 2 merged), add `func streamAnthropicWithTools(payload:apiKey:tools:maxTokens:) -> AsyncThrowingStream<StreamEvent, Error>`. IF NOT EXISTS, the executor CREATES this file with both Phase 2 baseline (`streamAnthropic`) AND the tools variant. Parses Messages API SSE: `message_start`, `content_block_start` (text vs tool_use), `content_block_delta` (`text_delta` vs `input_json_delta` — accumulate partial JSON per block index), `content_block_stop`, `message_delta`, `message_stop`. Emits `StreamEvent` enum (see Builder Notes).
- `Sources/Zion/Services/AIClient+OpenAI.swift` — IF EXISTS, add `func streamOpenAIWithTools(payload:apiKey:tools:maxTokens:) -> AsyncThrowingStream<StreamEvent, Error>`. IF NOT EXISTS, create with Phase 2 baseline + tools variant. Parses Chat Completions SSE: `choices[0].delta.content` (text), `choices[0].delta.tool_calls[]` (id, function.name, function.arguments — accumulate partial JSON per index).
- `Sources/Zion/Services/AIClient+Local.swift` — add `func streamLocalWithTools(payload:config:tools:maxTokens:modelID:) -> AsyncThrowingStream<StreamEvent, Error>`. Same OpenAI-compat shape (Ollama 0.3+, MLX-LM, vLLM, llama.cpp accept `tools` param + return `tool_calls` deltas).
- `Sources/Zion/Services/ChatService.swift` — add `@ObservationIgnored private let harness: ZionHarness` injected via init. In `send()`: read `@AppStorage("chat.toolsEnabled")`, `chat.allowEdits`, `chat.autoInject`. If tools enabled AND provider supports it: enter tool-streaming loop (call provider stream-with-tools, on `toolCallComplete` invoke `harness.execute`, append tool_result to history, continue; max 10 hops). If tools disabled OR provider unsupported AND autoInject on: call `IntentClassifier.classify(userText)`; if hit, run command via `worker`, prepend fenced output, set `message.autoInjectedIntent`. `newThread()` calls `await harness.resetSession()`.
- `Sources/Zion/Views/Chat/ChatMessageBubble.swift` — render `AutoInjectionChip` below user bubble when `message.autoInjectedIntent != nil`. Render `ToolEventBadge` list above assistant bubble when `message.toolEvents != nil && !message.toolEvents!.isEmpty`. Existing layout unchanged for messages without these fields.
- `Sources/Zion/Views/Settings/AISettingsTab.swift` — add "AI Harness" section with 3 toggles (`chat.toolsEnabled`, `chat.allowEdits`, `chat.autoInject`) and a read-only label showing local model tool-capability (computed from current `LocalLLMConfig.modelName` via `AIProviderSupport.localModelSupportsTools`). All labels via `L10n`.
- `Sources/Zion/ViewModel/RepositoryViewModel+Chat.swift` — at the `ChatService(...)` construction site (~line 12), instantiate `let harness = ZionHarness(worker: worker, repoURL: repositoryURL)` and pass to `ChatService` init.
- `Sources/Zion/Resources/en.lproj/Localizable.strings` — add all 18 new keys listed in spec input.
- `Sources/Zion/Resources/pt-BR.lproj/Localizable.strings` — same keys with PT-BR values.
- `Sources/Zion/Resources/es.lproj/Localizable.strings` — same keys with ES values.

### Dependencies between files
- `ZionHarness.swift` depends on `RepositoryWorker.swift` (for bash/git execution) and `ZionTools.swift` (for tool name/schema lookup when validating arguments).
- `ChatService.swift` depends on `ZionHarness.swift` (executes tools), `ZionTools.swift` (passes schemas to AIClient), `IntentClassifier.swift` (fallback), `AIClient+Anthropic.swift`/`+OpenAI.swift`/`+Local.swift` (provider streams), `ChatModels.swift` (writes `toolEvents` + `autoInjectedIntent`), `AppEnums.swift` (`supportsToolCalling`).
- `AIClient+Anthropic.swift`/`+OpenAI.swift`/`+Local.swift` depend on a shared `StreamEvent` enum — declare it in `AIClient+Helpers.swift` (single source).
- `RepositoryViewModel+Chat.swift` depends on `ZionHarness.swift` (constructs and injects).
- `ChatMessageBubble.swift` depends on `ToolEventBadge.swift`, `AutoInjectionChip.swift`, and the new `ChatMessage` fields.
- `AISettingsTab.swift` depends on `AIProviderSupport.swift` (`localModelSupportsTools`) and `LocalLLMConfig.swift`.
- `AppEnums.swift` (`supportsToolCalling`) depends on `AIProviderSupport.swift` (`localModelSupportsTools`) — keep extension declaration in `AppEnums.swift` but defer to AIProviderSupport for local-specific logic to avoid circular includes.

## Edge Cases
1. **Phase 2 not yet merged** — `AIClient+Anthropic.swift` / `AIClient+OpenAI.swift` don't exist. Executor must check with `ls Sources/Zion/Services/AIClient+Anthropic.swift` and either create the file (with both Phase 2 streaming baseline + tools variant) or modify the existing one. Surface mismatch as a task warning rather than silently failing.
2. **Path traversal** — Reject `..` segments after resolving symlinks. Use `URL.resolvingSymlinksInPath()` then check `standardizedPath.hasPrefix(repoURL.standardizedPath + "/")`.
3. **Symlink escape** — Resolve symlinks before path-prefix check (covers symlink-to-outside-repo attack).
4. **Bash command injection** — Pass arguments as `[String]` to `worker.runAction`, not as a single shell string. Allowlist regex matches only the binary name; arguments are not shell-evaluated.
5. **Partial JSON in `input_json_delta`** — Anthropic streams tool arguments as concatenated JSON fragments per `content_block_delta`. Accumulate per block index. Only dispatch `toolCallComplete` on `content_block_stop`. Catch JSON parse error and surface as `toolExecutionFailed`.
6. **Parallel tool calls in same turn** — Anthropic and OpenAI both allow multiple tool_use blocks per assistant response. Execute serially through harness in declaration order (deterministic for tests). FileMutationQueue handles cross-call same-path serialization.
7. **Tool call with no arguments** — Default to empty JSON object `{}`. Don't crash on missing/null fields.
8. **Max hops exceeded** — After hop 10, inject a system-flavored tool result `{"error":"max_hops_exceeded"}` and force one final non-tool generation. UI shows `chat.tool.error.maxHops`.
9. **Stream cancellation mid-tool-call** — `ChatService.stop()` cancels the parent task. Harness execution is awaited inside the loop; cancellation propagates and partially executed tool results are discarded.
10. **Large file read** — Cap at 8000 lines / 1MB. Return truncation marker `<...truncated; offset N to read more...>` so model can re-request with `offset`/`limit`.
11. **Large bash output** — Cap at 100 lines / 1MB. Stream full output to `$TMPDIR/zion-bash-<uuid>.txt` and return path in marker so model can `read` it.
12. **Concurrent edits to same path** — FileMutationQueue serializes by absolute path string. Different paths run in parallel actor-style.
13. **read-before-edit across turns** — Session state lives on `ZionHarness` instance. ChatService keeps one harness per ChatThread; `newThread()` calls `harness.resetSession()`.
14. **Settings `chat.allowEdits == false`** — Harness rejects `edit` and `write` with `chat.tool.error.editsDisabled`. Tools still appear in schema (model can request) but result is the disabled error — model self-corrects.
15. **Local model claims tool support but returns malformed `tool_calls`** — Parser catches JSON error, surfaces `toolExecutionFailed`, harness returns error result, model retries or falls back to text.
16. **Gemini selected as provider** — `supportsToolCalling == false` → falls through to intent classifier path. No Gemini tools code in Phase 3.
17. **`.none` provider selected** — `ChatService.send()` returns the existing "no provider" error before reaching harness.
18. **IntentClassifier false positive** — Auto-injection shows AutoInjectionChip with the exact command run. User sees what was injected and can correct in next message. Classifier is conservative (regex + keyword threshold) by design.
19. **Empty edit `oldText`** — Reject with `chat.tool.error.invalidEdit`. Empty string would match infinitely.
20. **edit `oldText` not found in file** — Return error `text_not_found` with first 200 chars of file as context so model can retry.

## Out of Scope
- Task-list mechanics and UI (Phase 5).
- Skills system (markdown lazy-load) (Phase 5).
- Plan Mode (Claude Code modal state) (Phase 5).
- Worktree-parallel sub-agents (Phase 5).
- Compaction algorithm (Phase 6).
- CLI subprocess providers — Claude Code / Codex / Gemini CLI (Phase 4, separate branch).
- MCP server passthrough (Phase 5).
- Tab-completion or inline edits — Zion is not an IDE (never).
- Speculative-edit fast-apply pattern (Phase 5).
- Gemini streaming with tools (Phase 4+).
- Web search / web fetch tools (Phase 4+).
- ML-based intent classification — regex/keyword only.
- Memory system `~/.zion/memory/` (Phase 5).
- Migrating non-streaming `AIClient.call` callers to streaming (out of scope; existing analysis/review/commit-msg paths stay non-streaming).
- Rewriting Phase 1/Phase 2 chat code (additive only).
- New SPM dependencies.

## Builder Notes
- **Phase 2 dependency check**: First task should `ls Sources/Zion/Services/AIClient+Anthropic.swift Sources/Zion/Services/AIClient+OpenAI.swift` and choose CREATE vs MODIFY for those two files. If creating, include the Phase 2 baseline streaming functions (`streamAnthropic`, `streamOpenAI`) as well, ported from the Phase 2 PR #437 diff.
- **Shared `StreamEvent` enum**: Declare in `AIClient+Helpers.swift`:
  ```swift
  enum StreamEvent {
      case textDelta(String)
      case toolCallStart(id: String, name: String)
      case toolCallArgsDelta(id: String, jsonFragment: String)
      case toolCallComplete(id: String, name: String, arguments: [String: Any])
      case done
  }
  ```
  All three provider extensions emit this same enum so ChatService is provider-agnostic.
- **Tool schema authoring**: Mirror the public Anthropic `text_editor_20250728` schema for `edit` (look up the exact JSON shape; the 4 commands are view/create/str_replace/insert but in Phase 3 we expose only the str_replace variant under tool name `edit` with array-of-pairs API). For `read/write/bash/grep/glob`, mirror Pi (earendil-works/pi) catalog descriptions. Keep total system-prompt token cost under 1000 tokens.
- **JSONSchema in Swift**: Use `[String: Any]` dictionaries and `JSONSerialization.data(withJSONObject:)`. Do not introduce a JSONSchema lib.
- **Bash allowlist regex**: Compile once as `NSRegularExpression` with anchor `^(git|swift|ls|pwd|cat|echo)(\\s|$)`. Reject otherwise. Args passed as `[String]` to `worker.runAction(args:in:)` — never join into a shell string.
- **Path safety helper**: Add private `func isPathInsideRepo(_ url: URL) -> Bool` to ZionHarness: resolve symlinks, standardize, then `path.hasPrefix(repoURL.standardizedFileURL.path + "/")` or equals.
- **FileMutationQueue**: Private nested `actor FileMutationQueue { private var inFlight: [String: Task<Void, Never>] = [:]; func withLock<T>(path: String, op: @Sendable () async throws -> T) async rethrows -> T }`. Tasks chain per-path.
- **AppStorage defaults**:
  - `chat.toolsEnabled` → `true`
  - `chat.allowEdits` → `false` (conservative)
  - `chat.autoInject` → `true`
  - Read inside `ChatService.send()` each call (not captured at init) so toggles take effect immediately.
- **Read-before-edit lives on harness, not ChatService**: keep ChatService dumb about session state — it just calls `harness.execute(toolCall)` and `harness.resetSession()` on `newThread`.
- **Tool loop bookkeeping**: ChatService maintains the running message array (system + history + tool_results) across hops in a local `var`, not on the stored thread, until the loop completes. Then it commits the final assistant text + accumulated `toolEvents` to the thread in one update (avoids UI flicker between hops).
- **UI rendering**: `toolEvents` array on `ChatMessage` is the source of truth. Update statuses on each `StreamEvent` — model bubble re-renders via `@Observable`. Don't introduce a separate observable for tool state.
- **L10n format strings**: Use `%@` format markers for tool names / commands / shas. Test with `ChatLocalizationTests` pattern (see existing `LocalLLMLocalizationTests.swift`).
- **Task list target**: 11-12 tasks max, ≤5 files each. Suggested split:
  1. ZionTools schemas + tests
  2. ZionHarness actor + FileMutationQueue + safety + tests
  3. IntentClassifier + tests
  4. AppEnums `supportsToolCalling` + AIProviderSupport whitelist + tests
  5. ChatModels additions + ChatLocalizationTests for new keys
  6. StreamEvent enum + AIClient+Helpers AIError cases
  7. AIClient+Anthropic streaming (create-or-modify) + tools variant + parser tests
  8. AIClient+OpenAI streaming (create-or-modify) + tools variant + parser tests
  9. AIClient+Local tools variant + parser tests
  10. ChatService tool loop + intent fallback + tool-loop tests
  11. UI: ToolEventBadge + AutoInjectionChip + ChatMessageBubble integration + AISettingsTab Harness section
  12. RepositoryViewModel+Chat wiring + L10n strings (en/pt-BR/es) + final integration test pass
- **Don't break Phase 1/2 tests**: Run `swift test --filter ChatServiceTests`, `ChatModelsTests`, `ChatContextBuilderTests`, `ChatSlashCommandParserTests`, `AIClientLocalDispatchTests`, `LocalSSEStreamParserTests` after each task. New fields on `ChatMessage` must default to nil.
- **Build verification per task**: After edits, run `./scripts/make-app.sh 2>&1 | tail -20` and confirm zero errors. Don't proceed if a task leaves compile broken.
- **Test runtime**: Full `swift test` takes ~60–90s on M-series; budget accordingly. Don't set sub-30s test timeouts.
- **Never commit `.sdd/`**: per memory rule — stage `Sources/`, `Tests/`, `scripts/` only. Do NOT `git add .`.
- **Branch hygiene**: Phase 3 work on branch `feature/zion-talks-phase3-harness` cut from `origin/master` AFTER PR #437 merges. If PR #437 is still open, base from PR #437's HEAD instead and call this out in the PR description.
- **Decision log**: After implementation, ask user whether to log "Harness layer enforces safety rules (not prompt)" in `docs/DECISIONS.md`.
