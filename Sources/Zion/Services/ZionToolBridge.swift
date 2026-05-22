// ZionToolBridge.swift — Central bridge that wires MCPClient, CapabilityProbe, and ToolLoopExecutor.
// Exposes a single entry point reused by AIClient provider streams.

import Foundation

// MARK: - ZionToolBridgeError

enum ZionToolBridgeError: Error, LocalizedError {
    case toolsDisabledBySettings
    case modelDoesNotSupportTools(AIProvider, String)
    case mcpClientNotConfigured

    var errorDescription: String? {
        switch self {
        case .toolsDisabledBySettings:
            return "Tool bridge disabled by settings"
        case .modelDoesNotSupportTools(let p, let m):
            return "Model '\(m)' on provider '\(p.rawValue)' does not support tools"
        case .mcpClientNotConfigured:
            return "MCP client not configured (binary not found)"
        }
    }
}

// MARK: - ZionToolBridge

/// Central bridge: translates tool schemas, probes capability, and runs the tool loop.
///
/// Implemented as a `final class` so `[String: Any]` conversation payloads can
/// cross the public boundary without Swift 6 sending-risk diagnostics. The
/// class is `@unchecked Sendable` because internal state mutations are
/// performed only via async methods that complete sequentially per instance.
final class ZionToolBridge: @unchecked Sendable {

    // MARK: Dependencies

    private let mcpClient: MCPClient
    private let capabilityProbe: CapabilityProbe
    private var isStarted = false

    // MARK: Settings key

    /// UserDefaults key that gates whether the bridge engages.
    static let settingsKey = "chat.providers.toolBridge"

    // MARK: Init

    init(mcpClient: MCPClient = MCPClient(), capabilityProbe: CapabilityProbe = CapabilityProbe()) {
        self.mcpClient     = mcpClient
        self.capabilityProbe = capabilityProbe
    }

    // MARK: Public API

    /// Run a tool-enabled conversation turn.
    ///
    /// - Parameters:
    ///   - family: The provider family (anthropic, openai, gemini, openrouter, localOpenAICompatible).
    ///   - modelID: The specific model identifier (for capability caching).
    ///   - conversation: The conversation so far as an array of role/content dicts.
    ///   - streamLines: Provider SSE data lines for the current response.
    ///   - repoCwd: Optional repo working directory for the MCP server.
    /// - Returns: Updated conversation after any tool round-trips.
    func run(
        family: ProviderFamily,
        modelID: String,
        conversation: [[String: Any]],
        streamLines: AsyncThrowingStream<String, Error>,
        repoCwd: URL? = nil
    ) async throws -> [[String: Any]] {

        // 1. Check settings gate
        guard UserDefaults.standard.object(forKey: Self.settingsKey) == nil
                || UserDefaults.standard.bool(forKey: Self.settingsKey)
        else {
            throw ZionToolBridgeError.toolsDisabledBySettings
        }

        // 2. Ensure MCP client is running
        if !isStarted {
            guard let binaryPath = MCPConfigBuilder.resolveBinaryPath() else {
                throw ZionToolBridgeError.mcpClientNotConfigured
            }
            try mcpClient.start(binaryPath: binaryPath, repoCwd: repoCwd)
            isStarted = true
        }

        // 3. Map AIProvider -> ProviderFamily for the probe
        let provider = aiProvider(for: family)

        // 4. Probe capability
        let supported = await capabilityProbe.supportsTools(
            provider: provider,
            modelID: modelID
        ) { [weak mcpClient] in
            // Simple capability probe: check if tools/list returns any tools
            guard let client = mcpClient else { return false }
            let tools = try await client.listTools()
            return !tools.isEmpty
        }

        guard supported else {
            throw ZionToolBridgeError.modelDoesNotSupportTools(provider, modelID)
        }

        // 5. Run tool loop
        let executor = ToolLoopExecutor(family: family, mcpClient: mcpClient)
        let (_, updatedConversation) = try await executor.run(
            streamLines: streamLines,
            conversation: conversation
        )

        return updatedConversation
    }

    /// Convenience: fetch translated tool schemas for the given family.
    func toolSchemas(for family: ProviderFamily) async throws -> [[String: Any]] {
        if !isStarted {
            guard let binaryPath = MCPConfigBuilder.resolveBinaryPath() else {
                return []
            }
            try mcpClient.start(binaryPath: binaryPath, repoCwd: nil)
            isStarted = true
        }
        let descriptors = try await mcpClient.listTools()
        return ToolSchemaTranslator.translate(descriptors, for: family)
    }

    /// Stop the underlying MCP client.
    func stop() async {
        await mcpClient.stop()
        isStarted = false
    }

    // MARK: Private helpers

    private func aiProvider(for family: ProviderFamily) -> AIProvider {
        switch family {
        case .anthropic:            return .anthropic
        case .openai:               return .openai
        case .openrouter:           return .openai   // openrouter maps to openai
        case .gemini:               return .gemini
        case .localOpenAICompatible: return .local
        }
    }
}
