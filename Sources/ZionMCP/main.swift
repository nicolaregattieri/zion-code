// main.swift — ZionMCP stdio JSON-RPC server entry point
// Spawned by Claude/Codex CLI as an MCP server.
// Protocol: one JSON-RPC 2.0 message per line on stdin/stdout.

import Foundation

// MARK: - CLI args

var repoPath: String? = nil
var allowEdits = false
var cliArgs = CommandLine.arguments.dropFirst()
var argIter = cliArgs.makeIterator()
while let arg = argIter.next() {
    if arg == "--repo", let path = argIter.next() {
        repoPath = path
    } else if arg == "--allow-edits" {
        allowEdits = true
    }
}

// MARK: - Registry + Server

let registry = ToolRegistry()
let server = Server()

// MARK: - Tool registration

let repoURL: URL = {
    if let path = repoPath { return URL(fileURLWithPath: path) }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}()

func registerMutationTools(in registry: ToolRegistry, repoURL: URL, allowEdits: Bool) {
    guard allowEdits else { return }
    registry.register(StashApplyTool(repoURL: repoURL))
    registry.register(EditTool(repoURL: repoURL))
}

func registerSessionTools(in registry: ToolRegistry, repoURL: URL, allowEdits: Bool) {
    registry.register(GitLog(repoURL: repoURL))
    registry.register(BranchList(repoURL: repoURL))
    registry.register(PendingChanges(repoURL: repoURL))
    registry.register(CommitInspect(repoURL: repoURL))
    registry.register(Worktrees(repoURL: repoURL))
    registry.register(StashListTool(repoURL: repoURL))
    registry.register(RepoMemorySearchTool(repoURL: repoURL))
    registry.register(RepoMapTool(repoURL: repoURL))
    registerMutationTools(in: registry, repoURL: repoURL, allowEdits: allowEdits)
}

// Advertise only tools that execute correctly for the active CLI session.
// `bash` and `zion_open_in_editor` stay unregistered until their runtime bridges exist.
registerSessionTools(in: registry, repoURL: repoURL, allowEdits: allowEdits)

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
