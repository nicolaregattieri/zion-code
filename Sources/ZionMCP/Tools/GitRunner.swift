// GitRunner.swift — shared git subprocess helper for ZionMCP tools

import Foundation

/// Run git and return stdout as a String. Throws ToolError.executionFailed on non-zero exit.
func git(args: [String], repoURL: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = repoURL

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe() // swallow stderr

    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
        throw ToolError.executionFailed("git \(args.joined(separator: " ")) exited \(process.terminationStatus)")
    }

    return String(data: data, encoding: .utf8) ?? ""
}

/// Wrap a [String: JSONValue] result as MCP tools/call content array.
func makeContent(_ dict: [String: JSONValue]) -> JSONValue {
    guard let data = try? JSONEncoder().encode(JSONValue.object(dict)),
          let text = String(data: data, encoding: .utf8) else {
        return .object(["content": .array([.object(["type": .string("text"), "text": .string("{}")])])])
    }
    return .object([
        "content": .array([
            .object(["type": .string("text"), "text": .string(text)])
        ])
    ])
}
