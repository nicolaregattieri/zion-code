# Zion Performance PRD v2 -- Runtime Intelligence

> Generated: 2026-04-03
> Philosophy: Every background operation must answer: **What does the user see? When do they need it? What's the cheapest way to deliver it?**

---

## The Problem

Zion treats every background cycle like a first-time load. Every 60 seconds it reloads ALL commits, branches, tags, stashes, worktrees, and remotes -- even if nothing changed. Every 120 seconds it runs `git fetch --all --prune` to a remote -- even if the user hasn't looked at the graph in 10 minutes. It does this because it never asks: **does the user need this right now?**

The result: a native app that idles hotter than Electron apps.

---

## The Framework: Three Tiers of Freshness

Every piece of data in Zion falls into one of three categories:

### Tier 1: INSTANT (event-driven, no polling)
Data the user is actively looking at. Must update within 1-2 seconds of the underlying change.

- **Uncommitted changes** (file tree badges, changes list)
- **Current branch name** (status bar)
- **File content** (editor)
- **Terminal output** (terminal pane)

**How it should work:** FSEvents detects change -> lightweight `git status --porcelain` -> update badges. No commit reload, no branch reload, no tag reload.

### Tier 2: FRESH (on-demand + smart prefetch)
Data the user checks periodically. Can be 30-60 seconds stale without anyone noticing.

- **Commit graph** (only when Graph tab is visible)
- **Behind/ahead badges** (only when visible in status bar)
- **PR list** (only when PR panel is open or badge is visible)
- **File tree structure** (only on structural file changes)

**How it should work:** Load when the user navigates to it. Prefetch in background only if the relevant UI is visible. Use cheap checks before expensive operations.

### Tier 3: ON-DEMAND (user-initiated only)
Data the user explicitly requests. Never load proactively.

- **Commit details/diff** (user clicks a commit)
- **GPG signatures** (niche feature)
- **Bridge state** (user opens Bridge tab)
- **Repo statistics** (user opens settings)
- **AI review findings** (user clicks review)
- **Blame data** (user opens blame)
- **File history** (user opens history)
- **Reflog** (user opens reflog sheet)

**How it should work:** Load when requested. Show loading indicator. Cache result.

---

## Feature-by-Feature Audit

### 1. Auto-Refresh Timer (every 60s)

**What is it for?** Keep the UI current when things change outside Zion (e.g., another terminal runs `git commit`).

**How would a human expect it?** "If I commit in another terminal, Zion should notice within a minute."

**What it actually does:** Runs `loadRepository()` which executes:
- `git rev-parse --is-inside-work-tree`
- `git rev-parse --abbrev-ref HEAD`
- `git rev-parse --short HEAD`
- `git branch -a` with ahead/behind info
- `git tag -l --sort=-version:refSort` (if full)
- `git stash list` (if full)
- `git worktree list --porcelain` (if full)
- `git remote -v`
- `git log` with 100 commits + graph
- `git ls-files --unmerged`
- `git status --porcelain`
- 5+ file existence checks (.git/MERGE_HEAD, etc.)
- Then: `loadCommitStats()` (another git command per commit batch)
- Then: `prefetchCommitDetails()` (up to 25 more git commands)

**Total: 15-40 git process invocations every 60 seconds. For what?** To check if something changed.

**Smart alternative:**
1. File watcher already detects local changes -- that covers "user edited a file"
2. For external git changes (commit in another terminal): just check `git rev-parse HEAD` (1 command). If HEAD changed, THEN do a full refresh.
3. If HEAD hasn't changed, only run `git status --porcelain` for badge updates
4. Tags, stashes, worktrees, remotes almost never change spontaneously -- load them on navigation to the relevant UI

**Proposed: Replace 60s full refresh with 60s HEAD-check. Full refresh only if HEAD or index changed.**

---

### 2. Background Fetch (every 120s)

**What is it for?** Keep the behind/ahead badges current so the user knows when to pull.

**How would a human expect it?** "I see a badge saying I'm 3 commits behind. I'll pull when I'm ready."

**What it actually does:**
- `git fetch --all --prune` (EXPENSIVE: network call to every remote, downloads all new objects)
- `git rev-list --count HEAD..@{upstream}` 
- `git rev-list --count @{upstream}..HEAD`
- If divergence changed: triggers ANOTHER full `refreshRepository()` 

**Total: 3 git commands + network I/O + potential cascade refresh, every 120 seconds.**

**The UX question:** Does the user need behind/ahead badges updated every 2 minutes? In most workflows, they check once when they're about to push or pull. A 5-10 minute interval would be invisible to most users.

**Smart alternative:**
1. Increase interval to 5 minutes (300s)
2. Before running `git fetch`, check `git ls-remote --heads origin HEAD` (lightweight network check, no object download). If refs haven't changed, skip the full fetch entirely.
3. Only run full fetch when: user is on Graph tab, or user clicks refresh, or user is about to push

**Proposed: 5-minute interval + ls-remote pre-check before full fetch.**

---

### 3. PR Polling (every 5min)

**What is it for?** Show PR badges in sidebar and notify about new PRs/review requests.

**How would a human expect it?** "I see a notification when someone requests my review."

**Current cost:** GitHub/GitLab API call every 5 minutes. Reasonable interval, but should not trigger a full refresh cascade.

**Proposed: Keep 5-minute interval. Ensure it doesn't cascade into full refresh. Only update PR badges, not commit graph.**

---

### 4. File Watcher -> Refresh Cascade

**What is it for?** Instantly reflect file changes in the UI (modified badges, file tree, editor content).

**How would a human expect it?** "When I save a file, the modified indicator appears immediately."

**What it actually does:**
- File change detected by FSEvents (1.0s latency after our fix)
- Debounced at 750ms (after our fix)
- If `hasWorktreeStatusImpact`: runs `refreshRepository(options: .worktreeStatus)` -- this is a FULL loadRepository minus tags/stashes
- If `hasStructuralImpact`: runs `refreshFileTree(forceReload: true)`

**The UX question:** For a file CONTENT change (user saves), does the user need commits, branches, worktrees reloaded? No. They need `git status --porcelain` for badge updates.

**Smart alternative:**
1. For content-only changes: only run `git status --porcelain` (1 command)
2. For structural changes (file created/deleted/renamed): run status + file tree refresh
3. For git metadata changes (.git/HEAD, .git/refs): run the lightweight HEAD-check, then full refresh only if HEAD changed

**Proposed: Tiered file watcher response. Content change = status only. Structure change = status + tree. Git metadata = HEAD check.**

---

### 5. Clipboard Monitor (every 1.5s)

**What is it for?** Smart clipboard history with auto-categorization (commands, paths, hashes, URLs, images).

**How would a human expect it?** "I can see my recent copies in a sidebar panel and paste them."

**Current cost:** Polls `NSPasteboard.general.changeCount` every 1.5s. Cheap when nothing changed (integer comparison). Expensive when image is copied (SHA256 hash + JPEG encode + file write).

**The UX question:** How often does a user use clipboard history vs Cmd+V? For most users, clipboard history is a "nice to have" they use a few times a day.

**Smart alternative:**
1. The polling is actually fine -- `changeCount` check is O(1)
2. But image processing should be deferred: save the image lazily only when the user expands the clipboard panel
3. The 1.5s interval could be 3s with zero perceptible difference

**Proposed: Increase to 3s. Defer image processing until clipboard panel is visible.**

---

### 6. Commit Stats Loading

**What is it for?** Show insertions/deletions counts (+42 / -17) on each commit row.

**How would a human expect it?** "I see how big each commit was at a glance."

**What it actually does:** After EVERY refresh (including auto-timer), runs `loadCommitStats()` which calls `fetchCommitStats()` with ALL 100 commit hashes. This runs `git diff-tree --numstat` for the batch.

**Then:** It replaces the ENTIRE `commits` array to update stats, triggering a full graph re-render.

**The UX question:** Stats are a secondary piece of info. The user primarily looks at commit messages and graph structure. Stats are nice but not essential for the first render.

**Smart alternative:**
1. Only load stats on FIRST load and user-initiated refresh, not on auto-timer or file-watcher refreshes
2. Load stats only for VISIBLE commits (scroll position), not all 100
3. Update stats in-place without replacing the commits array (avoid graph re-render)

**Proposed: Skip stats on auto-timer/file-watcher refreshes. Load only for visible commits.**

---

### 7. Commit Details Prefetch

**What is it for?** Pre-cache commit details so clicking a commit feels instant.

**How would a human expect it?** "When I click a commit, the diff appears immediately."

**What it actually does:** After EVERY refresh, prefetches details for top 25 commits via `prefetchCommitDetails()`. Each prefetch runs `git show` -- that's 25 git process invocations per refresh cycle.

**The UX question:** How many commits does a user actually click in a session? Usually 3-10. Prefetching 25 is overkill, especially on every auto-refresh.

**Smart alternative:**
1. Only prefetch on user-initiated refresh and repo switch, NOT on auto-timer/file-watcher
2. Reduce prefetch count from 25 to 10
3. Prefetch based on scroll position, not just top N

**Proposed: Skip prefetch on auto-timer/file-watcher. Reduce to 10. Only on user-initiated refresh.**

---

### 8. `refreshRepository` Property Assignment Storm

**What is it for?** Apply loaded git data to the ViewModel so views update.

**What actually happens:** Lines 404-491 of RepositoryViewModel+Git.swift assign 20+ properties sequentially. On an @Observable class, EACH assignment triggers an observation notification, potentially causing 20+ view re-evaluation passes in a single refresh cycle.

Many assignments are redundant -- they set the same value that was already there (e.g., `currentBranch = payload.currentBranch` when branch hasn't changed). But `@Observable` still notifies on assignment, not on value change (unless you guard with `!=`).

**Current guards:** Some properties are guarded (`uncommittedChanges`, `uncommittedCount`, `worktrees`, `statusMessage`). But most are NOT guarded: `currentBranch`, `headShortHash`, `branchInfos`, `branches`, `tags`, `stashes`, `commits`, `hasMoreCommits`, `hasConflicts`, `isMerging`, `isRebasing`, `isCherryPicking`.

**Smart alternative:**
Guard every property assignment with `!= oldValue` check. For arrays, use a hash or count+first+last comparison instead of full equality check.

**Proposed: Add change guards to all property assignments in the refresh handler.**

---

### 9. Snapshot Capture on Every Refresh

**What is it for?** Enable instant repo switching by caching the current state.

**What it actually does:** `captureRepositorySnapshot(for: repositoryURL)` runs at the END of every single refresh (line 492). It copies ALL commits, branches, tags, stashes, worktrees, remotes, file tree into a snapshot struct.

**The UX question:** Snapshots are only useful when SWITCHING repos. If the user hasn't switched repos in the last 60 seconds, the snapshot is wasted work.

**Smart alternative:**
Only capture snapshots when:
1. The user has more than 1 recent repo (they might switch)
2. Limit to once per 30 seconds (debounce)
3. Skip on auto-timer refreshes (snapshot was just captured on the previous manual/file-watcher refresh)

**Proposed: Only capture snapshots on user-initiated refresh, git actions, and repo switch -- not on auto-timer or file-watcher.**

---

## Summary: The Waste Map

| Operation | Current | Cost | User Need | Smart Version |
|-----------|---------|------|-----------|---------------|
| Auto-refresh | Full reload every 60s | 15-40 git processes | Check if anything changed | HEAD check (1 cmd), full only if changed |
| Background fetch | `git fetch --all` every 120s | Network + 3 cmds + cascade | Behind/ahead badge | 5min + ls-remote pre-check |
| File watcher refresh | Full `.worktreeStatus` reload | 12+ git processes | Updated badges | `git status --porcelain` only (1 cmd) |
| Commit stats | All 100 commits, every refresh | 1+ batch git command | Glanceable sizes | Only on user refresh, visible commits |
| Commit prefetch | 25 commits, every refresh | 25 git processes | Fast click response | Only on user refresh, 10 commits |
| Property storm | 20+ unguarded assignments | 20+ view re-evaluations | Correct UI | Guard with != checks |
| Snapshot capture | Every refresh | Full state copy | Repo switching | Only on user/git-action refreshes |

---

## Task Breakdown

### RT-001: Lightweight auto-refresh (HEAD check instead of full reload)
**Problem:** Auto-refresh runs full `loadRepository()` every 60s (15-40 git processes).
**Solution:** Check `git rev-parse HEAD` + `git status --porcelain` count. Only trigger full refresh if HEAD hash changed or uncommitted count changed.
**Files:** RepositoryViewModel+BackgroundRepos.swift (startAutoRefreshTimer), RepositoryViewModel+Git.swift (new lightweight refresh method)
**Risk:** Low -- falls back to full refresh when change detected

### RT-002: Tiered file watcher response
**Problem:** Any file change runs `.worktreeStatus` refresh (12+ git commands).
**Solution:** Content-only change -> `git status --porcelain` only. Structural change -> status + file tree. Git metadata -> HEAD check first.
**Files:** RepositoryViewModel+SnapshotHelpers.swift (processPendingFileWatcherEventIfNeeded)
**Risk:** Low -- existing event classification already distinguishes change types

### RT-003: Smart background fetch with ls-remote pre-check
**Problem:** `git fetch --all --prune` runs every 120s regardless of remote state.
**Solution:** Run `git ls-remote --heads origin HEAD` first (fast, small). Only full fetch if remote HEAD differs from last known.
**Files:** RepositoryViewModel+RemoteSync.swift (checkBehindRemote), increase interval to 300s
**Risk:** Low -- adds a cheap pre-check, doesn't remove functionality

### RT-004: Guard all property assignments in refresh handler
**Problem:** 20+ unguarded property assignments trigger 20+ observation notifications per refresh.
**Solution:** Wrap each assignment with `if property != newValue { property = newValue }` pattern.
**Files:** RepositoryViewModel+Git.swift (lines 404-491)
**Risk:** Low -- purely defensive, no behavior change

### RT-005: Skip commit stats and prefetch on background refreshes
**Problem:** `loadCommitStats()` and `prefetchCommitDetails()` run on EVERY refresh, including auto-timer.
**Solution:** Only run on `.userInitiated`, `.gitAction`, and `.repositorySwitch` origins.
**Files:** RepositoryViewModel+Git.swift (lines 514-515)
**Risk:** Low -- stats appear on first load and manual refresh, just not on background ticks

### RT-006: Skip snapshot capture on background refreshes
**Problem:** `captureRepositorySnapshot()` copies entire state on every refresh including auto-timer.
**Solution:** Only capture on `.userInitiated`, `.gitAction`, `.repositorySwitch`.
**Files:** RepositoryViewModel+Git.swift (line 492)
**Risk:** Low -- snapshots still captured after user actions and repo switches

### RT-007: Increase background fetch interval to 5 minutes
**Problem:** `git fetch --all --prune` every 120s is aggressive for a badge update.
**Solution:** Change `backgroundFetchInterval` from 120s to 300s.
**Files:** Constants.swift
**Risk:** Low -- behind/ahead badges update every 5min instead of 2min

### RT-008: Increase clipboard monitor interval to 3s
**Problem:** Polling every 1.5s for a feature used a few times per day.
**Solution:** Change timer interval from 1.5s to 3.0s.
**Files:** ClipboardMonitor.swift
**Risk:** Low -- clipboard items appear 1.5s later at worst

---

## Execution Order

| Priority | Tasks | Impact |
|----------|-------|--------|
| 1 | RT-001, RT-002 | Biggest win: 90% fewer git processes at idle |
| 2 | RT-004, RT-005, RT-006 | 80% fewer view re-evaluations per refresh |
| 3 | RT-003, RT-007, RT-008 | Reduce network + polling overhead |
