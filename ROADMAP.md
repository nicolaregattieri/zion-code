# Zion Roadmap — From Hype Analysis to Execution

> Generated from `/hype-analyst` audit on Feb 2026.
> Hype Score: **7.8/10** — Ready for soft launch with targeted gaps to close.

---

## Current Strengths (protect these)

| Asset | Why it matters |
|-------|---------------|
| Clipboard Drawer | No competitor has it. This is the "wait, why doesn't my tool do this?" moment |
| Glassmorphism design system | 10+ glass tokens, 3 themes with matching terminal palettes. Screenshots stop scrolling |
| Terminal + clipboard synergy | Click-to-paste from clipboard history into terminal tabs. Novel workflow |
| Line-level staging | Beyond hunk staging — individual line checkboxes. Matches Sublime Merge precision |
| Worktree-first workflow | Terminal sessions per worktree, sidebar cards, Finder integration |
| Graph visualization | Colored lane topology, search with ranked matching, keyboard nav |
| Interactive rebase UI | Drag-reorder with 6 color-coded actions. Visual and intuitive |

---

## Quick Wins (1-2 hours each)

Small, high-impact improvements that polish what already exists.

- [ ] **Keyboard shortcut hints in tooltips** — Add `⌘` hints to toolbar buttons (Fetch, Pull, Push). Users discover shortcuts faster
- [ ] **Commit message templates** — Detect `.gitmessage` or offer conventional-commit presets (feat/fix/chore dropdown)
- [ ] **Copy diff to clipboard** — Right-click on a hunk → "Copy as patch". Developers share diffs constantly
- [ ] **Stash preview** — Show `git stash show -p` when hovering/selecting a stash entry
- [ ] **Branch age indicator** — Show "3 days ago" or "2 months stale" next to branches in Operations. Helps cleanup
- [ ] **File change count in tab bar** — Show "(+12 -3)" next to filenames in the editor tab bar
- [ ] **Double-click commit hash to copy** — In CommitDetailContent, make the hash a clickable/copyable element
- [ ] **Empty state illustrations** — Replace text-only empty states with minimal SF Symbol compositions
- [ ] **Diff word-level highlighting** — Within changed lines, highlight the specific words that differ (not just whole lines)
- [ ] **Terminal paste confirmation** — Optional "Paste X to terminal?" toast when clicking clipboard items (prevent accidents)

---

## Medium Wins (1 session each)

Features that meaningfully expand capability without architectural changes.

- [ ] **Merge conflict editor** — Parse `<<<<<<<` / `=======` / `>>>>>>>` markers, show side-by-side with "Accept Ours / Theirs / Both" buttons. This is the #1 gap for daily use
- [ ] **Image diff viewer** — Detect binary image files in diffs, show side-by-side PNG/JPG comparison with onion-skin slider. Expected in 2026
- [ ] **Drag-and-drop branch operations** — Drag branch pill onto another → merge dialog. Drag commit onto branch → cherry-pick. Uses SwiftUI `.draggable()` / `.dropDestination()`
- [ ] **Commit activity heatmap** — GitHub-style contribution calendar in the stats card. Visual proof of project health
- [ ] **File history view** — `git log --follow -- <file>` displayed as a mini-graph for the selected file in the editor
- [ ] **Diff gutter annotations** — In the editor (non-blame mode), show colored marks in the gutter for modified/added/deleted lines vs HEAD
- [ ] **Search in diff** — Cmd+F within the diff viewer to find specific changes
- [ ] **Configurable keyboard shortcuts** — Let users rebind Cmd+1/2/3 and add custom shortcuts for git operations
- [ ] **Tag annotations** — Support annotated tags with message editor (currently only lightweight tags)
- [ ] **Partial stash** — Stage specific files, then stash only the staged changes (`git stash push -S`)

---

## Big Wins (2-3 sessions each)

Strategic features that change the competitive positioning.

- [ ] **PR review in-app** — Fetch PR diffs, show inline comments, add review comments. Turn Zion from "PR creation" to "PR workflow". Starts with GitHub, expands later
- [ ] **GitLab + Bitbucket support** — Abstract the `GitHubClient` into a `GitHostClient` protocol. Implement GitLab REST and Bitbucket Cloud API. Triples addressable market
- [ ] **Commit graph filtering** — Filter by: author, date range, path (file/directory), message regex. Power users managing large repos need this
- [ ] **Side-by-side diff mode** — Toggle between unified and split-pane diff. Table-stakes for code review workflows
- [ ] **Custom themes engine** — Let users import VS Code `.json` themes or define custom `ThemeColors`. Community themes drive adoption
- [ ] **Git LFS support** — Detect LFS-tracked files, show LFS status indicators, support lock/unlock operations
- [ ] **Multi-repo workspace** — Open multiple repositories in tabs or a project-level view. Monorepo and microservice developers need this
- [ ] **Undo system (visual)** — Build on the reflog browser to show a visual timeline of actions with one-click undo. "Time Machine for Git"

---

## Launch Blockers (before any public announcement)

These aren't features — they're infrastructure required to capture and retain users.

- [ ] **Landing page** — One-page site: hero screenshot (graph screen), 15s GIF (clipboard → terminal flow), feature grid, download button. Host on zion.app or similar
- [ ] **Auto-update (Sparkle)** — Integrate Sparkle framework for silent background updates. Users won't re-download manually
- [ ] **DMG with drag-to-Applications** — Professional installer experience (already have `make-dmg.sh`, verify it's polished)
- [ ] **Crash reporting** — Integrate a lightweight crash reporter (Sentry or custom). Can't fix what you can't see
- [ ] **First-run onboarding** — 3-screen welcome: "Open a repo", "Meet the Clipboard Drawer", "Your terminal lives here"
- [ ] **App notarization** — Code-sign and notarize for Gatekeeper. Without this, macOS blocks the app on first launch

---

## Strategic Skills to Build

Claude Code skills that protect quality and accelerate iteration.

| Skill | Purpose | Why it matters |
|-------|---------|---------------|
| `/regression-check` | After any change, verify: terminal sessions work, graph renders, themes apply correctly, staging pipeline intact | Prevents breaking core flows during rapid iteration |
| `/perf-audit` | Profile commit list scrolling, file tree loading, diff parsing. Flag O(n^2) patterns and unnecessary recomputations | Performance is the #1 reason users abandon Git GUIs |
| `/competitor-watch` | Given a competitor name, compare their latest release features against Zion's current state. Find new gaps and opportunities | Keeps the roadmap honest and market-aware |
| `/launch-checklist` | Run through every launch blocker: notarization, DMG quality, landing page status, crash reporting, auto-update. Report what's ready and what's not | Prevents premature launch that wastes the first-impression moment |
| `/accessibility-audit` | Check VoiceOver labels, keyboard navigation completeness, contrast ratios, dynamic type support | macOS power users include accessibility users. Apple features accessible apps |
| `/l10n-check` | Scan all views for hardcoded strings missing `L10n()` wrapping. Verify all keys exist in .lproj files for PT-BR, EN, ES | Broken localization is immediately visible and unprofessional |

---

## Execution Philosophy

### What got us here
- **Ship in sessions, not sprints** — Each feature lands in 1-3 focused sessions with `swift build` + `make-app.sh` at the end
- **Design tokens, not ad-hoc styling** — `DesignSystem.Colors` ensures every new view is automatically consistent
- **`@Observable` discipline** — `@State` for owners, `@Bindable` for binders, plain `var` for readers. No exceptions
- **Safety by default** — `performGitAction` confirmation system protects users from destructive operations
- **Portuguese-first, world-ready** — `L10n()` on every string from day one, not bolted on later

### What keeps us on track
1. **Never ship without rebuilding dist** — `./scripts/make-app.sh` after every change. The user tests the real app
2. **Read before you edit** — Understand existing patterns before adding new code
3. **Audit before you claim** — `/hype-analyst` reads source files to verify features exist. No vaporware
4. **Protect the golden rule** — `EditorTheme.isDark` is always `true`. Light themes use `isLightAppearance` for SwiftUI styling only
5. **Cache intentionally** — `maxLaneCount` via `didSet`, `flatFileCache` via `didSet`, regex cache in Coordinator. Every cache has a clear invalidation path

---

## Priority Order

```
NOW        → Launch Blockers (landing page, notarization, Sparkle)
THIS WEEK  → Quick Wins (keyboard hints, copy diff, stash preview)
NEXT WEEK  → Merge Conflict Editor (medium win, biggest daily-use gap)
AFTER      → Image Diff + Drag-and-Drop Branches (medium wins)
MONTH 2    → PR Review In-App + GitLab/Bitbucket (big wins, market expansion)
MONTH 3    → Custom Themes + Multi-Repo (big wins, community growth)
```

---

*Last updated: Feb 2026 — Hype Score 7.8/10*
*Run `/hype-analyst` again after completing a tier to re-evaluate.*
