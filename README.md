<div align="center">

# Zion

### The Git workspace that thinks with you.

A native macOS Git client that combines a visual commit graph, a real terminal, a code editor, and AI — all in one glassmorphic workspace.

**No Electron. No subscriptions. No bloat. Just Swift.**

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/sonoma/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)

</div>

<!-- Replace these with real screenshots before launch -->
<p align="center">
  <img src="docs/screenshots/graph.png" width="32%" alt="Zion Tree — visual commit graph" />
  <img src="docs/screenshots/code.png" width="32%" alt="Zion Code — editor + terminal" />
  <img src="docs/screenshots/operations.png" width="32%" alt="Operations Center" />
</p>

---

## Why Zion?

Most Git GUIs make you choose: **pretty graphs** or **real terminals**. **Simple UI** or **power features**. **Native speed** or **AI smarts**.

Zion doesn't make you choose.

| | Other Git GUIs | Zion |
|---|---|---|
| **Terminal** | External app / fake shell | Real PTY with splits, tabs, zoom |
| **Editor** | None / basic viewer | Syntax highlighting, blame, Quick Open |
| **AI** | None or paid addon | Built-in (Claude / GPT), free to configure |
| **Clipboard** | Copy-paste manually | Smart clipboard that auto-captures and pastes into terminal |
| **Performance** | Electron / web view | Native SwiftUI, zero web tech |
| **Price** | $50-100/year | Free and open source |

---

## Features at a Glance

### Zion Tree — Visual Commit Graph
> `Cmd+2`

Color-coded lane visualization with merge edges, branch decorations, commit search with `Cmd+F`, jump bar for quick branch navigation, pending changes row at the top, GPG/SSH signature verification, and keyboard navigation with arrow keys.

### Zion Code — Editor + Terminal
> `Cmd+1`

A real code editor with syntax highlighting, Git Blame, Quick Open (`Cmd+P`), file watcher, 6 themes (Dracula, Tokyo Night, Catppuccin Mocha, One Dark Pro, City Lights, GitHub Light), and configurable fonts. Side-by-side with a real PTY terminal that supports split panes, multiple tabs, and independent zoom.

### Smart Clipboard
> The feature no other Git GUI has.

Zion watches your clipboard and auto-categorizes everything: commands, file paths, git hashes, URLs, even images. **Single-click** to paste into your active terminal. **Double-click** to paste and execute. **Drag** items directly into any terminal pane. It keeps your last 20 items and auto-cleans temp files.

### Operations Center
> `Cmd+3`

A dashboard for everything Git. Commit with hunk and line-level staging, interactive rebase (pick/squash/fixup/drop/reorder with drag), branch management (create/merge/rebase/rename/delete), stash management, cherry-pick, revert, reset, tag management, worktrees, submodules, remotes, reflog, and repo stats — all in one place.

### AI Assistant
> Works with Anthropic Claude or OpenAI GPT.

Generate commit messages from your staged diff. Get plain-language explanations of file changes. Auto-draft PR titles and descriptions. Suggest descriptive stash messages. API key stored securely in macOS Keychain. Falls back to smart heuristics when AI is not configured.

### GitHub Integration

List open pull requests, create new PRs from your current branch, and let AI generate the PR description from your commit log.

### Worktree-First Workflow

Create worktrees with one click (auto-generated path and branch), get a dedicated terminal pane per worktree, remove and prune from the Operations Center.

---

## Install

### Download

Grab the latest `.dmg` from [**Releases**](../../releases), open it, and drag **Zion.app** to Applications.

### Build from Source

```bash
git clone https://github.com/nicolaregattieri/Zion.git
cd Zion
swift build
./scripts/make-app.sh   # -> dist/Zion.app
open dist/Zion.app
```

<details>
<summary>Generate a distributable DMG</summary>

```bash
./scripts/make-dmg.sh   # -> dist/Zion.dmg
```

</details>

### Requirements

| | Minimum |
|---|---|
| macOS | 14 (Sonoma) |
| Git | Installed and in `PATH` |
| Swift | 6.0+ (build from source only) |

---

## Keyboard Shortcuts

Zion is keyboard-first. Press `Cmd+?` to see all shortcuts inside the app.

| Shortcut | Action |
|----------|--------|
| `Cmd+1` / `2` / `3` | Switch workspace (Code / Graph / Operations) |
| `Cmd+P` | Quick Open (fuzzy file search) |
| `Cmd+B` | Toggle file browser |
| `Cmd+J` | Toggle terminal |
| `Shift+Cmd+J` | Maximize terminal |
| `Cmd+T` | New terminal tab |
| `Shift+Cmd+D` | Split terminal vertical |
| `Shift+Cmd+E` | Split terminal horizontal |
| `Shift+Cmd+W` | Close split pane |
| `Cmd+S` | Save file |
| `Cmd+F` | Search graph |
| `Ctrl+Plus` / `Ctrl+Minus` | Terminal zoom in / out |

---

## Feature Reference

<details>
<summary><strong>Full feature list</strong> (click to expand)</summary>

| Area | Features |
|------|----------|
| **Graph** | Lane visualization, commit search, jump bar, branch focus, pending changes, signature verification, keyboard navigation, paginated loading (up to 5000 commits) |
| **Editor** | Syntax highlighting (regex-cached), Quick Open, Git Blame, 6 themes, 5+ font families, line spacing control, line wrapping, file watcher, multi-tab, unsaved indicator |
| **Terminal** | Real PTY (`/bin/zsh -l`), split panes (H/V), multiple tabs, independent zoom, font config, clipboard paste/drag, process preservation across view changes |
| **Clipboard** | Auto-capture (0.5s polling), smart categorization (command/path/hash/URL/image/text), click-to-paste, double-click-to-execute, drag-and-drop, image capture, auto-cleanup |
| **Operations** | Hunk staging, line staging, interactive rebase (visual drag-reorder), cherry-pick, revert, reset (soft/hard), stash (create/apply/pop/drop), custom git commands, discard changes, add to .gitignore |
| **Branches** | Checkout, create, merge, rebase, push, pull, rename, delete, remote tracking |
| **Tags** | Create and delete lightweight tags |
| **AI** | Commit messages, diff explanations, PR descriptions, stash messages, provider config (Anthropic/OpenAI), Keychain API key storage, heuristic fallback |
| **GitHub** | PR list, create PR, AI-generated PR body |
| **Worktrees** | Add, quick create (one-click), remove, prune, dedicated terminal, open in Finder |
| **Remotes** | Fetch all, pull, push (normal/force-with-lease/force), add/remove, connection test |
| **Submodules** | Status, init, update (recursive), sync |
| **Reflog** | Visual viewer (last 50), undo last action (soft reset) |
| **Settings** | Language (PT-BR/EN/ES/System), external editor (VS Code/Cursor/Xcode/IntelliJ/Sublime/custom), external terminal (Terminal.app/iTerm/Warp/custom), confirmation mode, background fetch (60s) |
| **Diagnostics** | Ring-buffer logger, export/copy sanitized logs |

</details>

> Full reference with descriptions and shortcuts: [`docs/FEATURES.md`](docs/FEATURES.md)

---

## Themes

Zion ships with 6 curated editor + terminal palettes:

| Theme | Style |
|-------|-------|
| **Dracula** | Classic dark with vibrant accents |
| **Tokyo Night** | Deep indigo with soft pastels |
| **Catppuccin Mocha** | Warm dark with community-driven colors |
| **One Dark Pro** | The most popular VS Code theme |
| **City Lights** | Cool dark with muted tones |
| **GitHub Light** | Clean light theme for daytime |

---

## Languages

Zion speaks three languages out of the box:

- **Portugues (BR)** — default
- **English**
- **Espanol**

Switch anytime in Settings, or let Zion follow your system locale.

---

## Architecture

Zion is a Swift Package (no `.xcodeproj`) built entirely with SwiftUI and Swift Concurrency.

```
ZionApp / ContentView          App shell, navigation, toolbar
  -> RepositoryViewModel       Central state (@Observable, @MainActor)
    -> RepositoryWorker        Background Git operations (async/await)
      -> GitClient             Git CLI process execution
    -> GitGraphLaneCalculator  Lane & edge layout algorithm
    -> TerminalSession         PTY management (SwiftTerm + LocalProcess)
    -> AIClient                Anthropic / OpenAI API (actor-isolated)
```

Design pattern: **MVVM** with Swift Observation (`@Observable`).

---

## Contributing

Zion is open source and contributions are welcome. Before submitting a PR:

1. Make sure `swift build` passes
2. Test your changes with `./scripts/make-app.sh && open dist/Zion.app`
3. Add L10n keys for any user-facing strings in all 3 locales

---

## License

[MIT](LICENSE) — Use it, fork it, ship it.

## Acknowledgments

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza — Terminal emulator
- [Git](https://git-scm.com/) — The engine under the hood

---

<div align="center">
<sub>Built with SwiftUI by <a href="https://github.com/nicolaregattieri">Nicola Regattieri</a></sub>
</div>
