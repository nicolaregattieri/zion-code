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

        // 2b. Reject shell metacharacters that defeat the first-token allowlist.
        // Without this, `git status; rm -rf ~` would pass the first-token gate
        // because the first token is `git`, then `/bin/sh -c` would happily run
        // both halves. Same for `&&`, `||`, `|`, command substitution, env-var
        // expansion that escapes the repo via $HOME, etc.
        try Self.checkShellInjection(command: command)

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

    // Pre-release security hotfix (P14.5): refuse shell metacharacters that bypass
    // the first-token allowlist. The command is executed via `/bin/sh -c`, so any
    // unstripped chain (`;`, `&&`, `||`, `|`), command substitution (`$()`, backticks),
    // env-var escape (`$HOME`, `$PATH`), or redirection (`>`, `<`, `>>`) reaches the
    // shell unchecked. Reject those upfront with a clear error so users hit a wall
    // before any subprocess spawns.
    private static let bannedShellMetachars: [String] = [
        ";", "&&", "||", "|", "`", "$(", "${", ">>", "<", "$HOME", "$(",
        "&", ">",
        // Newlines / carriage returns are command separators inside `/bin/sh -c`,
        // so smuggling them past the first-token allowlist would let a single
        // payload run an arbitrary second command. Backslash makes escape
        // chaining trivial — reject upfront.
        "\n", "\r", "\\"
    ]

    private static func checkShellInjection(command: String) throws {
        // Allow `>` only when used inside arguments that don't start a redirection.
        // The conservative path here is to refuse any of the listed substrings.
        for pattern in bannedShellMetachars {
            if command.contains(pattern) {
                let label: String
                switch pattern {
                case "\n": label = "\\n"
                case "\r": label = "\\r"
                default:   label = pattern
                }
                throw BashError.blocked(reason: "shell metacharacter rejected (`\(label)`)")
            }
        }
        // Reject `$variable` style env expansion entirely (would escape repoURL via $HOME etc.)
        if command.range(of: #"\$[A-Z_]"#, options: .regularExpression) != nil {
            throw BashError.blocked(reason: "environment-variable expansion rejected")
        }
        // Reject leading tilde paths beyond the very first character
        if command.contains(" ~") || command.contains("=~") {
            throw BashError.blocked(reason: "tilde path-expansion rejected")
        }
    }

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
        /// Set once the continuation has been resumed, by exit or by timeout.
        var resumed = false

        /// Returns true only for the first caller.
        func claimResume() -> Bool {
            lock.withLock {
                if resumed { return false }
                resumed = true
                return true
            }
        }
    }

    /// Runs the command and resumes exactly once: when the process exits,
    /// or when the timeout fires, whichever comes first.
    ///
    /// Uses the same pattern as `GitClient.readPipesUntilExit`: both pipes
    /// are read to EOF on background threads while `waitUntilExit()` runs on
    /// a dedicated queue. It no longer depends on `terminationHandler`, and
    /// the timeout path resumes the caller itself after `terminate()`, so a
    /// missed exit can never leave the caller suspended forever (that hang
    /// stalled CI for an hour on `git status` with a 10 s timeout).
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

            do {
                try process.run()
            } catch {
                if state.claimResume() { continuation.resume(throwing: error) }
                return
            }

            // Read both pipes to EOF concurrently so a full pipe buffer can't
            // block the child.
            let readers = DispatchGroup()
            readers.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                state.lock.withLock { state.stdoutData = data }
                readers.leave()
            }
            readers.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                state.lock.withLock { state.stderrData = data }
                readers.leave()
            }

            // Timeout: terminate and resume right away.
            let timeoutItem = DispatchWorkItem {
                if process.isRunning { process.terminate() }
                if state.claimResume() { continuation.resume(throwing: BashError.timeout) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSec), execute: timeoutItem)

            // Exit: wait on a dedicated queue, then collect the output.
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                // The timeout item may still fire later; it finds the process
                // gone and the continuation already claimed, so it does nothing.
                // A grandchild that inherited the pipes could keep them open
                // after the shell exits, so don't wait on the readers forever.
                _ = readers.wait(timeout: .now() + 2)

                var outCopy = Data()
                var errCopy = Data()
                state.lock.withLock {
                    outCopy = state.stdoutData
                    errCopy = state.stderrData
                }

                guard state.claimResume() else { return }
                let (stdoutStr, stdoutTruncated) = Self.truncate(outCopy)
                let (stderrStr, stderrTruncated) = Self.truncate(errCopy)
                continuation.resume(returning: BashOutput(
                    stdout: stdoutStr,
                    stderr: stderrStr,
                    exitCode: process.terminationStatus,
                    truncated: stdoutTruncated || stderrTruncated
                ))
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
