# Changelog

All notable changes to Zion are documented here.

---

## 1.2.5 — 2026-02-24

### Fixed
- **Credential Transport Hardening** — Git credential retry/prompt flow now only runs for `https://` remotes, preventing credential handling on insecure `http://` remotes.
- **File Operation Validation** — File/folder create and rename now reject traversal/separator patterns that could escape the selected directory.
- **Shell Execution Surface** — Deprecated shell-string execution path was disabled in favor of argument-based process execution only.
- **AI Error Leakage Reduction** — Provider failure messages now avoid returning raw upstream payload bodies.

### Changed
- **Keychain Hardening** — AI API keys are now saved with stricter Keychain accessibility/data-protection attributes.
- **Release Versioning** — App bundle bumped to `1.2.5` (build `10`) for Sparkle distribution.

## 1.2.4 — 2026-02-24

### Fixed
- **Quick Commit Selection** — After committing from the graph pending-changes modal, the newly created commit is now selected/highlighted in the graph instead of keeping the previous selection.

### Changed
- **Release Versioning** — App bundle bumped to `1.2.4` (build `9`) for Sparkle distribution.

## 1.2.3 — 2026-02-24

### Changed
- **Changes Screen Hierarchy** — Promoted the file list header to the shared `CardHeader` pattern with grouped actions for clearer scanability and stronger visual consistency.
- **Interaction Feedback** — Added explicit hover + selection affordances to file rows in Changes and worktree rows in Sidebar to reduce ambiguous click targets.
- **Worktree Conflict Affordance** — Replaced the generic warning glyph with a semantic conflict icon for faster risk recognition.
- **Release Versioning** — App bundle bumped to `1.2.3` (build `8`) for Sparkle distribution.

## 1.2.2 — 2026-02-23

### New
- **Focus Mode Escape Affordance** — Added a compact in-screen exit control in Zion Code while in focus mode (`⌃⌘J`), reducing discoverability friction for new users.
- **Launch Playbook 1.2.2** — Added an updated hype/positioning launch document for the current release narrative.

### Changed
- **Integrated-Only Positioning** — Removed external terminal/editor messaging from in-app documentation surfaces and aligned feature docs with the integrated editor + terminal workflow.
- **Feature Reference Sync** — Updated `docs/FEATURES.md` for current editor themes and settings tab structure (General + Editor + AI + Notifications).
- **Release Versioning** — App bundle bumped to `1.2.2` (build `7`) for Sparkle distribution.

### Fixed
- **Doc Drift** — Corrected stale settings/customization docs that still referenced external terminal/editor configuration.

## 1.2.1 — 2026-02-23

### New
- **Zion Map Expanded Coverage** — Added missing detail cards for tree commit stats/avatars/branch search, advanced code actions/navigation/settings, terminal search, smart clipboard actions, repo init + stash badge, AI stash/branch/summary, and diagnostic sanitization.
- **Shortcut Sheet Parity** — Documented `Ctrl+F` find alias in keyboard shortcuts.

### Changed
- **Release Versioning** — App bundle bumped to `1.2.1` (build `6`) for public distribution.
- **Public Launch Messaging** — README release highlights updated for 1.2.1 and AI provider wording aligned with current support.

### Fixed
- **Help ↔ Map Drift** — HelpSheet bullets and Zion Map detail entries are now aligned with feature coverage.
- **L10n Completeness** — New documentation keys added in pt-BR, en, and es with full parity.

## 1.2.0 — 2026-02-23

### New
- **Smart Worktree Creation** — Prefix picker (`feat/fix/chore/hotfix/exp`) + name with derived branch/path and optional advanced mode.
- **Inline Worktree Flow in Sidebar** — `+ Novo Worktree` lets you create context without leaving current workspace.
- **Graph Worktree Pills** — Worktree switch pills now show in-pill dirty/conflict count.
- **Pending Changes Upgrades** — Visible `Create Branch Here` action and contextual menu improvements.
- **Copy/Move Changes Across Worktrees** — Safer default copy flow with explicit move action.
- **Recovery Vault (Operations)** — List active/dangling safety snapshots, copy references, and restore when needed.

### Changed
- **Recents Semantics** — Global recents remain root-only with per-project `WT n` badge.
- **Launch Validation Messaging** — README now positions Zion as daily-use ready with focused advanced-flow validation.

### Fixed
- **Stash/Transfer Recovery UX** — Better user-facing guidance when apply/pop fails due to local overwrite collisions.
- **Documentation Drift** — Help/Map/L10n/feature reference synchronized for worktree + recovery flows.

### Known Edge Case (tracked)
- Same-file/same-line edits across worktrees may block direct stash apply without generating unmerged (`-U`) entries. Recovery flow remains available via Operations + Recovery Vault references.

## 1.0.1 — 2026-02-20

### New
- **New app icon** — Crystal mountain prism logo replacing the old graph dots
- **"The view from the top."** — New tagline across the app and README
- **Beautiful by Design** section in README with full-width gallery screenshots
- Logo displayed in Welcome Screen and Sidebar using bundled PNG with SwiftUI clipping

### Changed
- README rebranded: "Git workspace" positioning, new tagline, logo in header
- Welcome Screen subtitle updated from "Seu cliente Git nativo para macOS" to the new tagline
- Sidebar repo card now shows the app logo instead of an SF Symbol
- Gallery screenshots added: Tokyo Night graph, One Dark Pro editor, Catppuccin Light editor, Operations dashboard

### Fixed
- App icon no longer shows double squircle border (uses full-bleed square PNG)
- Internal logo uses raw PNG with `clipShape` instead of `NSApp.applicationIconImage` to avoid jagged edges at small sizes
---

## 1.0.0 — 2026-02-20

### Initial Release

**Graph. Code. Terminal. One window.** — A native Git workspace for macOS.

#### Core
- Visual commit graph with lane-colored cards, merge edges, branch decorations
- Commit search (`Cmd+F`), jump bar, branch focus, pending changes row
- Status bar pills (current branch, change count), GPG/SSH signature verification
- Keyboard navigation with arrow keys, paginated loading (up to 5000 commits)

#### Editor
- Syntax highlighting (20+ languages), regex-cached for performance
- Git Blame with author-colored gutter
- Quick Open (`Cmd+P`) with fuzzy file search
- 6 themes: Dracula, Tokyo Night, Catppuccin Mocha, One Dark Pro, City Lights, GitHub Light
- 5+ font families, line spacing control, line wrapping, file watcher

#### Terminal
- Real PTY terminal (`/bin/zsh -l`) with xterm-256color
- Split panes (horizontal/vertical), multiple tabs, independent zoom
- Clipboard paste, drag-and-drop, process preservation across view changes

#### Operations
- Hunk and line-level staging
- Interactive rebase with visual drag-reorder (pick/squash/fixup/drop)
- Branch management (create/merge/rebase/rename/delete)
- Stash, cherry-pick, revert, reset (soft/hard)
- Tag management, worktrees, submodules, remotes, reflog

#### Smart Clipboard
- Auto-capture with smart categorization (command/path/hash/URL/image/text)
- Click-to-paste, double-click-to-execute, drag-and-drop into terminal

#### Conflict Resolution
- Built-in resolver: ours/theirs/both/custom edit
- File list with status icons, auto-continue merge/rebase/cherry-pick

#### AI Assistant
- Commit messages, diff explanations, PR descriptions, stash messages
- Anthropic Claude and OpenAI GPT support
- API key stored in macOS Keychain, heuristic fallback

#### GitHub Integration
- List PRs, create PRs, AI-generated PR descriptions

#### Platform
- Native SwiftUI — no Electron, no web views
- macOS 14+ (Sonoma), Swift 6
- 3 languages: Portugues (BR), English, Espanol
- Free and open source (MIT)
