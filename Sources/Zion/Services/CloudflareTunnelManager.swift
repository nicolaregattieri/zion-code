import Foundation

actor CloudflareTunnelManager {
    private static let tunnelURLPattern = try! NSRegularExpression(pattern: #"https://[a-z0-9.-]+\.trycloudflare\.com"#)
    private var process: Process?
    private var tunnelURL: String?

    var currentURL: String? { tunnelURL }
    var isRunning: Bool { process?.isRunning ?? false }

    // MARK: - Lifecycle

    func start(localPort: UInt16) async throws -> String {
        // Kill any existing tunnel process (ours or orphaned)
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        self.process = nil

        // Also kill any orphaned cloudflared processes on the same port
        Self.killOrphanedProcesses(port: localPort)

        guard let binaryPath = await Self.findCloudflaredBinary() else {
            throw TunnelError.cloudflaredNotFound
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["tunnel", "--url", "http://localhost:\(localPort)"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        try proc.run()
        process = proc

        // Parse tunnel URL from stderr (cloudflared writes URL there)
        let url = try await parseTunnelURL(from: stderrPipe)
        tunnelURL = url

        await MainActor.run {
            DiagnosticLogger.shared.log(.info, "Cloudflare tunnel started", context: url, source: "CloudflareTunnelManager")
        }

        return url
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        tunnelURL = nil
    }

    /// Kill any orphaned cloudflared tunnel processes targeting the same port
    private static func killOrphanedProcesses(port: UInt16) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        proc.arguments = ["-f", "cloudflared tunnel --url http://localhost:\(port)"]
        try? proc.run()
        proc.waitUntilExit()
    }

    // MARK: - Binary Detection

    static func findCloudflaredBinary() async -> String? {
        let searchPaths = [
            "/usr/local/bin/cloudflared",
            "/opt/homebrew/bin/cloudflared",
            "/usr/bin/cloudflared",
        ]

        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback: check PATH via `which`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["cloudflared"]
        let pipe = Pipe()
        proc.standardOutput = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty { return path }
            }
        } catch {
            // which not available or failed
        }

        return nil
    }

    static func isCloudflaredInstalled() async -> Bool {
        await findCloudflaredBinary() != nil
    }

    // MARK: - URL Parsing

    private func parseTunnelURL(from pipe: Pipe) async throws -> String {
        let handle = pipe.fileHandleForReading

        return try await withCheckedThrowingContinuation { continuation in
            let state = TunnelParseState()

            handle.readabilityHandler = { fileHandle in
                let newData = fileHandle.availableData
                guard !newData.isEmpty else {
                    if let result = Self.classifyTunnelOutput(state.currentText() ?? "") {
                        if state.tryResume() {
                            fileHandle.readabilityHandler = nil
                            continuation.resume(with: result.result)
                        }
                        return
                    }
                    if state.tryResume() {
                        fileHandle.readabilityHandler = nil
                        continuation.resume(throwing: TunnelError.urlParsingFailed)
                    }
                    return
                }

                state.appendData(newData)
                guard let text = state.currentText() else { return }

                if let result = Self.classifyTunnelOutput(text) {
                    if state.tryResume() {
                        fileHandle.readabilityHandler = nil
                        continuation.resume(with: result.result)
                    }
                }
            }

            // Timeout after 30 seconds
            Task { [state] in
                try? await Task.sleep(nanoseconds: Constants.RemoteAccess.tunnelURLTimeoutNanoseconds)
                if state.tryResume() {
                    handle.readabilityHandler = nil
                    continuation.resume(throwing: TunnelError.timeout)
                }
            }
        }
    }

    static func classifyTunnelOutput(_ text: String) -> TunnelOutputResult? {
        let range = NSRange(text.startIndex..., in: text)
        if let match = tunnelURLPattern.firstMatch(in: text, range: range),
           let matchRange = Range(match.range, in: text) {
            let candidate = String(text[matchRange])
            if URL(string: candidate)?.host != "api.trycloudflare.com" {
                return .url(candidate)
            }
        }

        if text.contains("429") || text.contains("Too Many Requests") {
            return .rateLimited
        }

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let failureLine = lines.last(where: Self.isFailureLine(_:)) {
            return .startupFailed(failureLine)
        }

        return nil
    }

    private static func isFailureLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.hasPrefix("failed ")
            || lowercased.contains("failed to request quick tunnel")
            || lowercased.contains("lookup ")
            || lowercased.contains("no such host")
            || lowercased.contains("unable to reach")
    }

    /// Thread-safe state holder for tunnel URL parsing
    private final class TunnelParseState: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private var resumed = false

        func tryResume() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if resumed { return false }
            resumed = true
            return true
        }

        func appendData(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(data)
        }

        func currentText() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return String(data: buffer, encoding: .utf8)
        }
    }

    // MARK: - Errors

    enum TunnelError: Error, Equatable, LocalizedError {
        case cloudflaredNotFound
        case urlParsingFailed
        case timeout
        case rateLimited
        case startupFailed(String)

        var errorDescription: String? {
            switch self {
            case .cloudflaredNotFound:
                return L10n("mobile.access.cloudflared.notFound")
            case .urlParsingFailed:
                return L10n("mobile.access.error.parseFailed")
            case .timeout:
                return L10n("mobile.access.error.timeout")
            case .rateLimited:
                return L10n("mobile.access.error.rateLimited")
            case .startupFailed(let message):
                return Self.userFacingStartupError(for: message)
            }
        }

        private static func userFacingStartupError(for message: String) -> String {
            let lowercased = message.lowercased()
            if lowercased.contains("lookup ") || lowercased.contains("no such host") {
                return L10n("mobile.access.error.dnsFailed")
            }
            if lowercased.contains("connection refused") {
                return L10n("mobile.access.error.localServerUnavailable")
            }
            return L10n("mobile.access.error.startupFailed", message)
        }
    }

    enum TunnelOutputResult: Equatable {
        case url(String)
        case rateLimited
        case startupFailed(String)

        var result: Result<String, TunnelError> {
            switch self {
            case .url(let url):
                return .success(url)
            case .rateLimited:
                return .failure(.rateLimited)
            case .startupFailed(let message):
                return .failure(.startupFailed(message))
            }
        }
    }
}
