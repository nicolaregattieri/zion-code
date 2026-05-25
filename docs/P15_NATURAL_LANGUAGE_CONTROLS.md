# P15 backlog — Natural language + slash control of Zion settings

User-facing chat as a control plane. Talking to Zion in any project should let
the user flip Zion settings without leaving the chat.

## Examples to support
- "entre em yolo mode" / "go yolo" → flip ApprovalPolicy → `.yolo`
- "modo seguro" / "safe mode" → ApprovalPolicy → `.manual`
- "liga edits" / "allow file edits" → `chat.cliAllowEdits = true`
- "sobe local" / "start local" → spawn `LocalServerLauncher` (still honors `LocalAutoStartPolicy`)
- "para o local" / "stop local" → `LocalServerLauncher.stop`
- "muda pra opus" / "use opus" → pin tier override for the next turn
- "esquece" / "reset auto" → clear tier override

## Slash equivalents
- `/yolo` `/safe` `/auto-safe` `/manual` → ApprovalPolicy
- `/allow-edits` `/no-edits` → cliAllowEdits
- `/local start` `/local stop` `/local status` → LocalServerLauncher + MemoryMonitor
- `/tier easy|medium|hard` → one-shot tier override
- `/model haiku|sonnet|opus` → one-shot model override

## Architecture
- `IntentRouter.swift` — pre-LLM regex/keyword classifier that catches these
  natural phrases BEFORE Smart Auto routes anywhere. Hit = apply locally + emit
  a "system" chat message confirming the change. Miss = falls through to the
  normal Auto pipeline.
- Slash commands registered via `SlashCommandRegistry`.
- Every action emits a chat-visible confirmation card so the user can undo.

## Safety
- `/yolo` requires double-confirm (banner) because it disables every approval.
- `cliAllowEdits` flip surfaces in the composer status bar so the next message
  visibly shows "edits enabled".
- All flips are reversible from the same chat.

## Why P15
Smart Auto v1 + per-tier model + local autostart-ask is the v2.0 release.
This adds true conversational control on top. Defer.
