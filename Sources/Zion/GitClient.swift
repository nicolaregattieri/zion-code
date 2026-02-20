import Foundation

private final class DataAccumulator: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func value() -> Data {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return snapshot
    }
}

enum GitClientError: LocalizedError {
    case repositoryNotSelected
    case commandFailed(command: String, message: String)

    var errorDescription: String? {
        switch self {
        case .repositoryNotSelected:
            return "Selecione um repositorio Git primeiro."
        case .commandFailed(let command, let message):
            return "Falha ao executar `\(command)`: \(message)"
        }
    }
}

struct GitCommandResult {
    let stdout: String
    let stderr: String
    let status: Int32
}

struct GitClient {
    func runWithStdin(args: [String], stdin: String, in repositoryURL: URL) throws -> GitCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = repositoryURL

        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutAccumulator = DataAccumulator()
        let stderrAccumulator = DataAccumulator()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stdoutAccumulator.append(chunk)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stderrAccumulator.append(chunk)
        }

        try process.run()

        if let inputData = stdin.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(inputData)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        stdoutAccumulator.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrAccumulator.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        let stdoutData = stdoutAccumulator.value()
        let stderrData = stderrAccumulator.value()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let command = (["git"] + args).joined(separator: " ")
            throw GitClientError.commandFailed(command: command, message: message)
        }

        return GitCommandResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
    }

    func run(args: [String], in repositoryURL: URL) throws -> GitCommandResult {
        let result = try runAllowingFailure(args: args, in: repositoryURL)
        if result.status != 0 {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let command = (["git"] + args).joined(separator: " ")
            throw GitClientError.commandFailed(command: command, message: message)
        }

        return result
    }

    func cloneWithProgress(
        remoteURL: String,
        destination: URL,
        onProgress: @escaping @Sendable (String) -> Void
    ) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "clone", "--progress", remoteURL, destination.path]
        process.currentDirectoryURL = destination.deletingLastPathComponent()

        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
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

        try process.run()
        return process
    }

    func runAllowingFailure(args: [String], in repositoryURL: URL) throws -> GitCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = repositoryURL

        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutAccumulator = DataAccumulator()
        let stderrAccumulator = DataAccumulator()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stdoutAccumulator.append(chunk)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stderrAccumulator.append(chunk)
        }

        try process.run()
        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        stdoutAccumulator.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrAccumulator.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        let stdoutData = stdoutAccumulator.value()
        let stderrData = stderrAccumulator.value()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return GitCommandResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
    }
}
