// BashTool.swift — Safe shell execution for the agentic loop.
// Enforces allowlists, always-blocked patterns, path traversal checks,
// CWD scoping, output truncation, and pre-execution recovery snapshots.

import Foundation
import CryptoKit

// MARK: - Output + Error Types

/// Result of a `BashTool.run` call.
struct BashOutput: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let truncated: Bool
}

/// Errors thrown by `BashTool.run`.
enum BashError: Error, Equatable {
    case blocked(reason: String)
    case timeout
    case pathTraversal(String)
    case workingDirInvalid
}

// MARK: - BashTool

/// Safe shell executor. Thread-safe Swift actor.
actor BashTool {

    static let shared = BashTool()

    // MARK: - Constants

    private static let outputCapBytes = 65_536 // 64 KB

    /// Commands allowed when tier == .workspaceWrite (first token match).
    private static let workspaceWriteAllowlist: Set<String> = [
        "git", "swift", "npm", "pnpm", "yarn", "cargo",
        "python", "python3", "node",
        "ls", "cat", "head", "tail", "grep", "find", "wc", "which"
    ]

    /// Commands that are read-only — no recovery snapshot needed.
    private static let readOnlyCommands: Set<String> = [
        "git", "ls", "cat", "head", "tail", "grep", "find", "wc", "which"
    ]

    // Read-only git subcommands (when first token is "git").
    private static let readOnlyGitSubcommands: Set<String> = [
        "status", "diff", "log", "show", "branch"
    ]

    // MARK: - Public API

    /// Execute a shell command safely.
    ///
    /// - Parameters:
    ///   - command: Raw shell command string.
    ///   - tier: Approval tier controlling which commands are allowed.
    ///   - repoURL: Repository root — CWD for the subprocess.
    ///   - timeoutSec: Kill process after this many seconds. Default 60.
    /// - Returns: `BashOutput` with stdout, stderr, exitCode, truncated flag.
    /// - Throws: `BashError` if the command is blocked, times out, or is unsafe.
    func run(
        command: String,
        tier: AgentApprovalTier,
        repoURL: URL,
        timeoutSec: Int = 60
    ) async throws -> BashOutput {
        // 1. Validate working directory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repoURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw BashError.workingDirInvalid
        }

        // 2. Always-blocked patterns (any tier including fullAccess)
        try Self.checkAlwaysBlocked(command: command)

        // 3. Parse first token
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let firstToken = trimmed.components(separatedBy: .whitespaces).first ?? ""

        // 4. Tier enforcement
        switch tier {
        case .readOnly:
            try Self.enforceReadOnly(command: trimmed, firstToken: firstToken)
        case .workspaceWrite:
            try Self.enforceWorkspaceWrite(firstToken: firstToken)
        case .fullAccess:
            break // Only always-blocked patterns apply
        }

        // 5. Path traversal check
        try Self.checkPathTraversal(command: trimmed, repoURL: repoURL)

        // 6. Recovery snapshot before non-readonly commands
        let needsSnapshot = !Self.isReadOnlyCommand(trimmed, firstToken: firstToken)
        if needsSnapshot && tier != .readOnly {
            await Self.createRecoverySnapshot(command: command, repoURL: repoURL)
        }

        // 7. Execute
        return try await Self.execute(command: command, repoURL: repoURL, timeoutSec: timeoutSec)
    }

    // MARK: - Tier Checks

    private static func enforceReadOnly(command: String, firstToken: String) throws {
        guard readOnlyCommands.contains(firstToken) else {
            throw BashError.blocked(reason: "readOnly tier rejects non-read command")
        }
        // For git, only read-only subcommands are allowed
        if firstToken == "git" {
            let tokens = command.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            let subcommand = tokens.dropFirst().first(where: { !$0.hasPrefix("-") }) ?? ""
            guard readOnlyGitSubcommands.contains(subcommand) else {
                throw BashError.blocked(reason: "readOnly tier rejects non-read git subcommand: \(subcommand)")
            }
        }
    }

    private static func enforceWorkspaceWrite(firstToken: String) throws {
        guard workspaceWriteAllowlist.contains(firstToken) else {
            throw BashError.blocked(reason: "not in workspaceWrite allowlist")
        }
    }

    // MARK: - Always-Blocked Patterns

    private static func checkAlwaysBlocked(command: String) throws {
        let lower = command.lowercased()

        let blockedPatterns: [(String) -> Bool] = [
            // rm -rf / variants
            { cmd in
                let normalized = cmd.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                return normalized.contains("rm -rf /") || normalized.contains("rm -rf /*")
            },
            // sudo
            { cmd in cmd.contains("sudo") },
            // curl|bash, curl|sh
            { cmd in
                (cmd.contains("curl") && (cmd.contains("| sh") || cmd.contains("|sh") ||
                    cmd.contains("| bash") || cmd.contains("|bash")))
            },
            // wget|bash, wget|sh
            { cmd in
                (cmd.contains("wget") && (cmd.contains("| sh") || cmd.contains("|sh") ||
                    cmd.contains("| bash") || cmd.contains("|bash")))
            },
            // chmod 777
            { cmd in cmd.contains("chmod 777") },
            // chown
            { cmd in
                let words = cmd.components(separatedBy: .whitespaces)
                return words.contains("chown")
            },
            // Redirections to sensitive paths or path traversal
            { cmd in
                Self.hasBlockedRedirection(cmd)
            }
        ]

        for check in blockedPatterns {
            if check(lower) {
                throw BashError.blocked(reason: "command matches always-blocked pattern")
            }
        }
    }

    private static func hasBlockedRedirection(_ lower: String) -> Bool {
        // Match > or >> followed by /etc/, /usr/, /System/, or paths with ..
        let pattern = #">{1,2}\s*(/etc/|/usr/|/System/|.*\.\.)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(lower.startIndex..., in: lower)
        return regex.firstMatch(in: lower, range: range) != nil
    }

    // MARK: - Path Traversal

    private static func checkPathTraversal(command: String, repoURL: URL) throws {
        let tokens = command.components(separatedBy: .whitespaces)
        for token in tokens {
            // Skip flags and non-path tokens
            if token.hasPrefix("-") || token.hasPrefix("--") { continue }
            guard token.hasPrefix("/") || token.hasPrefix("~") || token.contains("/") else { continue }

            // Expand tilde
            let expanded = token.hasPrefix("~") ? NSString(string: token).expandingTildeInPath : token

            // Resolve to canonical path
            let resolved = URL(fileURLWithPath: expanded, relativeTo: repoURL).standardized

            // Check if within repoURL
            let repoResolved = repoURL.standardized
            let resolvedPath = resolved.path
            let repoPath = repoResolved.path

            if !resolvedPath.hasPrefix(repoPath + "/") && resolvedPath != repoPath {
                throw BashError.pathTraversal(token)
            }
        }
    }

    // MARK: - Read-only classification

    private static func isReadOnlyCommand(_ command: String, firstToken: String) -> Bool {
        guard readOnlyCommands.contains(firstToken) else { return false }
        if firstToken == "git" {
            let tokens = command.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            let subcommand = tokens.dropFirst().first(where: { !$0.hasPrefix("-") }) ?? ""
            return readOnlyGitSubcommands.contains(subcommand)
        }
        return true
    }

    // MARK: - Recovery Snapshot

    private static func createRecoverySnapshot(command: String, repoURL: URL) async {
        let shortSha = shortHash(of: command)
        let stashMessage = "zion-pre-bash-\(shortSha)"

        // git stash create
        let createProcess = Process()
        createProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        createProcess.arguments = ["stash", "create"]
        createProcess.currentDirectoryURL = repoURL
        let createPipe = Pipe()
        createProcess.standardOutput = createPipe
        createProcess.standardError = Pipe()

        guard (try? createProcess.run()) != nil else { return }
        createProcess.waitUntilExit()

        let hashData = createPipe.fileHandleForReading.readDataToEndOfFile()
        let hashStr = String(data: hashData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !hashStr.isEmpty else { return }

        // git stash store -m "zion-pre-bash-<sha>" <hash>
        let storeProcess = Process()
        storeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        storeProcess.arguments = ["stash", "store", "-m", stashMessage, hashStr]
        storeProcess.currentDirectoryURL = repoURL
        storeProcess.standardOutput = Pipe()
        storeProcess.standardError = Pipe()
        try? storeProcess.run()
        storeProcess.waitUntilExit()
    }

    private static func shortHash(of command: String) -> String {
        let data = Data(command.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Process Execution

    /// Shared mutable state for process execution.
    /// Uses @unchecked Sendable + NSLock to satisfy Swift 6 strict concurrency.
    private final class ProcessState: @unchecked Sendable {
        let lock = NSLock()
        var stdoutData = Data()
        var stderrData = Data()
        var didTimeout = false
        var finished = false
    }

    private static func execute(command: String, repoURL: URL, timeoutSec: Int) async throws -> BashOutput {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = repoURL

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let state = ProcessState()

            // Timer for timeout
            let timerSource = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            timerSource.schedule(deadline: .now() + .seconds(timeoutSec))
            timerSource.setEventHandler {
                state.lock.withLock {
                    guard !state.finished else { return }
                    state.didTimeout = true
                    state.finished = true
                }
                process.terminate()
            }
            timerSource.resume()

            process.terminationHandler = { proc in
                timerSource.cancel()

                var outCopy: Data = Data()
                var errCopy: Data = Data()
                var timedOut: Bool = false
                state.lock.withLock {
                    if !state.finished { state.finished = true }
                    outCopy = state.stdoutData
                    errCopy = state.stderrData
                    timedOut = state.didTimeout
                }

                let (stdoutStr, stdoutTruncated) = Self.truncate(outCopy)
                let (stderrStr, stderrTruncated) = Self.truncate(errCopy)

                if timedOut {
                    continuation.resume(throwing: BashError.timeout)
                } else {
                    continuation.resume(returning: BashOutput(
                        stdout: stdoutStr,
                        stderr: stderrStr,
                        exitCode: proc.terminationStatus,
                        truncated: stdoutTruncated || stderrTruncated
                    ))
                }
            }

            // Read data asynchronously
            stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
                let chunk = fh.availableData
                state.lock.withLock { state.stdoutData.append(chunk) }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { fh in
                let chunk = fh.availableData
                state.lock.withLock { state.stderrData.append(chunk) }
            }

            do {
                try process.run()
            } catch {
                timerSource.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    private static func truncate(_ data: Data) -> (String, Bool) {
        if data.count <= outputCapBytes {
            return (String(data: data, encoding: .utf8) ?? "", false)
        }
        let sliced = data.prefix(outputCapBytes)
        let extra = data.count - outputCapBytes
        let base = String(data: sliced, encoding: .utf8) ?? ""
        return (base + "\n... [TRUNCATED \(extra) more bytes]", true)
    }
}
