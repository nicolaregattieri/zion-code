import Foundation

actor CloudflareTunnelManager {
    private var process: Process?
    private var tunnelURL: String?

    var currentURL: String? { tunnelURL }
    var isRunning: Bool { process?.isRunning ?? false }

    // MARK: - Lifecycle

    func start(localPort: UInt16) async throws -> String {
        if let process, process.isRunning {
            process.terminate()
        }

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
        }
        process = nil
        tunnelURL = nil
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
        let urlPattern = try NSRegularExpression(pattern: #"https://[a-z0-9-]+\.trycloudflare\.com"#)
        let handle = pipe.fileHandleForReading

        return try await withCheckedThrowingContinuation { continuation in
            let state = TunnelParseState()

            handle.readabilityHandler = { [urlPattern] fileHandle in
                let newData = fileHandle.availableData
                guard !newData.isEmpty else {
                    if state.tryResume() {
                        continuation.resume(throwing: TunnelError.urlParsingFailed)
                    }
                    return
                }

                state.appendData(newData)
                guard let text = state.currentText() else { return }

                let range = NSRange(text.startIndex..., in: text)
                if let match = urlPattern.firstMatch(in: text, range: range),
                   let matchRange = Range(match.range, in: text) {
                    let url = String(text[matchRange])
                    if state.tryResume() {
                        fileHandle.readabilityHandler = nil
                        continuation.resume(returning: url)
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

    enum TunnelError: Error, LocalizedError {
        case cloudflaredNotFound
        case urlParsingFailed
        case timeout

        var errorDescription: String? {
            switch self {
            case .cloudflaredNotFound:
                return L10n("mobile.access.cloudflared.notFound")
            case .urlParsingFailed:
                return "Failed to parse tunnel URL from cloudflared output"
            case .timeout:
                return "Timed out waiting for cloudflared tunnel URL"
            }
        }
    }
}
