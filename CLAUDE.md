# Zion - Project Context

Zion is a native Git client for macOS, focusing on a visual representation of the Git graph, branch management, and streamlined operations like commits, stashing, and worktree management.

## Project Overview

- **Type:** macOS Executable (SwiftUI)
- **Build:** `swift build` / `swift run` / `swift test`
- **Release:** `./scripts/make-app.sh` generates `Zion.app` in `dist/`
- **Architecture:** MVVM — `RepositoryViewModel` is the central state hub
- **Concurrency:** Swift Concurrency (Actors, Tasks). `RepositoryWorker` handles background Git ops
- **Git Integration:** Direct Git CLI interface through `GitClient`
- **Localization:** Portuguese (BR), English, Spanish via `.lproj` files and `L10n()` helper

## Key Files

| File | Purpose |
|------|---------|
| `Sources/Zion/ContentView.swift` | Main app layout, navigation, toolbar |
| `Sources/Zion/Models.swift` | `EditorTheme`, `ThemeColors`, enums |
| `Sources/Zion/DesignSystem.swift` | Design tokens: glass borders, spacing, colors |
| `Sources/Zion/RepositoryViewModel.swift` | Central app state and git operations |
| `Sources/Zion/Views/Code/SourceCodeEditor.swift` | NSTextView wrapper with syntax highlighting |
| `Sources/Zion/Views/Code/CodeScreen.swift` | Editor UI: toolbar, file browser, terminal |
| `Sources/Zion/Views/Components/GlassCard.swift` | `GlassCard` + `CardHeader` reusable components |
| `Sources/Zion/Views/Components/CommitDetailContent.swift` | Structured commit details parser/view |
| `Sources/Zion/Views/Components/CommitRowView.swift` | Commit row with hover states |

## Custom Skills

| Skill | Usage | Purpose |
|-------|-------|---------|
| `/ux-review` | `/ux-review [paste screenshots or describe screen]` | UX/UI expert analysis with actionable SwiftUI code suggestions |

## Critical Rules

### Light Themes in Dark Mode (GOLDEN RULE)

`EditorTheme.isDark` must ALWAYS return `true` for ALL themes — including light themes like GitHub Light. SwiftUI's internal compositing of `NSViewRepresentable` makes NSTextView text completely invisible when `isDark = false` in macOS dark mode. This is a SwiftUI framework bug/behavior that cannot be worked around at the NSView level.

**Pattern:** Use two properties on `EditorTheme`:
- `isDark: Bool` — always `true` — controls NSTextView rendering context
- `isLightAppearance: Bool` — actual visual truth — controls SwiftUI UI styling

```swift
// In CodeScreen — apply .light colorScheme ONLY to pure SwiftUI views
editorToolbar
    .background(theme.colors.background)
    .environment(\.colorScheme, theme.isLightAppearance ? .light : .dark)

// NEVER apply .environment(\.colorScheme) to SourceCodeEditor
```

### NSTextView Rendering

- Use `NSTextView.scrollableTextView()` factory method
- Set `usesAdaptiveColorMappingForDarkAppearance = false` in `makeNSView`
- Always `drawsBackground = true` with explicit `backgroundColor` for ALL themes
- Use `NSColor(srgbRed:green:blue:alpha:)` for text storage attributes — NEVER bridge through `SwiftUI.Color -> NSColor`
- Apply `.paragraphStyle` AFTER highlighting via `addAttribute`, not inside `setAttributes`

### Terminal

Uses `SwiftTerm` with real PTY via `LocalProcess`. Must be initialized as login shell (`-l`) with `TERM=xterm-256color`. Route all delegate callbacks to `DispatchQueue.main`.

## Design System

### Glass Tokens (`DesignSystem.Colors`)

Always use design tokens instead of hardcoded opacity values:

| Token | Value | Usage |
|-------|-------|-------|
| `glassBorderDark` | `white @ 0.12` | Card borders in dark mode |
| `glassBorderLight` | `white @ 0.55` | Card borders in light mode |
| `glassHover` | `white @ 0.08` | Hover background |
| `glassSubtle` | `white @ 0.04` | Subtle element backgrounds |
| `glassOverlay` | `black @ 0.15` | Overlay/inset backgrounds |
| `dangerBackground` | `red @ 0.06` | Danger zone backgrounds |
| `dangerBorder` | `red @ 0.25` | Danger zone borders |

### Component Patterns

- **Card headers:** Always use `CardHeader("Title", icon: "sf.symbol", subtitle: "optional")` inside `GlassCard`
- **Danger cards:** Use `GlassCard(borderTint: DesignSystem.Colors.dangerBorder)` for destructive sections
- **Toolbar groups:** Wrap related controls in `HStack` with `.background(DesignSystem.Colors.glassSubtle).clipShape(RoundedRectangle(cornerRadius: 8))`

## Development Conventions

- **UI Style:** Glassmorphism aesthetic with `ultraThinMaterial` and `GlassCard` containers
- **Git Safety:** Critical operations use `performGitAction` for confirmation alerts
- **Staging:** Supports individual file staging (`stageFile`) and batch operations
- **Language:** UI text uses Portuguese (BR) via `L10n()` localization helper
