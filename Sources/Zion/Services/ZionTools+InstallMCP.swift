import Foundation

/// Phase 6.3 — `install_mcp_server(json:)` MCP tool. Lets the model
/// (or the user via natural-language prompt that the model parses)
/// install a new MCP server by pasting / dropping the same JSON shape
/// Cursor + Claude Desktop use. No more "open Settings → click + →
/// fill four fields by hand". Persists through the existing
/// `MCPRegistryStore` so the rest of the app (settings, harness,
/// MCPConfigBuilder.allToolsIncludingUserServers) picks it up
/// immediately.
extension MCPConfigBuilder {

    static func installMCPServerDescriptor() -> MCPToolDescriptor {
        MCPToolDescriptor(
            name: "install_mcp_server",
            description: "Install an MCP server from a JSON config payload (single-server shape or `{\"mcpServers\":{\"<id>\":{...}}}` map). Persists via MCPRegistryStore so the next chat turn can use the new tools. Returns a summary of what was added; use this when the user pastes / drops MCP server JSON or asks to add an MCP by name.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "json": [
                        "type": "string",
                        "description": "Raw JSON. Accepted shapes: single server `{\"id\":\"foo\",\"command\":\"npx\",\"args\":[\"-y\",\"@org/server\"]}`, named single `{\"foo\":{\"command\":\"npx\",\"args\":[...]}}`, or full map `{\"mcpServers\":{\"foo\":{...}}}`."
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["json"]
            ]
        )
    }

    static func dispatchInstallMCPServer(args: [String: Any]) async throws -> String {
        let raw = (args["json"] as? String) ?? ""
        guard !raw.isEmpty else { return "[error: missing json]" }

        let parsed: [MCPServerConfig]
        do {
            parsed = try parseMCPConfigPayload(raw)
        } catch {
            return "[error: \(error.localizedDescription)]"
        }
        guard !parsed.isEmpty else {
            return "[error: no MCP server found in payload]"
        }

        let store = await MainActor.run { MCPRegistryStore() }
        var installed: [String] = []
        var failed: [(String, String)] = []
        for config in parsed {
            do {
                let added = try await store.addServer(config)
                installed.append(added.id)
            } catch {
                failed.append((config.id, error.localizedDescription))
            }
        }

        var lines: [String] = []
        if !installed.isEmpty {
            lines.append("Installed: " + installed.joined(separator: ", "))
        }
        if !failed.isEmpty {
            let fails = failed.map { "\($0.0) (\($0.1))" }.joined(separator: ", ")
            lines.append("Failed: " + fails)
        }
        return lines.joined(separator: "\n")
    }

    /// Parses Cursor / Claude Desktop / single-server MCP JSON shapes.
    static func parseMCPConfigPayload(_ raw: String) throws -> [MCPServerConfig] {
        let data = Data(raw.utf8)
        let any = try JSONSerialization.jsonObject(with: data, options: [])
        guard let object = any as? [String: Any] else {
            return []
        }
        if let map = object["mcpServers"] as? [String: Any] {
            return try map.compactMap { try decodeNamedServer(id: $0.key, raw: $0.value) }
        }
        if let id = object["id"] as? String,
           let command = object["command"] as? String {
            let args = (object["args"] as? [String]) ?? []
            let env = (object["env"] as? [String: String]) ?? [:]
            let transport = (object["transport"] as? String) ?? "stdio"
            let disabled = (object["disabled"] as? Bool) ?? false
            let autoApprove = (object["autoApprove"] as? [String]) ?? []
            return [MCPServerConfig(id: id, command: command, args: args, env: env, transport: transport, disabled: disabled, autoApprove: autoApprove)]
        }
        if object.count == 1, let first = object.first {
            if let decoded = try decodeNamedServer(id: first.key, raw: first.value) {
                return [decoded]
            }
        }
        return []
    }

    private static func decodeNamedServer(id: String, raw: Any) throws -> MCPServerConfig? {
        guard let dict = raw as? [String: Any] else { return nil }
        let command = (dict["command"] as? String) ?? ""
        guard !command.isEmpty else { return nil }
        let args = (dict["args"] as? [String]) ?? []
        let env = (dict["env"] as? [String: String]) ?? [:]
        let transport = (dict["transport"] as? String) ?? "stdio"
        let disabled = (dict["disabled"] as? Bool) ?? false
        let autoApprove = (dict["autoApprove"] as? [String]) ?? []
        return MCPServerConfig(id: id, command: command, args: args, env: env, transport: transport, disabled: disabled, autoApprove: autoApprove)
    }
}
