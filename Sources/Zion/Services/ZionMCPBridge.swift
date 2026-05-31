// ZionMCPBridge.swift — UNIX domain socket listener so ZionMCP tools can talk to the Zion app.
// ChatService creates and starts an instance. The bridge accepts one JSON line per connection
// and posts a NotificationCenter event for the Code tab to observe.

import Foundation
import Darwin

// MARK: - Notification

extension Notification.Name {
    static let zionMCPOpenInEditor = Notification.Name("zionMCPOpenInEditor")
}

// MARK: - Request model

private struct OpenRequest: Decodable {
    let file: String
    let line: Int?
}

// MARK: - Bridge actor

actor ZionMCPBridge {

    // MARK: State

    private var serverFD: Int32 = -1
    private var socketPath: String = ""
    private var listenTask: Task<Void, Never>?

    // MARK: Init

    init() {}

    // MARK: Start

    /// Bind a UNIX domain socket at `$TMPDIR/zion-mcp-<pid>.sock` and accept connections.
    func start() {
        let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp/"
        let pid = Int(getpid())
        let path = tmpDir.hasSuffix("/")
            ? "\(tmpDir)zion-mcp-\(pid).sock"
            : "\(tmpDir)/zion-mcp-\(pid).sock"
        socketPath = path

        // Remove any leftover socket from a previous run
        Darwin.unlink(path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        serverFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = path.utf8CString
        let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= sunPathSize else {
            Darwin.close(fd)
            return
        }

        let copyByteCount = min(pathBytes.count, sunPathSize)
        pathBytes.withUnsafeBufferPointer { src -> Void in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                UnsafeMutableRawPointer(ptr).copyMemory(
                    from: src.baseAddress!,
                    byteCount: copyByteCount
                )
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            Darwin.close(fd)
            return
        }

        guard Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd)
            return
        }

        let capturedFD = fd
        listenTask = Task.detached(priority: .background) { [weak self] in
            await self?.acceptLoop(serverFD: capturedFD)
        }
    }

    // MARK: Stop

    func stop() {
        listenTask?.cancel()
        listenTask = nil
        if serverFD >= 0 {
            Darwin.close(serverFD)
            serverFD = -1
        }
        if !socketPath.isEmpty {
            Darwin.unlink(socketPath)
            socketPath = ""
        }
    }

    // MARK: Accept loop

    private func acceptLoop(serverFD: Int32) async {
        while !Task.isCancelled {
            let clientFD = Darwin.accept(serverFD, nil, nil)
            guard clientFD >= 0 else { break }
            handleClient(fd: clientFD)
        }
    }

    private func handleClient(fd: Int32) {
        defer { Darwin.close(fd) }

        // Read until newline or EOF (max 4KB)
        var buffer = Data()
        var byte = UInt8(0)
        while buffer.count < 4096 {
            let n = Darwin.read(fd, &byte, 1)
            if n <= 0 { break }
            if byte == UInt8(ascii: "\n") { break }
            buffer.append(byte)
        }

        guard !buffer.isEmpty,
              let request = try? JSONDecoder().decode(OpenRequest.self, from: buffer) else {
            return
        }

        var userInfo: [String: Any] = ["file": request.file]
        if let line = request.line {
            userInfo["line"] = line
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .zionMCPOpenInEditor,
                object: nil,
                userInfo: userInfo
            )
        }
    }

    // MARK: Stale socket sweep

    /// Remove `zion-mcp-*.sock` files in `$TMPDIR` older than `maxAge` seconds.
    /// Called once at app launch to clean up leftovers from crashed prior instances.
    static func sweepStaleSockets(now: Date = Date(), maxAge: TimeInterval = 3600) {
        let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp/"
        let url = URL(fileURLWithPath: tmpDir, isDirectory: true)

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        ) else { return }

        for item in contents {
            let name = item.lastPathComponent
            guard name.hasPrefix("zion-mcp-") && name.hasSuffix(".sock") else { continue }

            guard let attrs = try? item.resourceValues(forKeys: [.contentModificationDateKey]),
                  let mtime = attrs.contentModificationDate else { continue }

            if now.timeIntervalSince(mtime) > maxAge {
                Darwin.unlink(item.path)
            }
        }
    }
}
