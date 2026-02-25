# Zion - macOS Git Client

- **Build:** `swift build` / **Release:** `./scripts/make-app.sh` → `dist/Zion.app`
- **Localization:** 3 locales (pt-BR, en, es) via `L10n()` helper

## @Observable (NOT ObservableObject)
- Owner: `@State private var model` | Bindings: `@Bindable var model` | Read-only: `var model`
- `@AppStorage` doesn't work — use computed + `UserDefaults` directly

## Critical Traps

### isDark GOLDEN RULE
`EditorTheme.isDark` must ALWAYS return `true` for ALL themes including light ones.
Use `isLightAppearance` for SwiftUI styling. Never apply `.environment(\.colorScheme)` to SourceCodeEditor.

### NSTextView
- `NSColor(srgbRed:green:blue:alpha:)` for text attributes — NEVER bridge `SwiftUI.Color → NSColor`
- `.paragraphStyle` AFTER highlighting via `addAttribute`, not inside `setAttributes`
- `usesAdaptiveColorMappingForDarkAppearance = false` in `makeNSView`

### Git UX Standard
- For Git issue handling (push/pull/fetch/divergence/auth/upstream), prefer market-standard IDE behavior when applicable: run fresh preflight state checks, present safe default recovery paths (especially for non-fast-forward/diverged branches), and avoid stale-state decisions.

## New Feature Checklist (MANDATORY)
1. Keyboard shortcut (hidden button pattern) where applicable
2. `.help()` tooltip with shortcut hint (except context menu items)
3. L10n keys in all 3 locales
4. Entry in `HelpSheet.swift` + `help.*` L10n keys in all 3 locales
5. Update `docs/FEATURES.md`
