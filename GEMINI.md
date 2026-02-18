# GraphForge - Project Context

GraphForge is a native Git client for macOS, focusing on a visual representation of the Git graph, branch management, and streamlined operations like commits, stashing, and worktree management.

## Project Overview

- **Type:** macOS Executable (SwiftUI)
- **Architecture:** MVVM (Model-View-ViewModel)
- **State Management:** `RepositoryViewModel` acts as the central hub for the application state.
- **Concurrency:** Uses Swift Concurrency (Actors, Tasks). `RepositoryWorker` handles background Git operations.
- **Git Integration:** Interfaces directly with the Git CLI through `GitClient`.
- **Localization:** Supports Portuguese (BR), English, and Spanish via `.lproj` files and a custom `L10n` helper.

## Key Features

- **Git Graph:** Visual representation of commits and branch lanes.
- **Changes Section:** Dedicated diff viewer with syntax highlighting for reviewing modified files.
- **Vibe Code:** Integrated development environment with:
    - **Source Editor:** Custom `NSTextView` wrapper with syntax highlighting and multiple themes (Dracula, City Lights, Everforest Light).
    - **Interactive Terminal:** Real PTY-based zsh terminal with OhMyZsh support and signal handling (CTRL+C).
    - **File Browser:** Integrated file explorer with recursive directory navigation.
- **Operations:** Centralized hub for commits (with file staging), branches, tags, stashes, and worktrees.

## Building and Running

### Development
- **Run:** `swift run`
- **Build:** `swift build`
- **Test:** `swift test`

### Production
- **Release Bundle:** Execute `./scripts/make-app.sh` to generate the `GraphForge.app` bundle in the `dist/` directory.

## Development Conventions

- **UI Style:** Modern "Glassmorphism" aesthetic using `ultraThinMaterial` and `GlassCard` containers.
- **Themes:** Supports global theme switching for the editor and terminal. Themes must handle both light and dark modes (see `EditorTheme.isDark`).
- **Terminal:** Uses `SwiftTerm` for professional-grade terminal emulation.
    - **GOLDEN RULE (Stability & Performance):** To prevent UI freezes and ensure full interactivity (OhMyZsh, CTRL+C), the terminal MUST use a real PTY via `SwiftTerm.LocalProcess`. It must be initialized as a login shell (`-l`) with proper environment variables (`TERM=xterm-256color`, `LANG=en_US.UTF-8`). 
    - **Concurrency Bridge:** All delegate callbacks must be routed to `DispatchQueue.main` (pass `dispatchQueue: .main` to `LocalProcess`). Use `MainActor.assumeIsolated` within protocol methods like `getWindowSize` to satisfy Swift 6 isolation rules without causing deadlocks or data races. Capture `terminalView` locally before jumping threads to feed data.
- **Editor:** `SourceCodeEditor` uses `NSRegularExpression` for real-time syntax highlighting.
    - **GOLDEN RULE (Visibility):** To prevent invisible text bugs, the `SourceCodeEditor` must use a manually constructed `NSScrollView` -> `NSClipView` -> `NSTextView` hierarchy. Never rely on `NSTextView.scrollableTextView()` alone if custom ruler views (line numbers) are attached, as it can cause layout collapses in SwiftUI. Always ensure `isVerticallyResizable = true`, `autoresizingMask = [.width]`, and `widthTracksTextView = true`.
- **Git Flow:** Supports individual file staging (`stageFile`) and batch operations. Commit messages are handled via `commitMessageInput`.
- **Safety:** Critical Git operations should use `performGitAction` to show confirmation alerts based on user settings.
