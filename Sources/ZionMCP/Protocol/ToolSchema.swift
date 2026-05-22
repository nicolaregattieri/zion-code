// ToolSchema.swift — Tool protocol + registry for ZionMCP

import Foundation

// MARK: - Tool protocol

protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    /// JSON Schema object describing the tool's input parameters.
    var inputSchema: [String: JSONValue] { get }
    /// Invoke the tool. Args decoded from the MCP `arguments` object.
    func call(args: [String: JSONValue]) throws -> JSONValue
}

// MARK: - ToolRegistry
// Uses a simple lock for synchronous access — the server's read loop is single-threaded.

final class ToolRegistry: @unchecked Sendable {
    private var tools: [String: any Tool] = [:]
    private let lock = NSLock()

    func register(_ tool: any Tool) {
        lock.withLock { tools[tool.name] = tool }
    }

    func allTools() -> [any Tool] {
        lock.withLock { Array(tools.values).sorted { $0.name < $1.name } }
    }

    func tool(named name: String) -> (any Tool)? {
        lock.withLock { tools[name] }
    }

    /// Serialise the registry as MCP `tools/list` result JSON.
    func listJSON() -> JSONValue {
        let toolArray: [JSONValue] = allTools().map { tool in
            .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": .object(tool.inputSchema)
            ])
        }
        return .object(["tools": .array(toolArray)])
    }
}

// MARK: - Arg decoder helpers

extension Dictionary where Key == String, Value == JSONValue {
    func requireString(_ key: String) throws -> String {
        guard let v = self[key], case .string(let s) = v else {
            throw ToolError.missingArgument(key)
        }
        return s
    }

    func optionalString(_ key: String) -> String? {
        guard let v = self[key], case .string(let s) = v else { return nil }
        return s
    }
}

enum ToolError: Error, LocalizedError {
    case missingArgument(String)
    case invalidArgument(String, String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let k):         return "Missing required argument: \(k)"
        case .invalidArgument(let k, let r):  return "Invalid argument '\(k)': \(r)"
        case .executionFailed(let reason):    return "Tool execution failed: \(reason)"
        }
    }
}
