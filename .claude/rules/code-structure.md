# Code Structure

## Folder Layout

```
Sources/Zion/
  ZionApp.swift              — App entry point
  ContentView.swift          — Root coordinator

  DesignSystem/              — Colors, typography, theme palettes
  Models/                    — Pure data types, enums, value objects
  ViewModel/                 — RepositoryViewModel + all extensions
  Services/                  — Networking, git client, file watcher, etc.
  Helpers/                   — Small utilities (shell escaping, font resolver, temp)
  Views/                     — Feature-based subdirectories (Code/, Graph/, Settings/, etc.)
  Resources/                 — Localization .lproj bundles
```

## File Size Awareness
- When a Swift file grows past ~800 lines, suggest splitting it into domain-focused extensions.
- When adding methods to a `+*.swift` extension that doesn't match its domain, suggest the right file.

## New File Placement

| Type | Where | Naming |
|------|-------|--------|
| Data struct/enum | `Models/<Domain>Models.swift` | Group related types in one file |
| ViewModel method | `ViewModel/RepositoryViewModel+<Domain>.swift` | See extension tables below |
| Service class | `Services/<Name>.swift` | One class per file |
| Small utility | `Helpers/<Name>.swift` | Pure functions or enum namespaces |
| View | `Views/<Feature>/<Name>.swift` | Feature-based grouping |
| Design token | `DesignSystem/DesignSystem.swift` | All tokens in one file |

## Extension Placement

### RepositoryViewModel Git Extensions
New git methods should land in the matching `+Git*.swift` file, not in `+Git.swift` core:

| File | Domain |
|------|--------|
| `+Git.swift` | Refresh engine, action runner, credential retry, thin wrappers |
| `+GitBranching.swift` | Checkout, branches, tags, worktrees |
| `+GitHistory.swift` | Blame, reflog, diffs, rebase, commit details, file history |
| `+GitConflicts.swift` | Conflict resolution, hunk/line staging |
| `+GitRecovery.swift` | Recovery snapshots, stash restore, stash reference resolution |
| `+GitStaging.swift` | Commit, stage/unstage, gitignore, abort operations |
| `+GitRemote.swift` | Fetch, pull, push, auth error detection |

### Other RepositoryViewModel Extensions
| File | Domain |
|------|--------|
| `+AI.swift` | AI features, code review, commit message generation |
| `+Settings.swift` | User preferences, configuration |
| `+FileBrowser.swift` | File tree, file operations |
| `+Terminal.swift` | Terminal session management |

### Model Files
| File | Contents |
|------|----------|
| `AppEnums.swift` | AppLanguage, L10n(), AppAppearance, ConfirmationMode, PushMode, AIProvider, etc. |
| `GitModels.swift` | Commit, BranchInfo, RemoteInfo, ReflogEntry, GitAuthContext |
| `DiffModels.swift` | DiffHunk, DiffLine, FileDiff, DiffExplanation |
| `TerminalModels.swift` | TerminalSession, TerminalPaneNode, SplitDirection |
| `ReviewModels.swift` | ReviewFinding, CodeReviewFile/Stats, PRReviewItem |
| `EditorTheme.swift` | EditorTheme enum, ThemeColors, theme-to-palette mapping |
| `WorktreeModels.swift` | WorktreeItem, WorktreePrefix |
| `RepositoryModels.swift` | RecoverySnapshot, SubmoduleInfo, RepositoryStats, BackgroundRepoState |
| `ConflictModels.swift` | ConflictFile, ConflictRegion, ConflictChoice, ConflictBlock |
| `FileModels.swift` | FileItem, FileHistoryEntry, EditorConfig, FindInFiles* |
| `RebaseModels.swift` | RebaseItem, RebaseAction |

## MARK Conventions
- Use `// MARK: -` to separate logical sections within a file.
- Extension files don't need MARKs unless they exceed ~200 lines.

## Test Coverage
- After adding a public method to any ViewModel extension, suggest a happy-path test.
- Tests live in `Tests/ZionTests/` and follow the `RepositoryViewModelXxxTests.swift` naming pattern.
