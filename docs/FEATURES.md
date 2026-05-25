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

## Contextual Feature Tour

| Feature | Description |
|---------|-------------|
| Spotlight Tour | Replayable 5-step guided tour highlighting key areas: recent repos, workspace switcher, graph, zen mode, worktrees |
| Replay Anytime | Launch from Help Sheet or "Replay feature tour" button — not limited to first launch |
| Visual Spotlight | Overlay with glassomorphic card and spotlight cutout on the target area |

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
| Commit Detail Loading | Loading spinners for commit details and file diffs with instant re-access via smart caching | — |
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
| File Browser Drag & Drop | Move files and folders within the repo by dragging; drop on empty space to move to root; import from Finder or Smart Clipboard | — |
| File Watcher | Auto-reload on external changes | — |
| Find/Replace | In-editor search with match highlighting and navigation | `⌘F` (alias `⌃F`) / `⌥⌘F` / `⌃G` / `⇧⌘G` |
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
| Go to Line | Jump to a specific line number | `⌃G` |
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
| New Tab | Create new terminal tab | `⇧⌘T` |
| Split Vertical | Split focused pane vertically | `⇧⌘D` |
| Split Horizontal | Split focused pane horizontally | `⇧⌘E` |
| Close Split | Close focused split pane | `⇧⌘W` |
| Resizable Splits | Drag dividers between split panes to resize; double-tap to reset 50/50 | — |
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
| Voice Pill | Floating voice-active pill with waveform animation while listening |
| Whisper Recovery | Graceful fallback to Apple Speech when Whisper is unavailable (quota, key missing, service down) with recovery guidance | — |

## Smart Clipboard

| Feature | Description |
|---------|-------------|
| Auto-Capture | Monitors system clipboard every 0.5s |
| Smart Categories | Detects: command, path, git hash, URL, image, text |
| Click to Paste | Single click sends text to active terminal |
| Double-Click Execute | Double click sends text + newline (executes) |
| Drag & Drop | Drag items directly into the terminal pane, or drop onto the file browser to import into the repository |
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
| Recovery Vault | Inspect active/dangling snapshots with paginated "Show More" view, copy refs, and restore safely |
| Stash & Tags Empty States | Helpful guidance text when stash or tag lists are empty |
| Interactive Rebase | Visual UI: pick, reword, edit, squash, fixup, drop + reorder |
| Cherry-pick | Apply a specific commit onto current branch |
| Revert | Create revert commit |
| Reset (Soft/Hard) | Reset branch to a commit with confirmation showing lost commit count and uncommitted files |
| Active Operation Banner | Persistent banner during merge/rebase/cherry-pick with Continue and Abort buttons plus conflict count |
| Abort Warning | Confirmation dialog before aborting operations when files have been resolved |
| Friendly Error Messages | User-friendly messages for rebase conflicts, detached HEAD, diverged branches, submodule errors, and more |
| Network Retry | Automatic single retry with 2s delay for transient network failures on push/pull/fetch |
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
| Quota Exceeded Banner | Actionable banner when AI quota is reached with "Switch Provider" and "Dismiss" buttons |
| Concurrency Gate | Limits concurrent AI operations (max 2) with user-visible "busy" message |
| Code Review Progress | Per-file progress indicator showing "Reviewing file 3/12: FileName.swift" |
| Provider Config | Anthropic (Claude), OpenAI (GPT), Google (Gemini), API keys in Keychain |
| Connected Providers | Multiple AI providers connected simultaneously — e.g., keep OpenAI for Whisper while using Claude as default |

## Zion Bridge

| Feature | Description |
|---------|-------------|
| AI Portability | Sync AI configurations (CLAUDE.md, .cursor/rules, AGENTS.md, GEMINI.md) between tools |
| Analyze & Sync | Discover source artifacts, map to destination paths, preview rendered content, and sync selected files |
| AI Smart Sync | Optional AI-powered content transformation that adapts semantics for the destination tool |
| Content Validation | Automatic compatibility checks per destination (frontmatter, syntax leaks, unsupported directives) with amber warning indicators |
| Compatibility Score | AI-generated 0-100% confidence score shown per file after AI Smart Sync |
| Cache-Based Mapping | Hash-based cache ensures repeat syncs are deterministic and fast |
| Loading & Cancel | Background analysis/apply with progress indicator and cancel button |
| Preview Truncation | Smart truncation at nearest newline with "[truncated]" indicator |

## AI Modes

| Feature | Description |
|---------|-------------|
| Efficient Mode | Fastest responses with lower token usage — good for simple tasks |
| Smart Mode | Balanced quality and speed — default for most workflows |
| Best Quality Mode | Maximum reasoning depth — best for complex code review and analysis |
| Mode-Aware Routing | AI provider and model selection adapts to the chosen mode |

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
| Notifications Tab | ntfy topic, pull request events, PR polling interval, Auto-review toggle | — |
| Find in Files | Search across all repository files with grouped results and go-to-line | `⇧⌘F` |
| Ntfy Push Notifications | Configurable ntfy server/topic for push notifications on Git events and AI completions | Settings |
| PR Merged/Closed Alerts | Notification when a tracked PR is merged or closed during polling | Settings |
| Keep-Awake Warnings | Local notifications at 15 min and 5 min before prevent-sleep timer expires | — |
| Notification Retry | Failed notifications are queued (max 10) and retried on next successful send | — |
| PR Event Batching | Multiple PR notifications within 30 seconds are batched into a single summary | — |
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
| All Open PRs | Browse all open PRs in the repo via segmented "All Open" tab, refreshed on the PR polling cadence |
| Auto-Review | AI automatically reviews assigned PRs when they arrive |
| Status Flow | Pending → Reviewing → Reviewed/Clean with severity badges |
| Notifications | macOS + ntfy push alerts for new PRs, review requests, and AI review completion |
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
| Settings | Git Hosting section in Settings > General tab for all provider credentials |

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
| Focus Mode | Full-screen code/terminal focus layout with explicit in-screen exit affordance (`⌘T`) |
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

All shortcuts are customizable via the Keyboard Shortcuts editor (`⌥⌘K`). Click any shortcut row to record a new key combination.

| Shortcut | Action |
|----------|--------|
| `⌘1` | Code workspace |
| `⌘2` | Graph workspace |
| `⌘3` | Operations workspace |
| `⌘E` | Code workspace (mnemonic) |
| `⌘G` | Graph workspace (mnemonic) |
| `⌥⌘K` | Keyboard shortcuts sheet |
| `⌘P` | Quick Open |
| `⌘B` | Toggle file browser |
| `⌘N` | New file |
| `⌘S` | Save file |
| `⇧⌘S` | Save As |
| `⌘R` | Refresh repository status |
| `⌘,` | Open settings window |
| `⌘J` | Toggle terminal |
| `⌃⌘J` | Maximize terminal |
| `⇧⌘T` | New terminal tab |
| `⇧⌘D` | Split vertical |
| `⇧⌘E` | Split horizontal |
| `⇧⌘W` | Close split pane |
| `⌃+` | Terminal zoom in |
| `⌃-` | Terminal zoom out |
| `⌘F` | Context search (graph, editor, terminal) |
| `⌃F` | Find alias in editor |
| `⌃G` | Go to Line / Find Next (when search open) |
| `⇧⌘G` | Find Previous |
| `⌥⌘F` | Find & Replace |
| `⌘Delete` | Delete selected file/folder in file browser |
| `⌘D` | Select Next Occurrence |
| `F12` | Go to Definition |
| `⇧F12` | Find References |
| `⇧⌘R` | Code Review |
| `⇧⌘H` | Toggle dotfiles visibility |
| `⇧⌘B` | Toggle Git Blame |
| `⌃⌘G` | Bisect: mark as good (active bisect only) |
| `⌃⌘B` | Bisect: mark as bad (active bisect only) |
| `⌃⌘S` | Bisect: skip commit (active bisect only) |
| `⇧⌥F` | Format Document |
| `⌃⌘Z` | Toggle Zion Mode |
| `⌥⌘X` | Voice Input |
| `⌘T` | Focus/Zen Mode |
| `⌘Enter` | Quick Commit |
| `⇧⌘A` | Stage All |
| `↑↓` | Navigate commits |
| `Esc` | Deselect / close |

---

## Zion Talks (beta) — AI Chat Workflow

> Zion is an **AI workflow workspace** with a native git layer underneath, not just a git client. Zion Talks is the chat surface that drives the workflow.

### Providers

| Feature | Description |
|---------|-------------|
| Multi-provider chat | Anthropic, OpenAI, Gemini, OpenRouter, local OpenAI-compatible (Ollama / MLX / LM Studio / llama.cpp), Claude CLI, Codex CLI |
| Subscription CLIs | Spawns the user's installed `claude` and `codex` CLIs as subprocesses, using existing Claude Pro and ChatGPT Plus subscriptions instead of paid API keys |
| Local LLM auto-start | Zion starts Ollama / MLX / LM Studio / llama.cpp on demand when the chat needs it, with a Stop button in Settings |
| Model picker per provider | Composer dropdown lists each provider's available models; static curated lists + dynamic discovery for local |
| Auto routing | Pick `Auto` in the composer to let Zion's `ProviderOrchestrator` select per task via a per-lane fallback chain (Summaries / General / Reviews / Reasoning). Configurable in Settings → Zion Talks → Routing Policy |
| Provider switch banner | On 429 / network failure mid-conversation, Zion fails over to the next provider in the chain and surfaces a small banner explaining the switch |

### Tools

| Feature | Description |
|---------|-------------|
| Zion MCP server | Embedded MCP server exposes git ops as tools to spawned CLIs: `zion_git_log`, `zion_branch_list`, `zion_pending_changes`, `zion_commit_inspect`, `zion_stash_list`, `zion_stash_apply`, `zion_worktrees`, `zion_repo_memory_search`, `zion_open_in_editor`, `zion_edit`, `zion_repo_map` |
| Universal tool bridge | API providers (Anthropic / OpenAI / Gemini / OpenRouter / local) gain the same MCP tools via client-side schema translation and a tool-call loop |
| Capability probe | Caches per-(provider, model) function-calling support for 24 h so local models without FC fall back gracefully |
| Repo map | Tree-sitter-style symbol scanner across Swift / TS / JS / Python / Go / Rust + PageRank ranking, queried via `zion_repo_map` |

### Plan mode

| Feature | Description |
|---------|-------------|
| Plan-first toggle | Header toggle puts the model in plan mode (`--permission-mode plan` for claude) so it proposes a structured plan before touching files |
| Plan card | Inline `<plan><step>` XML rendered as a card with Apply / Reject / Edit-raw buttons |
| Recovery-vault snapshot | Apply takes a `zion-pre-plan-apply-<sha>` git stash snapshot before re-running the turn |

### Edit harness

| Feature | Description |
|---------|-------------|
| SEARCH/REPLACE edit primitive | Streamed `<<<<<<< SEARCH … ======= … >>>>>>> REPLACE` blocks parsed in real time into preview cards |
| Apply ladder | exact match → whitespace-normalized → strip-indent → fuzzy (≥0.92) → reflection → 3-strike whole-file rewrite |
| Per-block diff preview | Each block renders as a card with the before/after diff, Apply / Reject / Edit-raw buttons |
| Apply all | Footer button applies every block in order, stops at the first failure, leaves the recovery snapshot intact |
| Auto-commit | After all blocks land, Zion stages the touched files and commits with an AI-suggested message prefixed `aiedit:` |
| Path safety | Rejects absolute paths and `..` traversal before any file write |

### Session + cost

| Feature | Description |
|---------|-------------|
| Session resume | Captures `session_id` from claude / `thread_id` from codex on first turn; subsequent turns reuse the same server-side session via `--resume` |
| Cost meter | Live USD pill in the conversation card header (claude reports `total_cost_usd`; codex Plus and local are unmetered) |
| Token meter | Live `k tok` pill per thread for every provider that reports usage |
| Cost budget | Per-provider daily $ cap in Settings — Auto routing skips providers over budget until local midnight |

### Context

| Feature | Description |
|---------|-------------|
| Sticky context | Auto-injected git context (`/diff`, `/log`, `/status`) stays attached to the thread across turns until the intent classifier picks a different one |
| Slash commands | `/diff`, `/log`, `/status`, `/file <path>`, `/commit <sha>` expand inline in the composer |
| Tool harness toggle | Settings → Zion Talks → Tool harness — opts the chat in/out of the universal tool bridge |
| Allow file edits | Settings toggle gating CLI Edit/Write tools (defaults off for CLI providers) |

### History

| Feature | Description |
|---------|-------------|
| Per-repo threads | Thread sidebar lives inside the chat card; SQLite-backed persistence per repo |
| Auto-title | First user message of a new thread renames it to the first 60 characters |
| Cross-launch persistence | Threads, messages, edit history, plan state, cost totals and session IDs all persist between Zion launches |

### Agentic Loop (beta)

> Multi-step autonomous tool execution across all supported providers. The agent runs a full tool-call loop without user input per step, stopping only when it reaches a terminal state, a hard cap, or the user cancels.

| Feature | Description |
|---------|-------------|
| Multi-provider loop | Full agentic loop on Anthropic, OpenAI, Gemini, OpenRouter, and local models (Qwen2.5-Coder, Qwen3-Coder). Claude CLI and Codex CLI pass through to their own internal loop. |
| Plan-first mode | Header toggle asks the model to propose a structured plan before any file is touched; user approves or rejects before the loop begins. |
| Bash tool | Safe shell execution inside the loop. Each command is checked against the active approval tier and optional per-command allowlist. Recovery-vault snapshot created before destructive shell operations. |
| Approval tiers | Three configurable tiers: **readOnly** (no file writes or shell), **workspaceWrite** (file edits inside the repo, no arbitrary shell), **fullAccess** (any command without prompting). Set per-session in the chat toolbar. |
| Sticky provider | The provider chosen at loop start is locked for every step. No automatic failover during an active loop — switch providers between sessions instead. |
| Hard caps | Configurable max-step count and per-provider daily cost budget. Loop halts and surfaces a summary when either cap is hit. User can cancel at any step via the step indicator. |
| ReAct text fallback | Local models without native function-calling support use a structured Thought / Action / Observation text loop (ReAct format). Older quantized models (Mistral, older LLaMA) automatically fall back to this mode. |
| Step indicator | Live capsule badge in the conversation header shows current step N / max and cumulative cost during a running loop. |

### Smart Context (beta)

Closes the Cursor-parity gap for vibe coding while staying provider-agnostic.

- **Repomap MCP tool** — `repo_map` returns a Markdown outline of the most relevant files + symbols, ranked by PageRank (focusFiles 50×, history 10×, mentioned identifiers 5×). Every provider gets a free "table of contents" to reduce blind grep calls.
- **find_symbol MCP tool** — Precise identifier lookup across the repo, faster than grep for "where is `X` defined".
- **@file / @folder / @selection / @web mentions** — Explicit context attachment in the composer. NSTextView-backed autocomplete popup, code-fence aware, with per-folder + per-file byte caps.
- **Multi-file diff summary** — When the agent changes ≥2 files, a single card surfaces the file list + Approve all / Reject all / Review all actions.
- **Settings → Zion Talks → Smart Context** — Toggle indexing, max files per @folder, max bytes per @file, token-confirm threshold, stats footer.
- **Cross-provider universal** — Works with Anthropic, OpenAI, Gemini, local models with tool calling, ReAct fallback for older models, Claude CLI and Codex CLI passthrough.

### Context Management (beta)

Cursor-parity context management on top of the agentic loop.

- **Token-aware history window** — Replaces the legacy 10-message cap. Drops oldest assistant prose first; pinned `@file` / `@selection` blocks survive.
- **Auto-compact at 75% of context window** — Older turns summarized via a cheap model (Haiku / 4o-mini / Flash), pinned attachments preserved verbatim.
- **Anthropic prompt caching** — `cache_control: ephemeral` on the system block. Multi-step loops pay only for the new round.
- **OpenAI auto-cache reorder** — System + tools at the head so automatic prefix caching engages.
- **Tool-result eviction in agentic loop** — Old `tool_result` blocks rewritten as `[elided: N bytes — earlier round]` once newer rounds exist.
- **Pre-send budget gate** — Banner blocks send when the request would exceed the model's window; user can override with `send anyway` or run a manual compaction.
- **Repomap auto-seed** — Top-K Markdown outline (~1.5k tokens) injected on every turn as cache-friendly system context.
- **Unified Approval Policy** — One picker (Manual / Auto-safe / Auto / YOLO) controls plan-mode, auto-commit, and bash tier. Legacy settings migrate automatically.
- **@web excerpt mode** — Pages > 32 KB chunk + BM25-lite rank against the user prompt; only top excerpts are injected.
- **ByteSafe truncation** — UTF-8 safe; no more half-emoji / half-CJK in `@file` or `@folder` payloads.

### Discoverability (beta)

Power-user surface that exposes what Zion Talks can do without spelunking through docs.

- **Slash autocomplete** — Type `/` in the composer; an inline dropdown lists every built-in command (`/diff`, `/log`, `/file`, `/status`, `/commit`, `/clear`, `/compact`, `/help`) plus every skill auto-loaded from `~/.claude/skills/` and `<repo>/.claude/skills/`. Arrow keys + Tab/Enter commit, Esc dismiss.
- **`/help` card** — Renders a structured SwiftUI card with collapsible sections (Built-in / Project Skills / User Skills / @ mentions / MCP tools / Shortcuts).
- **MCP servers panel** — Settings → Zion Talks → MCP Servers lists every configured MCP server with status dot + ellipsis menu (edit / remove). New Server sheet has 3 preset buttons (filesystem / git / github) + JSON editor. `Find more servers →` opens `registry.modelcontextprotocol.io` externally.
- **Skill scaffold** — Settings → Zion Talks → Skills lists every available skill. `New Skill` button writes `<scope>/.claude/skills/<slug>/SKILL.md` with starter template + YAML frontmatter. Invoke via `/skill-name` in chat — body appended as `[skill: <name>]` to the system prompt.
- **Spend meter** — Conversation card header shows a monthly spend pill: `$X.XX this month` for API providers, `Subscription · no API spend` for Claude CLI / Codex CLI, `$0 · local` for Ollama / MLX. Settings → Usage lists provider × model breakdown + soft-cap stepper.
- **Auto resolved chip** — When `Auto` provider is selected, the composer shows a chip ("Auto → Claude") so the user sees the orchestrator's pick.
- **Empty-state hero** — Brand-new threads show 4 starter cards: Browse repo (`/repo_map`), Edit a file (`@file`), Run tests (`/bash swift test`), Type / for all commands (`/help`). Click prefills the composer.
- **Discoverable placeholder** — Composer reads `Message · / for commands · @ for files`.

### Smart Auto v1 (beta)

Tier-aware routing, local-LLM model awareness, and onboarding polish shipped with PR #459 + #460.

- **Smart Auto tier routing** — Auto mode classifies every user message into `easy` / `medium` / `hard` and routes to a per-provider model (Claude: Haiku / Sonnet / Opus, OpenAI: gpt-4o-mini / 4o / o1, Gemini: Flash / Pro). The resolved chip (`Auto → Claude · sonnet · medium`) is color-coded by tier and updates live while you type.
- **Local LLM model discovery** — Zion scans Ollama, LM Studio, MLX, and llama.cpp default folders plus a user-configurable custom folder to enumerate which models exist on disk without spawning a server. The discovered list feeds the composer dropdown and the Smart Auto router.
- **Local-server status bar** — When a local LLM server is reachable, a bar inside the composer surfaces the active model, system RAM pressure, per-server RSS, and a Disconnect button. Zion never auto-disconnects; the bar clears only via the explicit Disconnect button or when the server is stopped manually.
- **Local auto-start banner** — When Auto could benefit from the local LLM but the server is off, a banner offers `Start once` / `Always start` / `Not now` / `Never ask`. The choice persists via `LocalAutoStartPolicy`. Zion never auto-spawns a server without consent.
- **Per-thread streaming** — Switching threads mid-stream no longer cancels the response. Background-streaming threads show a spinner in the sidebar so the user can context-switch and return without losing output.
- **Plan XML strip** — The raw `<plan>` block is stripped from the rendered message once the structured Plan card appears, keeping the conversation clean while the card remains fully interactive.
- **Smart Auto empty state** — When no AI provider is connected, the chat surfaces an onboarding card with Install Claude CLI + Install Ollama links so new users reach a working setup in one click.
- **Mention & slash autocomplete** — The `@` panel now works before `SymbolIndexer` finishes the cold scan (filesystem fallback). The `/` autocomplete triggers after any whitespace, not only at line start, so commands can be chained inside a sentence.
