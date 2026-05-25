import Foundation

/// Detected local model installed on the user's machine. Surfaced to the Talks
/// empty state and the Auto-mode banner so we can offer Smart Auto routing
/// without ever spawning a server unsolicited.
struct LocalModelHint: Equatable, Hashable {
    enum Runtime: String, Equatable, Hashable {
        case ollama
        case lmStudio
        case mlx
        case llamaCpp
        case customServer
    }

    let runtime: Runtime
    let modelID: String
    let location: String       // filesystem path or server URL
    let sizeBytes: Int64?      // nil = unknown

    var label: String {
        switch runtime {
        case .ollama:        return "\(modelID) · Ollama"
        case .lmStudio:      return "\(modelID) · LM Studio"
        case .mlx:           return "\(modelID) · MLX"
        case .llamaCpp:      return "\(modelID) · llama.cpp"
        case .customServer:  return "\(modelID) · custom server"
        }
    }
}

/// Discovers locally installed LLM models WITHOUT spawning any server.
/// Strategy:
///   1. Scan well-known filesystem paths for each runtime (Ollama / LM Studio /
///      MLX / llama.cpp). Returns model manifests and `.gguf` files.
///   2. If `LocalLLMConfig.serverURL` is set AND `probeCustomServer == true`,
///      issue a single short HTTP GET to list models from a running server.
///      Disabled by default so the scan stays offline-only.
///   3. Scan optional `customModelsFolderURL` (user-supplied folder of GGUFs).
///
/// All filesystem scans use `FileManager` defaults — no privileged paths, no
/// background processes, capped depth.
enum LocalModelDiscovery {

    /// Top-level scan. Aggregates hints from every runtime in deterministic order.
    static func scan(
        config: LocalLLMConfig? = nil,
        customModelsFolderURL: URL? = nil,
        probeCustomServer: Bool = false
    ) async -> [LocalModelHint] {
        var hints: [LocalModelHint] = []

        hints.append(contentsOf: scanOllama())
        hints.append(contentsOf: scanLMStudio())
        hints.append(contentsOf: scanMLX())
        hints.append(contentsOf: scanLlamaCpp())

        if let folder = customModelsFolderURL {
            hints.append(contentsOf: scanCustomGGUFFolder(folder))
        }

        if probeCustomServer, let url = config?.endpointURL {
            if let probed = await probeServer(url: url, kind: config?.engineKind) {
                hints.append(contentsOf: probed)
            }
        }

        // Deduplicate (some runtimes share filesystem-level caches with HF).
        var seen: Set<LocalModelHint> = []
        return hints.filter { seen.insert($0).inserted }
    }

    // MARK: - Ollama
    //
    // Layout:
    //   ~/.ollama/models/manifests/registry.ollama.ai/library/<model>/<tag>
    // Each `<tag>` file is a JSON manifest; presence = model installed.

    static func scanOllama() -> [LocalModelHint] {
        let home = NSHomeDirectory()
        let base = "\(home)/.ollama/models/manifests/registry.ollama.ai/library"
        guard let modelDirs = try? FileManager.default.contentsOfDirectory(atPath: base) else { return [] }
        var hints: [LocalModelHint] = []
        for model in modelDirs.sorted() {
            let modelPath = "\(base)/\(model)"
            guard let tags = try? FileManager.default.contentsOfDirectory(atPath: modelPath) else { continue }
            for tag in tags.sorted() where !tag.hasPrefix(".") {
                let id = "\(model):\(tag)"
                let size = fileSize(atPath: "\(modelPath)/\(tag)")
                hints.append(LocalModelHint(runtime: .ollama, modelID: id, location: "\(modelPath)/\(tag)", sizeBytes: size))
            }
        }
        return hints
    }

    // MARK: - LM Studio
    //
    // Layout (varies by version):
    //   ~/.lmstudio/models/<publisher>/<model>/<file>.gguf
    //   ~/.cache/lm-studio/models/<publisher>/<model>/<file>.gguf

    static func scanLMStudio() -> [LocalModelHint] {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.lmstudio/models",
            "\(home)/.cache/lm-studio/models"
        ]
        var hints: [LocalModelHint] = []
        for base in candidates where FileManager.default.fileExists(atPath: base) {
            hints.append(contentsOf: scanGGUFTree(base, runtime: .lmStudio))
        }
        return hints
    }

    // MARK: - MLX
    //
    // mlx-lm pulls weights from HuggingFace; cache lives at:
    //   ~/.cache/huggingface/hub/models--<org>--<model>/snapshots/<sha>/
    // Manifest presence = model installed.

    static func scanMLX() -> [LocalModelHint] {
        let home = NSHomeDirectory()
        let base = "\(home)/.cache/huggingface/hub"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: base) else { return [] }
        var hints: [LocalModelHint] = []
        for entry in entries.sorted() where entry.hasPrefix("models--") {
            // Trim "models--" prefix, replace "--" with "/" for readability.
            let stripped = String(entry.dropFirst("models--".count))
            let modelID = stripped.replacingOccurrences(of: "--", with: "/")
            // Only count it as MLX-capable if at least one snapshot dir exists.
            let snapshots = "\(base)/\(entry)/snapshots"
            if let snaps = try? FileManager.default.contentsOfDirectory(atPath: snapshots), !snaps.isEmpty {
                hints.append(LocalModelHint(runtime: .mlx, modelID: modelID, location: snapshots, sizeBytes: nil))
            }
        }
        return hints
    }

    // MARK: - llama.cpp / ad-hoc GGUF folders
    //
    // No canonical layout. We probe two common user habits and stop there:
    //   ~/Models/*.gguf
    //   ~/llama/models/*.gguf

    static func scanLlamaCpp() -> [LocalModelHint] {
        let home = NSHomeDirectory()
        let candidates = ["\(home)/Models", "\(home)/llama/models"]
        var hints: [LocalModelHint] = []
        for base in candidates where FileManager.default.fileExists(atPath: base) {
            hints.append(contentsOf: scanGGUFTree(base, runtime: .llamaCpp))
        }
        return hints
    }

    // MARK: - Custom folder (user-supplied)

    static func scanCustomGGUFFolder(_ folder: URL) -> [LocalModelHint] {
        scanGGUFTree(folder.path, runtime: .llamaCpp)
    }

    // MARK: - Custom server probe (opt-in)

    static func probeServer(url: URL, kind: LocalEngineKind?, timeout: TimeInterval = 0.8) async -> [LocalModelHint]? {
        // SSRF guard: only allow loopback for local-server probes. A user can
        // legitimately point the local config at 127.0.0.1 / localhost / *.local
        // but never at private subnets or cloud metadata IPs — those would be
        // someone else's network resource, not a local LLM.
        if let host = url.host?.lowercased() {
            let loopback = host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
            if !loopback, FileSystemMentionToolClient.isPrivateOrMetadataHost(host) {
                return nil
            }
        }
        // Pick the right list endpoint for the engine. Defaults to OpenAI-compatible.
        let listURL: URL?
        switch kind {
        case .ollama:
            // Ollama exposes /api/tags at the BASE host (sibling of /v1).
            listURL = URL(string: url.absoluteString.replacingOccurrences(of: "/v1", with: "") + "/api/tags")
        default:
            listURL = url.appendingPathComponent("models")
        }
        guard let target = listURL else { return nil }

        var request = URLRequest(url: target)
        request.timeoutInterval = timeout
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return parseServerList(data: data, kind: kind, location: url.absoluteString)
        } catch {
            return nil
        }
    }

    static func parseServerList(data: Data, kind: LocalEngineKind?, location: String) -> [LocalModelHint] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        // Ollama: { "models": [{ "name": "..." , "size": 123 }, ...] }
        if kind == .ollama, let models = obj["models"] as? [[String: Any]] {
            return models.compactMap { entry in
                guard let name = entry["name"] as? String else { return nil }
                let size = (entry["size"] as? Int64) ?? (entry["size"] as? Int).map(Int64.init)
                return LocalModelHint(runtime: .customServer, modelID: name, location: location, sizeBytes: size)
            }
        }
        // OpenAI-compatible: { "data": [{ "id": "..." }, ...] }
        if let dataArr = obj["data"] as? [[String: Any]] {
            return dataArr.compactMap { entry in
                guard let id = entry["id"] as? String else { return nil }
                return LocalModelHint(runtime: .customServer, modelID: id, location: location, sizeBytes: nil)
            }
        }
        return []
    }

    // MARK: - Helpers

    private static func scanGGUFTree(_ basePath: String, runtime: LocalModelHint.Runtime, maxDepth: Int = 3) -> [LocalModelHint] {
        var hints: [LocalModelHint] = []
        let baseURL = URL(fileURLWithPath: basePath)
        guard let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        while let url = enumerator.nextObject() as? URL {
            if enumerator.level > maxDepth { enumerator.skipDescendants(); continue }
            guard url.pathExtension.lowercased() == "gguf" else { continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            let size = (values?.fileSize).map(Int64.init)
            // Use the parent folder name + file stem as a readable id.
            let parent = url.deletingLastPathComponent().lastPathComponent
            let stem = url.deletingPathExtension().lastPathComponent
            let id = parent.isEmpty ? stem : "\(parent)/\(stem)"
            hints.append(LocalModelHint(runtime: runtime, modelID: id, location: url.path, sizeBytes: size))
        }
        return hints
    }

    private static func fileSize(atPath path: String) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return (attrs[.size] as? NSNumber)?.int64Value
    }
}
