# Zion — Feature Reference

> Source of truth for the Help Sheet (`HelpSheet.swift`).
> When adding a new feature, add it here first, then update the SwiftUI view and L10n keys.

---

## Zion Tree (Graph Visualization)

| Feature | Description | Shortcut |
|---------|-------------|----------|
| Lane Graph | Visual graph with color-coded lanes showing branch/merge topology | — |
| Commit Search | Search by hash, author, or message with prev/next navigation | `⌘F` |
| Jump Bar | Instant scroll to main, develop, or default branch | — |
| Pending Changes | Uncommitted changes at the top with quick commit & stash | — |
| Signature Verification | GPG/SSH commit signature status | — |
| Keyboard Navigation | Arrow keys to navigate commits, Escape to deselect | `↑↓` / `Esc` |
| Branch Focus | Double-click a branch to filter commits to that branch | — |
| Load More | Paginated loading (300 per page, up to 5000) | — |

## Zion Code (Editor)

| Feature | Description | Shortcut |
|---------|-------------|----------|
| Syntax Highlighting | NSTextView-based editor with regex caching | — |
| Quick Open | Fuzzy file search overlay | `⌘P` |
| File Browser | Tree view with `.gitignore` respect | `⌘B` toggle |
| Git Blame | Inline per-line blame with author colors | — |
| Multiple Tabs | Open/close files with tab bar | — |
| Save File | Save current file to disk | `⌘S` |
| Unsaved Indicator | Visual dot on tabs with unsaved changes | — |
| Themes | Dracula, GitHub Light, Monokai, etc. | — |
| Fonts | SF Mono, Menlo, Monaco, Fira Code, JetBrains Mono | — |
| Line Spacing | Adjustable 0.8x–3.0x | — |
| Line Wrapping | Toggle on/off | — |
| File Watcher | Auto-reload on external changes | — |

## Integrated Terminal

| Feature | Description | Shortcut |
|---------|-------------|----------|
| Real PTY | Native PTY with login shell and xterm-256color | — |
| Toggle Terminal | Show/hide terminal pane | `⌘J` |
| Maximize Terminal | Terminal-only layout | `⇧⌘J` |
| New Tab | Create new terminal tab | `⌘T` |
| Split Vertical | Split focused pane vertically | `⇧⌘D` |
| Split Horizontal | Split focused pane horizontally | `⇧⌘E` |
| Close Split | Close focused split pane | `⇧⌘W` |
| Zoom In/Out | Independent terminal font size | `⌃+` / `⌃-` |
| Font Settings | Configurable family and size | — |
| Paste from Clipboard | Click clipboard item to paste | — |
| Drag to Terminal | Drag clipboard items into terminal | — |

## Smart Clipboard

| Feature | Description |
|---------|-------------|
| Auto-Capture | Monitors system clipboard every 0.5s |
| Smart Categories | Detects: command, path, git hash, URL, image, text |
| Click to Paste | Single click sends text to active terminal |
| Double-Click Execute | Double click sends text + newline (executes) |
| Drag & Drop | Drag items directly into terminal pane |
| Image Capture | Saves copied images to temp dir as JPEG |
| Auto-Cleanup | Temp images purged after 1h, full cleanup on quit |
| Item Limit | Keeps up to 20 items, evicts oldest |

## Operations Center

| Feature | Description |
|---------|-------------|
| Commit | Create commit with staging, amend option, AI message suggestion |
| Hunk Staging | Stage/unstage individual diff hunks |
| Line Staging | Stage selected lines from a hunk |
| Branch Management | Checkout, create, merge, rebase, push, pull, rename, delete |
| Tag Management | Create and delete lightweight tags |
| Stash Management | Create (with message), apply, pop, drop stashes |
| Interactive Rebase | Visual UI: pick, reword, edit, squash, fixup, drop + reorder |
| Cherry-pick | Apply a specific commit onto current branch |
| Revert | Create revert commit |
| Reset (Soft/Hard) | Reset branch to a commit |
| Custom Command | Execute arbitrary `git` command |
| Discard Changes | Revert file changes (with confirmation) |
| Add to .gitignore | Ignore a file from context menu |

## Worktree Management

| Feature | Description |
|---------|-------------|
| Add Worktree | Create at specified path with optional branch |
| Quick Create | One-click with auto-generated path and branch |
| Remove Worktree | Remove and close associated terminal |
| Prune | Clean up stale worktree metadata |
| Dedicated Terminal | Each worktree opens a split terminal pane |
| Open in Finder | Reveal worktree directory |

## AI Assistant

| Feature | Description |
|---------|-------------|
| Commit Messages | Generate from staged diff (Anthropic/OpenAI/Gemini or heuristic fallback) |
| Diff Explanation | Plain-language explanation of a file diff |
| PR Description | Generate title and body from commit log |
| Stash Messages | Suggest descriptive stash messages |
| Smart Conflict Resolution | AI reads both sides of a merge conflict and proposes a semantically correct resolution |
| Code Review | Pre-commit code review that catches bugs, security issues, and style problems |
| Changelog Generator | Generates categorized release notes from a commit range (Features/Fixes/Improvements) |
| Semantic Search | Natural language search over git history ("when did we change the auth flow?") |
| Branch Summarizer | One-sentence summary of what any branch does, available in context menu |
| Blame Explainer | Click a blame entry to get an AI explanation of WHY that code was changed |
| Commit Split Advisor | Suggests how to split a large staged diff into multiple atomic commits |
| Provider Config | Anthropic (Claude), OpenAI (GPT), Google (Gemini), API keys in Keychain |

## GitHub Integration

| Feature | Description |
|---------|-------------|
| PR List | Fetch and display open PRs for current repo |
| Create PR | Sheet to create PR from current branch |
| AI PR Description | Auto-generate title and body |

## Remote Management

| Feature | Description |
|---------|-------------|
| Fetch | `git fetch --all --prune` |
| Pull | `git pull --ff-only` |
| Push | `git push` |
| Add/Remove Remote | Manage remote URLs |
| Test Connection | Verify remote connectivity |

## Submodule Management

| Feature | Description |
|---------|-------------|
| Status | List submodules with init/modified/up-to-date status |
| Init | Initialize submodules |
| Update | Update (with optional `--recursive`) |
| Sync | Synchronize submodule URLs |

## Reflog / Undo

| Feature | Description |
|---------|-------------|
| Reflog Viewer | Last 50 entries with hash, action, message, date |
| Undo Last Action | Reset `--soft` to previous reflog entry |

## Customization & Settings

| Feature | Description |
|---------|-------------|
| Language | Portuguese (BR), English, Spanish, System |
| External Editor | VS Code, Cursor, Antigravity, Xcode, IntelliJ, Sublime, custom |
| External Terminal | Terminal.app, iTerm, Warp, custom |
| Confirmation Mode | Never / Destructive Only / All |
| Background Fetch | Auto-checks remote every 60s |
| Recent Repositories | Quick access to last 5 opened repos |

## Diagnostics

| Feature | Description |
|---------|-------------|
| Diagnostic Log | Ring-buffer logger captures errors, git commands, and AI calls |
| Export Log | Save sanitized diagnostic log to file (Help menu) |
| Copy Log | Copy sanitized log to clipboard for quick sharing |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘1` | Code workspace |
| `⌘2` | Graph workspace |
| `⌘3` | Operations workspace |
| `⌘?` | Keyboard shortcuts sheet |
| `⌘P` | Quick Open |
| `⌘B` | Toggle file browser |
| `⌘S` | Save file |
| `⌘J` | Toggle terminal |
| `⇧⌘J` | Maximize terminal |
| `⌘T` | New terminal tab |
| `⇧⌘D` | Split vertical |
| `⇧⌘E` | Split horizontal |
| `⇧⌘W` | Close split pane |
| `⌃+` | Terminal zoom in |
| `⌃-` | Terminal zoom out |
| `⌘F` | Search graph |
| `↑↓` | Navigate commits |
| `Esc` | Deselect / close |
