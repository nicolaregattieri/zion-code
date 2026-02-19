# Zion - Project Context

Zion is a native Git client for macOS, focusing on a visual representation of the Git graph, branch management, and streamlined operations like commits, stashing, and worktree management.

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
    - **Source Editor:** Custom `NSTextView` wrapper with syntax highlighting and multiple themes (Dracula, City Lights, GitHub Light).
    - **Interactive Terminal:** Real PTY-based zsh terminal with OhMyZsh support and signal handling (CTRL+C).
    - **File Browser:** Integrated file explorer with recursive directory navigation.
- **Operations:** Centralized hub for commits (with file staging), branches, tags, stashes, and worktrees.

## Building and Running

### Development
- **Run:** `swift run`
- **Build:** `swift build`
- **Test:** `swift test`

### Production
- **Release Bundle:** Execute `./scripts/make-app.sh` to generate the `Zion.app` bundle in the `dist/` directory.

## Development Conventions

- **UI Style:** Modern "Glassmorphism" aesthetic using `ultraThinMaterial` and `GlassCard` containers.
- **Themes:** Supports global theme switching for the editor and terminal.
    - **GOLDEN RULE (Light Themes in Dark Mode):** `EditorTheme.isDark` must ALWAYS return `true` for ALL themes — including light themes. SwiftUI's internal compositing of `NSViewRepresentable` makes NSTextView text invisible when isDark=false in macOS dark mode. Use a separate `isLightAppearance` property for SwiftUI-only UI styling (toolbar, headers, buttons) with `.environment(\.colorScheme, .light)`. Never apply `.environment(\.colorScheme)` to the SourceCodeEditor itself.
- **Terminal:** Uses `SwiftTerm` for professional-grade terminal emulation.
    - **GOLDEN RULE (Stability & Performance):** To prevent UI freezes and ensure full interactivity (OhMyZsh, CTRL+C), the terminal MUST use a real PTY via `SwiftTerm.LocalProcess`. It must be initialized as a login shell (`-l`) with proper environment variables (`TERM=xterm-256color`, `LANG=en_US.UTF-8`). 
    - **Concurrency Bridge:** All delegate callbacks must be routed to `DispatchQueue.main` (pass `dispatchQueue: .main` to `LocalProcess`). Use `MainActor.assumeIsolated` within protocol methods like `getWindowSize` to satisfy Swift 6 isolation rules without causing deadlocks or data races. Capture `terminalView` locally before jumping threads to feed data.
- **Editor:** `SourceCodeEditor` uses `NSRegularExpression` for real-time syntax highlighting.
    - **GOLDEN RULE (NSTextView Rendering):** Always use `NSTextView.scrollableTextView()` factory. Set `usesAdaptiveColorMappingForDarkAppearance = false` and `drawsBackground = true` for ALL themes. Use `NSColor(srgbRed:...)` for text storage attributes — never bridge through SwiftUI Color. See the Light Themes golden rule above for the isDark/isLightAppearance pattern.
- **Git Flow:** Supports individual file staging (`stageFile`) and batch operations. Commit messages are handled via `commitMessageInput`.
- **Safety:** Critical Git operations should use `performGitAction` to show confirmation alerts based on user settings.
