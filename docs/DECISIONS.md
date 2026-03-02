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

## 2026-02-27 — Recovery Vault (pre-snapshot pattern)
Before any destructive git operation (reset --hard, rebase, discard), automatically create a stash snapshot prefixed `zion-pre-{operation}`. This gives users an undo path without requiring manual backups. Clean working trees skip the snapshot to avoid stash noise.

## 2026-02-27 — ntfy for push notifications
Chose ntfy.sh as the notification backend over native APNs or custom websockets. ntfy is self-hostable, works without Apple Developer account, and integrates with existing terminal workflows. Topic + server URL stored in UserDefaults, validated before use.

## 2026-02-28 — Mobile Remote Access via HTTP polling
Built mobile access as a lightweight HTTP server with long-polling instead of WebSocket. Simpler implementation, works through Cloudflare tunnels without upgrade headers, and the polling interval (200ms debounce) provides good enough latency for terminal streaming. AES-256-GCM encryption on all payloads.

## 2026-02-28 — Git Hosting provider abstraction
Created a protocol-based `GitHostingProvider` system instead of hardcoding GitHub. Supports GitHub (via `gh` CLI token), GitLab (PAT), and Bitbucket (app password). Auto-detects provider from remote URLs. Trade-off: more code, but extensible for future providers.

## 2026-03-01 — ViewModel extension split
Split the monolithic `RepositoryViewModel.swift` (~6,700 lines) into 14 domain-specific extensions (e.g., `+Git`, `+GitBranching`, `+FileBrowser`, `+AI`). Same class, same state coordination — just organized by domain. Reduced merge conflicts and improved navigability.

## 2026-03-01 — Code Formatter (built-in, no external tools)
Implemented code formatting for 16+ languages using built-in parsers rather than requiring external tools (prettier, black, gofmt). Trade-off: less sophisticated formatting, but zero dependencies and works offline. JSON uses Foundation's JSONSerialization, others use regex-based indent normalization.

## 2026-03-01 — EditorSymbolIndex for Go to Definition
Built a file-level symbol index that scans Swift/JS/TS/Python/Go/Rust files for function/class/struct definitions using regex patterns. Rebuilds on file tree refresh. Trade-off: regex-based (not AST-accurate), but fast enough for Go to Definition and Find References without an LSP server.
