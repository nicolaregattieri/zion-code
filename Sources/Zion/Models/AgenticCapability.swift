import Foundation

// MARK: - AgenticCapability

/// Describes how a provider/model combination participates in the agentic loop.
enum AgenticCapability {
    /// Provider natively supports tool/function calling (structured JSON).
    case nativeToolUse
    /// Provider does not support tool calling; the loop uses ReAct-style text prompting as a fallback.
    case reactTextFallback
    /// Provider is a CLI passthrough (e.g. claudeCLI, codexCLI) that manages its own tool loop.
    case passthrough
    /// Provider cannot participate in any agentic loop.
    case unsupported
}

// MARK: - Resolver

extension AgenticCapability {
    /// Resolves the agentic capability for a provider + optional model name.
    ///
    /// - Parameters:
    ///   - provider: The AI provider in use.
    ///   - modelName: The specific model identifier (required for `.local` to determine tool support).
    /// - Returns: The appropriate `AgenticCapability` for the combination.
    static func resolve(provider: AIProvider, modelName: String?) -> AgenticCapability {
        switch provider {
        case .anthropic, .openai:
            return .nativeToolUse

        case .gemini:
            // T2 will enable gemini supportsToolCalling
            return .nativeToolUse

        case .auto:
            // The orchestrator resolves a concrete tool-capable provider; assume native.
            return .nativeToolUse

        case .local:
            let name = modelName ?? ""
            return AIProviderSupport.localModelSupportsTools(name)
                ? .nativeToolUse
                : .reactTextFallback

        case .claudeCLI, .codexCLI:
            return .passthrough

        case .none:
            return .unsupported
        }
    }
}
