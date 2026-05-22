// main.swift — ZionMCP stdio JSON-RPC server entry point
// Spawned by Claude/Codex CLI as an MCP server.
// Protocol: one JSON-RPC 2.0 message per line on stdin/stdout.

import Foundation

// MARK: - CLI args

var repoPath: String? = nil
var cliArgs = CommandLine.arguments.dropFirst()
var argIter = cliArgs.makeIterator()
while let arg = argIter.next() {
    if arg == "--repo", let path = argIter.next() {
        repoPath = path
    }
}

// MARK: - Registry + Server

let registry = ToolRegistry()
let server = Server()

// MARK: - initialize

server.register(method: "initialize") { _ in
    return .object([
        "protocolVersion": .string("2026-05-22"),
        "capabilities": .object([
            "tools": .object([
                "listChanged": .bool(false)
            ])
        ]),
        "serverInfo": .object([
            "name": .string("zion-mcp"),
            "version": .string("0.1.0")
        ])
    ])
}

// MARK: - tools/list

server.register(method: "tools/list") { _ in
    return registry.listJSON()
}

// MARK: - tools/call (stub — real tools land in tasks 2-4)

server.register(method: "tools/call") { request in
    guard case .object(let params) = request.params,
          case .string(let toolName) = params["name"] else {
        throw JSONRPCError.invalidParams
    }

    guard let tool = registry.tool(named: toolName) else {
        throw JSONRPCError(code: -32601, message: "Unknown tool: \(toolName)")
    }

    var argsDict: [String: JSONValue] = [:]
    if case .object(let a) = params["arguments"] {
        argsDict = a
    }
    return try tool.call(args: argsDict)
}

// MARK: - Run

server.run()
