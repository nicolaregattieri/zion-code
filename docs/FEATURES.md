# Zion — Feature Reference

> Source of truth for the Help Sheet (`HelpSheet.swift`).
> When adding a new feature, add it here first, then update the SwiftUI view and L10n keys.

---

## Clone Repository

| Feature | Description |
|---------|-------------|
| Clone Sheet | Clone from URL with protocol detection (SSH/HTTPS) and destination picker |
| Welcome Screen | Available from the welcome screen for quick repository setup |

## Repository Statistics

| Feature | Description |
|---------|-------------|
| Stats Card | Commits, branches, tags, contributors, and language breakdown |
| Language Breakdown | Visual display of repository language composition |

## Branch Review (AI)

| Feature | Description |
|---------|-------------|
| Branch Diff Review | AI-powered branch-to-branch diff analysis with findings |

## Git Auth Prompt

| Feature | Description |
|---------|-------------|
| Credential Prompt | UI for entering credentials when remote operations fail (username/password or token) |

## Climbing Zion (First-Time Onboarding)

| Feature | Description |
|---------|-------------|
| 5-Step Flow | Welcome, Zion Tree, Zion Code, AI Assistant, Ready — guided introduction |
| First-Launch Detection | Shows only once via `UserDefaults` flag; returning users see normal WelcomeScreen |
| Feature Highlights | Each step showcases a pillar: graph visualization, code editor, terminal, AI |
| AI Setup (Optional) | Provider selection (Anthropic/OpenAI/Gemini) with direct API key links and inline input |
| Skip-Friendly | "Skip onboarding" link on step 0, "Skip for now" on AI step — non-blocking design |
| Localized | Full L10n support in Portuguese (BR), English, and Spanish |
| Navigation | Step dots, Back/Continue buttons, Enter/Escape keyboard shortcuts |

## Zion Tree (Graph Visualization)

| Feature | Description | Shortcut |
|---------|-------------|----------|
| Lane Graph | Visual graph with color-coded lanes showing branch/merge topology | — |
| Commit Search | Search by hash, author, or message with prev/next navigation | `⌘F` |
| Jump Bar | Instant scroll to main, develop, or default branch | — |
| Pending Changes | Uncommitted changes at the top with quick commit & stash | — |
| First Parent | Shows the first parent commit in commit details for merge context | — |
| Signature Verification | GPG/SSH commit signature status | — |
| Keyboard Navigation | Arrow keys to navigate commits, Escape to deselect | `↑↓` / `Esc` |
| Branch Focus | Double-click a branch to filter commits to that branch | — |
| Load More | Paginated loading (300 per page, up to 5000) | — |
| Path Breadcrumb | Breadcrumb navigation bar showing current file path with click-to-navigate | — |
| Commit AI Review | AI-powered single-commit review from the graph context menu | — |

## Zion Code (Editor)

| Feature | Description | Shortcut |
|---------|-------------|----------|
| Syntax Highlighting | NSTextView-based editor with regex caching | — |
| Quick Open | Fuzzy file search overlay | `⌘P` |
| File Browser | Tree view with smart 3-tier visibility, `.gitignore` respect, and dotfile toggle | `⌘B` toggle / `⇧⌘H` dotfiles |
| Git Blame | Inline per-line blame with author colors | `⇧⌘B` |
| Multiple Tabs | Open/close files with tab bar | — |
| Save File | Save current file to disk | `⌘S` |
| Unsaved Indicator | Visual dot on tabs with unsaved changes | — |
| Themes | Dracula, City Lights, GitHub Light, Catppuccin Mocha, One Dark Pro, Tokyo Night, SynthWave '84 | — |
| Fonts | SF Mono, Menlo, Monaco, Fira Code, JetBrains Mono | — |
| Line Spacing | Adjustable 0.8x–3.0x | — |
| Line Wrapping | Toggle on/off | — |
| New File | Create new untitled file in editor | `⌘N` |
| Save As | Save current file to a new location | `⇧⌘S` |
| Open in Editor | Open changed files from commit details, staging, or operations | — |
| File Browser Context Menu | Right-click: new file/folder, rename, duplicate, copy, cut, paste, delete, reveal in Finder | — |
| File Watcher | Auto-reload on external changes | — |
| Find/Replace | In-editor search with match highlighting and navigation | `⌘F` (alias `⌃F`) / `⌘H` / `⌘G` / `⇧⌘G` |
| Select Next Occurrence | Multi-cursor selection for next matching occurrence | `⌘D` |
| Go to Definition | Jump to symbol definition (opens in new tab) | `F12` / `⌘Click` |
| Find References | List references of the selected symbol across repository files | `⇧F12` |
| Markdown Preview | Optional side-by-side rendered preview for `.md` files with links and local images | — |
| Tab Size & Indent | Configurable 2/4/8 spaces or real tabs | Settings |
| Column Ruler | Thin vertical line at configurable column (80/100/120) | Settings |
| Bracket Pair Highlight | Highlights matching bracket when cursor is adjacent to `()[]{}` | Settings |
| Indent Guides | Subtle vertical lines at each indent level | Settings |
| Editor Settings Tab | Dedicated Settings tab for all editor preferences | `⌘,` |
| Per-Repo Config | `.zion/editor.json` overrides global editor settings | — |
| Go to Line | Jump to a specific line number | `⌘G` |
| File History | View commit history for any file from context menu or toolbar | — |
| Open With / Drag & Drop | Open files from Finder (Open With, double-click) or drag onto editor; auto-detects Git repo | — |
| Format Document | Built-in code formatting for 16+ languages (JSON, XML, HTML, CSS, JS/TS, Python, Go, Rust, Swift, SQL, YAML, and more) | `⇧⌥F` |
| Format on Save | Automatically format code when saving a file | Settings |
| JSON Sort Keys | Optional alphabetical key sorting for JSON formatting | Settings |

## Integrated Terminal

| Feature | Description | Shortcut |
|---------|-------------|----------|
| Real PTY | Native PTY with login shell and xterm-256color | — |
| Toggle Terminal | Show/hide terminal pane | `⌘J` |
| Maximize Terminal | Terminal-only layout | `⌃⌘J` |
| New Tab | Create new terminal tab | `⌘T` |
| Split Vertical | Split focused pane vertically | `⇧⌘D` |
| Split Horizontal | Split focused pane horizontally | `⇧⌘E` |
| Close Split | Close focused split pane | `⇧⌘W` |
| Zoom In/Out | Independent terminal font size | `⌃+` / `⌃-` |
| Font Settings | Configurable family and size | — |
| Session Persistence | Terminal sessions persist across repo switches with live processes | — |
| Transparency | Background transparency with blur effect, automatically enabled in Zen Mode | — |
| Background Badges | Orange badge on recent repos showing changed file count | — |
| Paste from Clipboard | Click clipboard item to paste | — |
| Drag to Terminal | Drag clipboard items into terminal | — |
| Scrollback Buffer | Configurable scrollback buffer size (1K–50K lines) | Settings |
| Bell Control | Enable/disable terminal bell sound | Settings |
| Hyperlink Detection | Clickable URLs in terminal output | Settings |
| Inline Images | Display images inline via `zion_display` (iTerm2 OSC 1337 protocol) | — |
| Voice Input | Dictate text to terminal via Apple Speech (free, real-time) or OpenAI Whisper | `⌥⌘X` |
| Voice Engines | Apple Speech for instant local recognition; Whisper for higher accuracy with API key | Settings |
| Voice Pill | Floating voice-active pill with waveform animation while listening | — |

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
| Search/Filter | Filter clipboard items by text content |
| Zen Mode Popover | Clipboard accessible via toolbar popover in zen mode |

## Zion Ops (Operations)

| Feature | Description |
|---------|-------------|
| Commit | Create commit with staging, amend option, AI message suggestion |
| Hunk Staging | Stage/unstage individual diff hunks |
| Line Staging | Stage selected lines from a hunk |
| Branch Management | Checkout, create, merge, rebase, push, pull, rename, delete |
| Tag Management | Create lightweight, annotated, and GPG-signed tags with message editor; push tags to remote; delete local and remote tags |
| Stash Management | Create (with message), apply, pop, drop stashes |
| Recovery Vault | Inspect active/dangling snapshots, copy refs, and restore recovery snapshots safely |
| Interactive Rebase | Visual UI: pick, reword, edit, squash, fixup, drop + reorder |
| Cherry-pick | Apply a specific commit onto current branch |
| Revert | Create revert commit |
| Reset (Soft/Hard) | Reset branch to a commit |
| Custom Command | Execute arbitrary `git` command |
| Discard Changes | Revert file changes (with confirmation) |
| Add to .gitignore | Ignore a file from context menu |
| Initialize Repository | Create a new Git repo from the welcome screen directory picker |

## Worktree Management

| Feature | Description |
|---------|-------------|
| Smart Branch Naming | Prefix picker (`feat/fix/chore/hotfix/exp`) + name input derives branch and path automatically |
| Advanced Mode | Manual `path + branch` fields behind "Advanced" disclosure |
| Inline Sidebar Create | `+ Novo Worktree` expands smart form directly in sidebar (no navigation needed) |
| Create & Open | `smartCreateWorktree()` creates and immediately opens the new context in Zion Code |
| Graph Worktree Pills | Cyan pills show `⊞ branch-name ● N` with in-pill dirty/conflict status |
| Remove Worktree | Remove and close associated terminal session |
| Prune | Clean up stale worktree metadata |
| Dedicated Terminal | Each worktree opens a split terminal pane |
| Reveal in Finder | Available from overflow menu on worktree cards |

## AI Assistant

| Feature | Description |
|---------|-------------|
| Commit Messages | Generate from staged diff (Anthropic/OpenAI/Gemini or heuristic fallback) |
| Diff Explanation | Plain-language explanation of a file diff |
| PR Description | Generate title and body from commit log with dynamic base branch selection |
| Stash Messages | Suggest descriptive stash messages |
| Smart Conflict Resolution | AI reads both sides of a merge conflict and proposes a semantically correct resolution |
| Code Review | Pre-commit code review that catches bugs, security issues, and style problems |
| Changelog Generator | Generates categorized release notes from a commit range (Features/Fixes/Improvements) |
| Semantic Search | Natural language search over git history ("when did we change the auth flow?") |
| Branch Summarizer | One-sentence summary of what any branch does, available in context menu |
| Blame Explainer | Click a blame entry to get an AI explanation of WHY that code was changed |
| Commit Split Advisor | Suggests how to split a large staged diff into multiple atomic commits |
| Commit Message Style | Toggle between compact (single-line) and detailed (header + bullet points) AI-generated messages |
| Pre-Commit Review Gate | Automatic AI review before committing — shows findings and lets you fix or commit anyway |
| Provider Config | Anthropic (Claude), OpenAI (GPT), Google (Gemini), API keys in Keychain |

## Zion Mode

| Feature | Description | Shortcut |
|---------|-------------|----------|
| Toggle | Activates SynthWave '84 neon cyberpunk theme across editor and terminal | `⌃⌘Z` |
| Settings Toggle | Available in Settings > General with gradient bolt icon | `⌘,` |
| Menu Item | Toggle from View > Zion Mode | `⌃⌘Z` |
| Theme Restore | Previous theme is saved and restored when Zion Mode is disabled | — |
| Auto-Disable | Picking a different theme in Editor Settings automatically disables Zion Mode | — |

## Settings Window

| Feature | Description | Shortcut |
|---------|-------------|----------|
| Native Settings | macOS Settings window with 6 tabs: General, Editor, Terminal, AI, Notifications, Mobile | `⌘,` |
| General Tab | Language, Appearance, Confirmation Mode | — |
| Editor Tab | Theme, font family/size, spacing, tab/indent, ruler, wrap, guides, bracket highlight | — |
| AI Tab | Provider, API key, Commit style, Diff explanation depth, Auto-explain | — |
| Notifications Tab | ntfy topic, events, PR polling interval, Auto-review toggle | — |
| Find in Files | Search across all repository files with grouped results and go-to-line | `⇧⌘F` |
| Ntfy Push Notifications | Configurable ntfy server/topic for push notifications on Git events and AI completions | Settings |
| Force Push Options | Force Push with Lease (safe) and Force Push (override) when push is rejected due to divergence | — |

## AI Diff Explanation

| Feature | Description |
|---------|-------------|
| Structured Analysis | Intent, Risks, and Narrative sections for every diff |
| Risk Severity | Color-coded badges (Safe/Moderate/Risky) with risk assessment |
| Auto-Explain | Automatically analyze diffs when selecting files |
| Copy to Clipboard | One-click copy of explanation text |

## Code Review

| Feature | Description | Shortcut |
|---------|-------------|----------|
| Full-Window Review | Dedicated 1000x700 window with file list and diff viewer | `⇧⌘R` |
| Per-File AI Analysis | Individual AI review for each changed file |  — |
| Inline PR Comments | View and post inline comments on PR diffs with reply threads | — |
| Review Submission | Submit reviews (Comment, Approve, Request Changes) with draft comments | — |
| Review Statistics | Files changed, additions/deletions, commit count, risk badge | — |
| Export Markdown | Export full review as Markdown for PR comments | — |
| Copy Summary | Copy review summary to clipboard | — |

## PR Inbox

| Feature | Description |
|---------|-------------|
| PR Queue | Sidebar card showing assigned PRs with status badges |
| All Open PRs | Browse all open PRs in the repo via segmented "All Open" tab |
| Auto-Review | AI automatically reviews assigned PRs when they arrive |
| Status Flow | Pending → Reviewing → Reviewed/Clean with severity badges |
| Notifications | macOS + ntfy push alerts when AI review completes |
| Open in Code Review | Click any PR (assigned or open) to open it in the full Code Review screen |

## Auto Updates

| Feature | Description |
|---------|-------------|
| Check for Updates | Manual check from Help menu via Sparkle framework |
| Automatic Checks | Background update check every 24 hours |
| Delta Updates | Smart downloads that only transfer version differences |
| EdDSA Signing | Secure update verification with EdDSA public key |

## Mobile Remote Access

| Feature | Description |
|---------|-------------|
| QR Pairing | Scan QR code from iPhone to pair with secure AES-256-GCM encrypted connection |
| Terminal Streaming | Live terminal output streamed to phone with throttled screen updates |
| Prompt Actions | Approve, Deny, and Abort buttons appear when Claude/AI prompts are detected |
| Quick Actions | Always-visible toolbar with Ctrl+C, Ctrl+D, Esc, Tab, Arrow Up, Arrow Down |
| Multi-Project Sessions | Sessions from all open repos (active + background) visible on phone, grouped by repo name |
| Text Input | Send commands and text to any terminal session from phone |
| LAN Mode | Connect over local Wi-Fi without Cloudflare tunnel |
| Cloudflare Tunnel | Secure remote access via Cloudflare tunnel (no port forwarding needed) |
| Prevent Sleep | Optional setting to keep Mac awake while remote server is active |
| Settings Tab | Dedicated Mobile tab in Settings with progressive onboarding |

## Git Hosting Integration

| Feature | Description |
|---------|-------------|
| Provider Abstraction | Protocol-based provider system supporting GitHub, GitLab, Bitbucket, and Azure DevOps |
| Auto-Detection | Automatically detects hosting provider from remote URLs (SSH and HTTPS) |
| GitHub | OAuth Device Flow sign-in, Personal Access Token, or `gh` CLI token — PRs, comments, reviews |
| GitLab | PAT authentication, self-hosted instance support, PR list and creation |
| Bitbucket | App password authentication, PR list and creation |
| Azure DevOps | PAT authentication with Code (Read & Write) scope, PR list and creation |
| PR List | Fetch and display open PRs for current repo |
| Create PR | Sheet to create PR from current branch with push validation |
| AI PR Description | Auto-generate title and body with dynamic base branch selection |
| Settings | Dedicated Git Hosting section in Settings for all provider credentials |

## Remote Management

| Feature | Description |
|---------|-------------|
| Fetch | `git fetch --all --prune` |
| Pull | `git pull --ff-only` |
| Push | `git push` with pre-push divergence check |
| Push Divergence Warning | Detects when branch is behind or diverged from remote before pushing; offers Pull First or Force Push with Lease |
| Ahead/Behind Badges | Status bar shows ↑N (ahead, blue) and ↓N (behind, orange) commit counts vs remote |
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
| Settings Window | Native macOS Settings window (`⌘,`) with General, Editor, Terminal, AI, Notifications, and Mobile tabs |
| Language | Portuguese (BR), English, Spanish, System |
| Appearance Mode | System, Light, Dark |
| Focus Mode | Full-screen code/terminal focus layout with explicit in-screen exit affordance (`⇧⌘J`) |
| Confirmation Mode | Never / Destructive Only / All |
| Background Fetch | Auto-checks remote every 60s |
| Recent Repositories | Root-only list (up to 10) with per-project `WT n` badge |

## Diagnostics

| Feature | Description |
|---------|-------------|
| Diagnostic Log | Ring-buffer logger captures errors, git commands, and AI calls |
| Export Log | Save sanitized diagnostic log to file (Help menu) |
| Copy Log | Copy sanitized log to clipboard for quick sharing |

## Git Bisect (Bug Finder)

| Feature | Description |
|---------|-------------|
| Start Bisect | Right-click any commit → "Find Bug with Bisect..." marks it as bad, prompts for good commit |
| Active Bisect Banner | Top banner with "This Works" / "This is Broken" / "Skip" / "Abort" buttons during binary search |
| Commit Visual States | Green (good), red (bad), blue (testing), culprit badge on the first bad commit |
| AI Culprit Explanation | When culprit is found, AI automatically explains what changed and why it likely caused the regression |
| Status Bar Pill | Capsule badge shows current bisect phase and step count |
| Bisect Detection | Detects ongoing bisect sessions (e.g. started from terminal) and syncs UI state |

## Wave 2 — Differentiation & Polish

| Feature | Description |
|---------|-------------|
| Terminal Search | Cmd+F search within terminal (prev/next/close) using SwiftTerm's built-in search |
| Stash Count Badge | Badge on Operations workspace button showing stash count when > 0 |
| Branch Search | Filter branches by name in the sidebar branch explorer |
| Commit Stats | Insertions (+N) and deletions (-M) shown per commit in the graph |
| AI Pending Changes Summary | One-click AI summary of what you've been working on, with "Use as commit message" |
| Smart Clipboard Actions | Context-aware actions: git hashes → Show in Graph, branch names → Checkout, file paths → Open in Editor |
| Author Avatars | Optional Gravatar identicons shown next to author names in the commit graph |

## Known Edge Case (Revisit)

| Topic | Current Behavior | Follow-up |
|-------|------------------|-----------|
| Stash transfer on same file/line across worktrees | Git may block `stash apply` with local-overwrite errors and no unmerged (`-U`) files. In this path, Zion shows support/recovery flow instead of opening conflict resolver. | Add deterministic same-file transfer strategy so users can resolve this case with less manual stash juggling. |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘1` | Code workspace |
| `⌘2` | Graph workspace |
| `⌘3` | Operations workspace |
| `⌘/` | Keyboard shortcuts sheet |
| `⌘P` | Quick Open |
| `⌘B` | Toggle file browser |
| `⌘N` | New file |
| `⌘S` | Save file |
| `⇧⌘S` | Save As |
| `⌘R` | Refresh repository status |
| `⌘,` | Open settings window |
| `⌘J` | Toggle terminal |
| `⌃⌘J` | Maximize terminal |
| `⌘T` | New terminal tab |
| `⇧⌘D` | Split vertical |
| `⇧⌘E` | Split horizontal |
| `⇧⌘W` | Close split pane |
| `⌃+` | Terminal zoom in |
| `⌃-` | Terminal zoom out |
| `⌘F` | Context search (graph, editor, terminal) |
| `⌃F` | Find alias in editor |
| `⌘G` | Go to Line / Find Next (when search open) |
| `⇧⌘G` | Find Previous |
| `⌘H` | Find & Replace |
| `⌘Delete` | Delete selected file/folder in file browser |
| `⌘D` | Select Next Occurrence |
| `F12` | Go to Definition |
| `⇧F12` | Find References |
| `⇧⌘R` | Code Review |
| `⇧⌘H` | Toggle dotfiles visibility |
| `⇧⌘B` | Toggle Git Blame |
| `⇧⌘G` | Bisect: mark commit as good |
| `⇧⌘B` | Bisect: mark commit as bad |
| `⇧⌘S` | Bisect: skip commit |
| `⇧⌥F` | Format Document |
| `⌃⌘Z` | Toggle Zion Mode |
| `⌥⌘X` | Voice Input |
| `⇧⌘J` | Focus/Zen Mode |
| `↑↓` | Navigate commits |
| `Esc` | Deselect / close |
