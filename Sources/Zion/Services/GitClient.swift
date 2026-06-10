import Foundation

private final class SendableBox: @unchecked Sendable {
    var data = Data()
}

enum GitClientError: LocalizedError, Equatable {
    case repositoryNotSelected
    case notAGitRepository
    case commandFailed(command: String, message: String)

    var errorDescription: String? {
        switch self {
        case .repositoryNotSelected:
            return L10n("Selecione um repositorio Git primeiro.")
        case .notAGitRepository:
            return L10n("error.notAGitRepository")
        case .commandFailed(let command, let message):
            return L10n("gitError.commandFailed", command, message)
        }
    }
}

/// Returns true when `stderr` represents git's `fatal: not a git repository` error.
/// Case-insensitive substring match so variants like the full
/// `fatal: not a git repository (or any parent up to mount point ...)` still match.
func isNotAGitRepoStderr(_ stderr: String) -> Bool {
    stderr.lowercased().contains("fatal: not a git repository")
}

struct GitCommandResult {
    let stdout: String
    let stderr: String
    let status: Int32
}

struct GitCredentialInput: Sendable {
    let username: String?
    let secret: String
}

enum GitExecutionMode: Sendable {
    case normal
    case withCredential(GitCredentialInput)
}

struct GitClient: Sendable {
    func runWithStdin(
        args: [String],
        stdin: String,
        in repositoryURL: URL,
        mode: GitExecutionMode = .normal
    ) throws -> GitCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = repositoryURL

        let environmentSetup = try prepareEnvironment(for: mode)
        defer { cleanupAskPassScript(at: environmentSetup.askPassScriptURL) }
        let environment = environmentSetup.environment
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        if let inputData = stdin.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(inputData)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        let (stdoutData, stderrData) = readPipesUntilExit(process: process, stdout: stdoutPipe, stderr: stderrPipe)

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            if isNotAGitRepoStderr(stderr) {
                throw GitClientError.notAGitRepository
            }
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let command = commandSummary(for: args)
            throw GitClientError.commandFailed(command: command, message: message)
        }

        return GitCommandResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
    }

    func run(
        args: [String],
        in repositoryURL: URL,
        mode: GitExecutionMode = .normal
    ) throws -> GitCommandResult {
        let result = try runAllowingFailure(args: args, in: repositoryURL, mode: mode)
        if result.status != 0 {
            if isNotAGitRepoStderr(result.stderr) {
                throw GitClientError.notAGitRepository
            }
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let command = commandSummary(for: args)
            throw GitClientError.commandFailed(command: command, message: message)
        }

        return result
    }

    func cloneWithProgress(
        remoteURL: String,
        destination: URL,
        onProgress: @escaping @Sendable (String) -> Void,
        mode: GitExecutionMode = .normal
    ) throws -> Process {
        let trimmedURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              !trimmedURL.hasPrefix("-"),
              !trimmedURL.lowercased().hasPrefix("ext::"),
              !trimmedURL.lowercased().hasPrefix("fd::") else {
            throw GitClientError.commandFailed(command: "clone", message: "Invalid or unsafe remote URL")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "clone", "--progress", "--", trimmedURL, destination.path]
        process.currentDirectoryURL = destination.deletingLastPathComponent()

        let environmentSetup = try prepareEnvironment(for: mode)
        let environment = environmentSetup.environment
        process.environment = environment

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe() // discard stdout

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                onProgress(str)
            }
        }

        if let askPassScriptURL = environmentSetup.askPassScriptURL {
            process.terminationHandler = { _ in
                try? FileManager.default.removeItem(at: askPassScriptURL)
            }
        }

        do {
            try process.run()
        } catch {
            cleanupAskPassScript(at: environmentSetup.askPassScriptURL)
            throw error
        }
        return process
    }

    func runAllowingFailure(
        args: [String],
        in repositoryURL: URL,
        mode: GitExecutionMode = .normal
    ) throws -> GitCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        // Network-touching subcommands hang forever when the remote stalls
        // (slow SSH handshake, dropped HTTP connection). Prepend tight low-speed
        // gates and bound the SSH connect handshake so the process exits with
        // an error instead of blocking the worker queue.
        let networkSub = Self.networkSubcommand(in: args)
        var finalArgs: [String] = ["git"]
        if networkSub != nil {
            finalArgs += [
                "-c", "http.lowSpeedLimit=1000",
                "-c", "http.lowSpeedTime=\(Constants.Timing.networkLowSpeedTimeSeconds)"
            ]
        }
        finalArgs += args
        process.arguments = finalArgs
        process.currentDirectoryURL = repositoryURL

        let environmentSetup = try prepareEnvironment(for: mode)
        defer { cleanupAskPassScript(at: environmentSetup.askPassScriptURL) }
        var environment = environmentSetup.environment
        if networkSub != nil, environment["GIT_SSH_COMMAND"] == nil {
            environment["GIT_SSH_COMMAND"] = "ssh -o ConnectTimeout=\(Constants.Timing.sshConnectTimeoutSeconds) -o ServerAliveInterval=15 -o ServerAliveCountMax=3"
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Hard wall-clock cap for network commands. If git still hasn't
        // returned (the low-speed gate failed to trip, e.g. proxy buffered
        // bytes trickling under threshold), terminate the process so the
        // worker queue can move on instead of the busy watchdog clearing the
        // UI flag while the orphan keeps running.
        var timeoutItem: DispatchWorkItem?
        if networkSub != nil {
            let item = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + .seconds(Constants.Timing.networkCommandTimeoutSeconds),
                execute: item
            )
            timeoutItem = item
        }

        let (stdoutData, stderrData) = readPipesUntilExit(process: process, stdout: stdoutPipe, stderr: stderrPipe)
        timeoutItem?.cancel()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return GitCommandResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
    }

    /// First positional token after option flags. Network-aware so we can
    /// special-case timeouts only for `fetch`/`pull`/`push`/`clone`/`ls-remote`
    /// — other subcommands (status, log, diff) must not pay the SSH/HTTP gate
    /// overhead and must not be killed at 45s.
    private static let networkSubcommands: Set<String> = ["fetch", "pull", "push", "clone", "ls-remote"]

    private static func networkSubcommand(in args: [String]) -> String? {
        var index = 0
        while index < args.count {
            let token = args[index]
            if token == "-C" || token == "-c" {
                index += 2
                continue
            }
            if token.hasPrefix("-") {
                index += 1
                continue
            }
            return networkSubcommands.contains(token) ? token : nil
        }
        return nil
    }

    /// Reads stdout and stderr pipes concurrently on background threads while waiting for process exit.
    /// Uses readDataToEndOfFile() instead of readabilityHandler to avoid GCD dispatch source overhead
    /// (each readabilityHandler creates an fd_monitoring queue that fires fstat/read on every data chunk).
    private func readPipesUntilExit(process: Process, stdout: Pipe, stderr: Pipe) -> (stdout: Data, stderr: Data) {
        let stdoutBox = SendableBox()
        let stderrBox = SendableBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBox.data = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        process.waitUntilExit()
        group.wait()
        return (stdoutBox.data, stderrBox.data)
    }

    private func commandSummary(for args: [String]) -> String {
        let subcommand = args.first ?? "command"
        return "git \(subcommand) [args=\(args.count)]"
    }

    private func prepareEnvironment(for mode: GitExecutionMode) throws -> (environment: [String: String], askPassScriptURL: URL?) {
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        environment["GIT_TERMINAL_PROMPT"] = "0"

        switch mode {
        case .normal:
            return (environment, nil)
        case .withCredential(let credential):
            let scriptURL = ZionTemp.directory
                .appendingPathComponent("zion-git-askpass-\(UUID().uuidString).sh")

            let script = """
            #!/bin/sh
            prompt="$1"
            case "$prompt" in
              *sername*|*USERNAME*) printf '%s\\n' "${ZION_GIT_USERNAME}" ;;
              *assword*|*PASSWORD*) printf '%s\\n' "${ZION_GIT_SECRET}" ;;
              *) printf '\\n' ;;
            esac
            """

            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            environment["GIT_ASKPASS"] = scriptURL.path
            environment["SSH_ASKPASS"] = scriptURL.path
            environment["GIT_ASKPASS_REQUIRE"] = "force"
            environment["ZION_GIT_USERNAME"] = credential.username ?? ""
            environment["ZION_GIT_SECRET"] = credential.secret

            return (environment, scriptURL)
        }
    }

    private func cleanupAskPassScript(at scriptURL: URL?) {
        guard let scriptURL else { return }
        try? FileManager.default.removeItem(at: scriptURL)
    }
}
