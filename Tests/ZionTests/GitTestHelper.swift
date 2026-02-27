import Foundation

enum GitTestHelper {
    static func makeTempRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zion-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try shell("git", "init", in: dir)
        try shell("git", "config", "user.email", "test@zion.dev", in: dir)
        try shell("git", "config", "user.name", "Test User", in: dir)

        try createFile(name: "README.md", content: "# Test Repo\n", in: dir)
        try commitAll(message: "Initial commit", in: dir)

        return dir
    }

    static func makeTempRepoWithBranches() throws -> URL {
        let dir = try makeTempRepo()

        try shell("git", "checkout", "-b", "feature/login", in: dir)
        try createFile(name: "login.swift", content: "// login\n", in: dir)
        try commitAll(message: "Add login feature", in: dir)

        try shell("git", "checkout", "-b", "feature/signup", in: dir)
        try createFile(name: "signup.swift", content: "// signup\n", in: dir)
        try commitAll(message: "Add signup feature", in: dir)

        // Return to main branch
        let mainBranch = try detectMainBranch(in: dir)
        try shell("git", "checkout", mainBranch, in: dir)

        return dir
    }

    static func makeTempRepoWithConflict() throws -> URL {
        let dir = try makeTempRepo()
        let mainBranch = try detectMainBranch(in: dir)

        // Create conflicting changes on two branches
        try shell("git", "checkout", "-b", "conflict-branch", in: dir)
        try createFile(name: "shared.txt", content: "branch content\n", in: dir)
        try commitAll(message: "Branch change", in: dir)

        try shell("git", "checkout", mainBranch, in: dir)
        try createFile(name: "shared.txt", content: "main content\n", in: dir)
        try commitAll(message: "Main change", in: dir)

        // Attempt merge (will fail with conflict)
        _ = try? shell("git", "merge", "conflict-branch", in: dir)

        return dir
    }

    static func createFile(name: String, content: String, in directory: URL) throws {
        let fileURL = directory.appendingPathComponent(name)
        // Create intermediate directories if needed
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func commitAll(message: String, in directory: URL) throws {
        try shell("git", "add", "-A", in: directory)
        try shell("git", "commit", "-m", message, in: directory)
    }

    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func detectMainBranch(in directory: URL) throws -> String {
        let result = try shellOutput("git", "branch", "--show-current", in: directory)
        if !result.isEmpty { return result }
        // Fallback: check if main or master exists
        let branches = try shellOutput("git", "branch", "--list", in: directory)
        if branches.contains("main") { return "main" }
        return "master"
    }

    @discardableResult
    private static func shell(_ args: String..., in directory: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.environment = [
            "LC_ALL": "C",
            "LANG": "C",
            "GIT_TERMINAL_PROMPT": "0",
            "HOME": ProcessInfo.processInfo.environment["HOME"] ?? "/tmp"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "GitTestHelper", code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: "Command failed: \(args.joined(separator: " "))\n\(output)"])
        }
        return process
    }

    private static func shellOutput(_ args: String..., in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.environment = [
            "LC_ALL": "C",
            "LANG": "C",
            "GIT_TERMINAL_PROMPT": "0",
            "HOME": ProcessInfo.processInfo.environment["HOME"] ?? "/tmp"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
