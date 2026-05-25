import Foundation

/// Difficulty tier picked by SmartAutoTriage. Drives per-provider model selection
/// in `SmartAutoTierTable` so easy turns land on Haiku/Flash and hard turns on
/// Opus/o1 without the user having to think about it.
enum SmartAutoTier: String, Codable, Equatable, CaseIterable {
    case easy       // chit-chat, ack, trivial question
    case medium     // single-file code work, focused explanation
    case hard       // multi-file refactor, architecture, deep reasoning
}

/// Per-(provider, tier) model id table. Returns the *preferred* model for a
/// provider given the difficulty. Production-tuned defaults; can be overridden
/// by user via Settings → AI → Smart Auto Tier Map (future).
///
/// Resolution falls back to the provider's catalog default (`AIModelCatalogService`)
/// when no explicit entry exists.
struct SmartAutoTierTable {

    static let `default` = SmartAutoTierTable()

    /// Returns the model id to use for `(provider, tier)`, or `nil` to let the
    /// catalog default kick in.
    func modelID(provider: AIProvider, tier: SmartAutoTier) -> String? {
        switch (provider, tier) {
        // Anthropic API
        case (.anthropic, .easy):   return "claude-haiku-4-5"
        case (.anthropic, .medium): return "claude-sonnet-4-6"
        case (.anthropic, .hard):   return "claude-opus-4-7"

        // OpenAI API
        case (.openai, .easy):   return "gpt-4o-mini"
        case (.openai, .medium): return "gpt-4o"
        case (.openai, .hard):   return "o1"

        // Gemini API
        case (.gemini, .easy):   return "gemini-2.5-flash"
        case (.gemini, .medium): return "gemini-2.5-pro"
        case (.gemini, .hard):   return "gemini-2.5-pro"

        // Claude Code CLI — same family routing via --model flag
        case (.claudeCLI, .easy):   return "haiku"
        case (.claudeCLI, .medium): return "sonnet"
        case (.claudeCLI, .hard):   return "opus"

        // Codex CLI — gpt-5 family
        case (.codexCLI, .easy):   return "gpt-5-mini"
        case (.codexCLI, .medium): return "gpt-5"
        case (.codexCLI, .hard):   return "gpt-5-pro"

        // Local — relies on user's configured model. Tier is advisory only;
        // the local config has one model, we just respect difficulty by
        // letting the orchestrator skip local for `.hard` if the user wants.
        case (.local, _):  return nil

        case (.auto, _), (.none, _): return nil
        }
    }
}

extension SmartAutoTier {
    /// Lane mapping used by the orchestrator. Easy → cheapSummary (chain favors
    /// local/CLI/cheap-API), medium → general, hard → reasoning.
    var lane: AITaskLane {
        switch self {
        case .easy:   return .cheapSummary
        case .medium: return .general
        case .hard:   return .reasoning
        }
    }

    var label: String {
        switch self {
        case .easy:   return "easy"
        case .medium: return "medium"
        case .hard:   return "hard"
        }
    }
}
