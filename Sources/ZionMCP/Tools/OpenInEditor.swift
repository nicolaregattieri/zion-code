// OpenInEditor.swift — zion_open_in_editor tool
// Sends a file+line request to the running Zion app via UNIX domain socket.

import Foundation
import Darwin

struct OpenInEditorTool: Tool {
    var name: String { "zion_open_in_editor" }
    var description: String { "Ask the running Zion app to open a file at a given line in the Code tab." }

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "file": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the file to open.")
                ]),
                "line": .object([
                    "type": .string("integer"),
                    "description": .string("1-based line number to scroll to (optional).")
                ])
            ]),
            "required": .array([.string("file")])
        ]
    }

    func call(args: [String: JSONValue]) throws -> JSONValue {
        // Resolve the Zion app PID from environment
        guard let pidString = ProcessInfo.processInfo.environment["ZION_APP_PID"],
              let pid = Int(pidString) else {
            return makeContent(["success": .bool(false), "reason": .string("zion app not reachable")])
        }

        guard let file = args["file"], case .string(let filePath) = file else {
            return makeContent(["success": .bool(false), "reason": .string("missing 'file' argument")])
        }

        // Optional line number
        var lineNumber: Int? = nil
        if let lineVal = args["line"] {
            if case .int(let l) = lineVal { lineNumber = l }
        }

        // Build socket path
        let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp/"
        let socketPath = tmpDir.hasSuffix("/")
            ? "\(tmpDir)zion-mcp-\(pid).sock"
            : "\(tmpDir)/zion-mcp-\(pid).sock"

        // Build JSON payload
        var payload: [String: JSONValue] = ["file": .string(filePath)]
        if let line = lineNumber {
            payload["line"] = .int(line)
        }

        guard let data = try? JSONEncoder().encode(JSONValue.object(payload)),
              var jsonLine = String(data: data, encoding: .utf8) else {
            return makeContent(["success": .bool(false), "reason": .string("json encoding failed")])
        }
        jsonLine += "\n"

        // Connect via UNIX domain socket
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return makeContent(["success": .bool(false), "reason": .string("socket() failed: \(errno)")])
        }
        defer { Darwin.close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= sunPathSize else {
            return makeContent(["success": .bool(false), "reason": .string("socket path too long")])
        }

        let copyByteCount = min(pathBytes.count, sunPathSize)
        pathBytes.withUnsafeBufferPointer { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                UnsafeMutableRawPointer(ptr).copyMemory(
                    from: src.baseAddress!,
                    byteCount: copyByteCount
                )
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            return makeContent(["success": .bool(false), "reason": .string("zion app not reachable")])
        }

        // Write JSON line
        let written = jsonLine.withCString { ptr in
            Darwin.write(fd, ptr, strlen(ptr))
        }

        guard written > 0 else {
            return makeContent(["success": .bool(false), "reason": .string("write() failed: \(errno)")])
        }

        return makeContent(["success": .bool(true)])
    }
}
