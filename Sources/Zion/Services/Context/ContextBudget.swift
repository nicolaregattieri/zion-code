import Foundation

// MARK: - ContextLayer

enum ContextLayer: String, Sendable, CaseIterable {
    case systemPrompt
    case tools
    case repoSeed
    case history
    case attachedMentions
    case userText
    case response
}

// MARK: - ContextBudget

actor ContextBudget {
    /// Default response reserve — keep room for the model to actually answer.
    static let defaultResponseReserve: Int = 16_000

    private(set) var consumed: [ContextLayer: Int] = [:]

    // MARK: - Window size table

    /// Returns the window size in tokens for (provider, model).
    /// Default table covers known production models; unknown models get a conservative 32k.
    static func windowSize(forProvider provider: AIProvider, model: String?) -> Int {
        switch provider {
        case .anthropic:
            // All current Claude models: claude-3-haiku, claude-3-5-sonnet, claude-opus-4, etc.
            if model?.contains("claude-3-haiku") == true { return 200_000 }
            if model?.contains("claude-opus-4") == true { return 200_000 }
            if model?.contains("claude") == true { return 200_000 }
            return 200_000

        case .openai:
            if model?.contains("gpt-5") == true { return 200_000 }
            if model?.contains("o1") == true || model?.contains("o3") == true { return 200_000 }
            if model?.contains("gpt-4o") == true { return 128_000 }
            if model?.contains("gpt-4") == true { return 128_000 }
            return 128_000

        case .gemini:
            return 1_000_000

        case .local, .none, .auto, .claudeCLI, .codexCLI:
            return 32_768
        }
    }

    // MARK: - Budget queries

    /// Returns available tokens for input (window - reserve - already consumed).
    func available(
        forProvider provider: AIProvider,
        model: String?,
        responseReserve: Int = defaultResponseReserve
    ) -> Int {
        let window = Self.windowSize(forProvider: provider, model: model)
        let used = consumed.values.reduce(0, +)
        return max(0, window - responseReserve - used)
    }

    /// Returns true if `tokens` fits within the remaining input budget.
    func fits(
        _ tokens: Int,
        forProvider provider: AIProvider,
        model: String?,
        responseReserve: Int = defaultResponseReserve
    ) -> Bool {
        return tokens <= available(forProvider: provider, model: model, responseReserve: responseReserve)
    }

    /// Record tokens consumed at a layer (cumulative). Reset via `reset()` between turns.
    func consume(_ tokens: Int, layer: ContextLayer) {
        consumed[layer, default: 0] += max(0, tokens)
    }

    /// Reset all consumption counters (call at the start of each user turn).
    func reset() {
        consumed.removeAll()
    }
}
