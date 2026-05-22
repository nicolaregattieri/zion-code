import Foundation

struct LocalLLMConfig: Codable, Equatable {
    var version: Int = 2
    var serverURL: String = "http://localhost:11434/v1"
    var modelName: String = "qwen3-coder:30b"
    var requestTimeoutSeconds: Int = 60
    var apiKey: String = ""
    /// Detected or user-selected engine. Drives `LocalServerLauncher` auto-start.
    /// `.custom` (default for unknown URLs) disables auto-start entirely.
    var engineKind: LocalEngineKind = .ollama
    /// When true, ChatService will attempt to spawn the engine before each chat
    /// if the endpoint is unreachable. When false, behaviour is unchanged.
    var autoStartEnabled: Bool = true

    var endpointURL: URL? {
        URL(string: serverURL)
    }

    enum CodingKeys: String, CodingKey {
        case version, serverURL, modelName, requestTimeoutSeconds, apiKey
        case engineKind, autoStartEnabled
    }

    init(
        version: Int = 2,
        serverURL: String = "http://localhost:11434/v1",
        modelName: String = "qwen3-coder:30b",
        requestTimeoutSeconds: Int = 60,
        apiKey: String = "",
        engineKind: LocalEngineKind = .ollama,
        autoStartEnabled: Bool = true
    ) {
        self.version = version
        self.serverURL = serverURL
        self.modelName = modelName
        self.requestTimeoutSeconds = requestTimeoutSeconds.clamped(to: 5...600)
        self.apiKey = apiKey
        self.engineKind = engineKind
        self.autoStartEnabled = autoStartEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        serverURL = try container.decodeIfPresent(String.self, forKey: .serverURL) ?? "http://localhost:11434/v1"
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? "qwen3-coder:30b"
        let rawTimeout = try container.decodeIfPresent(Int.self, forKey: .requestTimeoutSeconds) ?? 60
        requestTimeoutSeconds = rawTimeout.clamped(to: 5...600)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        // v2 fields: when migrating from v1, infer engine from URL so existing
        // users get sensible defaults without re-configuring.
        if let stored = try container.decodeIfPresent(LocalEngineKind.self, forKey: .engineKind) {
            engineKind = stored
        } else {
            engineKind = LocalEngineKind.detect(from: serverURL)
        }
        autoStartEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoStartEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(serverURL, forKey: .serverURL)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(requestTimeoutSeconds, forKey: .requestTimeoutSeconds)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(engineKind, forKey: .engineKind)
        try container.encode(autoStartEnabled, forKey: .autoStartEnabled)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
