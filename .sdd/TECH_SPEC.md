# Tech Spec: Performance Wave 3 (Primitives + Watcher Polish + autoReveal)

## Goal
Three finishing touches on top of Waves 1-2: (1) reusable Swift `@Throttle` / `@Debounce` property-wrapper primitives (or equivalent global helpers) that ViewModel extensions can adopt without hand-writing `Task.sleep`, (2) a watcher regex filter that drops `.git/index.lock` and `*.pack.tmp` noise before it hits the coalescer, and (3) `autoReveal` parity with VS Code — when the active editor file changes, the file tree expands parent directories and selects the file.

## Context & Motivation
Reference: `docs/VSCODE_GIT_LEARNINGS.md`. VS Code source anchors:
- Throttle/debounce decorators: `extensions/git/src/decorators.ts` (`_throttle`, `_sequentialize`, `debounce(delay:)`, `memoize`).
- Watcher filter: `extensions/git/src/repository.ts:465-470` — `filterEvent(rootWatcher.event, uri => !/\.git(\/index\.lock|...)$|\/\.watchman-cookie-/.test(uri.path))`.
- autoReveal: `extensions/vscode-main/src/vs/workbench/contrib/files/browser/views/explorerView.ts` — `selectActiveFile(reveal:)` reveals the active-editor file in the tree.

Observed today:
- `FileWatcher` already has a coalescer (Wave 1) + debounce. But `.git/index.lock` file create/delete — which git itself generates during every commit — still flows through classifier into coalescer. Even though the classifier returns `nil` for pure `.git/` internals, the classifier call itself runs; filtering earlier saves work and removes an entire class of pointless iteration.
- `*.pack.tmp` files (git GC, repack) generate FSEvents spikes. They land under `.git/objects/pack/` — same category.
- Zion has no `@throttle` / `@debounce` reusable primitive. Wave 1 `FileWatcher` coalescer writes its own `Task` + `Task.sleep(nanoseconds:)` + cancel pattern. Wave 2 `IdleFocusGate` wrote its own 200 ms grace with another `Task.sleep`. Further waves will duplicate this unless we extract.
- Editor opens a file via `selectedCodeFile` but tree expansion does not auto-follow when the active file lives in a currently-collapsed directory.

## Constraints
- Language: Swift 6.2. `@MainActor` `@Observable` ViewModel + SwiftUI.
- Dependencies: no new external deps. Uses Combine / Foundation / AppKit only.
- Boundaries:
  - Must NOT break Wave 1 (coalescer) or Wave 2 (Operation / gate / auto-dispose) behaviour. Tests must stay green.
  - Must NOT touch editor, terminal, SwiftTerm, Sparkle, or mobile remote code paths.
  - `@throttle` / `@debounce` primitives are optional to apply retroactively — this wave does NOT rewrite Wave 1/2 callers to use them. New primitives only. (Rewrite can come in a tidy-up wave if desired.)
  - Must use `L10n("key")` for any new user-facing string.
  - All new timing values go in `Constants.Timing.*` / `Constants.Limits.*`.

## Reuse
- `Sources/Zion/Services/FileWatcher.swift` — `classifyChangeEvent(paths:flags:)` at line ~97 and `isInsideGitDirectory`, `isGitMetadataPath` at line ~120+. The watcher filter hooks into the path-normalization stage, before classify.
- `Sources/Zion/ViewModel/RepositoryViewModel+FileTree.swift` — `expandedPathsByRepository`, `loadChildrenIfNeeded(for:)`, `pruneExpandedPaths(_:)` (from Wave 1). The autoReveal helper calls `loadChildrenIfNeeded` up the parent chain.
- `Sources/Zion/ViewModel/RepositoryViewModel.swift` — `selectedCodeFile: FileItem?` (Observable) is the active-editor file. `autoRevealOnEditorFileChange` observer attaches here.
- `Sources/Zion/Helpers/Constants.swift` — add new `Timing.debouncePrimitiveDefault` and `Timing.throttlePrimitiveDefault` if primitives accept an optional default. Honor `Constants.*` pattern.

## Acceptance Criteria
1. `Debouncer` helper exists as a reusable primitive in `Sources/Zion/Helpers/Debouncer.swift`: an `@MainActor` class with `init(interval: UInt64)` and `func schedule(_ work: @Sendable @MainActor @escaping () -> Void)` that cancels prior scheduled work and fires after `interval` ns. Verify: `swift test --filter ZionTests.DebouncerTests`.
2. `Throttler` helper exists as a reusable primitive in `Sources/Zion/Helpers/Throttler.swift` with semantics matching VS Code `_throttle` (repository.ts:39): if running, enqueue exactly one next invocation (collapses duplicates). `init(interval: UInt64)` + `func schedule(_ work: @Sendable @MainActor @escaping () async -> Void)`. Verify: `swift test --filter ZionTests.ThrottlerTests`.
3. `FileWatcher` drops `.git/index.lock`, `.git/<worktree>/index.lock`, and `*.pack.tmp` paths BEFORE classification. Feeding the classify layer a burst of 5 paths — 2 real, 1 `index.lock`, 1 `.pack.tmp`, 1 watchman cookie — produces a classify result whose `changedPaths` contains only the 2 real paths (+ none of the filtered ones). Verify: `swift test --filter ZionTests.FileWatcherTests/testWatcherFiltersGitNoise`.
4. `FileWatcher.isFilteredNoisePath(_:) -> Bool` is exposed as an `internal` static helper returning true for `index.lock`, `pack.tmp`, and `.watchman-cookie-` variants. Verify: `swift test --filter ZionTests.FileWatcherTests/testIsFilteredNoisePath`.
5. Auto-reveal: observing a change to `selectedCodeFile` triggers `revealSelectedCodeFileInTree()` which (a) computes the parent chain of the URL relative to `repositoryURL`, (b) inserts each ancestor directory into `expandedPaths`, (c) calls `loadChildrenIfNeeded` on each newly-expanded ancestor. Verify: `swift test --filter ZionTests.AutoRevealTests/testRevealExpandsParentChain`.
6. Auto-reveal no-ops when the file is not inside the repository, when `repositoryURL == nil`, and when `autoRevealEnabled == false` (new `@AppStorage("code.autoReveal")` flag defaulting to true — value stored via existing `UserDefaults` convention, not `@AppStorage` inside `@Observable` per the project's known-bugs rule). Verify: `swift test --filter ZionTests.AutoRevealTests/testRevealSkipsWhenDisabled`.
7. Full suite: `swift test` exits 0 (baseline 923 tests from Wave 2 + new tests, 0 failures).
8. Build artifact: `./scripts/make-app.sh` exits 0 and produces `dist/Zion.app`.

## Architecture

### Files to create
- `Sources/Zion/Helpers/Debouncer.swift` — `@MainActor final class Debouncer` with private `Task<Void, Never>?` and `UInt64` interval. `schedule(_:)` cancels the prior task, starts a new `Task` that `await Task.sleep(nanoseconds: interval)` then invokes the closure. `cancel()` cancels without firing. `deinit` cancels the pending task.
- `Sources/Zion/Helpers/Throttler.swift` — `@MainActor final class Throttler` mirroring VS Code `_throttle` semantics. Keep a `current: Task<Void, Never>?` and `next: (@Sendable @MainActor () async -> Void)?`. On `schedule(work:)`, if `current == nil`, fire immediately as a `Task`. When that task completes, if `next != nil`, take it and schedule the next run. Additional `schedule` calls while both current and next exist overwrite `next` (collapses duplicates to exactly one follow-up).
- `Sources/Zion/ViewModel/RepositoryViewModel+AutoReveal.swift` — `@MainActor func revealSelectedCodeFileInTree()`. Reads `selectedCodeFile`, `repositoryURL`, and the `autoRevealEnabled` persisted flag; inserts ancestors into `expandedPaths` and calls `loadChildrenIfNeeded`. Also add `var autoRevealEnabled: Bool { get set }` as a computed property reading/writing `UserDefaults` with key `code.autoReveal` (default true). Subscribing to `selectedCodeFile` changes happens in an existing `didSet` on that property OR via a new `onChange` observer registered in `RepositoryViewModel.init`. Prefer `didSet` — simpler, no Combine.
- `Tests/ZionTests/DebouncerTests.swift` — AC 1 tests: schedule fires once after interval; repeat-schedule cancels prior; `cancel` prevents fire; deinit is safe.
- `Tests/ZionTests/ThrottlerTests.swift` — AC 2 tests: first call fires immediately; calls during current collapse to exactly one follow-up; idle state runs follow-up.
- `Tests/ZionTests/AutoRevealTests.swift` — AC 5 + AC 6 tests.

### Files to modify
- `Sources/Zion/Services/FileWatcher.swift` — add `static func isFilteredNoisePath(_ path: String) -> Bool` that returns true if the path matches `.git/index.lock` suffix, a worktree `.git/worktrees/<name>/index.lock` pattern, a `.pack.tmp` suffix inside `.git/objects/pack/`, or contains `.watchman-cookie-`. Then in the FSEvents callback (line ~50 area) and in the test-seam `ingestForTesting(paths:)`, filter out noise paths BEFORE calling `classifyChangeEvent`. If after filtering no paths remain, skip the classify call entirely.
- `Sources/Zion/ViewModel/RepositoryViewModel.swift` — modify `selectedCodeFile` to trigger auto-reveal: add `didSet { revealSelectedCodeFileInTree() }`. Keep the existing assignment semantics intact (no re-entry — the reveal helper is sync and does not mutate `selectedCodeFile`).

### Dependencies between files
- `Debouncer.swift` and `Throttler.swift` depend only on `Foundation` (Task / Task.sleep).
- `FileWatcher.swift` depends on its own static regex detection; no cross-file changes.
- `RepositoryViewModel+AutoReveal.swift` depends on existing `+FileTree` extension (`pruneExpandedPaths`, `loadChildrenIfNeeded`) and on `selectedCodeFile` / `repositoryURL` / `expandedPaths` in the main ViewModel.

## Edge Cases
1. **Debouncer interval 0** — fires immediately on the next run loop turn. Useful for tests. `Task.sleep(nanoseconds: 0)` still yields.
2. **Throttler with rapid fire** — if 1000 calls come in during a 200ms window, the collapse-to-one-next rule keeps total executions at exactly 2 (current + one follow-up), not 1000.
3. **`isFilteredNoisePath` false positives** — a user file literally named `index.lock` outside `.git/` must NOT be filtered. Anchor the suffix to `.git/index.lock$` (allow worktree `.git/worktrees/<slug>/index.lock` too).
4. **Auto-reveal with file outside repo** — if `selectedCodeFile.url` is not a descendant of `repositoryURL`, no-op. Do not crash.
5. **Auto-reveal during bulk repo switch** — the snapshot restore path (`+SnapshotHelpers`) sets `selectedCodeFile` while restoring. That restore run should NOT trigger a reveal that contradicts the snapshot's own `expandedPaths`. Mitigation: the auto-reveal just adds ancestors to `expandedPaths` (a merge, not replace). If a restored expansion set already contains those ancestors, this is a no-op.
6. **Auto-reveal UI noise** — adding parents to `expandedPaths` re-fires the SwiftUI observation; if the tree is not currently visible (e.g. user on Graph tab), the expansion happens silently. No explicit visibility guard needed — SwiftUI only renders visible views.
7. **Throttler deinit with pending next** — cancel `current`, drop `next` without firing. Document explicitly.

## Out of Scope
- Retroactive rewrites of Wave 1 coalescer or Wave 2 idle gate to use the new Debouncer/Throttler primitives.
- Any change to the existing FileWatcher coalescer flush cadence (Wave 1) or the 200 ms grace (Wave 2).
- Any change to `pruneExpandedPaths` from Wave 1.
- Any UI surface for `autoRevealEnabled` (Settings toggle comes in a later UX pass — for now it is a silent default-on flag persisted in `UserDefaults`).
- Any change to editor code paths beyond observing `selectedCodeFile`.

## Builder Notes
- Prefer `didSet` on `selectedCodeFile` over Combine observers — the property is already `@Observable`, so a `didSet` runs synchronously on the same MainActor tick.
- `UserDefaults` key: `"code.autoReveal"`. Default true. Follow the known-bugs rule: NO `@AppStorage` inside `@Observable`; use a computed property backed by `UserDefaults.standard.bool(forKey:)`.
- The watcher filter regex should be fast — avoid `NSRegularExpression`. Use `hasSuffix`/`contains` on the lowercased path string. Match the VS Code approach of inline detection.
- Throttler implementation: the trickiest part is ensuring `next` is captured exactly once and drained when `current` completes. A simple pattern — when `current` ends, check `next`, move it to `current`, fire it — is sufficient. Swift Concurrency takes care of the rest.
- After all 8 tasks: `swift test` + `./scripts/make-app.sh`. Do not push or open a PR — stack on Wave 2 branch.
- Branch name: `perf/wave-3-primitives-polish` (already checked out).
