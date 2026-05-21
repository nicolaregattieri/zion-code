import Foundation

struct LocalLLMConfig: Codable, Equatable {
    var version: Int = 1
    var backend: LocalLLMBackend = .ollama
    var serverURL: String = "http://localhost:11434"
    var modelName: String = "qwen3-coder:30b"
    var requestTimeoutSeconds: Int = 60
    var apiKey: String = ""

    var endpointURL: URL? {
        URL(string: serverURL)
    }

    enum CodingKeys: String, CodingKey {
        case version, backend, serverURL, modelName, requestTimeoutSeconds, apiKey
    }

    init(
        version: Int = 1,
        backend: LocalLLMBackend = .ollama,
        serverURL: String = "http://localhost:11434",
        modelName: String = "qwen3-coder:30b",
        requestTimeoutSeconds: Int = 60,
        apiKey: String = ""
    ) {
        self.version = version
        self.backend = backend
        self.serverURL = serverURL
        self.modelName = modelName
        self.requestTimeoutSeconds = requestTimeoutSeconds.clamped(to: 5...600)
        self.apiKey = apiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        backend = try container.decodeIfPresent(LocalLLMBackend.self, forKey: .backend) ?? .ollama
        serverURL = try container.decodeIfPresent(String.self, forKey: .serverURL) ?? "http://localhost:11434"
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? "qwen3-coder:30b"
        let rawTimeout = try container.decodeIfPresent(Int.self, forKey: .requestTimeoutSeconds) ?? 60
        requestTimeoutSeconds = rawTimeout.clamped(to: 5...600)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(backend, forKey: .backend)
        try container.encode(serverURL, forKey: .serverURL)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(requestTimeoutSeconds, forKey: .requestTimeoutSeconds)
        try container.encode(apiKey, forKey: .apiKey)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
