import Foundation

// MARK: - ProviderModelCatalog

/// Returns the list of model identifiers a user can pick from per provider.
/// Static for API providers (curated from public docs as of 2026-05).
/// Dynamic for local (queried from the running endpoint via `AIClient.discoverModels`).
/// For CLI providers, returns the list the CLI itself advertises (we keep a
/// small curated list to avoid an extra subprocess per Settings render).
enum ProviderModelCatalog {

    static func staticModels(for provider: AIProvider) -> [String] {
        switch provider {
        case .anthropic:
            return [
                "claude-opus-4-7",
                "claude-sonnet-4-6",
                "claude-haiku-4-5-20251001",
                "claude-3-7-sonnet-latest",
                "claude-3-5-haiku-latest"
            ]
        case .openai:
            return [
                "gpt-5",
                "gpt-5-mini",
                "gpt-4o",
                "gpt-4o-mini",
                "o1",
                "o1-mini"
            ]
        case .gemini:
            return [
                "gemini-2.0-pro",
                "gemini-2.0-flash",
                "gemini-2.0-flash-thinking",
                "gemini-1.5-pro",
                "gemini-1.5-flash"
            ]
        case .claudeCLI:
            return [
                "claude-opus-4-7",
                "claude-sonnet-4-6",
                "claude-haiku-4-5-20251001"
            ]
        case .codexCLI:
            return [
                "gpt-5",
                "gpt-5-mini",
                "o1",
                "o3"
            ]
        case .auto, .local, .none:
            return []
        }
    }

    /// Discovers models dynamically from the local OpenAI-compatible endpoint.
    /// Returns the configured fallback ("qwen3-coder:30b" default) if discovery fails.
    static func discoverLocalModels() async -> [String] {
        guard let config = AIClient.loadLocalConfig() else { return [] }
        return (try? await AIClient.discoverModels(config: config)) ?? []
    }

    /// Returns the user's current per-provider selection, or the provider's
    /// recommended default when no preference is stored.
    static func selectedModel(for provider: AIProvider) -> String {
        let key = userDefaultsKey(for: provider)
        if let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty {
            return stored
        }
        return staticModels(for: provider).first ?? ""
    }

    /// Persists the user's selection for a provider.
    static func setSelectedModel(_ modelID: String, for provider: AIProvider) {
        UserDefaults.standard.set(modelID, forKey: userDefaultsKey(for: provider))
    }

    static func userDefaultsKey(for provider: AIProvider) -> String {
        "chat.model.\(provider.rawValue)"
    }
}
