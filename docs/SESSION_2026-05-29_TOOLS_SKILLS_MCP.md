# Session map — 2026-05-29: tools, skills, MCP, native loops

End-to-end record of what landed today on master + what's deferred. Use as the source of truth when planning the next iteration.

---

## PRs merged this session

| # | Title | What it ships |
|---|---|---|
| #527 | `feat(chat): MCP runtime dispatch via JSON-RPC pool` | `MCPClientPool` actor, `MCPServerProcess` full JSON-RPC client, lazy warm, dispatch routing table. |
| #528 | `fix(chat): preserve composer text across async thread load` | Bug: typing in a fresh-project chat → Enter swallowed. `onChange(activeThreadID)` was wiping `composerText` mid-typing. |
| #529 | `feat(chat): surface skills + user MCPs in system prompt; bridge MCPs into CLI` | Skill catalog + MCP catalog blocks in `taskInstructions`. `MCPConfigBuilder.build` merges `~/.zion/mcp.json` into Claude CLI `--mcp-config`. |
| #530 | `feat(chat): skill triggers auto-inject + use_skill tool` | `Skill.triggers` substring auto-injection (cap 3 per turn). New built-in `use_skill(id)` tool dispatch. |
| #531 | `feat(chat): Anthropic native tool-use loop (flag-gated)` | `runAnthropicToolLoop` + body builder w/ extra messages + Sendable-friendly body entry. Flag `chat.nativeToolLoop.enabled` (default OFF). |
| #532 | `feat(chat): OpenAI + Local + Gemini native tool-use loops` | Same shape as #531 for OpenAI, OpenAI-compat local, Gemini. `MCPConfigBuilder.dispatch(name:argsJSON:Data)` Sendable overload. |
| #533 | `fix(chat): audit P0 + cheap P1 — MCP warm, use_skill framing, intent lanes` | `MCPClientPool.warmFromDisk()` (P0: registry was never loaded). `consumeWarmErrors` + transient banner. `use_skill` directive framing. `laneForIntent` pipes IntentClassifier into orchestrator. |
| #534 | `feat(chat): capture MCP initialize.instructions, inject routing block` | Captures the MCP spec `result.instructions` field at handshake. Server tells model when to use its tools — generic, no hardcode. |
| #535 | `feat(chat): tool-affinity lane bias in Auto mode` | `toolAffinityLane` overrides lane: tool-name mention or reasoning verbs → `.general`/`.reasoning`. Precedence: tool > intent > tier. |

---

## Capability matrix (today, after PR #535)

### MCP support

| Surface | Status | Notes |
|---|---|---|
| stdio JSON-RPC transport | ✅ | `MCPServerProcess` |
| `initialize` handshake | ✅ | Captures `serverInfo` + `instructions` |
| `tools/list` + schemas | ✅ | Forwarded as `inputSchema` via `ToolSchemaTranslator` |
| `tools/call` dispatch | ✅ | Routing table in `MCPClientPool` |
| Built-in precedence by name | ✅ | `MCPConfigBuilder.allToolsIncludingUserServers` |
| Paste-to-install (3 JSON shapes) | ✅ | `PasteAutoInstall` |
| Registry on disk (`~/.zion/mcp.json`) | ✅ | `MCPRegistryStore` + direct disk read |
| User MCPs visible to native providers | ✅ (flag on) | Anthropic, OpenAI, Local, Gemini loops |
| User MCPs visible to Claude / Codex CLI | ✅ | `--mcp-config` bridge |
| Launch failure surfacing | ✅ | 6s transient banner with reason |
| `initialize.instructions` → system prompt | ✅ | Per-server routing block |
| HTTP / SSE / websocket transport | ❌ | Hosted MCPs unsupported |
| OAuth / token refresh | ❌ | |
| `prompts/list` + `prompts/get` | ❌ | Camada 2A deferred |
| `resources/list` + `resources/read` | ❌ | |
| Subprocess crash auto-reconnect | ❌ | Stays dead until session restart |
| Per-tool `autoApprove` editor in UI | ❌ | Stored only as JSON in registry |

### Skill support

| Surface | Status | Notes |
|---|---|---|
| `~/.zion/skills/` (user) + `<repo>/.zion/skills/` (project) scan | ✅ | `SkillIndex` |
| `.claude/skills/` legacy fallback | ✅ | |
| `/<id>` slash injection | ✅ | `injectSkillIfMatched` |
| `Skill.triggers` substring auto-injection | ✅ | Case-insensitive, cap 3, server-side |
| `use_skill(id)` built-in tool | ✅ | Returns body with execution-directive framing |
| Skill catalog in system prompt | ✅ | Cap 30, name + description |
| `create_skill` tool (paste / NL) | ✅ | |
| Slash autocomplete picker in composer | ❌ | Documented `/<id>` but no UI affordance |
| Word-boundary trigger matcher | ❌ | Current substring matches "plan" inside "airplane" |
| Plugin format scanner (`.claude/plugins/**`) | ❌ | Vendor-specific — declined per "no hardcode" |
| Plugin `skills/` import on MCP install | ❌ | Camada 2B declined for same reason |

### Native tool-use loops

| Provider | Status | Notes |
|---|---|---|
| Anthropic API | ✅ flag-gated | `runAnthropicToolLoop`, cap 8 rounds |
| OpenAI API | ✅ flag-gated | `runOpenAICompatToolLoop` |
| Local (OpenAI-compat) | ✅ flag-gated | Reuses OpenAI loop; needs model with function-calling |
| Gemini API | ✅ flag-gated | `runGeminiToolLoop` via `streamGeminiWithToolsBody` |
| Claude CLI | ✅ via subprocess | Owns its own harness + sees `--mcp-config` |
| Codex CLI | ✅ via subprocess | Same |
| Round cap (8) UX | ⚠️ | Cryptic `[tool loop capped at 8 rounds]` — no "Continue" affordance |
| Tool error visibility in UI | ⚠️ | Only as `[tool error: …]` inside model bubble |
| Schema forward into native loop | ✅ | `ToolSchemaTranslator` per provider family |

### Auto-mode routing

| Signal | Status | Notes |
|---|---|---|
| Tier (`HeuristicTriageClassifier`) → lane | ✅ | Default baseline |
| `IntentClassifier` → lane | ✅ | #533: `status` → cheapSummary, `currentChanges` → review |
| Tool-affinity → lane | ✅ | #535: tool name + reasoning verbs |
| Vision attachment → vision-capable provider | ✅ | Existing |
| Rate-limit / 429 fallback | ✅ | `orchestrator.markRateLimited` + `nextFallback` |
| 401 handled like permanent for session | ⚠️ | Treated as `serverError`, 30s cooldown — should be session-long until key fix |
| MCP-specific provider affinity | ❌ | E.g., "web search tool → prefer Anthropic with web tool support" — not modeled |

### Composer UX

| Feature | Status | Notes |
|---|---|---|
| Paste-to-install banner | ✅ | 3s transient |
| Bash toggle pill | ✅ | Per session |
| Attachment buttons | ✅ | Image / PDF / file |
| Slash autocomplete | ❌ | Not in this audit's reach — verify in next pass |
| MCP picker | ❌ | |
| Skill picker | ❌ | |
| Warm progress indicator | ❌ | `npx -y X` cold-start is invisible |

---

## Files touched

```
Sources/Zion/Services/ChatService.swift                   # skill catalog, mcp catalog, mcp routing block,
                                                          #   laneForIntent, toolAffinityLane, native loops switch
Sources/Zion/Services/ChatService+AnthropicToolLoop.swift # new — Anthropic loop
Sources/Zion/Services/ChatService+OpenAIToolLoop.swift    # new — OpenAI/Local loop
Sources/Zion/Services/ChatService+GeminiToolLoop.swift    # new — Gemini loop
Sources/Zion/Services/ChatService+PasteAutoInstall.swift  # paste handler
Sources/Zion/Services/AIClient+Anthropic.swift            # additionalMessages, Sendable body entry
Sources/Zion/Services/AIClient+OpenAI.swift               # Sendable body entry
Sources/Zion/Services/AIClient+Gemini.swift               # GeminiModelTurn + Sendable body entry
Sources/Zion/Services/AIClient+Helpers.swift              # request body w/ messages variants
Sources/Zion/Services/MCP/MCPClientPool.swift             # warmFromDisk, consumeWarmErrors, allServerInstructions
Sources/Zion/Services/MCP/MCPServerProcess.swift          # capture initialize.instructions
Sources/Zion/Services/MCPConfigBuilder.swift              # use_skill descriptor, dispatch overload,
                                                          #   bridge ~/.zion/mcp.json into CLI config
Sources/Zion/Services/ZionTools+UseSkill.swift            # new — use_skill dispatcher with directive framing
Sources/Zion/Views/Chat/ChatScreen.swift                  # composer draft race fix
Sources/Zion/Resources/{en,pt-BR,es}.lproj/Localizable.strings  # chat.mcp.warmFailed
Tests/ZionTests/*ToolLoopBodyTests.swift                  # body shape pins
Tests/ZionTests/*ToolAffinityLaneTests.swift              # lane bias
Tests/ZionTests/AuditP0FixesTests.swift                   # intent lane + pool errors
Tests/ZionTests/PromptCatalogTests.swift                  # catalog block
Tests/ZionTests/SkillAutoTriggerTests.swift               # triggers
Tests/ZionTests/UseSkillToolTests.swift                   # use_skill dispatch
docs/ZION_LLM_ARCHITECTURE.md                             # earlier flow doc
docs/SESSION_2026-05-29_TOOLS_SKILLS_MCP.md               # this file
```

---

## Open follow-ups (sorted by ROI)

### Bugs / correctness (high)
- **[P0] HTTP/SSE MCP transport** — Hosted MCPs (Linear, Cloudflare, GitHub remote) cannot connect today.
- **[P1] Subprocess auto-reconnect** — Crashed MCP stays dead until session restart. Add one retry-with-backoff per turn.
- **[P1] 401 session-long suppression** — Treat invalid-key as 86,400s cooldown like local-disconnect, not 30s.
- **[P2] Word-boundary skill trigger matcher** — Avoid "plan" matching "airplane".

### UX (medium)
- **[P1] Skill / MCP pickers in composer** — Slash autocomplete + tool-toggle button. Today's affordances are documented but invisible.
- **[P1] Warm progress** — Spinner / inline note "warming MCP servers (1/3)…" via `pendingToolEvents` channel.
- **[P1] `autoApprove` editor field** in `MCPServerEditorSheet`. JSON-only today.
- **[P1] `[tool loop capped at 8 rounds]` → Continue affordance** in the bubble.
- **[P2] Tool error chip** — Surface `[tool error: …]` as a visible chip outside the model bubble.

### Routing / Auto (medium)
- **[P2] MCP-specific provider affinity** — Tag MCP categories (search, vision, web, exec) → preferred provider set. Bias orchestrator beyond keyword toolAffinity.
- **[P2] Tool-loop default-OFF inconsistency** — Either default ON (after smoke validation) or surface a one-time banner when OFF explaining the gap.

### Spec parity (medium-low)
- **[P2] MCP `prompts/list` + `prompts/get`** (Camada 2A) — Adds parameterised templates per server with a `mcp_prompt(server, name, args)` built-in tool.
- **[P2] MCP `resources/list` + `resources/read`** — Lets servers publish docs / templates we can mention via `@server/path`.

### Declined (vendor-specific)
- **Plugin format scanner (`.claude/plugins/**`)** — Claude Code-specific. Declined per "no hardcode".
- **Plugin `skills/` import on MCP install** (Camada 2B) — Same reason.
- **`CLAUDE.md` auto-surface in repo root** — Vendor-specific; project rule `project-file-safety.md` already bars auto-modifying user repo files.

---

## How to validate end-to-end (manual smoke)

1. Enable flag once: `defaults write com.nicolaregattieri.Zion chat.nativeToolLoop.enabled -bool true`.
2. Install an MCP via paste:
   ```json
   { "mcpServers": { "context-mode": { "command": "npx", "args": ["-y", "context-mode"] } } }
   ```
3. Restart app.
4. Auto mode + Anthropic / OpenAI / Gemini / Local — ask natural language ("find auth middleware", "analyze this stacktrace").
5. Verify in `~/Library/Logs/Zion/diagnostic.log`:
   - `orchestrator.resolve lane=general` (tool-affinity firing)
   - No `[tool error: …]` in response unless intentional
   - MCP subprocess running: `ps aux | grep context-mode`

If the model responds in plain text without tool calls, check:
- Flag actually on (`defaults read com.nicolaregattieri.Zion chat.nativeToolLoop.enabled`)
- `~/.zion/mcp.json` contains the server (case-sensitive)
- `MCPClientPool.consumeWarmErrors` didn't return launch failures
- The provider's API key/local server is actually reachable

---

*Generated at end of session 2026-05-29. Next session: pick from the "Open follow-ups" table by ROI.*
