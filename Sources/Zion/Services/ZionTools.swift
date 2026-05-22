import Foundation

/// Defines the 6 standard Zion tools and exports their schemas for OpenAI and Anthropic envelopes.
struct ZionTools {

    // MARK: - Internal schema representation

    struct ToolDef: @unchecked Sendable {
        let name: String
        let description: String
        let properties: [String: [String: Any]]
        let required: [String]
    }

    // MARK: - Tool definitions

    static let tools: [ToolDef] = [
        ToolDef(
            name: "read",
            description: "Read file contents from the local filesystem.",
            properties: [
                "path":   ["type": "string",  "description": "Absolute path to the file."],
                "offset": ["type": "integer", "description": "Line number to start reading from (1-based)."],
                "limit":  ["type": "integer", "description": "Maximum number of lines to return."]
            ],
            required: ["path"]
        ),
        ToolDef(
            name: "edit",
            description: "Apply str_replace edits to a file. Each edit replaces oldText with newText.",
            properties: [
                "path": ["type": "string", "description": "Absolute path to the file to edit."],
                "edits": [
                    "type": "array",
                    "description": "List of str_replace operations to apply in order.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "oldText": ["type": "string", "description": "Exact string to find and replace."],
                            "newText": ["type": "string", "description": "Replacement string."]
                        ] as [String: Any],
                        "required": ["oldText", "newText"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            required: ["path", "edits"]
        ),
        ToolDef(
            name: "write",
            description: "Write content to a file, creating or overwriting it.",
            properties: [
                "path":    ["type": "string", "description": "Absolute path to the file to write."],
                "content": ["type": "string", "description": "Full content to write to the file."]
            ],
            required: ["path", "content"]
        ),
        ToolDef(
            name: "bash",
            description: "Execute a shell command and return stdout/stderr.",
            properties: [
                "command": ["type": "string",  "description": "Shell command to execute."],
                "timeout": ["type": "integer", "description": "Timeout in milliseconds (default 30000)."]
            ],
            required: ["command"]
        ),
        ToolDef(
            name: "grep",
            description: "Search for a regex pattern across files.",
            properties: [
                "pattern":    ["type": "string",  "description": "Regex pattern to search for."],
                "path":       ["type": "string",  "description": "Directory or file path to search in."],
                "glob":       ["type": "string",  "description": "Glob pattern to filter files (e.g. '*.swift')."],
                "ignoreCase": ["type": "boolean", "description": "Perform case-insensitive matching."]
            ],
            required: ["pattern"]
        ),
        ToolDef(
            name: "glob",
            description: "List files matching a glob pattern.",
            properties: [
                "pattern": ["type": "string", "description": "Glob pattern (e.g. 'Sources/**/*.swift')."],
                "path":    ["type": "string", "description": "Base directory to search from."]
            ],
            required: ["pattern"]
        )
    ]

    // MARK: - OpenAI envelope

    /// Returns tool schemas in OpenAI function-calling format.
    /// Shape: [{ "type": "function", "function": { "name": ..., "description": ..., "parameters": { ... } } }]
    static func toolSchemasJSON() -> [[String: Any]] {
        tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": [
                        "type": "object",
                        "properties": tool.properties,
                        "required": tool.required
                    ] as [String: Any]
                ] as [String: Any]
            ]
        }
    }

    // MARK: - Anthropic envelope

    /// Returns tool schemas in Anthropic tool-use format.
    /// Shape: [{ "name": ..., "description": ..., "input_schema": { ... } }]
    static func anthropicToolSchemas() -> [[String: Any]] {
        tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": [
                    "type": "object",
                    "properties": tool.properties,
                    "required": tool.required
                ] as [String: Any]
            ]
        }
    }
}
