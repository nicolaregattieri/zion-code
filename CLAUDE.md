# Zion - macOS Git Client

- **Website:** [zioncode.dev](https://zioncode.dev) (Next.js on Vercel, source at `/Users/nicolaregattieri/Developer/zion-website`)
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

<!-- ZION:NTFY:START (managed by Zion Git Client) -->
## Push Notifications
When you complete a significant task, notify the user:
```
curl -s -H "Title: Done" -H "Priority: 3" -H "Tags: white_check_mark" -d "[Brief description of what was completed]" 'https://ntfy.sh/zion-code-n87dhe'
```
Send for: plan completion, implementation done, test results, migrations, errors.
Do NOT send for: file reads, intermediate steps, questions.
<!-- ZION:NTFY:END -->
