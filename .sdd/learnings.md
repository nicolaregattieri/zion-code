# Build Learnings — Performance Wave 2

Wave 1 learnings archived in `.sdd/archive/wave-1/learnings.md` (pending).

Key context from Wave 1 that applies here:
- `swift build` + `swift test` require `dangerouslyDisableSandbox: true`.
- `porcelainStatusEntries` is `private` to `RepositoryViewModel+Git.swift`. From another extension: `uncommittedChanges.compactMap(Self.parsePorcelainStatusLine)`.
- `@MainActor final class` types isolate all stored state automatically — no extra annotations.
- Test seams via dual-init or `internal var *ForTesting` hooks are the established pattern.
- `runGitAction` already has `onFailure: (() -> Void)? = nil` param from Wave 1 (do not remove it).

(Wave 2 tasks append lessons below.)
