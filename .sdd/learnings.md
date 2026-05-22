# Build Learnings — Zion Talks Phase 3 (ZionHarness)

## Critical
- NEVER commit .sdd/ files — user dev folder, excluded from repo
- swift build needs `dangerouslyDisableSandbox: true`
- Use `swift build --scratch-path /tmp/zion-build-fresh` if SwiftPM lock contention
- Phase 1 (PR #436) merged; Phase 2 (PR #437) in review — Phase 3 builds on Phase 1 only
- Branch off master; will rebase onto Phase 2 once merged

## Approach
- str_replace_based_edit_tool schema (Anthropic verbatim) for edit tool — model fires correctly
- Hard rules harness-enforced (not prompt): read-before-edit, prefer-edit-over-create, bash allowlist, path safety
- StreamEvent enum in AIClient+Helpers.swift = single source for provider-agnostic streaming with tools

### Task 5: ZionHarness actor + FileMutationQueue + tests (DONE, 3 cycles)
- Swift 6 strict concurrency: `[[String: Any]]` is non-Sendable — convert to typed `Sendable` struct BEFORE the `@Sendable` closure boundary; `var` for that struct array must be renamed to `let` at capture site
- XCTestCase is not Sendable — extract `let h = harness!` before `withTaskGroup` to avoid `self` capture error in Swift 6 test code
- `FileMutationQueue` pattern: chain `Task` references per path key; works for serializing same-path writes while allowing different paths in parallel
- `validatePath` uses `resolvingSymlinksInPath()` + `standardizedFileURL` + trailing-`/` prefix check to block symlink traversal outside repo
- `chat.allowEdits` UserDefaults key must be set `true` in test `setUp`, otherwise all edit tests fail with `editsDisabled`

### Task 6: StreamEvent enum + AIError tool cases (DONE, 1 cycle)
- StreamEvent lives at the bottom of AIClient+Helpers.swift, just above the AIError block
- `[String: Any]` in enum case requires `@unchecked Sendable` on the enum (not individual cases)
- New L10n key `ai.error.toolExecution.failed` uses `%@` format specifier; caller uses String(format:...) 
- Read-before-edit tool requirement: must Read locale files before Edit even for append-only changes

### Task 10: ToolEventBadge + AutoInjectionChip + ChatMessageBubble integration (DONE, 1 cycle)
- `Capsule()` shape avoids any `cornerRadius:` literal — use it for pill/capsule backgrounds
- `ProgressView().scaleEffect(0.6)` is the idiomatic SwiftUI way to shrink circular progress inline
- Switch on `event.status` inside `@ViewBuilder` with `case .pending, .running:` combined works cleanly
- `DesignSystem.Typography.label` is `Font.system(size: 10)` — correct token for badge/chip text
- AutoInjectionChip keeps L10n format string as-is; the en.lproj value already includes the sparkle emoji so the `sparkles` SF Symbol is additional decoration
- ChatMessageBubble integration: tool badges go above bubble content (inside VStack before messageText); AutoInjectionChip goes inside the same VStack after messageText with `HStack { Spacer(); chip }` for right-alignment

### Task 1: ZionTools — tool schemas (DONE, 2 cycles)
- AIProviderSupport.swift had a pre-existing broken `}` brace (localModelSupportsTools orphaned outside enum) — had to fix it to allow build; logged as out-of-scope but necessary
- `[String: Any]` in a `Sendable` struct requires `@unchecked Sendable` — use it for JSON schema types
- edit tool items schema: properties dict uses `[String: Any]` nested casts — tests must cast through `[String: Any]` at each level to reach `oldText`/`newText` keys
- ZionTools.tools is a `static let` array — Swift strict concurrency requires `@unchecked Sendable` on the element type

### Task 11: AISettingsTab AI Harness section + StatusBar .chat button (DONE, 1 cycle)
- `if defaultProvider == .local { let ... }` block inside a SwiftUI Section compiles fine — no `@ViewBuilder` wrapper needed for simple let bindings
- statusBarSectionLabel(_:) delegates to `L10n(section.title)` — no explicit switch needed for new AppSection cases
- Read-before-edit rule applies to locale files even for append-only insertions
