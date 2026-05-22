# MacSwitch — PRD

**Feature:** Zen Mode project switcher chip
**Status:** Draft, awaiting build approval
**Owner:** Nicola
**Date:** 2026-04-24

---

## Problem

Power users live inside Zen mode (terminal-only layout, sidebar + tree + editor hidden). Today, switching to a different project requires exiting Zen, opening sidebar or status bar recents, picking the project, then re-entering Zen. Friction kills "stay in flow" promise.

## Goal

Switch active project from inside Zen mode in one click or one shortcut, without leaving Zen.

## Target User

- People who only interact with terminal + agents in Zen
- Mouse users + keyboard users (both flows must work)
- Multi-project switchers (open 3-5 repos in parallel)

## Non-Goals (v1)

- Pinning favorite projects
- Drag-reorder recents
- Git status dots / dirty indicators on chip
- Branch name on chip
- Remote / SSH project entries
- Hover-edge auto-reveal drawer
- Project icons / avatars

---

## Solution

### UI: Project Chip in Zen Terminal Toolbar

Small pill, bottom-right of terminal toolbar, next to existing zen exit button. Clicking opens native macOS `Menu` with up to 8 recent projects. Selecting a project switches active repo and stays in Zen.

**Visual spec:**
- Folder glyph (`folder.fill`) + current project name (`repositoryURL.lastPathComponent`) + chevron (`chevron.up.chevron.down`)
- Glass background matching `zenModeExitButton`: `DesignSystem.Colors.glassSubtle` fill, `DesignSystem.Colors.glassBorderDark` stroke, `DesignSystem.Spacing.elementCornerRadius`
- Padding: 10 horizontal, 6 vertical
- Typography: `DesignSystem.Typography.bodyMedium` for project name
- Tooltip: `"Switch project (⌘⇧O)"`

**Empty state:** Chip label shows `"No project open"`. Menu shows `"No recent projects"` + `"Open folder…"` action.

### Interaction

- Click chip → native macOS menu opens with recents list
- Pick recent → `model.saveRecentRepository(url)` then `model.openRepository(url)`. Repo switches. Zen stays on.
- ESC dismisses menu
- Arrow keys + Enter to navigate menu (free from native `Menu`)
- Type-ahead search (free from native `Menu`)

### Shortcut: ⌘⇧O

Global shortcut (active in Zen) opens same menu programmatically.
- Registered as `.zenProjectPicker` in `ShortcutRegistry`
- No new overlay component — triggers same chip menu

### No QuickOpen-style overlay

Decided against custom overlay. Native `Menu` already has search + keyboard nav. Reusing avoids reinventing what already works in `StatusBarRecentsMenu`.

---

## Reuse

`Sources/Zion/Views/Main/StatusBarRecentsMenu.swift` lines 48-64 already contain recents list logic. Extract `recentsSection` body into shared `RecentsMenuContent` view. Both existing status bar menu and new zen chip render it. Zero duplication.

---

## Acceptance Criteria

1. Enter Zen mode (⌘T). Chip visible in bottom-right of terminal toolbar.
2. Chip displays current project name (or "No project open").
3. Click chip. Menu lists up to 8 most recent projects, ordered by last-accessed.
4. Select a project. Active repo switches. Zen mode stays active. Terminal re-attaches to new repo.
5. ⌘⇧O opens same menu without clicking. ESC closes it.
6. Empty recents state shows correct message + "Open folder…" action.
7. Selecting a recent reorders it to top of recents list (saved via `saveRecentRepository`).
8. Existing `StatusBarRecentsMenu` behavior unchanged.
9. CPU usage during 30s of `claude` streaming: chip-visible vs chip-hidden delta ≤ 0.5%.
10. All strings localized in en, pt-BR, es.

---

## Out of Scope (deferred to v2+)

- Hover-edge drawer (reveal on cursor near bottom edge)
- Floating mini-dock with project icons
- Side-tab rail (Discord-style)
- Search field inside menu (native `Menu` type-ahead is enough)
- ⌘1 … ⌘8 number-key shortcuts to recent slots

---

## Open Questions

1. Chip side: bottom-right (next to exit btn) or bottom-left of terminal toolbar?
2. ⌘⇧O conflict check — any existing binding uses it?
3. Chip label: folder name only, or `parent/folder` path?
4. Should chip show repo branch subtly? (Adds observation cost — recommend no for v1)

---

## Implementation Outline

| File | Change |
|---|---|
| `Sources/Zion/Views/Main/RecentsMenuContent.swift` | NEW — shared menu body |
| `Sources/Zion/Views/Main/StatusBarRecentsMenu.swift` | EDIT — consume shared |
| `Sources/Zion/Views/Code/ZenProjectChip.swift` | NEW — chip + menu trigger |
| `Sources/Zion/Views/Code/CodeScreen+Terminal.swift` | EDIT — insert chip line ~215 in `if isZenMode` block |
| `Sources/Zion/Services/ShortcutRegistry.swift` | EDIT — `.zenProjectPicker` case |
| `Sources/Zion/Views/Code/CodeScreen.swift` | EDIT — bind ⌘⇧O to chip menu open |
| `Sources/Zion/Views/Code/CodeScreen+ZenMode.swift` | EDIT — drop dead `focusModeExitBar` (separate commit) |
| `Sources/Zion/Resources/{en,pt-BR,es}.lproj/Localizable.strings` | EDIT — 5 keys × 3 locales |

### Locale Keys

```
"zen.project.none"           = "No project open"
"zen.project.switch.hint"    = "Switch project"
"zen.project.picker.empty"   = "No recent projects"
"zen.project.picker.open"    = "Open folder…"
"zen.project.picker.title"   = "Switch project"
```

---

## Performance Notes

- Chip observes `repositoryURL` + `recentRepositories` only
- Native `Menu` body builds lazily on open — recents not iterated during normal terminal redraws
- Snapshot recents into `let recents: [URL]` at menu construction to break observation chain
- No prefetch on chip hover; existing `RecentRepositoryPrefetcher` at app boot is sufficient
- No SwiftTerm modifications

---

## Tests

- `RecentsMenuContent` renders correct item count for N ∈ {0, 1, 8, 50}
- Tapping a recent calls `saveRecentRepository` then `openRepository` with right URL
- All 5 locale keys present in en, pt-BR, es
- ⌘⇧O shortcut wired and triggers menu visibility

---

## Commit Plan

Branch: `feature/zen-project-switcher` (from fresh `origin/master`)

1. `feat(zen): extract RecentsMenuContent for reuse`
2. `feat(zen): add project chip in zen terminal toolbar`
3. `feat(zen): bind ⌘⇧O to open zen project chip menu`
4. `chore(zen): drop unused focusModeExitBar`

PR opens after step 4. Wait for explicit user approval before push.
