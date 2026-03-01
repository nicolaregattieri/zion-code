import CryptoKit
import Foundation
import Network

actor RemoteAccessServer {
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var pairingKey: SymmetricKey?
    private var validPairingTokens: Set<String> = []
    private var authenticatedConnections: Set<ObjectIdentifier> = []
    private var messageTimestamps: [ObjectIdentifier: [Date]] = [:]

    var onMessageReceived: (@Sendable (RemoteMessage) async -> Void)?
    var onConnectionCountChanged: (@Sendable (Int) async -> Void)?

    var connectedDeviceCount: Int { authenticatedConnections.count }

    // MARK: - Lifecycle

    func start(port: UInt16, key: SymmetricKey) throws {
        pairingKey = key

        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let nwPort = NWEndpoint.Port(rawValue: port)!
        let newListener = try NWListener(using: parameters, on: nwPort)

        newListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleListenerState(state) }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handleNewConnection(connection) }
        }

        listener = newListener
        newListener.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()
        authenticatedConnections.removeAll()
        messageTimestamps.removeAll()
        validPairingTokens.removeAll()
    }

    func addPairingToken(_ token: String) {
        validPairingTokens.insert(token)
    }

    // MARK: - Broadcasting

    func broadcast(_ message: RemoteMessage) async {
        guard let key = pairingKey else { return }
        do {
            let jsonData = try JSONEncoder().encode(message)
            let encrypted = try RemoteAccessEncryption.encrypt(jsonData, using: key)

            for connectionID in authenticatedConnections {
                guard let connection = connections[connectionID] else { continue }
                let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
                let context = NWConnection.ContentContext(identifier: "broadcast", metadata: [metadata])
                connection.send(content: encrypted, contentContext: context, completion: .idempotent)
            }
        } catch {
            await MainActor.run {
                DiagnosticLogger.shared.log(.warn, "Broadcast encrypt failed", context: error.localizedDescription, source: "RemoteAccessServer")
            }
        }
    }

    // MARK: - Connection Handling

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            Task { @MainActor in
                DiagnosticLogger.shared.log(.info, "WebSocket server ready", source: "RemoteAccessServer")
            }
        case .failed(let error):
            Task { @MainActor in
                DiagnosticLogger.shared.log(.error, "WebSocket listener failed", context: error.localizedDescription, source: "RemoteAccessServer")
            }
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let connectionID = ObjectIdentifier(connection)

        if connections.count >= Constants.RemoteAccess.maxConcurrentConnections {
            connection.cancel()
            return
        }

        connections[connectionID] = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleConnectionState(connectionID, state: state) }
        }

        connection.start(queue: .global(qos: .userInitiated))
        receiveMessage(from: connection, id: connectionID)
    }

    private func handleConnectionState(_ id: ObjectIdentifier, state: NWConnection.State) {
        switch state {
        case .ready:
            Task { @MainActor in
                DiagnosticLogger.shared.log(.info, "Client connected", source: "RemoteAccessServer")
            }
        case .failed, .cancelled:
            connections.removeValue(forKey: id)
            authenticatedConnections.remove(id)
            messageTimestamps.removeValue(forKey: id)
            let count = authenticatedConnections.count
            Task {
                await onConnectionCountChanged?(count)
            }
        default:
            break
        }
    }

    // MARK: - Receiving

    private func receiveMessage(from connection: NWConnection, id: ObjectIdentifier) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            Task {
                if let error {
                    await MainActor.run {
                        DiagnosticLogger.shared.log(.warn, "Receive error", context: error.localizedDescription, source: "RemoteAccessServer")
                    }
                    return
                }

                guard let data else { return }

                // Rate limiting
                if await self.isRateLimited(id) { return }

                if await !self.authenticatedConnections.contains(id) {
                    await self.handlePairingAttempt(data: data, connectionID: id)
                } else {
                    await self.handleAuthenticatedMessage(data: data)
                }

                await self.receiveMessage(from: connection, id: id)
            }
        }
    }

    private func isRateLimited(_ id: ObjectIdentifier) -> Bool {
        let now = Date()
        let cutoff = now.addingTimeInterval(-1)
        var timestamps = messageTimestamps[id] ?? []
        timestamps = timestamps.filter { $0 > cutoff }
        timestamps.append(now)
        messageTimestamps[id] = timestamps
        return timestamps.count > Constants.RemoteAccess.maxMessagesPerSecond
    }

    // MARK: - Pairing

    private func handlePairingAttempt(data: Data, connectionID: ObjectIdentifier) {
        guard let tokenString = String(data: data, encoding: .utf8),
              validPairingTokens.contains(tokenString) else {
            connections[connectionID]?.cancel()
            connections.removeValue(forKey: connectionID)
            return
        }

        validPairingTokens.remove(tokenString)
        authenticatedConnections.insert(connectionID)
        let count = authenticatedConnections.count
        Task {
            await onConnectionCountChanged?(count)
        }

        // Send ACK
        if let connection = connections[connectionID] {
            let ack = "paired".data(using: .utf8)!
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "ack", metadata: [metadata])
            connection.send(content: ack, contentContext: context, completion: .idempotent)
        }
    }

    private func handleAuthenticatedMessage(data: Data) async {
        guard let key = pairingKey else { return }
        do {
            let decrypted = try RemoteAccessEncryption.decrypt(data, using: key)
            let message = try JSONDecoder().decode(RemoteMessage.self, from: decrypted)
            await onMessageReceived?(message)
        } catch {
            await MainActor.run {
                DiagnosticLogger.shared.log(.warn, "Failed to decrypt/decode message", context: error.localizedDescription, source: "RemoteAccessServer")
            }
        }
    }
}
