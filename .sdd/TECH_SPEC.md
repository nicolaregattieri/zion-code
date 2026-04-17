# Tech Spec: Performance Wave 2 (Operation Kind + Focus + Auto-Dispose)

## Goal
Reduce wasted CPU / log noise and build the foundation for future optimistic paths by absorbing three VS Code Git extension patterns: (1) tipified `Operation` kind with flags (`{ readOnly, blocking, remote, showProgress }`), (2) idle + window-focus gate on file-watcher-driven `refreshRepository`, and (3) auto-dispose repository state when git reports `NotAGitRepository`.

## Context & Motivation
Reference: `docs/VSCODE_GIT_LEARNINGS.md` (written in Wave 1). Matching VS Code source:
- Operation kind + `OperationManager` → `extensions/git/src/operation.ts` and `repository.ts:2695` (the `run<T>()` choke point).
- Idle + focus gate → `repository.ts:3186-3213` (`eventuallyUpdateWhenIdleAndWait` + `whenIdleAndFocused`).
- Auto-dispose on `NotAGitRepository` → `repository.ts:2721` (`this.state = RepositoryState.Disposed`).

Observable today:
- Every git subcommand goes through `runGitAction` with only a `String` label. There is no way to ask "is a commit currently running?" for UI gating or to know whether a reload is safe to skip. Optimistic-path work in Wave 1 needed ad-hoc closures as a workaround.
- `refreshRepository(origin: .fileWatcher)` fires while Zion window is in the background, wasting CPU and battery.
- Opening a folder without `.git` (e.g. `~/Developer/liquid-flow-agent` in the runtime log) produces three warns per switch: `Failed to load submodules`, `Failed to load gitignored paths`, `Repo memory refresh failed` — each caused by a git command returning `fatal: not a git repository`. The repo state is never marked as not-a-git-repo, so subsequent watcher events keep trying.

## Constraints
- Language: Swift 6.2; framework: SwiftUI `@Observable`, SwiftPM executable `Zion`, macOS 14+.
- Test runner: `swift test` (`ZionTests` in `Tests/ZionTests/`).
- Dependencies: no new external deps. Uses `AppKit.NSApp.isActive` for window-focus detection and `NSApplication.didBecomeActiveNotification` / `willResignActiveNotification` observation.
- Boundaries:
  - Must NOT change the public `runGitAction` signature's existing positional parameters (the `onFailure` closure added in Wave 1 stays). New parameters have default values.
  - Must NOT change the destructive-op pre-snapshot pattern (`zion-pre-*` stashes).
  - Must NOT break any Wave 1 behavior (stage/unstage/discard optimistic UI, FileWatcher coalescer, `GIT_OPTIONAL_LOCKS=0`, expansion prune).
  - Must NOT alter editor, terminal, SwiftTerm, Sparkle, or mobile remote code paths.
  - Must use `L10n("key")` for any new user-facing string (dot-notation key, added to `en.lproj`, `pt-BR.lproj`, `es.lproj`).
  - Timing/limit constants go through `Constants.Timing.*` / `Constants.Limits.*`.

## Reuse
- `Sources/Zion/ViewModel/RepositoryViewModel+Git.swift` — central `runGitAction` (gained `onFailure` param in Wave 1); `refreshStatusOnly`; `refreshRepository(setBusy:options:origin:...)` call sites.
- `Sources/Zion/ViewModel/RepositoryViewModel.swift` — `@Observable` class; `@ObservationIgnored` private stored state; `isGitRepository: Bool` already exists (line 104) — piggy-back the auto-dispose state on that plus a new `isRepositoryDisposed` flag.
- `Sources/Zion/ViewModel/RepositoryViewModel+SnapshotHelpers.swift` — hosts `startFileWatcher(for:)` (line 599 area) where watcher callbacks fire `refreshRepository(origin: .fileWatcher)`. This is the injection site for the idle+focus gate.
- `Sources/Zion/Services/RepositoryWorker+Execution.swift` — `runAction`, `runActionAllowingFailure`, `runActionWithStdin`. For auto-dispose, inspect the stderr of failed calls and detect `fatal: not a git repository` to propagate a typed error.
- `Sources/Zion/Services/GitClient*.swift` — existing `GitClientError` enum is the natural home for a new `.notAGitRepository` case. Grep for the enum definition; add a case.
- `Sources/Zion/Helpers/Constants.swift` — `Constants.Timing.*` (add `refreshRepositoryIdleGrace: UInt64 = 200_000_000 // 200ms`).

## Acceptance Criteria
1. `Operation` enum exists with at least these cases wired through `runGitAction`: `status`, `add`, `commit`, `restore` (discard), `fetch`, `push`, `stash`, `checkout`, `merge`, `rebase`, `reset`, `revert`, `tag`, `branch`, `cloning`, `remote`, `log`, `diff`, `show`, `other(String)`. Every case has a statically-known `kind`, `readOnly`, `blocking`, `remote`, `showProgress` flag value. Verify: `swift test --filter ZionTests.OperationKindTests/testAllCasesHaveKnownFlags`.
2. `OperationManager` tracks currently-running operations and exposes `isIdle`, `isRunning(_ kind: OperationKind) -> Bool`, and `shouldShowProgress() -> Bool`. Verify: `swift test --filter ZionTests.OperationManagerTests/testIsIdleTogglesCorrectly`.
3. `runGitAction` accepts an `operation: Operation` parameter (defaulted to `.other(label)` for back-compat with existing callers); start/end the manager on begin/finish. Verify: `swift test --filter ZionTests.OperationManagerTests/testRunGitActionStartsAndEndsOperation`.
4. At least the four Wave 1 staging/discard call sites and the `refreshStatusOnly` / `fetch` / `push` / `pull` / `commit` paths pass an explicit `Operation` case (not `.other(label)`) so they participate in `isRunning(_:)` correctly. Verify: `grep -c 'operation: \.' Sources/Zion/ViewModel/RepositoryViewModel+*.swift` returns at least `10`.
5. `refreshRepository(origin: .fileWatcher)` is gated by idle + focus — while `NSApp.isActive == false` OR any non-read-only operation is running, the refresh request is **deferred** (not dropped). When the app becomes active and the manager reports `isIdle`, the latest deferred request fires exactly once. Multiple deferred requests during the gated period coalesce to one. Verify: `swift test --filter ZionTests.IdleFocusGateTests`.
6. User-initiated refreshes (`origin: .userInitiated`) and repository-switch refreshes (`origin: .repositorySwitch`) BYPASS the gate — they always run immediately. Regression guard. Verify: `swift test --filter ZionTests.IdleFocusGateTests/testUserInitiatedBypassesGate`.
7. When any `runAction` fails with stderr matching `fatal: not a git repository`, the worker throws `GitClientError.notAGitRepository`. Verify: `swift test --filter ZionTests.GitClientErrorTests/testNotAGitRepositoryDetection`.
8. On receiving `GitClientError.notAGitRepository`, the ViewModel sets `isGitRepository = false` AND marks the repo state disposed (new `@ObservationIgnored var isRepositoryDisposed: Bool`); further watcher events and scheduled refreshes exit early; no more warns from `loadSubmodules`, `loadGitIgnoredPaths`, or `refreshRepoMemory` for the same repo during that session. Verify: `swift test --filter ZionTests.AutoDisposeTests`.
9. Reopening a repository URL that was previously disposed **clears** the disposed flag and retries detection (so a `git init` done externally is picked up). Verify: `swift test --filter ZionTests.AutoDisposeTests/testReopenClearsDisposedFlag`.
10. Full suite: `swift test` exits 0 (should stay at 903 baseline plus the new tests, zero pre-existing regressions).
11. Build artifact: `./scripts/make-app.sh` exits 0 and produces `dist/Zion.app`.

## Architecture

### Files to create
- `Sources/Zion/Services/Operation.swift` — hosts `enum OperationKind` and `struct Operation` with the static flags. Keep flat: one file per domain.
- `Sources/Zion/Services/OperationManager.swift` — `@MainActor final class OperationManager` that tracks active operations via a `[OperationKind: Int]` reference count (some kinds — like `status` — can fire in overlap). Exposes `start(_:)`, `end(_:)`, `isRunning(_:)`, `isIdle`, `shouldShowProgress()`. Instance lives on `RepositoryViewModel` as `@ObservationIgnored let operations: OperationManager`.
- `Sources/Zion/ViewModel/RepositoryViewModel+IdleFocusGate.swift` — implements the gate: a single `pendingFileWatcherRefresh: Bool` flag plus observation of `NSApplication.didBecomeActiveNotification`; when fire conditions are met, call `refreshRepository(origin: .fileWatcher)` exactly once, then clear the flag. Register the observer in `RepositoryViewModel.init` (add a call there) or lazily on first watcher event. Prefer lazy to keep init lean.
- `Sources/Zion/ViewModel/RepositoryViewModel+AutoDispose.swift` — exposes `markRepositoryDisposed(reason:)` and the short-circuit checks `shouldSkipBecauseDisposed()` called from `refreshRepository`, `loadSubmodules`, `loadGitIgnoredPaths`, `refreshRepoMemory`, file-watcher callback fan-out. On `openRepository(_:silent:)`, clear the flag for the new URL.
- `Tests/ZionTests/OperationKindTests.swift` — AC 1 (flags table). Table-driven: every `OperationKind` case has expected `readOnly/blocking/remote/showProgress` asserted.
- `Tests/ZionTests/OperationManagerTests.swift` — AC 2 + AC 3 (isIdle toggle; runGitAction wraps start/end correctly; refcount handles overlap).
- `Tests/ZionTests/IdleFocusGateTests.swift` — AC 5 + AC 6 (deferred while inactive/busy; coalesces; fires once on activation; user-initiated bypasses).
- `Tests/ZionTests/GitClientErrorTests.swift` — AC 7 (stderr match → typed error). Drive via a mock/stub stderr string, not a real git call.
- `Tests/ZionTests/AutoDisposeTests.swift` — AC 8 + AC 9 (dispose on error; short-circuits subsequent calls; reopen clears).

### Files to modify
- `Sources/Zion/Helpers/Constants.swift` — add `static let refreshRepositoryIdleGrace: UInt64 = 200_000_000 // 200ms` in `enum Timing`.
- `Sources/Zion/Services/RepositoryWorker+Execution.swift` — in the existing `Process` stream path (line 85+), when the process exits non-zero and stderr begins with `fatal: not a git repository`, throw `GitClientError.notAGitRepository` instead of the generic failure.
- `Sources/Zion/Services/GitClient*.swift` — add `case notAGitRepository` to `GitClientError`. Match L10n convention: add a new localized key `error.notAGitRepository = "Not a git repository."` + PT-BR + ES equivalents.
- `Sources/Zion/ViewModel/RepositoryViewModel.swift` — add `@ObservationIgnored let operations = OperationManager()` (line ~100 alongside other service members) and `@ObservationIgnored var isRepositoryDisposed: Bool = false`. Provide `@MainActor` `markRepositoryDisposed(reason: String)` that sets `isGitRepository = false`, sets `isRepositoryDisposed = true`, logs the reason via `DiagnosticLogger`.
- `Sources/Zion/ViewModel/RepositoryViewModel+Git.swift` — `runGitAction` gains `operation: Operation = .other(label)` parameter (the existing `label` stays for log continuity). In the `try` path, call `self.operations.start(operation)` before the work and `self.operations.end(operation)` in `defer`. In the `catch` path, inspect the thrown error — if it's `GitClientError.notAGitRepository`, call `markRepositoryDisposed(reason: "runGitAction: not a git repo")` before surfacing.
- `Sources/Zion/ViewModel/RepositoryViewModel+SnapshotHelpers.swift` — `startFileWatcher(for:)` callback currently calls `refreshRepository(origin: .fileWatcher)` directly. Route through a new `requestFileWatcherRefresh()` on the IdleFocusGate extension. Also guard with `guard !isRepositoryDisposed else { return }`.
- `Sources/Zion/ViewModel/RepositoryViewModel+Git.swift` + any extension that calls `loadSubmodules`, `loadGitIgnoredPaths`, `refreshRepoMemory` — prepend `guard !isRepositoryDisposed else { return }` (or equivalent). Must not regress the normal-repo flow.
- Update all call sites to `runGitAction` in the ViewModel extensions to pass a concrete `operation: Operation` — start with `refreshStatusOnly`, `commit`, `fetch`, `push`, `pull`, `stageFile`, `unstageFile`, `stageAllFiles`, `unstageAllFiles`, `discardChanges(in:)`. Rest can keep the `.other(label)` default.
- `Resources/en.lproj/Localizable.strings` + `Resources/pt-BR.lproj/Localizable.strings` + `Resources/es.lproj/Localizable.strings` — add `"error.notAGitRepository"` key with the translated strings.

### Dependencies between files
- `Operation.swift` and `OperationManager.swift` have no cross-dep beyond `Foundation`.
- `RepositoryViewModel+AutoDispose.swift` depends on `GitClientError.notAGitRepository` and on `RepositoryViewModel.markRepositoryDisposed`.
- `RepositoryViewModel+IdleFocusGate.swift` depends on `AppKit` (for `NSApp`), on `OperationManager`, and on the existing `refreshRepository` entry point.
- Watcher callbacks in `+SnapshotHelpers` depend on both the gate and the auto-dispose guard.
- Test files each `@testable import Zion`.

## Edge Cases
1. **Rapid app activate / resign bursts** — observer must debounce itself. Use a simple latch: when `willResignActiveNotification` fires, drop any pending one-shot gate task; when `didBecomeActiveNotification` fires and `pendingFileWatcherRefresh == true` AND `operations.isIdle`, schedule the refresh through `DispatchQueue.main.asyncAfter(wallDeadline: .now() + 0.2)` — the 200 ms grace prevents thrash if user resigns immediately again.
2. **Operation that runs across many small subprocesses** (e.g. a big `fetch` that internally loops) — reference count on `start(_:)` / `end(_:)`. `isIdle` is true only when ALL counts are zero.
3. **Repo becomes a git repo after `git init`** — user runs `git init` externally. Zion does not observe `.git/HEAD` creation inside a disposed repo (watcher is still active for the non-git folder). Solution: on `openRepository(_:silent:)`, always clear the disposed flag and do a one-time detection retry. Already covered by AC 9.
4. **`fatal: not a git repository` returned by a non-status command** (e.g. `submodule` query) — should dispose just the same; the detection is stderr-based, not command-specific.
5. **User-initiated refresh while disposed** — treat as an explicit retry. Clear the disposed flag and attempt the refresh. If it fails again with `.notAGitRepository`, re-dispose. This is the "reload" escape hatch.
6. **`OperationManager.isIdle` during bootstrap** — before any `start(_:)` call, `isIdle` is `true`; tests that rely on this must not pre-fire a dummy operation.
7. **Notification observer retain cycle** — use `[weak self]` in the observer block. Unregister in `deinit` of the ViewModel (if not already).
8. **Running a command like `git -C <non-repo> log` returns exit 128 with stderr about `fatal: not a git repository`** — our detection matches this substring anywhere in stderr, not only at the start. Use `contains("fatal: not a git repository")`.

## Out of Scope
- Swift `@throttle` / `@debounce` property wrapper primitives (Wave 3).
- Watcher regex filter for `.git/index.lock` and `*.pack.tmp` (Wave 3).
- `autoReveal` parity check (Wave 3).
- Any refactor of existing destructive-op pre-snapshot pattern.
- Any change to mobile remote (`openRepository(_:silent:)` bulk path) beyond clearing the disposed flag on reopen.
- Any change to optimistic staging/discard logic from Wave 1.
- Any new progress-indicator UI — `shouldShowProgress()` returns the flag, but wiring it to a spinner is deferred.

## Builder Notes
- Start Wave 2 tasks with `Operation.swift` + `OperationManager.swift` first — everything else builds on top.
- Observing `NSApp` notifications requires importing `AppKit`. Guard with `#if os(macOS)` if the file would otherwise be cross-platform (Zion is macOS-only today so the guard is optional but idiomatic).
- For auto-dispose, the stderr inspection lives in the lowest Process-run layer (`RepositoryWorker+Execution.swift`), not in the ViewModel. The ViewModel only reacts to the typed error.
- When adding `Operation` cases, prefer enum-with-associated-values for string labels (e.g. `case checkout(refLabel: String)`) only where the label is needed downstream. Otherwise plain cases. Match VS Code's style but do not port every single case (ref `extensions/git/src/operation.ts` — pick the ~20 most common; use `.other(String)` for the rest).
- L10n: any new user-facing string uses `L10n("error.notAGitRepository")` and must be added to all 3 locale files. Do NOT reuse existing Portuguese-keyed strings.
- After implementation: `swift test` and `./scripts/make-app.sh`. Do not push or open a PR — keep it local until the user reviews.
- Branch name: `perf/wave-2-ops-and-focus` (already checked out, stacked on Wave 1).
