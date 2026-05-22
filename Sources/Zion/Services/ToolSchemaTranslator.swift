// ToolSchemaTranslator.swift — Translates MCPToolDescriptors into provider-specific JSON shapes.

import Foundation

// MARK: - MCPToolDescriptor

/// Lightweight descriptor for an MCP tool, local to Zion target (no ZionMCP import).
struct MCPToolDescriptor: @unchecked Sendable {
    let name: String
    let description: String
    /// JSON Schema object describing tool parameters (e.g. {"type": "object", "properties": {...}}).
    let inputSchema: [String: Any]
}

// MARK: - ProviderFamily

enum ProviderFamily: String, Sendable {
    case anthropic
    case openai
    case gemini
    case openrouter           // follows OpenAI format exactly
    case localOpenAICompatible // same as openai
}

// MARK: - ToolSchemaTranslator

enum ToolSchemaTranslator {

    // MARK: - Public

    /// Translate an array of MCP tool descriptors to a provider-specific JSON representation.
    static func translate(_ tools: [MCPToolDescriptor], for family: ProviderFamily) -> [[String: Any]] {
        switch family {
        case .anthropic:
            return tools.map { anthropicShape($0) }
        case .openai, .openrouter, .localOpenAICompatible:
            return tools.map { openAIShape($0) }
        case .gemini:
            return tools.map { geminiShape($0) }
        }
    }

    // MARK: - Private builders

    /// Anthropic: `{"name": "...", "description": "...", "input_schema": {...}}`
    private static func anthropicShape(_ tool: MCPToolDescriptor) -> [String: Any] {
        return [
            "name": tool.name,
            "description": tool.description,
            "input_schema": tool.inputSchema
        ]
    }

    /// OpenAI: `{"type": "function", "function": {"name": "...", "description": "...", "parameters": {...}}}`
    private static func openAIShape(_ tool: MCPToolDescriptor) -> [String: Any] {
        let params = normalizeForOpenAIStrict(tool.inputSchema)
        return [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": params
            ] as [String: Any]
        ]
    }

    /// Gemini: `{"name": "...", "description": "...", "parameters": {...}}`
    private static func geminiShape(_ tool: MCPToolDescriptor) -> [String: Any] {
        return [
            "name": tool.name,
            "description": tool.description,
            "parameters": tool.inputSchema
        ]
    }

    // MARK: - OpenAI strict normalisation

    /// Recursively adds `"additionalProperties": false` to every `"type": "object"` in the schema.
    static func normalizeForOpenAIStrict(_ schema: [String: Any]) -> [String: Any] {
        var result = schema

        // Enforce additionalProperties: false on objects
        if let type_ = result["type"] as? String, type_ == "object" {
            result["additionalProperties"] = false
        }

        // Recurse into "properties"
        if let props = result["properties"] as? [String: Any] {
            var newProps: [String: Any] = [:]
            for (key, val) in props {
                if let sub = val as? [String: Any] {
                    newProps[key] = normalizeForOpenAIStrict(sub)
                } else {
                    newProps[key] = val
                }
            }
            result["properties"] = newProps
        }

        // Recurse into "items" (array schemas)
        if let items = result["items"] as? [String: Any] {
            result["items"] = normalizeForOpenAIStrict(items)
        }

        return result
    }
}
