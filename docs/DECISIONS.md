# Decision Log

> Historical record of architectural decisions and rejected approaches.
> These entries are context, not constraints — revisit and override freely as the project evolves.

## 2026-02-19 — Single RepositoryViewModel as state hub
Chose to centralize all app state in one @Observable @MainActor class (~6,700 lines) instead of splitting into multiple ViewModels. Trade-off: large file size, but simpler state coordination and no cross-VM synchronization issues.

## 2026-02-19 — Rebrand from GraphForge to Zion
Renamed from "GraphForge" → "Zion" → "Zion Tree" → "Zion". Repository directory kept as GraphForge (renaming git repos is disruptive). All user-facing references use "Zion".

## 2026-02-20 — Custom NSClipView for scroll anchoring
After 7 attempts to fix horizontal scroll drift in the code editor (NSTextView), solved it with a custom NSClipView subclass that overrides setBoundsOrigin. AppKit's default scroll behavior fights SwiftUI container resizing.

## 2026-02-20 — @Observable over @StateObject
Migrated entire app from ObservableObject/@StateObject to @Observable macro (macOS 14+). Requires minimum macOS 14 but gives cleaner observation with less boilerplate.

## 2026-02-26 — Sparkle for auto-updates (not Mac App Store)
Chose Sparkle framework with EdDSA signing for distribution instead of Mac App Store. Faster iteration, no review delays, direct DMG distribution via GitHub Releases. App Store submission remains a future option.
