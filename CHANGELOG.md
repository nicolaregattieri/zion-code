# Changelog

All notable changes to Zion are documented here.

---

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
