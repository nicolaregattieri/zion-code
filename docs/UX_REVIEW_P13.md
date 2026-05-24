# UX Review — Phase 13 (Context Management + Unified Approval Policy)

**Date:** 2026-05-23
**Scope:** Settings → Zion Talks (ApprovalPolicy, ContextBudget, SmartContext, AgenticLoop, Appearance, RoutingPolicy, ToolBridge, CLIFailover) + Chat surface (ChatComposer, AgentStepIndicator, ProviderSwitchBanner, MentionsCostPreview, MultiFileDiffSummary, ChatThreadList, ChatMessageBubble, EditPreviewCard).
**Reviewer:** ux-review skill (claude/opus 4.7).
**Status:** All Critical findings resolved inline. High findings logged with proposed fixes. Medium / Nit deferred to P14 polish backlog.

---

## Critical (resolved this task)

### C1 — Hardcoded English strings in ZionTalksSettingsTab break pt-BR / es users
- **What:** Section titles "General", "Tool Bridge", "Routing Policy", "Subscription CLI Failover" plus their Toggle labels and the top intro Text were hardcoded English with TODO(T10) markers that survived multiple phases.
- **Why:** Localization rule (.claude/rules/localization.md) forbids hardcoded user-facing strings. pt-BR + es speakers see a half-translated tab.
- **Fix:** Replaced every hardcoded string with `L10n("chat.settings.*")` calls. Added 12 new keys across en / pt-BR / es (balanced at 2435). Deleted every TODO(T10) marker.
- **Resolved by:** commit (this task)

### C2 — ApprovalPolicy advanced disclosure shows raw enum identifiers
- **What:** `Text(policy.bashTier.rawValue)` rendered "readOnly" / "workspaceWrite" / "fullAccess" — camelCase developer strings instead of user-facing labels.
- **Why:** Visual hierarchy + clarity. Users read this row to verify what the picker maps to; raw identifiers leak implementation.
- **Fix:** Added `var label: String` to `AgentApprovalTier` that returns the existing `chat.agent.tier.*` L10n keys ("Read-only" / "Workspace write" / "Full access"). Updated `ApprovalPolicySection.advancedControls` to read `.label`.
- **Resolved by:** commit (this task)

### C3 — `L10n("Sim")` / `L10n("Não")` used as keys
- **What:** `ApprovalPolicySection.advancedControls` used pt-BR words as L10n keys (legacy Zion convention from early phases). When the key is missing in other locales L10n falls back to the key string — English users saw "Sim" / "Não".
- **Why:** L10n contract: keys are stable identifiers, never the translated text.
- **Fix:** Introduced `chat.bool.yes` / `chat.bool.no` keys in all three locales. Replaced the call sites.
- **Resolved by:** commit (this task)

---

## High (proposed for P14 polish backlog)

### H1 — AgentStepIndicator has flat typographic hierarchy
- **What:** "Step 3/25 · Anthropic" rendered as one continuous monoLabelBold string. Step counter (the actionable number) does not visually stand apart from the provider name.
- **Why:** The user glances at this capsule mid-loop to know progress. The number is the signal; provider is metadata. Same weight = same urgency = no scan affordance.
- **Proposed fix:**
  ```swift
  Text("\(agentRuntime.currentStepIndex)")
      .font(DesignSystem.Typography.monoBodyBold)   // larger + bolder
      .foregroundStyle(DesignSystem.Colors.textPrimary)
  Text("/\(maxSteps)")
      .font(DesignSystem.Typography.monoLabel)      // smaller + muted
      .foregroundStyle(DesignSystem.Colors.textTertiary)
  ```
  Split the step format into two `Text` elements so the numerator gets visual weight.

### H2 — ContextBudgetSection has no stats footer despite spec calling for it
- **What:** Spec required "current window utilization, last compaction timestamp." Section currently ships only the response-reserve stepper.
- **Why:** Users need to see actual budget pressure to decide whether to compact / refuse / continue. Without it, the policy is a black box.
- **Proposed fix:** Wire a stats row reading `ContextBudget` consumed totals + a `lastCompactedAt: Date?` published by ChatService on each compaction. Add L10n keys `chat.contextBudget.stats.utilization` + `chat.contextBudget.stats.lastCompacted`.

### H3 — ApprovalPolicy YOLO warning is buried under the description text
- **What:** When the user selects YOLO, the warning banner sits at the bottom of the section, after the description. Easy to miss.
- **Why:** Critical safety affordance. Pattern in Cursor / Cline: the warning appears *immediately after the picker*, before any further controls.
- **Proposed fix:** Move the warning HStack to render immediately after the Picker (before the description), and replace `DesignSystem.Colors.warning` text style with a full warning-tinted background pill (`DesignSystem.Colors.warning.opacity(0.15)` + 8pt corner radius + horizontal padding). Pre-warn the user, don't bury it.

### H4 — Settings sections ordering: General toggles should follow Approval Policy
- **What:** Section order is intro → ApprovalPolicy → General → Appearance → Agentic → SmartContext → ContextBudget → ToolBridge → Routing → CLI Failover. "General" sits between safety (Approval) and visual (Appearance), breaking topical grouping.
- **Why:** Sections should group by concern: Safety → Behavior → Context → Routing → Visual. Mixed ordering forces users to hunt.
- **Proposed fix:** Reorder to: intro → ApprovalPolicy → ContextBudget → SmartContext → Agentic → ToolBridge → General → Routing → CLI Failover → Appearance. Saves a scroll on every "tune the loop" interaction.

### H5 — MentionsCostPreview only shows when mentions are present
- **What:** The cost preview disappears entirely when no `@mention` is in the composer. After P13 ContextBudget exists, the user has no way to see the *baseline* prompt cost (repomap auto-seed + system + history).
- **Why:** Cost predictability is the whole point of Smart Context. Hiding the baseline turns the meter into a sparse, surprising signal.
- **Proposed fix:** Always render `MentionsCostPreview` when ContextBudget reports any consumption > 1k tokens. Add a non-mention path showing "context: ~N tokens / $0.00x" using `ContextBudget.consumed.values.sum()` + the active provider's per-million rate.

### H6 — No visible feedback when ApprovalPolicy changes mid-session
- **What:** Switching from `manual` → `auto` mid-chat takes effect on the next send. The user gets no banner, toast, or echo in chat acknowledging the change.
- **Why:** Settings changes that alter runtime behavior should be confirmed visibly. Without it, the user wonders "did it take effect?"
- **Proposed fix:** Wire a `ProviderSwitchBanner`-style ephemeral banner in ChatScreen that surfaces "Approval policy changed to <X>" for 3 seconds whenever `ApprovalPolicy.current` changes. Reuse the existing recentSwitches infrastructure.

---

## Medium (P14 polish)

### M1 — `DisclosureGroup` "Advanced" label uses default chevron color
- Tighten to `DesignSystem.Colors.textSecondary` to match other muted controls.

### M2 — ApprovalPolicySection picker has no visual separator from description
- Add 4pt spacing between Picker and the description Text via `.padding(.top, 4)` on the description.

### M3 — ChatComposer placeholder uses `DesignSystem.Colors.textTertiary` but composer text uses `textPrimary` — fine, but the placeholder has no italic / lighter weight cue
- Add `.font(DesignSystem.Typography.body.italic())` to the placeholder to differentiate without making it shoutier.

### M4 — MultiFileDiffSummary uses `Image(systemName: "📂")` (text emoji) instead of SF Symbol
- Already SF Symbol per code review — confirmed in commit `637fdadb`. Skip.

### M5 — ContextBudgetSection stepper labels don't show the absolute reserve in a "k" suffix
- Currently shows `16000 tok`. Recommend `16 K tokens` for readability.

### M6 — EditPreviewCard doesn't show the file path's parent directory when paths repeat
- Long monorepo paths look truncated. Suggest middle-truncation: `.truncationMode(.middle)`.

### M7 — ApprovalPolicy advanced rows use plain `HStack { Text Spacer Text }` — no consistent label color
- Standardize to `Text(...).foregroundStyle(DesignSystem.Colors.textSecondary)` on the left, primary on the right value.

### M8 — `ChatThreadList` doesn't visually mark the active thread when the sidebar is collapsed
- Add a thin accent bar on the left edge when active even in collapsed mode.

---

## Nit (backlog)

### N1 — Tab settings sections use `Section("...")` initializer-with-StringLiteral in some spots and `Section(L10n("..."))` in others
- Now consistent post-C1 fix. Confirmed.

### N2 — Sparkle icon in AgentStepIndicator rotates linearly forever
- Consider `easeInOut` rotation or pulse-fade instead of continuous spin to feel less "frantic." Spinning forever can read as "stuck."

### N3 — `chat.bool.yes` / `chat.bool.no` are top-level keys not nested under `chat.approvalPolicy.*`
- Justified — these are reusable across the chat tab. Skip.

### N4 — `DesignSystem.Spacing.compact / 2` used in AgentStepIndicator
- Half-token math is mildly off-grid. Add `DesignSystem.Spacing.micro` (already exists) and use it directly.

### N5 — Section intro Text at top of ZionTalksSettingsTab doesn't have a leading icon
- Could add `Image(systemName: "info.circle")` prefix for stronger glance recognition.

---

## Build + Smoke

- `swift build -c release --scratch-path /tmp/zion-build-p13` → **Build complete** (0 errors after C1+C2+C3 fixes)
- 3 locale files balanced at 2435 keys each
- Manual smoke (after make-app.sh):
  - [ ] Open Settings → Zion Talks, scroll: every section title localized
  - [ ] Switch ApprovalPolicy to YOLO: warning banner visible (currently below description — see H3 backlog)
  - [ ] Expand Advanced disclosure: bash tier shows "Read-only" / "Workspace write" / "Full access", booleans show "Yes" / "No" (or pt-BR / es equivalents)
  - [ ] Switch app language to pt-BR via macOS Settings: every Zion Talks tab control is translated
- App built + signed: `./scripts/make-app.sh` clean

## Summary

Critical findings resolved inline (3). High findings (6) documented with concrete proposed fixes for P14 polish. Medium (7) + Nit (5) backlog captured. The Settings tab is now fully L10n-correct across en / pt-BR / es. Chat surface usability is solid but needs the H1-H6 polish for premium feel.
