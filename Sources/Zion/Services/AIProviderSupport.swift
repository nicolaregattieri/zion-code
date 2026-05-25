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
    static let configurableProviders: [AIProvider] = [.auto, .anthropic, .openai, .gemini, .local, .claudeCLI, .codexCLI]

    static func dashboardURL(for provider: AIProvider) -> URL? {
        switch provider {
        case .auto:
            return nil
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai:
            return URL(string: "https://platform.openai.com/api-keys")
        case .gemini:
            return URL(string: "https://aistudio.google.com/apikey")
        case .local:
            return URL(string: "https://ollama.com/library")
        case .claudeCLI:
            return URL(string: "https://docs.anthropic.com/en/docs/claude-code")
        case .codexCLI:
            return URL(string: "https://github.com/openai/codex")
        case .none:
            return nil
        }
    }

    static func isCLIConnected(provider: AIProvider, discovery: CLIDiscoveryService) async -> Bool {
        guard provider == .claudeCLI || provider == .codexCLI else { return false }
        let tool: CLITool = provider == .claudeCLI ? .claude : .codex
        let status = await discovery.status(for: tool)
        return status.installed && (status.isAuthenticated ?? false)
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
        if provider == .auto {
            return true
        }
        if provider == .claudeCLI || provider == .codexCLI {
            // Sync probe: filesystem path + keychain/auth check. Mirrors
            // CLIDiscoveryService.status() but without spawning subprocesses.
            let tool: CLITool = provider == .claudeCLI ? .claude : .codex
            guard cliBinaryExistsSync(tool: tool) else { return false }
            switch tool {
            case .claude: return CLIDiscoveryService.checkClaudeAuthRealtime()
            case .codex:  return CLIDiscoveryService.checkCodexAuthRealtime()
            }
        }
        guard provider != .none else { return false }
        guard let key = loadKey(provider)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !key.isEmpty
    }

    /// Cache for `cliBinaryExistsSync`. 60s TTL — long enough that repeated UI
    /// renders / orchestrator resolves don't hammer the filesystem, short enough
    /// that installing/removing a CLI propagates within a minute.
    private static let cliProbeCacheTTL: TimeInterval = 60
    nonisolated(unsafe) private static var cliProbeCache: [CLITool: (Bool, Date)] = [:]
    private static let cliProbeCacheLock = NSLock()

    /// Sync filesystem probe for a CLI binary in well-known install locations.
    /// Mirrors CLIDiscoveryService.buildProbePaths but without subprocess calls.
    /// Result is memoised for `cliProbeCacheTTL` to keep `isConnected` cheap.
    static func cliBinaryExistsSync(tool: CLITool) -> Bool {
        cliProbeCacheLock.lock()
        if let (cached, ts) = cliProbeCache[tool],
           Date().timeIntervalSince(ts) < cliProbeCacheTTL {
            cliProbeCacheLock.unlock()
            return cached
        }
        cliProbeCacheLock.unlock()

        let result = computeCliBinaryExists(tool: tool)

        cliProbeCacheLock.lock()
        cliProbeCache[tool] = (result, Date())
        cliProbeCacheLock.unlock()
        return result
    }

    private static func computeCliBinaryExists(tool: CLITool) -> Bool {
        let home = NSHomeDirectory()
        let fixed: [String] = [
            "/opt/homebrew/bin/\(tool.rawValue)",
            "/usr/local/bin/\(tool.rawValue)",
            "\(home)/.local/bin/\(tool.rawValue)",
            "\(home)/.bun/bin/\(tool.rawValue)",
            "\(home)/.volta/bin/\(tool.rawValue)",
            "\(home)/.deno/bin/\(tool.rawValue)",
        ]
        for p in fixed where FileManager.default.fileExists(atPath: p) { return true }

        let nodeBases = [
            "\(home)/.nvm/versions/node",
            "\(home)/.asdf/installs/nodejs",
            "/usr/local/n/versions/node",
        ]
        for base in nodeBases {
            if let dirs = try? FileManager.default.contentsOfDirectory(atPath: base) {
                for dir in dirs {
                    if FileManager.default.fileExists(atPath: "\(base)/\(dir)/bin/\(tool.rawValue)") {
                        return true
                    }
                }
            }
        }
        let fnmBase = "\(home)/.fnm/node-versions"
        if let dirs = try? FileManager.default.contentsOfDirectory(atPath: fnmBase) {
            for dir in dirs {
                if FileManager.default.fileExists(atPath: "\(fnmBase)/\(dir)/installation/bin/\(tool.rawValue)") {
                    return true
                }
            }
        }
        return false
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
            provider != defaultProvider
                && provider != .auto                 // .auto is a routing pseudo-provider, never a fallback
                && isConnected(provider: provider, loadKey: loadKey)
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

    // MARK: - Tool Calling

    /// Returns true if the given local model name is known to support tool calling.
    /// Matching is case-insensitive.
    static func localModelSupportsTools(_ name: String) -> Bool {
        let patterns: [String] = [
            "qwen3-coder",
            "qwen2\\.5-coder",
            "llama-3\\.[3-9]",
            "mistral-large",
            "deepseek-v3",
            "gpt-oss",
            "glm-4"
        ]
        let combined = patterns.joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: combined, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(name.startIndex..., in: name)
        return regex.firstMatch(in: name, options: [], range: range) != nil
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
