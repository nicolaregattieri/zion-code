import Foundation

/// Returns a copy of `environment` with `GIT_OPTIONAL_LOCKS=0` merged in when `args`
/// describes a `git status` invocation, and returns `environment` unchanged for all other
/// subcommands.  Leading `-C <path>` and `-c <key=value>` flag pairs are skipped before
/// inspecting the first positional token, matching git's own flag ordering rules.
///
/// Made `internal` (not `private`) so `@testable import Zion` can call it directly from
/// the test target (Task 4).
func applyStatusEnvOverride(args: [String], environment: [String: String]) -> [String: String] {
    var index = 0
    while index < args.count {
        let token = args[index]
        if token == "-C" || token == "-c" {
            // Each flag consumes itself plus one value token.
            index += 2
        } else if token.hasPrefix("-") {
            // Other single-token flags (e.g. --no-pager).
            index += 1
        } else {
            // First non-flag token is the git subcommand.
            if token == "status" {
                var updated = environment
                updated["GIT_OPTIONAL_LOCKS"] = "0"
                return updated
            }
            return environment
        }
    }
    return environment
}

extension RepositoryWorker {

    func runAction(
        args: [String],
        in repositoryURL: URL,
        mode: GitExecutionMode = .normal
    ) throws -> String {
        let result = try git.run(args: args, in: repositoryURL, mode: mode)
        return result.stdout.clean.isEmpty ? result.stderr.clean : result.stdout.clean
    }

    func runActionAllowingFailure(
        args: [String],
        in repositoryURL: URL,
        mode: GitExecutionMode = .normal
    ) throws -> (output: String, status: Int32) {
        let result = try git.runAllowingFailure(args: args, in: repositoryURL, mode: mode)
        let output = result.stdout.clean.isEmpty ? result.stderr.clean : result.stdout.clean
        return (output, result.status)
    }

    func runActionWithStdin(
        args: [String],
        stdin: String,
        in repositoryURL: URL,
        mode: GitExecutionMode = .normal
    ) throws -> String {
        let result = try git.runWithStdin(args: args, stdin: stdin, in: repositoryURL, mode: mode)
        return result.stdout.clean.isEmpty ? result.stderr.clean : result.stdout.clean
    }

    nonisolated func cloneRepository(
        remoteURL: String,
        destination: URL,
        onProgress: @escaping @Sendable (String) -> Void,
        mode: GitExecutionMode = .normal
    ) throws -> Process {
        let client = GitClient()
        return try client.cloneWithProgress(remoteURL: remoteURL, destination: destination, onProgress: onProgress, mode: mode)
    }

    @available(*, unavailable, message: "runShellStream is disabled for security. Use runProcessStream(executable:args:in:onOutput:).")
    nonisolated func runShellStream(command: String, in repositoryURL: URL, onOutput: @escaping @Sendable (String) -> Void) throws {
        throw GitClientError.commandFailed(command: command, message: "runShellStream is unavailable for security reasons.")
    }

    nonisolated func runProcessStream(
        executable: String,
        args: [String],
        in repositoryURL: URL,
        onOutput: @escaping @Sendable (String) -> Void
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = repositoryURL
        let baseEnvironment = ProcessInfo.processInfo.environment
        process.environment = applyStatusEnvOverride(args: args, environment: baseEnvironment)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                onOutput(str)
            }
        }

        try process.run()
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
    }
}
