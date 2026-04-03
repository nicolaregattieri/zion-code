# Zion Performance PRD

> Generated: 2026-04-03
> Baseline: 400MB RAM, 35% CPU at launch, ~5-10% idle
> Benchmark: Antigravity at 132MB RAM, 1.2% CPU idle

---

## 1. System Overview

### Architecture Summary

Zion is a 57K-line native macOS Git client built with Swift/SwiftUI. The architecture centers on a single **god object** -- `RepositoryViewModel` (693 lines of properties + 35 extension files totaling 12,519 lines) -- that owns everything: git state, editor state, terminal sessions, AI services, clipboard, remote access, PR data, bridge state, and 38+ UserDefaults-synced settings.

Every view in the app reads from this one `@Observable` object, meaning a change to *any* observable property triggers re-evaluation across the entire view tree.

### Main Performance Bottlenecks

| Category | Issue | Impact |
|----------|-------|--------|
| **Architecture** | Single @Observable god object with ~170 properties | Every property mutation invalidates 50+ views |
| **Startup** | 8+ git commands + terminal spawn + 4 timers fire simultaneously | 35% CPU spike, 400MB within seconds |
| **Memory** | Unbounded caches (snapshots, reviews, buffers) with no eviction | Memory grows monotonically, never shrinks |
| **CPU at idle** | 6+ concurrent polling timers (1.5s to 120s intervals) | Sustained 3-5% CPU doing nothing |
| **SwiftUI** | All 3 main screens kept alive via opacity toggling (not conditional) | Invisible screens still redraw on model changes |
| **Git processes** | No queuing/concurrency limit; up to 15+ simultaneous git processes on refresh | Process spawn overhead + pipe allocation |
| **deinit gaps** | Only 4 of 30+ Task properties cancelled in deinit | Zombie tasks retain closures + captured state |

### Risk Areas

- **Memory**: Terminal output buffers, repository switch snapshots, diff caches, avatar cache -- all unbounded
- **CPU**: Clipboard polling, auto-refresh, background fetch, PR polling, file watcher -- all running at idle
- **UI**: `uncommittedChanges` array mutation triggers 50+ view re-evaluations; `currentFileDiffLines` computed property recomputes on every access
- **Lifecycle**: 132 Task{} creations across 28 files; only a fraction properly cancelled

---

## 2. Performance Goals

| Metric | Current (Estimated) | Target | How to Measure |
|--------|---------------------|--------|----------------|
| Idle RAM | ~400MB | <180MB | Activity Monitor after 60s idle |
| Idle CPU | ~5-10% | <1% | Activity Monitor after 60s idle |
| Startup CPU spike | 35% for ~5s | <15% for <2s | Instruments Time Profiler |
| Git processes per refresh | 8-12 simultaneous | 3-5 sequential | Count Process() in logs |
| View re-evaluations per model change | 50+ views | <10 views | SwiftUI Instruments |
| Time to interactive after launch | ~4s | <1.5s | Stopwatch from icon click to usable UI |

---

## 3. Optimization Strategy

### A. Memory (Target: -200MB)

| ID | Issue | Fix | Est. Savings |
|----|-------|-----|-------------|
| M-1 | `repositorySwitchSnapshots` never evicted (TTL exists but unused) | Enforce TTL eviction after each snapshot read | 15-40MB |
| M-2 | `commitReviewCache` unbounded dictionary | Convert to LRU with cap=32 | 5-20MB |
| M-3 | `avatarCache` NSCache has no size limit | Set `totalCostLimit = 10MB`, `countLimit = 200` | 5-15MB |
| M-4 | `terminalOutputBuffers` never cleared | Clear per-session buffer after flush; cap at 1MB per session | 20-80MB |
| M-5 | `backgroundRepoStates` accumulate terminal sessions | Evict states for repos not in recent list | 20-50MB |
| M-6 | LRUCache.set() uses O(n) `removeAll` scan | Use linked list or move-to-end pattern | CPU + allocation |
| M-7 | `currentFileDiffLines` recomputes on every access | Cache as stored property, invalidate on `currentFileDiff` didSet | Repeated allocs |
| M-8 | deinit only cancels 4 of 30+ tasks | Cancel ALL task properties in deinit | 10-30MB zombie tasks |
| M-9 | `previousPRTitles`, `avatarDownloadTasks`, `commitSignatureStatus` unbounded | Add eviction or convert to LRU | 2-5MB |
| M-10 | `ignoredPathsCacheByRepository` TTL never enforced | Enforce TTL on access | 5-10MB |

### B. CPU (Target: -80% idle CPU)

| ID | Issue | Fix | Est. Savings |
|----|-------|-----|-------------|
| C-1 | ClipboardMonitor polls every 1.5s | Use `NSPasteboard.changeCount` check only; increase to 3s | Minor but constant |
| C-2 | Auto-refresh every 60s runs full `refreshRepository()` | Make auto-refresh lightweight (status only, skip if no changes) | 100-200ms/min |
| C-3 | Background fetch every 120s runs `git fetch --all --prune` | Check `git ls-remote` for new refs first; only full fetch if changed | 500ms-2s/cycle |
| C-4 | `recalculateMaxLaneCount()` iterates all commits on main thread | Compute during graph layout (already iterating), not separately | 5-20ms/refresh |
| C-5 | File tree: double enumeration (once without gitignore, once with) | Cache gitignored paths aggressively; single pass | 50-100ms/refresh |
| C-6 | Diff hunk parser uses regex twice per `@@` line | Single-pass integer extraction | 10-50ms/large diff |
| C-7 | Branch search: one `git log -1` per branch (100 branches = 100 processes) | Single `git log` with multiple refs | 90% reduction |

### C. UI Rendering (Target: -80% unnecessary redraws)

| ID | Issue | Fix | Est. Savings |
|----|-------|-----|-------------|
| U-1 | All 3 screens (Code/Graph/Ops) kept alive via opacity, redraw when invisible | Use conditional `if/switch` to destroy inactive screens | 30-40% fewer redraws |
| U-2 | `uncommittedChanges` array mutation redraws 8+ views including file tree | Pre-compute `uncommittedPathsSet: Set<String>` on model; FileTreeNodeView does O(1) lookup instead of O(n) scan | Major for large repos |
| U-3 | `OpsCommitCard` uses ScrollView+VStack instead of LazyVStack | Replace with LazyVStack | Fixes 50+ eager renders |
| U-4 | CommitRowView has 8 graphic layers (overlays, backgrounds, shapes) per row | Consolidate into 2-3 layers using Canvas or combined Shape | Smoother scrolling |
| U-5 | ContentView has 11 `.sheet()` modifiers evaluated sequentially | Consolidate to single `.sheet(item:)` with enum | Fewer modifier evaluations |
| U-6 | 11 `.onReceive(UserDefaults.didChangeNotification)` fires for ANY default | Filter to relevant keys only | Fewer spurious redraws |

### D. Startup (Target: <1.5s to interactive)

| ID | Issue | Fix | Est. Savings |
|----|-------|-----|-------------|
| S-1 | Terminal shell spawned immediately on repo open | Defer terminal creation until Code tab's terminal pane is visible | 20-50MB + 200ms |
| S-2 | All background timers start simultaneously in `finalizeRepositorySwitch` | Stagger: auto-refresh at +30s, fetch at +60s, PR polling at +120s | Spread CPU load |
| S-3 | 300 commits loaded with full graph calculation on first refresh | Load 50 commits initially, paginate on scroll | 200-500ms faster |
| S-4 | `loadSignatureStatuses()` runs on every repo open | Defer until user scrolls to commit or opens detail | 50-200ms |
| S-5 | `loadBridgeState()` runs on every repo open | Defer until Bridge tab is accessed | 20-50ms |

### E. Background Processes (Target: near-silent idle)

| ID | Issue | Fix | Est. Savings |
|----|-------|-----|-------------|
| B-1 | 6 timers running at idle with no app-backgrounded check for all | Add `NSApp.isActive` guard to clipboard and terminal coordinator | Fewer wakeups |
| B-2 | File watcher debounce at 350ms, FSEvents at 250ms | Increase FSEvents latency to 1.0s, debounce to 500ms | Fewer wakeups |
| B-3 | Inactive repo burst mode at 15s for 30s after any file change | Increase burst to 30s interval, 60s window | Fewer git status calls |

### F. Resource Lifecycle (Target: zero leaks)

| ID | Issue | Fix | Est. Savings |
|----|-------|-----|-------------|
| L-1 | deinit cancels only 4 tasks: `deferredRepositoryLoadTask`, `autoRefreshTask`, `prPollingTimer`, `fileWatcherGateTask` | Add ALL 30+ task properties to deinit cancellation | Prevent zombie tasks |
| L-2 | TerminalView installs 5 NSEvent monitors; cleanup conditional on coordinator ownership | Always remove monitors in `dismantleNSView` | Prevent global event tap accumulation |
| L-3 | Notification observers in TerminalView only removed in `killProcess()` | Remove in `dismantleNSView` | Prevent observer accumulation |

---

## 4. UX Constraints

- **Terminal state must survive tab switches** -- cannot destroy Code screen if terminal has running processes. (Note: U-1 needs a carve-out for terminal; destroy Graph/Ops only.)
- **Repository switch must feel instant** -- snapshot restore pattern is correct; don't break it.
- **Auto-fetch keeps badges current** -- don't remove, just make smarter (check before fetch).
- **File watcher gives "live" feel** -- don't remove, just tune intervals.
- **Clipboard monitor is a feature** -- don't remove, just make cheaper.

Reference points:
- **Xcode**: ~200MB for a medium project, <1% CPU at idle
- **VS Code**: ~300MB (Electron), but 0.1% CPU at idle via event-driven architecture
- **Antigravity**: 132MB, 1.2% CPU -- the direct competitor benchmark

---

## 5. Risk Analysis

### Safe to Change (Low Risk)
- Timer intervals (Constants.swift)
- Cache eviction policies (adding limits to existing caches)
- deinit task cancellation (adding missing cancels)
- `currentFileDiffLines` caching (purely internal)
- LRUCache implementation (internal struct, no external API)
- NSCache configuration (totalCostLimit/countLimit)
- FSEvents latency parameter

### Moderate Risk
- Deferring terminal creation (must still work when user switches to terminal)
- Reducing initial commit count (must still show meaningful history)
- Staggering background timers (must not break fetch/PR badge timing)
- Opacity-to-conditional screen switching (terminal state preservation)

### Must NOT Touch
- Repository switch snapshot/restore mechanism
- FileWatcher event classification logic
- Terminal session stashing/restoration (`backgroundRepoStates` swap pattern)
- Git credential flow
- Remote access server handshake
- Any `@MainActor` annotations (removing could cause data races)

---

## 6. Task Breakdown

### PERF-001: Cache `currentFileDiffLines` instead of recomputing on every access

**Scope:**
- `RepositoryViewModel.swift` (lines 108-111)

**Problem:**
`currentFileDiffLines` is a computed property that calls `.split()` + `.map(String.init)` on every access. For a 100KB diff, this allocates thousands of String objects each time any view reads it.

**Solution:**
Convert to stored property. Invalidate in `currentFileDiff` didSet.

**Implementation Steps:**
1. Replace computed `currentFileDiffLines` with stored `var currentFileDiffLines: [String] = []`
2. Add didSet to `currentFileDiff` that recalculates `currentFileDiffLines`

**Safety Checks:**
- Grep all usages of `currentFileDiffLines` to ensure no write dependency
- Build succeeds
- Diff view displays correctly

**Expected Impact:** Eliminates repeated O(n) allocations on every view access

**Risk Level:** Low

---

### PERF-002: Add missing task cancellations to deinit

**Scope:**
- `RepositoryViewModel.swift` (lines 673-692)

**Problem:**
deinit only cancels 4 of 30+ stored Task properties. Missing: `refreshTask`, `detailsTask`, `actionTask`, `blameTask`, `reflogTask`, `bisectTask`, `bridgeAnalysisTask`, `prTask`, `codeReviewTask`, `explainDiffTask`, `submoduleTask`, `aiTask`, `repoMemoryTask`, `signatureStatusTask`, `backgroundFetchTask`, `heartbeatTask`, `remoteAccessStartupTask`, `remoteAccessTunnelTask`, `sleepTimerTask`, `fileHistoryTask`, `recoverySnapshotsTask`, `conflictTask`, `commitStatsTask`, `cloneTask`, `pushPreflightTask`, `busyWatchdogTask`, `prPollingTask`, `gitSearchTask`, `editorSymbolIndexTask`, `zenResumeTask`, `pendingSummaryTask`.

**Solution:**
Cancel all stored task properties in deinit.

**Implementation Steps:**
1. Add every `Task<Void, Never>?` property to the deinit cancellation block
2. Group logically (git tasks, AI tasks, remote tasks, etc.)

**Safety Checks:**
- Build succeeds
- No functional change (deinit only fires when ViewModel is deallocated)

**Expected Impact:** Prevents 30+ zombie tasks from retaining closures and captured state after ViewModel deallocation. Estimated 10-30MB savings.

**Risk Level:** Low

---

### PERF-003: Enforce repository switch snapshot TTL eviction

**Scope:**
- `RepositoryViewModel+SnapshotHelpers.swift` (line 101-128)
- `RepositoryViewModel.swift` (line 611, 614)

**Problem:**
`repositorySwitchSnapshots` dictionary grows unbounded. The TTL (`repositorySwitchSnapshotTTL = 5s`) exists but is only checked on read -- stale entries are never removed.

**Solution:**
Evict expired snapshots after each capture, and limit total snapshot count.

**Implementation Steps:**
1. In `captureRepositorySnapshot`, after storing the new snapshot, iterate and remove entries older than a generous TTL (e.g., 60s)
2. Cap total snapshots at 5 most recent (by `capturedAt`)

**Safety Checks:**
- Rapid repo switching still works (snapshot restore within 5s window)
- No crash on missing snapshot (existing guard handles nil)

**Expected Impact:** 15-40MB savings for users who switch between many repos

**Risk Level:** Low

---

### PERF-004: Configure `avatarCache` NSCache limits

**Scope:**
- `RepositoryViewModel.swift` (line 148)

**Problem:**
`NSCache<NSString, NSImage>()` created with no `totalCostLimit` or `countLimit`. Grows unbounded as user scrolls through commits with different authors.

**Solution:**
Set `countLimit = 200` and `totalCostLimit = 10 * 1024 * 1024` (10MB).

**Implementation Steps:**
1. After `avatarCache` initialization, set both limits
2. When storing images, pass estimated byte cost

**Safety Checks:**
- Avatars still display correctly
- Cache eviction doesn't cause visible flicker (NSCache evicts under memory pressure anyway)

**Expected Impact:** 5-15MB cap on avatar memory

**Risk Level:** Low

---

### PERF-005: Pre-compute `uncommittedPathsSet` for O(1) file tree lookups

**Scope:**
- `RepositoryViewModel.swift` (add new property)
- `FileTreeNodeView.swift` (line ~12-25 where `isModified` is computed)

**Problem:**
`FileTreeNodeView` computes `isModified` by scanning the entire `uncommittedChanges` array with string operations (`contains`, `hasSuffix`) for every file in the tree. With 200 files and 50 changes, this is 10,000 string comparisons per redraw.

**Solution:**
Add a derived `Set<String>` property on ViewModel that's updated when `uncommittedChanges` changes. FileTreeNodeView does O(1) Set lookup.

**Implementation Steps:**
1. Add `@ObservationIgnored var uncommittedPathsSet: Set<String> = []` and `@ObservationIgnored var uncommittedDirectoryPrefixes: Set<String> = []`
2. In `uncommittedChanges` didSet, recompute both sets
3. Update FileTreeNodeView to use the sets

**Safety Checks:**
- Modified file indicators still show correctly
- Modified directory indicators still show correctly

**Expected Impact:** O(1) lookups instead of O(n) scans per file node. Major improvement for large repos.

**Risk Level:** Low

---

### PERF-006: Stagger background timer startup

**Scope:**
- `RepositoryViewModel+SnapshotHelpers.swift` `finalizeRepositorySwitch()` (lines 397-409)
- `RepositoryViewModel+BackgroundRepos.swift` (auto-refresh timer)
- `RepositoryViewModel+RemoteSync.swift` (background fetch, PR polling)

**Problem:**
`finalizeRepositorySwitch` starts all background timers simultaneously: `startPRPollingTimer()`, `startBackgroundFetch()`, `startAutoRefreshTimer()`. Combined with the initial refresh, this creates a thundering herd of git operations.

**Solution:**
Add initial delays: auto-refresh starts after 45s, background fetch after 30s, PR polling after 90s.

**Implementation Steps:**
1. Increase `startAutoRefreshTimer` initial sleep to 45s
2. Increase `startBackgroundFetch` initial sleep to 30s
3. Increase `startPRPollingTimer` initial sleep to 90s

**Safety Checks:**
- Timers still fire correctly after initial delay
- No visual regression (badges appear with slight delay, acceptable)

**Expected Impact:** Spreads startup CPU over 90s instead of concentrating in first 15s

**Risk Level:** Low

---

### PERF-007: Increase FSEvents latency and file watcher debounce

**Scope:**
- `FileWatcher.swift` (line 29: debounce, line 60: FSEvents latency)

**Problem:**
FSEvents fires at 250ms latency, debounce is 350ms. This is aggressive for a Git client where sub-second file change response isn't critical.

**Solution:**
Increase FSEvents latency to 1.0s, debounce to 750ms.

**Implementation Steps:**
1. Change line 60: `0.25` to `1.0`
2. Change line 29: `350_000_000` to `750_000_000`

**Safety Checks:**
- File changes still detected within ~2s
- UI still feels responsive after saving files

**Expected Impact:** ~60% fewer wakeups from file system monitoring

**Risk Level:** Low

---

### PERF-008: Replace OpsCommitCard ScrollView+VStack with LazyVStack

**Scope:**
- `OpsCommitCard.swift` (lines ~31-42)

**Problem:**
File change list uses `ScrollView { VStack { ForEach } }` -- renders all items eagerly even though only 5-10 fit in the 160pt frame.

**Solution:**
Replace `VStack` with `LazyVStack`.

**Implementation Steps:**
1. Change `VStack` to `LazyVStack` inside the ScrollView

**Safety Checks:**
- File list still scrolls correctly
- Selection/interaction still works
- Visual appearance unchanged

**Expected Impact:** With 50+ uncommitted files, renders only visible ~10 instead of all 50+

**Risk Level:** Low

---

### PERF-009: Add eviction to `commitReviewCache`

**Scope:**
- `RepositoryViewModel.swift` (line 268)

**Problem:**
`commitReviewCache: [String: [ReviewFinding]] = [:]` grows unbounded as user reviews commits. Never cleared except on repo switch.

**Solution:**
Replace with LRUCache of capacity 32.

**Implementation Steps:**
1. Change type to `LRUCache<String, [ReviewFinding]>(capacity: 32)`
2. Update all access sites to use `.get()` / `.set()` instead of subscript

**Safety Checks:**
- AI review findings still display correctly
- Cache miss just triggers fresh review (existing behavior for uncached commits)

**Expected Impact:** Caps review cache at 32 entries instead of unbounded growth

**Risk Level:** Low

---

### PERF-010: Improve LRUCache efficiency (O(n) to O(1) dedup)

**Scope:**
- `LRUCache.swift` (line 20)

**Problem:**
`order.removeAll { $0 == key }` is O(n) on every `.set()`. With 96-entry diff cache, this scans 96 elements per insert.

**Solution:**
Track position with a Dictionary for O(1) existence check; only do linear removal when key exists.

**Implementation Steps:**
1. Add `private var keySet: Set<Key> = Set()` for O(1) contains check
2. Only call `order.removeAll { $0 == key }` when `keySet.contains(key)`
3. Maintain keySet on insert/evict/clear

**Safety Checks:**
- Cache behavior unchanged (same eviction order, same capacity)
- Build succeeds

**Expected Impact:** Cache operations go from O(n) to amortized O(1) for new keys

**Risk Level:** Low

---

### PERF-011: Defer terminal creation until terminal pane is visible

**Scope:**
- `RepositoryViewModel+SnapshotHelpers.swift` (line 256: `createDefaultTerminalSession`)

**Problem:**
Every repository open immediately spawns a shell process via `createDefaultTerminalSession()`, even if the user never opens the terminal pane. This costs 20-50MB and 200ms.

**Solution:**
Only create the default terminal session when the terminal pane becomes visible for the first time.

**Implementation Steps:**
1. Remove `createDefaultTerminalSession()` call from `openRepository` fresh-open path
2. Add lazy creation check in the terminal pane's `onAppear` or when terminal tab is first accessed
3. Preserve existing behavior for restored sessions (they already have terminals)

**Safety Checks:**
- Terminal still works when user opens it
- Terminal tab still shows correct repo directory
- No crash if terminal pane accessed before session exists

**Expected Impact:** 20-50MB savings + 200ms faster startup for users who don't immediately use terminal

**Risk Level:** Medium (need to handle edge cases where code expects terminal to exist)

---

### PERF-012: Defer `loadSignatureStatuses()` and `loadBridgeState()` at startup

**Scope:**
- `RepositoryViewModel+SnapshotHelpers.swift` `finalizeRepositorySwitch()` (lines 403, 406)

**Problem:**
`loadSignatureStatuses()` and `loadBridgeState()` run on every repo open even though most users don't check GPG signatures or use Bridge immediately.

**Solution:**
Load on-demand when user accesses the relevant UI.

**Implementation Steps:**
1. Remove `loadSignatureStatuses()` from `finalizeRepositorySwitch()`
2. Trigger signature loading when commit detail panel opens or when signature column becomes visible
3. Remove `loadBridgeState()` from `finalizeRepositorySwitch()`
4. Trigger bridge state loading when Bridge tab is selected

**Safety Checks:**
- GPG badges still appear (with slight delay on first access)
- Bridge tab still works

**Expected Impact:** 50-200ms less work on startup

**Risk Level:** Low

---

### PERF-013: Clear terminal output buffers after remote access flush

**Scope:**
- `RepositoryViewModel.swift` (line 399: `terminalOutputBuffers`)
- `RepositoryViewModel+RemoteAccess.swift` (wherever buffers are written/read)

**Problem:**
`terminalOutputBuffers: [UUID: Data]` accumulates all terminal output per session, never cleared. Can grow to 50-80MB per session with heavy terminal use.

**Solution:**
Clear buffer after each successful flush to remote client. Cap individual buffer at 1MB, dropping oldest data.

**Implementation Steps:**
1. After successful remote access screen update, clear the buffer for that session
2. Add a 1MB cap check before appending to buffer
3. If not using remote access, don't buffer at all

**Safety Checks:**
- Remote access terminal still displays correctly
- No data loss for active remote sessions

**Expected Impact:** 20-80MB savings for users with remote access enabled

**Risk Level:** Low

---

### PERF-014: Reduce initial commit load from 300 to 100

**Scope:**
- `RepositoryViewModel.swift` (line 638: `defaultCommitLimitAll = 300`)

**Problem:**
Loading 300 commits with full graph lane calculation on startup is expensive. Most users look at the top 20-30 commits.

**Solution:**
Reduce default to 100. The existing "load more" pagination handles the rest.

**Implementation Steps:**
1. Change `defaultCommitLimitAll` from 300 to 100
2. Optionally reduce `commitPageSize` from 300 to 200

**Safety Checks:**
- Graph still shows enough context
- "Load more" button still works
- Branch focus still works

**Expected Impact:** ~66% less data to parse, layout, and render on startup

**Risk Level:** Low

---

### PERF-015: Clean up `backgroundRepoStates` for repos not in recents

**Scope:**
- `RepositoryViewModel+BackgroundRepos.swift`

**Problem:**
`backgroundRepoStates` accumulates terminal sessions for every repo opened during the session. If user opens 10 repos, all 10 retain their terminal processes and buffers.

**Solution:**
After stashing a new repo, evict states for repos not in the recent 5 list. Kill their terminal processes.

**Implementation Steps:**
1. After adding a new entry to `backgroundRepoStates`, check count
2. If > 5, find entries whose URL is not in `recentRepositories.prefix(5)`
3. Stop their file watchers, cancel monitor tasks, kill terminal processes
4. Remove from dictionary

**Safety Checks:**
- Recent repos still restore terminals correctly
- No crash when switching to evicted repo (just creates fresh terminal)

**Expected Impact:** Caps background terminal memory at ~5 repos instead of unbounded

**Risk Level:** Medium

---

## 7. Execution Order

| Priority | Tasks | Theme | Cumulative Impact |
|----------|-------|-------|-------------------|
| 1 (Quick wins) | PERF-001, 002, 004, 010 | Fix leaks & waste | -20-50MB, fewer zombies |
| 2 (Timer tuning) | PERF-006, 007 | Reduce idle CPU | -60% idle wakeups |
| 3 (Cache hygiene) | PERF-003, 009, 013 | Bound memory growth | -40-80MB cap |
| 4 (Algorithmic) | PERF-005, 008 | Faster rendering | O(1) lookups, lazy lists |
| 5 (Startup defer) | PERF-011, 012, 014 | Faster launch | -200ms, -30MB at launch |
| 6 (Cleanup) | PERF-015 | Long-session memory | -20-50MB after many repos |

---

## 8. Future Work (Not in Scope)

These are architectural changes that would yield the biggest improvements but require significant refactoring and are too risky for incremental tasks:

- **Split RepositoryViewModel** into 5-6 focused @Observable classes (Graph, Code, Terminal, Hosting, AI) to eliminate cascade redraws
- **Conditional screen switching** (replace opacity-hidden screens with if/switch) -- requires terminal state preservation solution
- **Consolidate ContentView sheets** into single `.sheet(item:)` with enum
- **Move git operations off @MainActor** using child actors
- **Git process queuing** -- limit concurrent git processes to 3-4
- **Stream git output** instead of buffering entire stdout in memory
