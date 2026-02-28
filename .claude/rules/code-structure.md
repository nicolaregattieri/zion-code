# Code Structure

## File Size Awareness
- When a Swift file grows past ~800 lines, suggest splitting it into domain-focused extensions.
- When adding methods to a `+*.swift` extension that doesn't match its domain, suggest the right file.

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

## Test Coverage
- After adding a public method to any ViewModel extension, suggest a happy-path test.
- Tests live in `Tests/ZionTests/` and follow the `RepositoryViewModelXxxTests.swift` naming pattern.
