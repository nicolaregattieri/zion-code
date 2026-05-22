// StashTools.swift — zion_stash_list and zion_stash_apply tools

import Foundation

// MARK: - zion_stash_list

struct StashListTool: Tool {
    let repoURL: URL

    var name: String { "zion_stash_list" }
    var description: String { "List all stash entries in the repository." }

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([:]),
            "required": .array([])
        ]
    }

    func call(args: [String: JSONValue]) throws -> JSONValue {
        // format: stash@{N}|<message>|<iso-date>
        let raw = try gitWithStderr(
            args: ["stash", "list", "--format=%gd|%gs|%ai"],
            repoURL: repoURL
        ).stdout

        let stashes: [JSONValue] = raw
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> JSONValue? in
                let parts = line.components(separatedBy: "|")
                guard parts.count >= 3 else { return nil }
                let id      = parts[0]
                let message = parts[1]
                let date    = parts[2...].joined(separator: "|").trimmingCharacters(in: .whitespaces)
                return .object([
                    "id":      .string(id),
                    "message": .string(message),
                    "date":    .string(date)
                ])
            }

        return makeContent(["stashes": .array(stashes)])
    }
}

// MARK: - zion_stash_apply

struct StashApplyTool: Tool {
    let repoURL: URL

    var name: String { "zion_stash_apply" }
    var description: String { "Apply a stash entry by id (e.g. stash@{0}). Optionally pass use_index: true to restore the index." }

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "id": .object([
                    "type": .string("string"),
                    "description": .string("Stash id, e.g. stash@{0}.")
                ]),
                "use_index": .object([
                    "type": .string("boolean"),
                    "description": .string("Pass --index to restore the index state. Default false.")
                ])
            ]),
            "required": .array([.string("id")])
        ]
    }

    func call(args: [String: JSONValue]) throws -> JSONValue {
        let id = try args.requireString("id")
        let useIndex: Bool
        if let v = args["use_index"], case .bool(let b) = v {
            useIndex = b
        } else {
            useIndex = false
        }

        var gitArgs = ["stash", "apply"]
        if useIndex { gitArgs.append("--index") }
        gitArgs.append(id)

        let result = try gitWithStderr(args: gitArgs, repoURL: repoURL)

        // Parse conflict paths from stderr/stdout
        // git prints "CONFLICT (content): Merge conflict in <path>" lines
        let combined = result.stdout + "\n" + result.stderr
        let conflicts: [String] = combined
            .components(separatedBy: "\n")
            .compactMap { line -> String? in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("CONFLICT") else { return nil }
                // "CONFLICT (content): Merge conflict in some/path.swift"
                if let range = t.range(of: " in ") {
                    return String(t[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
                return nil
            }

        let applied = result.exitCode == 0
        return makeContent([
            "applied":   .bool(applied),
            "conflicts": .array(conflicts.map { .string($0) })
        ])
    }
}

// MARK: - Internal: git runner with stderr + exit code

struct GitResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

/// Run git, capture stdout + stderr, return all three. Throws only on process spawn failure.
func gitWithStderr(args: [String], repoURL: URL) throws -> GitResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = repoURL

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError  = errPipe

    try process.run()
    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    let stdout = String(data: outData, encoding: .utf8) ?? ""
    let stderr = String(data: errData, encoding: .utf8) ?? ""
    let exitCode = process.terminationStatus

    if exitCode != 0 && exitCode != 1 {
        throw ToolError.executionFailed("git \(args.joined(separator: " ")) exited \(exitCode): \(stderr)")
    }

    return GitResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
}
