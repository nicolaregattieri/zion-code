import Foundation

// MARK: - Public types

struct ToolCall: @unchecked Sendable {
    let id: String
    let name: String
    let arguments: [String: Any]
}

struct ToolResult: Sendable {
    let toolCallID: String
    let content: String
    let isError: Bool
}

enum HarnessError: Error {
    case readBeforeEdit
    case fileExists
    case outsideRepo
    case bashNotAllowed
    case editsDisabled
    case invalidEdit
    case textNotFound(snippet: String)
    case fileNotFound
    case unknownTool(String)
}

// MARK: - FileMutationQueue

private actor FileMutationQueue {
    private var pending: [String: Task<Void, Never>] = [:]

    func enqueue<T: Sendable>(path: String, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        // Chain onto any existing task for this path to serialize writes
        let previousTask = pending[path]
        let resultHolder = ResultHolder<T>()

        let newTask = Task<Void, Never> {
            // Wait for any prior task on this path
            await previousTask?.value

            do {
                let result = try await operation()
                await resultHolder.set(.success(result))
            } catch {
                await resultHolder.set(.failure(error))
            }
        }

        pending[path] = newTask
        await newTask.value

        // Clean up finished tasks
        if pending[path]?.isCancelled == false {
            pending.removeValue(forKey: path)
        }

        return try await resultHolder.get()
    }
}

private actor ResultHolder<T: Sendable> {
    private var result: Result<T, Error>?

    func set(_ result: Result<T, Error>) {
        self.result = result
    }

    func get() throws -> T {
        switch result! {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

// MARK: - ZionHarness

actor ZionHarness {
    let worker: RepositoryWorker
    let repoURL: URL
    private var sessionReadFiles: Set<URL> = []
    private let mutationQueue: FileMutationQueue

    // Caps
    private static let readLineCap = 8000
    private static let readByteCap = 1_048_576      // 1 MB
    private static let bashLineCap = 100
    private static let bashByteCap = 1_048_576       // 1 MB

    private static let bashAllowlist = try! NSRegularExpression(
        pattern: "^(git|swift|ls|pwd|cat|echo)\\s",
        options: []
    )

    init(worker: RepositoryWorker, repoURL: URL) {
        self.worker = worker
        self.repoURL = repoURL
        self.mutationQueue = FileMutationQueue()
    }

    func execute(toolCall: ToolCall) async -> ToolResult {
        do {
            let content = try await dispatch(toolCall: toolCall)
            return ToolResult(toolCallID: toolCall.id, content: content, isError: false)
        } catch let error as HarnessError {
            return ToolResult(toolCallID: toolCall.id, content: harnessErrorMessage(error), isError: true)
        } catch {
            return ToolResult(toolCallID: toolCall.id, content: error.localizedDescription, isError: true)
        }
    }

    func resetSession() {
        sessionReadFiles.removeAll()
    }

    // MARK: - Path safety

    func validatePath(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path, relativeTo: repoURL).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath()
        let repoResolved = repoURL.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(repoResolved.path + "/") || resolved.path == repoResolved.path else {
            throw HarnessError.outsideRepo
        }
        return resolved
    }

    // MARK: - Dispatch

    private func dispatch(toolCall: ToolCall) async throws -> String {
        switch toolCall.name {
        case "read":   return try await handleRead(args: toolCall.arguments)
        case "edit":   return try await handleEdit(args: toolCall.arguments)
        case "write":  return try await handleWrite(args: toolCall.arguments)
        case "bash":   return try await handleBash(args: toolCall.arguments)
        case "grep":   return try await handleGrep(args: toolCall.arguments)
        case "glob":   return try await handleGlob(args: toolCall.arguments)
        default:       throw HarnessError.unknownTool(toolCall.name)
        }
    }

    // MARK: - read

    private func handleRead(args: [String: Any]) async throws -> String {
        guard let path = args["path"] as? String else {
            throw HarnessError.fileNotFound
        }
        let url = try validatePath(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw HarnessError.fileNotFound
        }

        // Mark as read for edit permission
        sessionReadFiles.insert(url)

        let data = try Data(contentsOf: url)
        let raw = String(data: data.prefix(Self.readByteCap), encoding: .utf8) ?? ""
        var lines = raw.components(separatedBy: "\n")

        let offset = (args["offset"] as? Int ?? 1) - 1   // convert to 0-based
        let limit  = args["limit"]  as? Int ?? Self.readLineCap

        let start = max(0, offset)
        let end   = min(lines.count, start + limit)
        lines = Array(lines[start..<end])

        // Apply line cap
        if lines.count > Self.readLineCap {
            lines = Array(lines.prefix(Self.readLineCap))
        }

        return lines.enumerated().map { "\($0.offset + start + 1)\t\($0.element)" }.joined(separator: "\n")
    }

    // MARK: - edit

    private func handleEdit(args: [String: Any]) async throws -> String {
        guard let path = args["path"] as? String else { throw HarnessError.fileNotFound }

        let allowEdits = UserDefaults.standard.object(forKey: "chat.allowEdits") as? Bool ?? false
        guard allowEdits else { throw HarnessError.editsDisabled }

        let url = try validatePath(path)

        // Read-before-edit enforcement
        guard sessionReadFiles.contains(url) else { throw HarnessError.readBeforeEdit }

        guard let editsRaw = args["edits"] as? [[String: Any]], !editsRaw.isEmpty else {
            throw HarnessError.invalidEdit
        }

        // Convert to typed pairs before crossing Sendable boundary
        struct EditPair: Sendable { let old: String; let new: String }
        var editPairsMut: [EditPair] = []
        for edit in editsRaw {
            guard let oldText = edit["oldText"] as? String else { throw HarnessError.invalidEdit }
            guard let newText = edit["newText"] as? String else { throw HarnessError.invalidEdit }
            guard !oldText.isEmpty else { throw HarnessError.invalidEdit }
            editPairsMut.append(EditPair(old: oldText, new: newText))
        }
        let editPairs = editPairsMut

        return try await mutationQueue.enqueue(path: url.path) {
            var content = try String(contentsOf: url, encoding: .utf8)

            for pair in editPairs {
                guard let range = content.range(of: pair.old) else {
                    let snippet = String(content.prefix(200))
                    throw HarnessError.textNotFound(snippet: snippet)
                }
                content = content.replacingCharacters(in: range, with: pair.new)
            }

            try content.write(to: url, atomically: true, encoding: .utf8)
            return "ok"
        }
    }

    // MARK: - write

    private func handleWrite(args: [String: Any]) async throws -> String {
        guard let path    = args["path"]    as? String else { throw HarnessError.fileNotFound }
        guard let content = args["content"] as? String else { throw HarnessError.invalidEdit }

        let allowEdits = UserDefaults.standard.object(forKey: "chat.allowEdits") as? Bool ?? false
        guard allowEdits else { throw HarnessError.editsDisabled }

        let url = try validatePath(path)

        // prefer-edit-over-create: reject if file already exists
        if FileManager.default.fileExists(atPath: url.path) {
            throw HarnessError.fileExists
        }

        return try await mutationQueue.enqueue(path: url.path) {
            // Create parent directories if needed
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "ok"
        }
    }

    // MARK: - bash

    private func handleBash(args: [String: Any]) async throws -> String {
        guard let command = args["command"] as? String else { throw HarnessError.bashNotAllowed }

        // Allowlist check
        let range = NSRange(command.startIndex..., in: command)
        guard Self.bashAllowlist.firstMatch(in: command, range: range) != nil else {
            throw HarnessError.bashNotAllowed
        }

        let timeout = args["timeout"] as? Int ?? 30_000

        return try await runBash(command: command, in: repoURL, timeoutMs: timeout)
    }

    // MARK: - grep

    private func handleGrep(args: [String: Any]) async throws -> String {
        guard let pattern = args["pattern"] as? String else { throw HarnessError.invalidEdit }

        var grepArgs = ["grep", "-r", "-n"]
        if args["ignoreCase"] as? Bool == true { grepArgs.append("-i") }
        grepArgs.append(pattern)

        if let path = args["path"] as? String {
            let url = try validatePath(path)
            grepArgs.append(url.path)
        } else {
            grepArgs.append(repoURL.path)
        }

        if let glob = args["glob"] as? String {
            grepArgs += ["--include", glob]
        }

        return try await runBash(command: grepArgs.joined(separator: " "), in: repoURL, timeoutMs: 30_000, skipAllowlist: true)
    }

    // MARK: - glob

    private func handleGlob(args: [String: Any]) async throws -> String {
        guard let pattern = args["pattern"] as? String else { throw HarnessError.invalidEdit }

        let base: URL
        if let path = args["path"] as? String {
            base = try validatePath(path)
        } else {
            base = repoURL
        }

        let findCommand = "find \(base.path) -path \"\(base.path)/\(pattern)\" -not -path '*/\\.git/*'"
        return try await runBash(command: findCommand, in: repoURL, timeoutMs: 30_000, skipAllowlist: true)
    }

    // MARK: - Bash runner

    private func runBash(command: String, in directory: URL, timeoutMs: Int, skipAllowlist: Bool = false) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = directory

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError  = errPipe

            let deadline = DispatchTime.now() + .milliseconds(timeoutMs)

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if process.isRunning { process.terminate() }
            }

            process.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

            var combined = ""
            if let out = String(data: outData, encoding: .utf8), !out.isEmpty { combined += out }
            if let err = String(data: errData, encoding: .utf8), !err.isEmpty { combined += err }

            // Apply caps
            let bytesCapped = combined.prefix(Self.bashByteCap).description
            var lines = bytesCapped.components(separatedBy: "\n")
            if lines.count > Self.bashLineCap {
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("zion-bash-\(UUID().uuidString).txt")
                try? bytesCapped.write(to: tmpURL, atomically: true, encoding: .utf8)
                lines = Array(lines.prefix(Self.bashLineCap))
                lines.append("[output truncated — full output at \(tmpURL.path)]")
            }

            continuation.resume(returning: lines.joined(separator: "\n"))
        }
    }

    // MARK: - Error messages

    private func harnessErrorMessage(_ error: HarnessError) -> String {
        switch error {
        case .readBeforeEdit:
            return "readBeforeEdit: file must be read before it can be edited"
        case .fileExists:
            return "fileExists: file already exists — use edit to modify existing files"
        case .outsideRepo:
            return "outsideRepo: path is outside repository root"
        case .bashNotAllowed:
            return "bashNotAllowed: command is not in the allowed list (git, swift, ls, pwd, cat, echo)"
        case .editsDisabled:
            return "editsDisabled: file editing is not enabled for this session"
        case .invalidEdit:
            return "invalidEdit: edit parameters are invalid or oldText is empty"
        case .textNotFound(let snippet):
            return "textNotFound: oldText not found in file. File begins with: \(snippet)"
        case .fileNotFound:
            return "fileNotFound: path parameter missing or file does not exist"
        case .unknownTool(let name):
            return "unknownTool: \(name)"
        }
    }
}
