// BashToolMCP.swift — MCP `bash` tool for the ZionMCP server.
// Executes shell commands with safety checks matching BashTool.swift in the Zion target.
// ZionMCP cannot import Zion, so safety logic is self-contained here.
// T8 (AgentRuntime) will wire the approval tier from the active chat session.

import Foundation

struct BashToolMCP: Tool {
    let repoURL: URL

    var name: String { "bash" }
    var description: String {
        "Execute a shell command in the workspace. Respects approval tier."
    }

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "command": .object([
                    "type": .string("string")
                ]),
                "timeoutSec": .object([
                    "type": .string("integer"),
                    "minimum": .int(1),
                    "maximum": .int(300)
                ])
            ]),
            "required": .array([.string("command")])
        ]
    }

    func call(args: [String: JSONValue]) throws -> JSONValue {
        let command = try args.requireString("command")
        let timeoutSec: Int
        if case .int(let t) = args["timeoutSec"] {
            timeoutSec = t
        } else {
            timeoutSec = 60
        }

        // TODO: T8 (AgentRuntime) will inject AgentApprovalTier from the chat session.
        // Until then, return a descriptive error so the tool is registered but not yet dispatching.
        _ = command
        _ = timeoutSec
        return .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string("bash: repoURL not yet wired (T8 pending)")
                ])
            ])
        ])
    }
}
