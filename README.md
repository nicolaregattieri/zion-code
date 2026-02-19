# Zion (macOS)

Zion is a local macOS Git Graph app built in SwiftUI.
It uses your system Git CLI to provide visual history plus advanced operations (including worktrees).

## What is implemented

- Commit graph view with lanes, merge edges, commit metadata, and full commit details
- Branch tree panel (local + remote) with optional inferred branch ancestry/origin
- Configurable confirmation mode for Git actions (never, critical-only, all actions)
- Rich right-click context menus on branches and commits (checkout, pull, push modes, rename, delete local/remote, create branch/tag/stash/worktree/archive, cherry-pick, revert, reset, merge, rebase, copy)
- Remote actions: `fetch`, `pull --ff-only`, `push`
- Branch actions: checkout, create branch, merge, list local/remotes
- Tag actions: create/delete, list tags
- History actions: rebase, cherry-pick, reset hard
- Stash actions: create/apply/pop/drop, list stashes
- Worktree actions: list/add/remove/prune, open worktree path in Finder
- Custom Git command runner (`git <args>`) for anything else

## Requirements

- macOS 13+
- Swift 6+
- Git installed in PATH

## Run in dev mode

```bash
cd /Users/nicolaregattieri/Developer/Zion
swift build
swift run Zion
```

## Build a .app bundle

```bash
cd /Users/nicolaregattieri/Developer/Zion
./scripts/make-app.sh
open /Users/nicolaregattieri/Developer/Zion/dist/Zion.app
```

## Project structure

- `Sources/Zion/ZionApp.swift`: app entry point
- `Sources/Zion/ContentView.swift`: UI tabs and components
- `Sources/Zion/RepositoryViewModel.swift`: command orchestration + parsing
- `Sources/Zion/GitClient.swift`: Git process execution layer
- `Sources/Zion/GitGraphLaneCalculator.swift`: lane/edge layout logic
- `Sources/Zion/Models.swift`: domain models
- `scripts/make-app.sh`: creates `.app` from release build

## Open source baseline used

- Git CLI itself (official docs): https://git-scm.com/docs
- Worktree command behavior: https://git-scm.com/docs/git-worktree
- Feature inspiration from Git Graph extension capabilities: https://github.com/mhutchie/vscode-git-graph

Note: Git Graph extension license is custom (`LICENSE.md` in the repo). This project was implemented from scratch and does not copy source code.
