import Foundation

struct AIProviderConnectionInfo: Equatable {
    let provider: AIProvider
    let isConnected: Bool
    let dashboardURL: URL?

    var supportsWhisper: Bool {
        provider == .openai
    }
}

struct AIQuotaRecoveryInfo: Equatable {
    let alternativeProviders: [AIProvider]

    var hasAlternativeProvider: Bool {
        !alternativeProviders.isEmpty
    }
}

enum AIProviderSupport {
    static let configurableProviders: [AIProvider] = [.anthropic, .openai, .gemini, .local]

    static func dashboardURL(for provider: AIProvider) -> URL? {
        switch provider {
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai:
            return URL(string: "https://platform.openai.com/api-keys")
        case .gemini:
            return URL(string: "https://aistudio.google.com/apikey")
        case .local:
            return URL(string: "https://ollama.com/library")
        case .none:
            return nil
        }
    }

    static func isConnected(
        provider: AIProvider,
        loadKey: (AIProvider) -> String? = AIClient.loadAPIKey,
        loadLocalConfig: () -> LocalLLMConfig? = AIClient.loadLocalConfig,
        localHealthProbe: (LocalLLMConfig) -> Bool = { _ in
            let lastHealthy = UserDefaults.standard.double(forKey: UserDefaultsKeys.AI.localLastHealthyAt)
            guard lastHealthy > 0 else { return false }
            return Date().timeIntervalSince1970 - lastHealthy < Constants.Timing.localHealthFreshnessSeconds
        }
    ) -> Bool {
        if provider == .local {
            guard let config = loadLocalConfig() else { return false }
            return localHealthProbe(config)
        }
        guard provider != .none else { return false }
        guard let key = loadKey(provider)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !key.isEmpty
    }

    static func probeOnce(config: LocalLLMConfig) async -> Bool {
        await AIClient.probeHealth(config: config)
    }

    static func connectionInfo(
        loadKey: (AIProvider) -> String? = AIClient.loadAPIKey
    ) -> [AIProviderConnectionInfo] {
        configurableProviders.map { provider in
            AIProviderConnectionInfo(
                provider: provider,
                isConnected: isConnected(provider: provider, loadKey: loadKey),
                dashboardURL: dashboardURL(for: provider)
            )
        }
    }

    static func alternativeProviders(
        excluding defaultProvider: AIProvider,
        loadKey: (AIProvider) -> String? = AIClient.loadAPIKey
    ) -> [AIProvider] {
        configurableProviders.filter { provider in
            provider != defaultProvider && isConnected(provider: provider, loadKey: loadKey)
        }
    }

    static func quotaRecoveryInfo(
        defaultProvider: AIProvider,
        loadKey: (AIProvider) -> String? = AIClient.loadAPIKey
    ) -> AIQuotaRecoveryInfo {
        AIQuotaRecoveryInfo(
            alternativeProviders: alternativeProviders(excluding: defaultProvider, loadKey: loadKey)
        )
    }
}

enum SpeechEngineSupport {
    static func isWhisperAvailable(
        loadKey: (AIProvider) -> String? = AIClient.loadAPIKey
    ) -> Bool {
        AIProviderSupport.isConnected(provider: .openai, loadKey: loadKey)
    }

    static func isGeminiAvailable(
        loadKey: (AIProvider) -> String? = AIClient.loadAPIKey
    ) -> Bool {
        AIProviderSupport.isConnected(provider: .gemini, loadKey: loadKey)
    }

    static func effectiveEngine(
        storedValue: String?,
        loadKey: (AIProvider) -> String? = AIClient.loadAPIKey
    ) -> SpeechRecognitionService.Engine {
        switch SpeechRecognitionService.Engine(rawValue: storedValue ?? "") {
        case .whisper:
            return isWhisperAvailable(loadKey: loadKey) ? .whisper : .apple
        case .gemini:
            return isGeminiAvailable(loadKey: loadKey) ? .gemini : .apple
        case .apple:
            return .apple
        case nil:
            return .apple
        }
    }
}
