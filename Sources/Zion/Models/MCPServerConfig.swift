import Foundation

struct MCPServerConfig: Sendable, Codable, Equatable, Identifiable {
    let id: String  // map key from mcpServers, e.g. "filesystem"
    var command: String  // e.g. "npx"
    var args: [String]   // e.g. ["@modelcontextprotocol/server-filesystem", "/tmp"]
    var env: [String: String] = [:]
    var transport: String = "stdio"
    var disabled: Bool = false
    var autoApprove: [String] = []  // tool names auto-approved without prompt
}

enum MCPServerStatus: Sendable, Equatable {
    case disabled
    case starting
    case running(toolCount: Int)
    case crashed(reason: String)
}
