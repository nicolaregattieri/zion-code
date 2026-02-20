# Zion

**A native Git client for macOS with a visual commit graph, integrated terminal, and code editor.**

<!-- Screenshot placeholders — replace before launch -->
<p align="center">
  <img src="docs/screenshots/graph.png" width="32%" alt="Zion Tree — commit graph" />
  <img src="docs/screenshots/code.png" width="32%" alt="Zion Code — editor + terminal" />
  <img src="docs/screenshots/operations.png" width="32%" alt="Operations Center" />
</p>

---

## Highlights

- **Visual Commit Graph** — Color-coded lanes, merge edges, branch focus, signature verification, and keyboard navigation
- **Integrated Terminal** — Real PTY with split panes, multiple tabs, drag-and-drop from clipboard, and per-terminal font/zoom
- **Code Editor** — Syntax highlighting, Quick Open (fuzzy search), Git Blame, multiple tabs, themes, and configurable fonts
- **Operations Center** — Commit with hunk/line staging, interactive rebase (pick/squash/fixup/drop/reorder), stash, cherry-pick, reset
- **AI Assistant** — Generate commit messages, explain diffs, draft PR descriptions (Anthropic Claude or OpenAI)
- **GitHub Integration** — List open PRs, create PRs with AI-generated descriptions
- **Worktree Management** — Create, remove, prune worktrees with dedicated terminal panes
- **Localization** — Portuguese (BR), English, and Spanish

## Requirements

| Requirement | Version |
|-------------|---------|
| macOS       | 14+ (Sonoma) |
| Git         | Installed and in `PATH` |
| Swift       | 6.0+ (build from source only) |

## Install

### From Releases

Download the latest `.dmg` from [Releases](../../releases), open it, and drag **Zion.app** to your Applications folder.

### Build from Source

```bash
git clone https://github.com/nicolaregattieri/Zion.git
cd Zion
swift build
./scripts/make-app.sh      # generates dist/Zion.app
open dist/Zion.app
```

To generate a distributable DMG:

```bash
./scripts/make-dmg.sh       # generates dist/Zion.dmg
```

## Feature Overview

> Full reference with descriptions and shortcuts: [`docs/FEATURES.md`](docs/FEATURES.md)

| Area | Key Features |
|------|--------------|
| Graph | Lane visualization, commit search, jump bar, branch focus, signature verification |
| Editor | Syntax highlighting, Quick Open, Git Blame, themes, line wrapping, file watcher |
| Terminal | Real PTY, split panes, multiple tabs, zoom, clipboard paste/drag |
| Operations | Hunk/line staging, interactive rebase, cherry-pick, stash, reset, custom commands |
| AI | Commit messages, diff explanations, PR descriptions, stash messages |
| GitHub | PR list, create PR, AI-generated PR body |
| Worktrees | Add/remove/prune, quick create, dedicated terminal per worktree |
| Remotes | Fetch, pull, push, add/remove remotes, connection test |
| Submodules | Status, init, update, sync |
| Reflog | Visual viewer, undo last action |
| Settings | Language, external editor/terminal, confirmation mode, background fetch |
| Diagnostics | Ring-buffer logger, export/copy sanitized logs |

## Architecture

Zion is a Swift Package (no Xcode project) built with SwiftUI.

| Layer | Description |
|-------|-------------|
| `ZionApp` / `ContentView` | App entry point, navigation, toolbar |
| `RepositoryViewModel` | Central state hub (`@Observable`, `@MainActor`) |
| `RepositoryWorker` | Background Git operations (Swift Concurrency) |
| `GitClient` | Git CLI process execution |
| `GitGraphLaneCalculator` | Lane and edge layout for the commit graph |
| `TerminalSession` / `SwiftTerm` | Real PTY terminal with `LocalProcess` |

Design pattern: **MVVM** with Swift Observation (`@Observable`).

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘1` | Code workspace |
| `⌘2` | Graph workspace |
| `⌘3` | Operations workspace |
| `⌘P` | Quick Open |
| `⌘B` | Toggle file browser |
| `⌘J` | Toggle terminal |
| `⇧⌘J` | Maximize terminal |
| `⌘T` | New terminal tab |
| `⇧⌘D` | Split vertical |
| `⇧⌘E` | Split horizontal |
| `⌘S` | Save file |
| `⌘F` | Search graph |
| `⌘?` | All shortcuts |

## Localization

Zion ships with three languages:

- **Portugues (BR)** — default
- **English**
- **Espanol**

Switch via Settings > Language, or follow the system locale.

## License

[MIT](LICENSE)

## Acknowledgments

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — Terminal emulator
- [Git](https://git-scm.com/) — The engine under the hood
