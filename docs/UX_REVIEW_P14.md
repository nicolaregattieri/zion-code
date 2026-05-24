# UX Review — Phase 14 (Discoverability + Power-User Surface)

**Date:** 2026-05-24
**Scope:** New P14 surfaces — MCPServersSettingsSection, MCPServerEditorSheet, SkillsSettingsSection, UsageSettingsSection, SlashAutocompletePanel, SlashHelpCard, SpendMeterPill, AutoResolvedChip, ChatEmptyState (4-card hero), ChatComposer (placeholder)
**Reviewer:** ux-review skill (claude/opus 4.7)
**Status:** Critical findings resolved inline. High findings logged for P15 backlog. Medium / Nit deferred.

---

## Critical (resolved this task)

### C1 — SpendMeterPill linter collapsed multiline Text+modifier chains
- **What:** SpendMeterPill.swift had four `Text(L10n("...")).font(...)` pairs collapsed to a single line by a linter pass mid-task, producing `Text("...").modifier` consecutive-statements compile errors.
- **Why:** Build broke until the pill component was reformatted to one modifier per line.
- **Fix:** Reformatted each Text builder to put `.font(...)` and `.foregroundStyle(...)` on their own lines (verified via swift build).
- **Resolved by:** commit 6d6e9d9e (T10 polish).

### C2 — ChatComposer leftover TODO(P14:T10) marker after T10
- **What:** ChatComposer.swift line 135 still carried `// MARK: - TODO(P14:T10): L10n — "Message · / for commands · @ for files"` after T10 added the locale key.
- **Why:** Stale TODO markers signal "incomplete work" to future maintainers and pollute grep audits.
- **Fix:** Removed the marker line; the L10n() call already in place.
- **Resolved by:** commit 6d6e9d9e (T10 cleanup).

---

## High (P15 polish backlog)

### H1 — SpendMeterPill not interactive (no popover on click)
- **What:** `SpendMeterPill.swift:19-43` renders a capsule with monthly total but no `.onTapGesture` / Button wrapper. Hard to spot for users expecting a breakdown popover.
- **Why:** Cursor's spend pill opens a per-provider breakdown on click; users expect the same affordance.
- **Proposed fix:** Wrap the pill in a Button + use `.popover(isPresented:)` showing the same content as UsageSettingsSection's monthly rows.

### H2 — UsageSettingsSection soft-cap stepper has no enforcement
- **What:** `UsageSettingsSection.swift:14-22` writes `chat.spend.softCapUSD` but no path in ChatService reads it to refuse sends or surface a banner when totals exceed the cap.
- **Why:** Setting reads as cosmetic until the cap is wired into the send guard.
- **Proposed fix:** Add a pre-send check in `ChatService.send` that queries `SpendLedger.monthlyTotals(forMonth: Date())` and refuses with a banner if the API aggregate exceeds the configured cap (when cap > 0). Mirror the `BudgetOverflowState` pattern from P13.

### H3 — MCPServersSettingsSection status dot is binary green/gray only
- **What:** `MCPServersSettingsSection.swift` (`statusDot(for:)`) only branches on `server.disabled`. The richer `.starting / .crashed / .running(toolCount:)` enum from MCPServerProcess is not consulted.
- **Why:** No way to surface crashed servers or starting state in the UI.
- **Proposed fix:** Subscribe each row to its `MCPServerProcess.status` (async via Task), render yellow for `.starting`, red for `.crashed(reason:)`, with `.help(...)` tooltip carrying the reason.

### H4 — MCPServerEditorSheet missing JSON validation feedback
- **What:** Editor sheet collects id/command/args/disabled but accepts any input. Invalid commands silently fail when the row tries to launch.
- **Why:** Users get no feedback when typing `npx-missing-package` or leaving args blank for a tool that needs them.
- **Proposed fix:** Add a Validate button that runs a 5-second dry-run process (`command --version` or `--help`), shows green/red result inline.

### H5 — SkillsSettingsSection has no edit/preview path
- **What:** `SkillsSettingsSection.swift` lists skills with name/description but no row tap action. User can only scaffold new ones, not view/edit existing markdown.
- **Why:** Editing a skill requires opening the SKILL.md file outside Zion.
- **Proposed fix:** Tap row → opens the SKILL.md in Zion's built-in editor (existing CodeScreen path).

### H6 — SlashAutocompletePanel — Esc dismisses but next `/` doesn't reopen immediately
- **What:** After dismiss-via-Esc, the slash trigger heuristic in `ComposerNSTextView` requires the user to delete the existing slash, type a new one. Confusing for muscle memory.
- **Why:** Most editors re-open the picker on the next `/` keystroke regardless of context.
- **Proposed fix:** Track a `recentlyDismissed` flag with 200ms decay; re-open on next `/` if outside the decay window.

### H7 — AutoResolvedChip only shows after first send (no pre-send hint)
- **What:** `AutoResolvedChip.swift:18` reads `chat.resolvedProvider` which is `nil` until `ChatService.send` completes the orchestrator resolve. Users selecting Auto don't see a hint until their first response arrives.
- **Why:** Inconsistent affordance — chip appears after action instead of before.
- **Proposed fix:** Pre-resolve the auto provider on policy change + provider change via an async observer in ChatService; publish `previewResolvedProvider: AIProvider?` before the first send.

### H8 — ChatEmptyState starter cards do not adapt to repo state
- **What:** All 4 cards render unconditionally. Empty git repos / repos with no Swift tests show cards that prefill commands that can't succeed.
- **Why:** Confusing for first-launch users on a brand-new repo.
- **Proposed fix:** Condition the "Run tests" card on detected test infrastructure (`Package.swift` for swift / `package.json` test script for node / `pytest.ini` for python). Fall back to a generic "Ask anything" card.

---

## Medium (P15 polish)

### M1 — MCPServerEditorSheet form is too plain (no description / docs link per field)
- Add inline helper text under each field explaining purpose; link "MCP server convention →" to anthropic.com/mcp.

### M2 — UsageSettingsSection breakdown rows lack ratio bars
- Show a thin horizontal bar (DesignSystem.Colors.brandPrimary) proportional to the row's `usdCost` relative to the max row. Visual scanning improvement.

### M3 — SlashHelpCard sections collapse-state not persisted
- After opening `/help`, scrolling away, re-opening — every section is collapsed to default state. Persist `expanded: Set<String>` to UserDefaults `chat.slash.help.expandedSections`.

### M4 — SpendMeterPill `.api(0.0)` collapses to `.empty` — should still show "$0.00 this month"
- Currently the empty state hides spend entirely when zero. Better to show `$0.00 this month` so the pill is always reassuring even before first send.

### M5 — MCPServersSettingsSection "Find more servers →" link uses `.font(.label)` but no icon
- Add `Image(systemName: "arrow.up.right.square")` prefix to signal external link.

### M6 — ChatEmptyState hero icon (sparkles) is the same icon used in AgentStepIndicator
- Reusing the spinning sparkles icon dilutes its meaning. Use `bubble.left.and.bubble.right.fill` (CardHeader icon for chat) here.

### M7 — UsageSettingsSection: footer "Resets in N days" not actually computed
- Currently a static L10n string. Wire to actual end-of-month delta: `Calendar.current.daysUntilEndOfMonth()`.

### M8 — MCPServerEditorSheet doesn't disable Save when id collides with existing server
- Add `disabled(...)` predicate that includes `store.servers.contains(where: { $0.id == id && initial?.id != id })`.

---

## Nit (backlog)

### N1 — `chat.spend.pill.month` value reads "this month" — could also read just "month-to-date"
- Stylistic; current copy fine.

### N2 — SlashAutocompletePanel row source badge uses lowercase ("built-in" / "project" / "user")
- Capitalize for visual consistency with other Zion capsules.

### N3 — SkillsSettingsSection scope icon (folder / house) — house feels off-brand
- Use `person.circle` for user, `folder.fill` for project — clearer pairing.

### N4 — SpendMeterPill task callback only fires on initial appearance
- Doesn't update when ChatService writes a new ledger row. Add an explicit pub-sub via NotificationCenter or @Observable when SpendLedger.shared.append completes.

### N5 — AutoResolvedChip not announced to VoiceOver
- Add `.accessibilityLabel(L10n("chat.auto.resolvedChip.a11y", resolved.label))`.

---

## Build + Smoke

- `swift build -c release --scratch-path /tmp/zion-build-p14` → **Build complete** (0 errors)
- `./scripts/make-app.sh` → signed `dist/Zion.app`
- 3 locale files balanced at 2513 keys each
- Manual smoke (recommended after merge):
  - [ ] Open Settings → Zion Talks. Verify Approval Policy / MCP / Skills / Usage / ContextBudget sections all present and localized.
  - [ ] Click "+ New Server" in MCP. Verify 3 preset buttons populate id+command+args.
  - [ ] Click "+ New Skill" in Skills. Verify scaffold writes `<root>/.claude/skills/<slug>/SKILL.md` and reload picks it up.
  - [ ] In chat composer type `/`. Verify autocomplete popup appears with built-in commands + any skills.
  - [ ] Send `/help`. Verify SlashHelpCard renders with collapsible sections.
  - [ ] Select Auto provider. Send a message. Verify `AutoResolvedChip` appears after response.
  - [ ] Verify `SpendMeterPill` in conversation header shows `$0.00 this month` (empty ledger) or subscription badge (claudeCLI).
  - [ ] Open Settings → Zion Talks → Usage. Verify monthly breakdown table (empty initially, populated after first API call).
  - [ ] Switch language to pt-BR. Verify every new control localized.

## Summary

3 Critical findings — all resolved inline as part of T10 cleanup before this review (SpendMeterPill linter mangle + ChatComposer TODO marker). 8 High findings documented for P15 polish backlog. 8 Medium + 5 Nit captured. The Discoverability surface is solid and ready to ship; P15 will tighten interactivity (clickable pill, status dots, scoped empty state) and persistence (compact-state, soft-cap enforcement).
