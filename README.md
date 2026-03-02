<div align="center">

<img src="docs/zion-logo.png" width="128" alt="Zion" />

# Zion

*The view from the top.*

**Graph. Code. Terminal. One window.**

A native Git workspace for macOS that puts your commit graph, a real code editor,
and a full terminal in one window. Stage hunks, resolve conflicts, write code, and
run commands — without switching apps.

**No Electron. No subscriptions. No bloat. Just Swift.**

[![Website](https://img.shields.io/badge/Website-zioncode.dev-7c3aed?style=flat-square&logo=vercel&logoColor=white)](https://zioncode.dev)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/sonoma/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)

</div>

<p align="center">
  <img src="docs/screenshots/hero-code.png" width="32%" alt="Zion Code — editor + terminal + clipboard" />
  <img src="docs/screenshots/hero-graph.png" width="32%" alt="Zion Tree — visual commit graph with lane-colored cards" />
  <img src="docs/screenshots/hero-operations.png" width="32%" alt="Operations Center — full Git dashboard" />
</p>

---

## Why Zion?

Most Git GUIs make you choose: **pretty graphs** or **real terminals**. **Simple UI** or **power features**. **Native speed** or **AI smarts**.

Zion doesn't make you choose.

| | Other Git GUIs | Zion |
|---|---|---|
| **Terminal** | External app / fake shell | Real PTY with splits, tabs, zoom |
| **Editor** | None / basic viewer | Syntax highlighting, blame, Quick Open, code formatter |
| **Conflicts** | External merge tool | Built-in resolver (ours/theirs/both/edit) |
| **AI** | None or paid addon | 12 AI features (Claude / GPT / Gemini), free to configure |
| **Clipboard** | Copy-paste manually | Smart clipboard that auto-captures and pastes into terminal |
| **Mobile** | Nothing | Monitor terminals from your phone, approve AI prompts remotely |
| **Safety** | Hope for the best | Recovery Vault auto-snapshots before every destructive operation |
| **Hosting** | GitHub only | GitHub + GitLab + Bitbucket with auto-detection |
| **Performance** | Electron / web view | Native SwiftUI, zero web tech |
| **Price** | $50-100/year | Free and open source |

---

## What's New in 1.4.0

> Your Git workspace, everywhere.

- **Mobile Remote Access** — Monitor and control your Mac terminals from your phone. QR pairing, AES-256-GCM encryption, rich xterm.js terminal with full ANSI colors. Approve AI prompts from anywhere.
- **Recovery Vault** — Auto-snapshots before every destructive operation (reset --hard, rebase, discard). Never lose work again.
- **Git Hosting Providers** — GitHub, GitLab, and Bitbucket support with automatic remote URL detection. Inline PR comments and review submission.
- **Rich Mobile Terminal** — Replaced plain-text streaming with xterm.js for full ANSI color, bold/italic, cursor positioning, and TUI app support (Claude Code, Gemini, etc.)
- **AI Agent Integration** — Slash commands for Claude Code (`/zion-img`), Gemini CLI (`/zion-img`), and Codex CLI (`$zion-img`) — auto-installed when AI Inline Images is enabled.
- **Annotated & Signed Tags** — Create annotated and GPG-signed tags with message editor, push to remote, delete remote tags.
- **Force Push Options** — Force Push with Lease (safe) and Force Push (override) from branch context menu.
- **Code Formatter** — Built-in formatting for 16+ languages with format-on-save.
- **Security & Performance Audit** — Shell injection patches, connection limits, search debounce, batch mutations, design token adoption, accessibility labels.

---

## Beautiful by Design

Zion is the only Git workspace that brings the modern macOS **Glassmorphism** (UltraThinMaterial) aesthetic to your developer workflow. Whether you prefer deep indigo, classic dark, or a clean light theme, Zion looks stunning on every Mac.

<p align="center">
  <img src="docs/screenshots/dual-terminal.png" width="100%" alt="Zion Mode — Editor + dual terminal split" />
</p>
<p align="center">
  <img src="docs/screenshots/light-theme.png" width="100%" alt="GitHub Light — clean light theme for daytime" />
</p>


---

## Features at a Glance


### Zion Code — Editor + Terminal
> `Cmd+1`

A real code editor with syntax highlighting, Git Blame, Quick Open (`Cmd+P`), code formatter (16+ languages), file watcher, 7 themes (Dracula, Tokyo Night, Catppuccin Mocha, One Dark Pro, City Lights, GitHub Light, SynthWave '84), and configurable fonts. Side-by-side with a real PTY terminal that supports split panes, multiple tabs, independent zoom, Finder drag-and-drop, and inline image display.

<p align="center">
  <img src="docs/screenshots/hero-code.png" width="100%" alt="Zion Mode — Editor + Terminal" />
</p>

### Zion Tree — Visual Commit Graph
> `Cmd+2`

Lane-colored commit cards with colored left stripes matching branch lanes, merge edges, branch decorations, commit search with `Cmd+F`, jump bar for quick branch navigation, pending changes row at the top, status bar pills showing current branch and change count, GPG/SSH signature verification, and keyboard navigation with arrow keys.

<p>
  <img src="docs/screenshots/hero-graph.png" width="100%" alt="Graph" />
</p>

### Smart Clipboard
> The feature no other Git GUI has.

Zion watches your clipboard and auto-categorizes everything: commands, file paths, git hashes, URLs, even images. **Single-click** to paste into your active terminal. **Double-click** to paste and execute. **Drag** items directly into any terminal pane. It keeps your last 20 items and auto-cleans temp files.

<p align="center">
  <img src="docs/screenshots/clipboard.png" width="100%" alt="Smart Clipboard with auto-categorized items" />
</p>

### Operations Center
> `Cmd+3`

A dashboard for everything Git. Commit with hunk and line-level staging, interactive rebase (pick/squash/fixup/drop/reorder with drag), branch management (create/merge/rebase/rename/delete), stash management, cherry-pick, revert, reset, annotated/signed tag management, worktrees, submodules, remotes, reflog, and repo stats — all in one place.

<p align="center">
  <img src="docs/screenshots/hero-operations.png" width="100%" alt="Operations Center — full Git dashboard" />
</p>

### Mobile Remote Access
> Monitor your Mac from anywhere.

Scan a QR code to pair your phone with Zion. See live terminal output with full ANSI colors powered by xterm.js. Approve, deny, or abort AI prompts. Switch between terminal sessions across all open projects. Works over Cloudflare Tunnel (remote) or LAN (local Wi-Fi). All communication encrypted with AES-256-GCM.

<p align="center">
  <img src="docs/screenshots/mobile-remote.png" width="32%" alt="Mobile Remote Access — QR pairing and session list" />
  &nbsp;&nbsp;&nbsp;
  <img src="docs/screenshots/mobile-terminal.png" width="32%" alt="Mobile Terminal — live xterm.js with ANSI colors" />
</p>

### Recovery Vault
> Never lose work again.

Zion auto-snapshots your working tree before every destructive operation — reset --hard, interactive rebase, discard all changes. If something goes wrong, restore from the Recovery Vault in Operations Center. Snapshots are named `zion-pre-{operation}` and visible in the stash list.

### Worktree-First Workflow

Create worktrees with a smart prefix+name flow, open directly into Zion Code, and keep a dedicated terminal context per worktree. In Zion Tree, switch context through worktree pills, create branches directly from Pending Changes, and copy/move pending work safely across worktrees.

<p align="center">
  <img src="docs/screenshots/worktree-vault.png" width="100%" alt="Operations Center — Worktrees, Recovery Vault, Branches, and more" />
</p>

### Conflict Resolution
> Built-in. No external merge tools needed.

When a merge, rebase, or cherry-pick hits conflicts, Zion opens a dedicated resolver. A file list on the left shows conflict status with red/green icons. The inline editor on the right highlights conflict regions — **ours** (green) vs **theirs** (blue) — with one-click actions: accept ours, accept theirs, accept both, or edit manually. Once resolved, Zion auto-continues the operation.

### AI Assistant
> 12 features. 3 providers. Free to configure.

Works with Anthropic Claude, OpenAI GPT, or Google Gemini. Generate commit messages, explain diffs, draft PR descriptions, review code before committing, resolve conflicts with AI, search git history in natural language, summarize branches, explain blame entries, and suggest how to split large commits. API keys stored securely in macOS Keychain. Falls back to smart heuristics when AI is not configured.

<p align="center">
  <img src="docs/screenshots/ai-commit.png" width="49%" alt="AI-generated commit message in Zion Tree" />
  <img src="docs/screenshots/ai-review.png" width="49%" alt="AI Code Review side pane in Zion Tree" />
</p>

### Git Hosting Integration
> GitHub + GitLab + Bitbucket

Automatic provider detection from remote URLs. List open PRs, create PRs with AI-generated descriptions, post inline review comments, and submit reviews (approve/request changes). GitLab supports self-hosted instances. Bitbucket uses app passwords.

<p align="center">
  <img src="docs/screenshots/settings.png" width="100%" alt="Settings — Git hosting provider configuration" />
</p>

---

## Install

### Download

Grab the latest `.dmg` from [**Releases**](../../releases), open it, and drag **Zion.app** to Applications.

### Security Note (Current Distribution)

Zion releases are open source and currently distributed without Apple Developer ID notarization.

- Download only from the official [**Releases**](../../releases) page.
- On first launch, macOS Gatekeeper may block the app. Use **Right click > Open** for a per-app override.
- For maximum trust, build from source locally.

### Build from Source

```bash
git clone https://github.com/nicolaregattieri/zion-code.git
cd zion-code
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

Zion is keyboard-first. Press `Cmd+/` to see all shortcuts inside the app.

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
| `Cmd+R` | Refresh repository status |
| `Cmd+F` | Context search (graph / editor / terminal) |
| `Shift+Cmd+F` | Find in Files |
| `Shift+Cmd+R` | Open Code Review |
| `Shift+Alt+F` | Format Document |
| `Cmd+G` | Go to line |
| `Ctrl+Cmd+Z` | Toggle Zion Mode |
| `Ctrl+Cmd+J` | Focus / Zen Mode |
| `Ctrl+Plus` / `Ctrl+Minus` | Terminal zoom in / out |

---

## Feature Reference

<details>
<summary><strong>Full feature list</strong> (click to expand)</summary>

| Area | Features |
|------|----------|
| **Graph** | Lane-colored commit cards, commit search, jump bar, branch focus, pending changes with quick actions, worktree pills with dirty status, signature verification, keyboard navigation, paginated loading (up to 5000 commits), main branch pinned to lane 0 |
| **Editor** | Syntax highlighting, Quick Open, Git Blame, 7 themes, 5+ font families, code formatter (16+ languages), format on save, bracket pair highlight, indent guides, column ruler, find/replace, find in files, go to definition, find references, markdown preview, file history, multi-tab |
| **Terminal** | Real PTY (`/bin/zsh -l`), split panes (H/V), multiple tabs, independent zoom, font config, clipboard paste/drag, Finder drag-and-drop, inline images, hyperlink detection, scrollback buffer config, process preservation |
| **Clipboard** | Auto-capture, smart categorization (command/path/hash/URL/image/text), click-to-paste, double-click-to-execute, drag-and-drop, context-aware actions (hash → Show in Graph, branch → Checkout, path → Open) |
| **Operations** | Hunk staging, line staging, interactive rebase (visual drag-reorder), cherry-pick, revert, reset (soft/hard), stash management, annotated/signed tags, custom git commands, discard changes, force push with lease |
| **Conflicts** | Built-in resolver, ours/theirs/both/custom edit, AI-powered semantic resolution, auto-continue merge/rebase/cherry-pick |
| **Branches** | Checkout, create, merge, rebase, push, pull, rename, delete, force push (with lease / override), remote tracking |
| **Tags** | Create lightweight, annotated, and GPG-signed tags; push to remote; delete local and remote tags |
| **AI** | Commit messages, diff explanations, PR descriptions, code review, conflict resolution, changelog generator, semantic search, branch summarizer, blame explainer, commit split advisor, stash messages, pre-commit review gate. Providers: Anthropic / OpenAI / Google |
| **Git Hosting** | GitHub (via `gh` CLI), GitLab (PAT, self-hosted), Bitbucket (app passwords). Auto-detection from remote URLs. PR list, create, inline comments, review submission |
| **Mobile** | QR pairing, AES-256-GCM encryption, xterm.js terminal with ANSI colors, prompt actions (approve/deny/abort), quick actions (Ctrl+C/D, Esc, Tab, arrows), multi-project sessions, Cloudflare tunnel or LAN mode, keep-awake |
| **Recovery** | Auto-snapshot before destructive ops (reset, rebase, discard), named stash refs (`zion-pre-*`), restore from Operations Center |
| **Worktrees** | Smart create (prefix+name), graph quick-switch pills, copy/move pending changes, dedicated terminal, remove/prune |
| **Remotes** | Fetch all, pull, push (normal/force-with-lease/force), divergence warning, ahead/behind badges, add/remove, connection test |
| **Submodules** | Status, init, update (recursive), sync |
| **Reflog** | Visual viewer (last 50), undo last action (soft reset) |
| **Settings** | 6 tabs (General, Editor, Terminal, AI, Notifications, Mobile), language (PT-BR/EN/ES), external editor/terminal, background fetch, ntfy push notifications |
| **Diagnostics** | Ring-buffer logger, export/copy sanitized logs |

</details>

> Full reference with descriptions and shortcuts: [`docs/FEATURES.md`](docs/FEATURES.md)

---

## Themes

<p align="center">
  <img src="docs/screenshots/one-dark-pro.png" width="32%" alt="One Dark Pro theme" />
  <img src="docs/screenshots/hero-code.png" width="32%" alt="Zion Mode — SynthWave '84" />
  <img src="docs/screenshots/light-theme.png" width="32%" alt="GitHub Light theme" />
</p>

Zion ships with 7 curated editor + terminal palettes:

| Theme | Style |
|-------|-------|
| **Dracula** | Classic dark with vibrant accents |
| **Tokyo Night** | Deep indigo with soft pastels |
| **Catppuccin Mocha** | Warm dark with community-driven colors |
| **One Dark Pro** | The most popular VS Code theme |
| **City Lights** | Cool dark with muted tones |
| **GitHub Light** | Clean light theme for daytime |
| **SynthWave '84** | Neon cyberpunk (activated via Zion Mode) |

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
ZionApp / ContentView            App shell, navigation, toolbar
  -> RepositoryViewModel         Central state (@Observable, @MainActor)
    -> RepositoryWorker          Background Git operations (async/await)
      -> GitClient               Git CLI process execution
    -> GitGraphLaneCalculator    Lane & edge layout algorithm
    -> TerminalSession           PTY management (SwiftTerm + LocalProcess)
    -> AIClient                  Anthropic / OpenAI / Gemini (actor-isolated)
    -> HostingProvider           GitHub / GitLab / Bitbucket abstraction
    -> RemoteAccessServer        Mobile terminal streaming (HTTP polling)
    -> CloudflareTunnelManager   Secure remote access tunneling
```

Design pattern: **MVVM** with Swift Observation (`@Observable`).

---

## Contributing

Zion is open source and contributions are welcome. The `master` branch is protected — all changes must go through pull requests.

Before submitting a PR:

1. Make sure `swift build` passes
2. Test your changes with `./scripts/make-app.sh && open dist/Zion.app`
3. Add L10n keys for any user-facing strings in all 3 locales

---

## License

[MIT](LICENSE) — Use it, fork it, ship it.

## Acknowledgments

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza — Terminal emulator
- [xterm.js](https://xtermjs.org/) — Mobile terminal rendering
- [Sparkle](https://sparkle-project.org/) — Auto-update framework
- [Git](https://git-scm.com/) — The engine under the hood

---

<div align="center">
<sub>Built with SwiftUI by <a href="https://github.com/nicolaregattieri">Nicola Regattieri</a></sub>
</div>
