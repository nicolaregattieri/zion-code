import Foundation

// MARK: - CLIToolStatus

struct CLIToolStatus: Equatable {
    let installed: Bool
    let path: URL?
    let version: String?
    let isAuthenticated: Bool?
}

// MARK: - CLIDiscoveryService

actor CLIDiscoveryService {

    // MARK: - Injectable process runner

    typealias ProcessRunner = @Sendable (String, [String], TimeInterval) async -> (Int32, String, String)

    // MARK: - Private state

    private let processRunner: ProcessRunner
    private static let cacheKeyPrefix = "cli.discovery"

    // MARK: - Init

    init(processRunner: ProcessRunner? = nil) {
        self.processRunner = processRunner ?? CLIDiscoveryService.realProcessRunner
    }

    // MARK: - Public API

    func status(for tool: CLITool, refresh: Bool = false) async -> CLIToolStatus {
        let absPath = await resolveAbsolutePath(for: tool)

        guard let absPath else {
            return CLIToolStatus(installed: false, path: nil, version: nil, isAuthenticated: nil)
        }

        let version = await resolveVersion(absPath: absPath, tool: tool)
        let cacheKey = "\(Self.cacheKeyPrefix).\(tool.rawValue).\(absPath).\(version ?? "")"

        if !refresh, let cached = loadCache(key: cacheKey) {
            return cached
        }

        let authStatus = await resolveAuth(absPath: absPath, tool: tool)
        let result = CLIToolStatus(
            installed: true,
            path: URL(fileURLWithPath: absPath),
            version: version,
            isAuthenticated: authStatus
        )
        saveCache(key: cacheKey, status: result)
        return result
    }

    // MARK: - Discovery

    private func resolveAbsolutePath(for tool: CLITool) async -> String? {
        // 1. Try `which`
        let (whichExit, whichOut, _) = await processRunner("/usr/bin/which", [tool.rawValue], 5.0)
        if whichExit == 0 {
            let path = whichOut.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { return path }
        }

        // 2. Probe well-known absolute paths
        let probePaths = buildProbePaths(for: tool)
        for path in probePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func buildProbePaths(for tool: CLITool) -> [String] {
        var paths: [String] = [
            "/opt/homebrew/bin/\(tool.rawValue)",
            "/usr/local/bin/\(tool.rawValue)",
            "\(NSHomeDirectory())/.local/bin/\(tool.rawValue)"
        ]

        // nvm glob: ~/.nvm/versions/node/*/bin/<cli>
        let nvmNodeBase = "\(NSHomeDirectory())/.nvm/versions/node"
        if let nodeDirs = try? FileManager.default.contentsOfDirectory(atPath: nvmNodeBase) {
            for nodeDir in nodeDirs.sorted() {
                paths.append("\(nvmNodeBase)/\(nodeDir)/bin/\(tool.rawValue)")
            }
        }

        return paths
    }

    // MARK: - Version

    private func resolveVersion(absPath: String, tool: CLITool) async -> String? {
        let (_, stdout, _) = await processRunner(absPath, ["--version"], 5.0)
        return CLIDiscoveryService.parseSemver(from: stdout)
    }

    static func parseSemver(from output: String) -> String? {
        let pattern = #"(\d+\.\d+\.\d+)"#
        guard let range = output.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(output[range])
    }

    // MARK: - Auth Check

    private func resolveAuth(absPath: String, tool: CLITool) async -> Bool? {
        switch tool {
        case .claude:
            return await checkClaudeAuth(absPath: absPath)
        case .codex:
            return await checkCodexAuth(absPath: absPath)
        }
    }

    private func checkClaudeAuth(absPath: String) async -> Bool {
        let (exitCode, stdout, _) = await processRunner(
            absPath,
            ["-p", "ping", "--output-format", "json"],
            Constants.Timing.cliAuthProbeTimeout
        )
        if exitCode != 0 { return false }
        // Check for permission_denials field in JSON
        if let data = stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let denials = json["permission_denials"],
           !(denials is NSNull) {
            // If permission_denials key is present (and non-null), treat as unauthenticated
            return false
        }
        return true
    }

    private func checkCodexAuth(absPath: String) async -> Bool {
        let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
        let (exitCode, _, _) = await processRunner(
            absPath,
            ["exec", "--json", "-s", "read-only", "-C", tmpDir],
            Constants.Timing.cliAuthProbeTimeout
        )
        return exitCode == 0
    }

    // MARK: - Cache

    private struct CacheEntry: Codable {
        let status: CodableCLIToolStatus
        let indexedAt: TimeInterval
    }

    private struct CodableCLIToolStatus: Codable {
        let installed: Bool
        let path: String?
        let version: String?
        let isAuthenticated: Bool?
    }

    private func saveCache(key: String, status: CLIToolStatus) {
        let codable = CodableCLIToolStatus(
            installed: status.installed,
            path: status.path?.path,
            version: status.version,
            isAuthenticated: status.isAuthenticated
        )
        let entry = CacheEntry(status: codable, indexedAt: Date().timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadCache(key: String) -> CLIToolStatus? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            return nil
        }
        let age = Date().timeIntervalSince1970 - entry.indexedAt
        guard age < Constants.Timing.cliDiscoveryCacheTTL else { return nil }

        return CLIToolStatus(
            installed: entry.status.installed,
            path: entry.status.path.map { URL(fileURLWithPath: $0) },
            version: entry.status.version,
            isAuthenticated: entry.status.isAuthenticated
        )
    }

    // MARK: - Real Process Runner

    private static let realProcessRunner: ProcessRunner = { executable, arguments, timeout in
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var timedOut = false
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                timedOut = true
                process.terminate()
                timer.cancel()
            }

            do {
                try process.run()
                timer.resume()
                process.waitUntilExit()
                timer.cancel()
            } catch {
                timer.cancel()
                continuation.resume(returning: (1, "", error.localizedDescription))
                return
            }

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let code: Int32 = timedOut ? 124 : process.terminationStatus

            continuation.resume(returning: (code, stdout, stderr))
        }
    }
}
