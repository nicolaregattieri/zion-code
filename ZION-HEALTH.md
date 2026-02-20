# ZION-HEALTH.md — Codebase Health Audit

Last updated: 2026-02-20

This document catalogs every known workaround, silent failure point, and architectural constraint in Zion. Developers modifying the codebase **must** consult this before changing any of the listed areas.

---

## 1. Critical Workarounds

### 1.1 GOLDEN RULE: `isDark` Must Always Return `true`

**File:** `Models.swift` (`EditorTheme.isDark`)

`EditorTheme.isDark` must ALWAYS return `true` for ALL themes, including light themes like GitHub Light. SwiftUI's internal compositing of `NSViewRepresentable` makes NSTextView text completely invisible when `isDark = false` in macOS dark mode.

**Pattern:** Two properties on `EditorTheme`:
- `isDark: Bool` — always `true` — controls NSTextView rendering context
- `isLightAppearance: Bool` — actual visual truth — controls SwiftUI UI styling

```swift
// Apply .light colorScheme ONLY to pure SwiftUI views, NEVER to SourceCodeEditor
editorToolbar
    .environment(\.colorScheme, theme.isLightAppearance ? .light : .dark)
```

### 1.2 NSTextView Rendering

**File:** `SourceCodeEditor.swift`

- Must use `NSTextView.scrollableTextView()` factory method
- `usesAdaptiveColorMappingForDarkAppearance = false` in `makeNSView`
- Always `drawsBackground = true` with explicit `backgroundColor`
- Use `NSColor(srgbRed:green:blue:alpha:)` for text attributes — NEVER bridge through `SwiftUI.Color -> NSColor`
- Apply `.paragraphStyle` AFTER highlighting via `addAttribute`, not inside `setAttributes`

### 1.3 @Observable Architecture

**File:** `RepositoryViewModel.swift`, all views

| Pattern | When |
|---------|------|
| `@State private var model` | Owner view (ContentView) |
| `@Bindable var model` | Child views needing `$model.property` bindings |
| `var model` | Child views that only read |

**Rules:**
- Never use `@StateObject` or `@ObservedObject` — those are for `ObservableObject`, not `@Observable`
- `@AppStorage` doesn't work in `@Observable` — use computed property with `UserDefaults` directly
- Use `@ObservationIgnored` on private implementation properties (git client, worker, tasks, file watchers)

### 1.4 Performance Caches (`didSet` Invalidation)

**File:** `RepositoryViewModel.swift`

| Cache | Trigger | Purpose |
|-------|---------|---------|
| `maxLaneCount` | `commits.didSet` → `recalculateMaxLaneCount()` | Avoids O(n) per row in graph |
| `flatFileCache` | `repositoryFiles.didSet` → `rebuildFlatFileCache()` | Avoids recomputation on every QuickOpen render |

These `didSet` hooks MUST remain in place. Removing them causes severe performance degradation.

### 1.5 HSplitView VStack Layout Bug

Pinning a view to the bottom of a VStack inside HSplitView is unreliable. `layoutPriority`, `safeAreaInset`, removing `frame(maxHeight: .infinity)` all fail.

**Fix:** Place the pinned view inside the ScrollView content with padding instead.

### 1.6 Terminal Login Shell

**File:** `TerminalSession.swift`

Terminal must be initialized as login shell (`-l`) with `TERM=xterm-256color`. Route all delegate callbacks to `DispatchQueue.main`.

---

## 2. Silent Failure Points

These catch blocks recover gracefully but produce **no user feedback**. The DiagnosticLogger now logs them all at `.warn` or `.info` level.

| File | Method | Line | What Happens on Error | Log Level |
|------|--------|------|----------------------|-----------|
| `RepositoryViewModel.swift` | `loadGitIgnoredPaths()` | ~459 | Returns empty set, files not filtered | warn |
| `RepositoryViewModel.swift` | `loadFiles(at:)` | ~493 | Returns empty array, file tree missing | warn |
| `RepositoryViewModel.swift` | `resolveStashReference()` | ~1283 | Falls back to raw value | warn |
| `RepositoryViewModel.swift` | `loadCommitDetails(for:)` | ~1465 | Shows error string in details pane | warn |
| `RepositoryViewModel.swift` | `loadDiff(for:)` | ~1487 | Shows error string in diff view | warn |
| `RepositoryViewModel.swift` | `loadDiffForCommitFile()` | ~1734 | Shows error string in diff view | warn |
| `RepositoryViewModel.swift` | `loadBlame(for:)` | ~1763 | Clears blame entries, shows status | warn |
| `RepositoryViewModel.swift` | `loadReflog()` | ~1858 | Clears reflog entries silently | warn |
| `RepositoryViewModel.swift` | `loadSubmodules()` | ~2033 | Clears submodules array | warn |
| `RepositoryViewModel.swift` | `loadSignatureStatuses()` | ~2293 | Clears signature dict | warn |
| `RepositoryViewModel.swift` | `checkBehindRemote()` | ~2327 | Resets count to 0 (expected if no upstream) | info |
| `RepositoryViewModel.swift` | `loadRepositoryStats()` | ~2392 | Clears stats to nil | warn |
| `FileWatcher.swift` | `watch(directory:)` | ~17 | `guard fd >= 0` silently returns | warn |

---

## 3. Architecture Notes

### 3.1 Adding a New Git Operation

1. Add a public method on `RepositoryViewModel`
2. Call `runGitAction(label:args:)` for simple commands — it handles busy state, error logging, and auto-refresh
3. For multi-step operations, use `actionTask = Task { ... }` with `worker.runAction()` and call `handleError()` in the catch block
4. The logger automatically traces `runGitAction` calls (command before, result/error after)

### 3.2 Adding a New View

1. Determine if it needs bindings → `@Bindable var model` or just reads → `var model`
2. Never use `@StateObject` or `@ObservedObject`
3. Add L10n keys to all 3 locale files (pt-BR, en, es)
4. Evaluate for keyboard shortcut, `.help()` tooltip, HelpSheet entry

### 3.3 Error Handling Pattern

```swift
// For catch blocks that recover silently, always log:
} catch {
    logger.log(.warn, "Description: \(error.localizedDescription)", context: relevantContext, source: #function)
    // ... existing recovery logic
}

// For catch blocks that surface to user, use handleError:
} catch {
    handleError(error)
    // handleError already logs at .error level
}
```

---

## 4. AI Integration Error Paths

### 4.1 AIError Enum

Defined in `AIClient.swift`: `noProvider`, `invalidAPIKey`, `invalidResponse`, `networkError`, `apiError`.

### 4.2 Fallback Chain

`suggestCommitMessage()`:
1. Try AI provider (Anthropic/OpenAI) → success
2. AI fails → fallback to `generateCommitMessage()` heuristic (diffStat + status parsing)
3. Heuristic fails → empty string

`suggestPRDescription()`, `suggestStashMessage()`, `explainFileDiff()`:
- No fallback — sets `lastError` on failure

### 4.3 Error Surfaces

- `lastError` → displayed in status bar
- `isGeneratingAIMessage` → spinner in UI
- DiagnosticLogger captures all AI requests and failures at `.ai` / `.error` level

---

## 5. Patterns That Must Not Be Broken

- [ ] `EditorTheme.isDark` always returns `true` (GOLDEN RULE)
- [ ] `@Observable` patterns: `@State` for owner, `@Bindable` for bindings, plain `var` for read-only
- [ ] `@ObservationIgnored` on all private implementation properties
- [ ] `commits.didSet` triggers `recalculateMaxLaneCount()`
- [ ] `repositoryFiles.didSet` triggers `rebuildFlatFileCache()`
- [ ] Terminal initialized with `-l` flag and `TERM=xterm-256color`
- [ ] `NSColor(srgbRed:...)` for text attributes, never `SwiftUI.Color -> NSColor`
- [ ] `usesAdaptiveColorMappingForDarkAppearance = false`
- [ ] `handleError()` logs to DiagnosticLogger
- [ ] `runGitAction()` traces commands to DiagnosticLogger
- [ ] Silent catch blocks log to DiagnosticLogger at `.warn` level
- [ ] L10n keys exist in all 3 locales for every user-visible string
