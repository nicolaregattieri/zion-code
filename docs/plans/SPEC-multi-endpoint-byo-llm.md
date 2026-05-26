# SPEC — Multi-endpoint BYO LLM (Caminho 2)

**Status:** draft
**Owner:** Zion Talks
**Date:** 2026-05-26
**Related:** PR #475 (renamed Local slot), session research with citations (Zed, Continue.dev, Cherry Studio, Msty, Jan)

## Problem

The `AIProvider.local` slot today accepts ANY OpenAI-compatible URL — Ollama / MLX / LM Studio (on-device) OR OpenRouter / Together / Fireworks / Groq (remote API gateway). The user can only configure ONE endpoint at a time. Switching from Ollama to OpenRouter overwrites the previous config; Smart Auto cannot route to both simultaneously.

This is the outlier pattern. Every competitor surveyed (Zed, Continue.dev, Cherry Studio, Msty, Jan) models providers as a **list of N user-defined endpoints**. OpenRouter itself ships a `models[]` fallback array, productizing the local→remote failover pattern.

## Goal

Replace the single `LocalLLMConfig` slot with a typed list of named OpenAI-compatible endpoints. Each endpoint declares its label, URL, optional API key, model id, and an `isLocal` hint that drives memory-pressure-aware routing.

## Non-goals

- Role-based routing per endpoint (chat / autocomplete / embed) — Continue.dev style. Defer to a v2.
- Provider-specific quirks beyond OpenAI-compatible (Anthropic SDK, Gemini SDK). Existing first-class providers (`.anthropic`, `.openai`, `.gemini`) stay as-is.
- Per-endpoint cost/latency hints. Ordered list + health check covers v1.

## Data model

```swift
struct OpenAICompatibleEndpoint: Sendable, Codable, Identifiable, Equatable {
    let id: UUID
    var label: String                // user-facing name, e.g. "Local MLX" / "OpenRouter"
    var url: String                  // OpenAI-compatible base URL with /v1
    var apiKey: String               // empty for on-device servers that don't require one
    var modelName: String            // default model id for this endpoint
    var isLocal: Bool                // drives memory-pressure routing
    var autoStartEnabled: Bool       // only meaningful when isLocal == true
    var engineKind: LocalEngineKind  // ollama / mlx / lmstudio / llamacpp / custom — only for isLocal
    var timeoutSec: Int
    var disabled: Bool
}

// Persisted via UserDefaultsKeys.AI.openAICompatibleEndpoints (JSON array)
```

Smart Auto chain entries today reference `.local`. After this change, `.local` becomes a *family* — the orchestrator walks the endpoint array in priority order. Each endpoint that's healthy + within cost cap + connectivity-OK is a candidate.

## Migration

On first launch after the upgrade:

1. Read the legacy `LocalLLMConfig` (UserDefaults key `chat.localLLMConfig`).
2. If present, synthesize an `OpenAICompatibleEndpoint` with:
   - `label = "Local"` (or inferred from engineKind)
   - `url`, `apiKey`, `modelName`, `engineKind`, `autoStartEnabled`, `timeoutSec` copied verbatim
   - `isLocal = true`
   - `id = UUID()`
3. Persist as entry[0] in the new array.
4. Delete the legacy key.

Silent migration. No user prompt. Settings will show the imported endpoint pre-populated.

## Settings UI

`LocalLLMSettingsSection` retired. Replace with `OpenAICompatibleEndpointsSection`:

- **Header:** "OpenAI-compatible endpoints" with subtitle "On-device servers (Ollama, MLX) and remote gateways (OpenRouter, Together, Fireworks). Smart Auto walks this list in order."
- **List rows:** for each endpoint, show:
  - Status dot (healthy / unhealthy / disabled)
  - Label (editable inline)
  - Model name (truncated)
  - Badge: "Local" / "Remote"
  - Reorder handle (drag to change priority)
  - Edit button → opens sheet with full fields
  - Toggle (enabled / disabled)
  - Delete button
- **"+ Add endpoint" button** at bottom → sheet with empty form. Quick-add templates: "Ollama (localhost:11434)", "MLX (localhost:8080)", "OpenRouter", "Together", "Groq" — populate URL + engineKind appropriately.
- **Empty state:** "No endpoints configured. Add Ollama for on-device or OpenRouter for remote."

## Orchestrator changes

`RoutingPolicy.chains[lane]` entries that today contain `"local"` get replaced by a virtual entry that expands at resolve-time into the user's endpoint list (filtered by `disabled == false`).

`ProviderOrchestrator.firstEligible`:
- When it encounters `.local`, iterate `endpoints` instead of treating it as a single slot.
- For each endpoint:
  - Check `isLocal == true` → if memory pressure red, skip and log "skip local endpoint <label>: memory pressure red".
  - Check connectivity (probe /v1/models for non-local; check localLastHealthyAt for local).
  - Check cost cap (use a virtual key like `local:<id>` to keep per-endpoint budget).
- First eligible wins; remaining endpoints are the fallback chain for `nextFallback`.

## Dispatch

`AIClient.call` and `streamLocalLLM` today read `loadLocalConfig()`. After the change, the orchestrator's resolved provider includes the endpoint id so dispatch can read the specific endpoint by id from the array. New API:

```swift
extension AIClient {
    static func loadEndpoint(id: UUID) -> OpenAICompatibleEndpoint?
    static func endpoints() -> [OpenAICompatibleEndpoint]
}
```

`ResolvedProvider` (currently just `AIProvider`) gains an associated payload:

```swift
enum ResolvedProvider {
    case anthropic, openai, gemini, claudeCLI, codexCLI
    case openAICompatible(endpointID: UUID)
}
```

Note: keeping the legacy `AIProvider` enum is fine — add a sibling type for routing decisions or extend with associated values via a separate "RoutedSelection" struct.

## AutoResolvedChip

Show the resolved endpoint's `label` + its model id when `.local` is resolved, instead of the generic "Local" short label.

## Diagnostic log

Each endpoint check in `firstEligible` emits a log line. Healthy/skipped/picked transitions are recorded with endpoint id + label so the user can attach `~/Library/Logs/Zion/diagnostic.log` when reporting routing bugs.

## Tests

- Migration: legacy LocalLLMConfig → array of 1 entry, fields preserved.
- Orchestrator: endpoint list of 3 with first unhealthy → second picked.
- Memory pressure: red + 2 local endpoints + 1 remote → remote picked.
- Persistence: array round-trips via UserDefaults JSON encode/decode.
- Diff vs legacy: in tests with only one endpoint, behavior matches the current LocalLLMConfig path.

## Risks

- **Config drift:** users who manually edit `~/Library/Preferences/...zion.plist` between launches could end up with a partial entry. Migration must be idempotent + tolerant.
- **Settings UI complexity:** Today's "Local server" card is a single form. The list view is heavier. Mitigate by collapsing rows to a single line when not editing.
- **Smart Auto regression:** ordered list semantics change the meaning of "preferred local". Need to document that the FIRST endpoint in the list is preferred — and provide reorder handles, not alphabetic sort.
- **CLI subprocess plumbing:** `AIClient+CLISubprocess.swift` reads `LocalLLMConfig` for the `--allow-edits` flag plumbing. Audit every reference to `loadLocalConfig()` and adapt.

## Phasing

1. **Phase 1 — Data model + migration** (1 day): new struct + UserDefaults round-trip + silent migration + unit tests.
2. **Phase 2 — Dispatch** (1 day): orchestrator + AIClient adapt to read from array; treat legacy single entry as the only candidate.
3. **Phase 3 — Settings UI** (1-2 days): list view + add/edit sheets + reorder + delete + status dots.
4. **Phase 4 — Smart Auto rotation** (1 day): chain expansion in firstEligible + per-endpoint health/cost tracking + diagnostic logging.
5. **Phase 5 — UX polish** (0.5 day): AutoResolvedChip endpoint label + memory-pressure skip indicator.

Total: ~5 days focused.

## Open questions

- Quick-add templates: ship which set in v1? Definite: Ollama, OpenRouter. Probable: MLX, LM Studio, Together, Groq. Skip: DeepInfra, Fireworks (less popular).
- Should `isLocal` be auto-detected from URL hostname (localhost / 127.0.0.1 / *.local) or user-declared? Auto-detect default + user-overridable seems right.
- Per-endpoint cost cap UI: defer to v2? Today the global per-provider cap key would need to fan out to per-endpoint keys.
