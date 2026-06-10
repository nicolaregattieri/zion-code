import Foundation

// MARK: - AI Computed Properties

extension RepositoryViewModel {

    var aiAPIKey: String {
        get {
            let _ = _aiKeyRevision // Register dependency
            if _cachedAIKeyProvider == aiProvider, let cached = _cachedAIKey {
                return cached
            }
            let key = AIClient.loadAPIKey(for: aiProvider) ?? ""
            _cachedAIKey = key
            _cachedAIKeyProvider = aiProvider
            return key
        }
        set {
            if newValue.isEmpty {
                AIClient.deleteAPIKey(for: aiProvider)
            } else {
                AIClient.saveAPIKey(newValue, for: aiProvider)
            }
            _cachedAIKey = newValue
            _cachedAIKeyProvider = aiProvider
            _aiKeyRevision += 1 // Trigger observation
            aiQuotaExceeded = false // Reset on key change
        }
    }

    var isAIConfigured: Bool {
        if aiProvider == .none { return false }
        if aiProvider == .local {
            return AIClient.loadLocalConfig() != nil
        }
        // `.auto` doesn't have its own Keychain entry. It only counts as
        // configured if at least one concrete backend is connected.
        if aiProvider == .auto {
            return effectiveAIProvider != .none
        }
        return !aiAPIKey.isEmpty
    }

    /// Resolves the user-facing `aiProvider` to a concrete backend. For
    /// `.auto` this picks the first connected provider in a deterministic
    /// priority order (Anthropic → Gemini → OpenAI → CLI → local). Returns
    /// `.none` if nothing is connected.
    ///
    /// Every call site that needs a real API key or makes a network call
    /// must read this instead of `aiProvider` directly — otherwise `.auto`
    /// would silently fall back to the heuristic generator because the
    /// Keychain has no entry for account="auto".
    var effectiveAIProvider: AIProvider {
        if aiProvider != .auto { return aiProvider }
        let priority: [AIProvider] = [.anthropic, .gemini, .openai, .claudeCLI, .codexCLI, .local]
        for candidate in priority where AIProviderSupport.isConnected(provider: candidate) {
            return candidate
        }
        return .none
    }

    /// Key for `effectiveAIProvider`. CLI/local providers don't need a key
    /// (string is empty by contract); concrete API providers fetch from
    /// Keychain.
    var effectiveAIAPIKey: String {
        let provider = effectiveAIProvider
        switch provider {
        case .none, .local, .claudeCLI, .codexCLI:
            return ""
        case .auto:
            return ""
        case .anthropic, .openai, .gemini:
            return AIClient.loadAPIKey(for: provider) ?? ""
        }
    }
}

// MARK: - Branch Computed Properties

extension RepositoryViewModel {

    var localBranchOptions: [String] {
        branchInfos
            .filter { !$0.isRemote }
            .map(\.name)
            .sorted()
    }

    var remoteBranchOptions: [String] {
        branchInfos
            .filter(\.isRemote)
            .map(\.name)
            .sorted()
    }
}
