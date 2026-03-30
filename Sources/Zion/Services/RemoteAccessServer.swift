import CryptoKit
import Foundation
import Network

actor RemoteAccessServer {
    nonisolated static func isAddressInUseError(_ error: Error) -> Bool {
        if let nwError = error as? NWError,
           case .posix(let code) = nwError,
           code == .EADDRINUSE
        {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EADDRINUSE) {
            return true
        }

        let description = error.localizedDescription.lowercased()
        return description.contains("address already in use") || description.contains("error 48")
    }

    private final class ListenerStartupGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        private var result: Result<Void, Error>?

        func waitUntilResolved() async throws {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(with: result)
                    return
                }
                self.continuation = continuation
                lock.unlock()
            }
        }

        func resolve(with result: Result<Void, Error>) {
            lock.lock()
            guard self.result == nil else {
                lock.unlock()
                return
            }
            self.result = result
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(with: result)
        }
    }

    private var listener: NWListener?
    private var pairingKey: SymmetricKey?
    private var validPairingTokens: [String: ContinuousClock.Instant] = [:]  // token → creation time
    private var authenticatedTokens: Set<String> = []
    private static let tokenTTL = Duration.seconds(Constants.RemoteAccess.pairingTokenTTLSeconds)
    private var connectionCount: Int = 0
    private var tokenModes: [String: Bool] = [:]  // token -> true if LAN
    private var persistedToken: String?

    // Pending events queue per token (consumed on poll)
    private var pendingEvents: [String: [RemoteMessage]] = [:]

    // WebSocket connections: token → NWConnection (persistent, messages pushed directly)
    private var wsConnections: [String: NWConnection] = [:]

    // Rate limiting: token → [request timestamps]
    private var requestTimestamps: [String: [ContinuousClock.Instant]] = [:]

    // Disconnect detection: token → last poll time
    private var lastPollTime: [String: ContinuousClock.Instant] = [:]
    private var disconnectCheckTask: Task<Void, Never>?

    // Max request body size (64 KB)
    private static let maxContentLength = 65_536

    var onMessageReceived: (@Sendable (RemoteMessage) async -> Void)?
    var onConnectionCountChanged: (@Sendable (Int) async -> Void)?

    var connectedDeviceCount: Int { authenticatedTokens.count }

    var lanConnectedCount: Int {
        authenticatedTokens.filter { tokenModes[$0] == true }.count
    }
    var tunnelConnectedCount: Int {
        authenticatedTokens.filter { tokenModes[$0] != true }.count
    }

    // MARK: - Lifecycle

    private var wsListener: NWListener?

    func start(port: UInt16, key: SymmetricKey) async throws {
        pairingKey = key

        // HTTP listener (existing polling clients + web client)
        let parameters = NWParameters.tcp
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let newListener = try NWListener(using: parameters, on: nwPort)
        let httpStartupGate = ListenerStartupGate()

        newListener.stateUpdateHandler = { [weak self, httpStartupGate] state in
            switch state {
            case .ready:
                httpStartupGate.resolve(with: .success(()))
            case .failed(let error):
                httpStartupGate.resolve(with: .failure(error))
            default:
                break
            }
            guard let self else { return }
            Task { await self.handleListenerState(state) }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handleNewConnection(connection) }
        }

        listener = newListener
        newListener.start(queue: .global(qos: .userInitiated))

        // WebSocket listener (native iOS app)
        let wsParams = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsParams.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let wsPort = NWEndpoint.Port(rawValue: port + 1)!
        let newWSListener = try NWListener(using: wsParams, on: wsPort)
        let wsStartupGate = ListenerStartupGate()

        newWSListener.stateUpdateHandler = { [weak self, wsStartupGate] state in
            switch state {
            case .ready:
                wsStartupGate.resolve(with: .success(()))
            case .failed(let error):
                wsStartupGate.resolve(with: .failure(error))
            default:
                break
            }
            guard let self else { return }
            Task { await self.handleWSListenerState(state) }
        }

        newWSListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handleNewWSConnection(connection) }
        }

        wsListener = newWSListener
        newWSListener.start(queue: .global(qos: .userInitiated))

        try await httpStartupGate.waitUntilResolved()
        try await wsStartupGate.waitUntilResolved()
        startDisconnectChecker()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        wsListener?.cancel()
        wsListener = nil
        for (_, conn) in wsConnections {
            conn.cancel()
        }
        wsConnections.removeAll()
        disconnectCheckTask?.cancel()
        disconnectCheckTask = nil
        authenticatedTokens.removeAll()
        validPairingTokens.removeAll()
        pendingEvents.removeAll()
        requestTimestamps.removeAll()
        lastPollTime.removeAll()
        tokenModes.removeAll()
    }

    func addPairingToken(_ token: String) {
        validPairingTokens.removeAll()
        validPairingTokens[token] = ContinuousClock.now
    }

    /// Disconnect all authenticated clients
    func disconnectAll() {
        authenticatedTokens.removeAll()
        pendingEvents.removeAll()
        for (_, conn) in wsConnections {
            conn.cancel()
        }
        wsConnections.removeAll()
        lastPollTime.removeAll()
        requestTimestamps.removeAll()
        tokenModes.removeAll()
        let count = 0
        Task { await onConnectionCountChanged?(count) }
    }

    func setPersistedToken(_ token: String) {
        persistedToken = token
        authenticatedTokens.insert(token)
        pendingEvents[token] = []
    }

    private func isValidPairingToken(_ token: String) -> Bool {
        guard let created = validPairingTokens[token] else { return false }
        if ContinuousClock.now - created > Self.tokenTTL {
            validPairingTokens.removeValue(forKey: token)
            return false
        }
        return true
    }

    // MARK: - Rate Limiting

    private func isRateLimited(token: String) -> Bool {
        let now = ContinuousClock.now
        let windowDuration = Duration.seconds(1)

        var timestamps = requestTimestamps[token] ?? []
        timestamps = timestamps.filter { now - $0 < windowDuration }
        timestamps.append(now)
        requestTimestamps[token] = timestamps

        return timestamps.count > Constants.RemoteAccess.maxMessagesPerSecond
    }

    // MARK: - Disconnect Detection

    private func startDisconnectChecker() {
        disconnectCheckTask?.cancel()
        disconnectCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Constants.RemoteAccess.heartbeatIntervalNanoseconds)
                guard !Task.isCancelled, let self else { break }
                await self.checkDisconnectedClients()
            }
        }
    }

    private func checkDisconnectedClients() {
        let now = ContinuousClock.now
        // Consider disconnected if no poll for 3x heartbeat interval
        let timeout = Duration.nanoseconds(Constants.RemoteAccess.heartbeatIntervalNanoseconds * 3)
        var disconnected: [String] = []

        for (token, lastTime) in lastPollTime {
            if now - lastTime > timeout {
                disconnected.append(token)
            }
        }

        for token in disconnected {
            authenticatedTokens.remove(token)
            // Keep pendingEvents for persisted token so re-pair is seamless
            if token != persistedToken {
                pendingEvents.removeValue(forKey: token)
            }
            lastPollTime.removeValue(forKey: token)
            requestTimestamps.removeValue(forKey: token)
            tokenModes.removeValue(forKey: token)
        }

        if !disconnected.isEmpty {
            let count = authenticatedTokens.count
            Task { await onConnectionCountChanged?(count) }
        }
    }

    // MARK: - Sanitization

    /// Only allow URL-safe base64 chars + UUID chars for injected values
    private static func sanitizeForJS(_ value: String) -> String {
        value.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    // MARK: - Broadcasting

    func broadcast(_ message: RemoteMessage) async {
        for token in authenticatedTokens {
            // WebSocket clients: push directly
            if let wsConn = wsConnections[token] {
                let isLAN = tokenModes[token] == true
                wsSendMessage(message, to: wsConn, isLAN: isLAN, key: pairingKey)
                continue
            }

            // HTTP polling clients: queue for next poll
            var queue = pendingEvents[token] ?? []
            queue.append(message)
            if queue.count > Constants.RemoteAccess.maxPendingEventsPerToken {
                queue = Array(queue.suffix(Constants.RemoteAccess.maxPendingEventsPerToken))
            }
            pendingEvents[token] = queue
        }
    }

    // MARK: - Connection Handling

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            Task { @MainActor in
                DiagnosticLogger.shared.log(.info, "Remote access server ready", source: "RemoteAccessServer")
            }
        case .failed(let error):
            guard !Self.isAddressInUseError(error) else { return }
            Task { @MainActor in
                DiagnosticLogger.shared.log(.error, "Remote access listener failed", context: error.localizedDescription, source: "RemoteAccessServer")
            }
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { await self.readHTTPRequest(connection: connection) }
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    // MARK: - HTTP Request Reading

    private func readHTTPRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Constants.RemoteAccess.httpRequestBufferSize) { [weak self] data, _, _, error in
            guard let self else { return }
            Task {
                guard error == nil, let data else {
                    connection.cancel()
                    return
                }

                let request = String(data: data, encoding: .utf8) ?? ""

                // Check if we need to read more data (body not yet received)
                if let contentLength = RemoteAccessServer.parseContentLength(from: request) {
                    // Reject oversized requests
                    if contentLength > RemoteAccessServer.maxContentLength {
                        await self.sendHTTP(connection: connection, status: "413 Payload Too Large", body: "Request body too large")
                        return
                    }

                    if let headerEndRange = request.range(of: "\r\n\r\n") {
                        let headerByteCount = request[request.startIndex..<headerEndRange.upperBound].utf8.count
                        let bodyBytesReceived = data.count - headerByteCount
                        let remaining = contentLength - bodyBytesReceived

                        if remaining > 0 {
                            // Need to read the rest of the body
                            await self.readRemainingBody(
                                connection: connection,
                                headerData: data,
                                request: request,
                                remaining: remaining
                            )
                            return
                        }
                    }
                }

                await self.routeRequest(request, body: data, connection: connection)
            }
        }
    }

    private static func parseContentLength(from request: String) -> Int? {
        for line in request.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value)
            }
        }
        return nil
    }

    private func readRemainingBody(connection: NWConnection, headerData: Data, request: String, remaining: Int) {
        connection.receive(minimumIncompleteLength: remaining, maximumLength: remaining) { [weak self] data, _, _, error in
            guard let self else { return }
            Task {
                guard error == nil, let bodyData = data else {
                    connection.cancel()
                    return
                }

                var fullData = headerData
                fullData.append(bodyData)
                await self.routeRequest(request, body: fullData, connection: connection)
            }
        }
    }

    // MARK: - HTTP Router

    private func routeRequest(_ request: String, body: Data, connection: NWConnection) {
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        let method = parts.first ?? ""
        let path = parts.count > 1 ? parts[1] : "/"

        // Parse query params from path
        let pathComponents = path.components(separatedBy: "?")
        let basePath = pathComponents.first ?? "/"
        let queryString = pathComponents.count > 1 ? pathComponents[1] : ""
        let params = parseQuery(queryString)

        switch (method, basePath) {
        case ("GET", "/"):
            serveHTML(params: params, connection: connection)

        case ("GET", "/pair"):
            handlePair(params: params, connection: connection)

        case ("GET", "/poll"):
            handlePoll(params: params, connection: connection)

        case ("POST", "/input"):
            handleInput(params: params, request: request, body: body, connection: connection)

        case ("POST", "/action"):
            handleAction(params: params, request: request, body: body, connection: connection)

        case ("OPTIONS", _):
            sendJSON(connection: connection, status: "204 No Content", json: "")

        default:
            sendHTTP(connection: connection, status: "404 Not Found", body: "Not Found")
        }
    }

    private func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 {
                result[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        return result
    }

    // MARK: - Routes

    private func serveHTML(params: [String: String], connection: NWConnection) {
        // Inject query params into HTML so the JS can read them even if fragment is lost
        var html = MobileWebClient.html
        if let key = params["k"], let token = params["t"] {
            let safeKey = Self.sanitizeForJS(key)
            let safeToken = Self.sanitizeForJS(token)
            let safeMode = Self.sanitizeForJS(params["m"] ?? "")
            let injection = "<script>window.PAIRING={k:'\(safeKey)',t:'\(safeToken)',m:'\(safeMode)'};</script>"
            html = html.replacingOccurrences(of: "<script>", with: injection + "<script>", options: [], range: html.range(of: "<script>"))
        }
        let body = Data(html.utf8)
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\n\r\n"
        var responseData = Data(headers.utf8)
        responseData.append(body)
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func handlePair(params: [String: String], connection: NWConnection) {
        guard let token = params["t"] else {
            sendJSON(connection: connection, status: "403 Forbidden", json: #"{"error":"invalid_token"}"#)
            return
        }

        // Rate limit pairing attempts to prevent brute-force
        if isRateLimited(token: token) {
            sendJSON(connection: connection, status: "429 Too Many Requests", json: #"{"error":"rate_limited"}"#)
            return
        }

        // Already authenticated, valid pairing token, or persisted token — allow re-pair
        guard authenticatedTokens.contains(token) || isValidPairingToken(token) || token == persistedToken else {
            sendJSON(connection: connection, status: "403 Forbidden", json: #"{"error":"invalid_token"}"#)
            return
        }

        // Enforce connection limit (skip if already authenticated — re-pair)
        if !authenticatedTokens.contains(token),
           authenticatedTokens.count >= Constants.RemoteAccess.maxConcurrentConnections {
            sendJSON(connection: connection, status: "429 Too Many Requests", json: #"{"error":"max_connections"}"#)
            return
        }

        authenticatedTokens.insert(token)
        pendingEvents[token] = []
        tokenModes[token] = (params["m"] == "lan")
        let count = authenticatedTokens.count
        Task { await onConnectionCountChanged?(count) }

        sendJSON(connection: connection, status: "200 OK", json: #"{"status":"paired"}"#)
    }

    private func handlePoll(params: [String: String], connection: NWConnection) {
        guard let token = params["t"],
              authenticatedTokens.contains(token) else {
            sendJSON(connection: connection, status: "403 Forbidden", json: #"{"error":"not_authenticated"}"#)
            return
        }

        // Track last poll time for disconnect detection
        lastPollTime[token] = ContinuousClock.now

        // Drain pending events
        let events = pendingEvents[token] ?? []
        pendingEvents[token] = []

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if tokenModes[token] == true {
            // LAN mode: send events as plain JSON array (no encryption)
            var jsonEvents: [String] = []
            for event in events {
                if let jsonData = try? encoder.encode(event) {
                    jsonEvents.append(jsonData.base64EncodedString())
                }
            }
            let jsonArray = "[" + jsonEvents.map { #""\#($0)""# }.joined(separator: ",") + "]"
            sendJSON(connection: connection, status: "200 OK", json: jsonArray)
        } else {
            // Tunnel mode: encrypt events with AES-256-GCM
            guard let key = pairingKey else {
                sendJSON(connection: connection, status: "500 Internal Server Error", json: #"{"error":"no_key"}"#)
                return
            }
            var encryptedEvents: [String] = []
            for event in events {
                if let jsonData = try? encoder.encode(event),
                   let encrypted = try? RemoteAccessEncryption.encrypt(jsonData, using: key) {
                    encryptedEvents.append(encrypted.base64EncodedString())
                }
            }
            let jsonArray = "[" + encryptedEvents.map { #""\#($0)""# }.joined(separator: ",") + "]"
            sendJSON(connection: connection, status: "200 OK", json: jsonArray)
        }
    }

    private func handleInput(params: [String: String], request: String, body: Data, connection: NWConnection) {
        // Authenticate: require valid token
        guard let token = params["t"],
              authenticatedTokens.contains(token) else {
            sendJSON(connection: connection, status: "403 Forbidden", json: #"{"error":"not_authenticated"}"#)
            return
        }

        // Rate limit
        if isRateLimited(token: token) {
            sendJSON(connection: connection, status: "429 Too Many Requests", json: #"{"error":"rate_limited"}"#)
            return
        }

        guard let httpBody = extractHTTPBody(from: request, fullData: body) else {
            sendJSON(connection: connection, status: "400 Bad Request", json: #"{"error":"bad_request"}"#)
            return
        }

        do {
            let messageData: Data
            if tokenModes[token] == true {
                // LAN mode: plaintext JSON (Web Crypto API unavailable over plain HTTP)
                messageData = httpBody
            } else {
                // Tunnel mode: decrypt AES-256-GCM
                guard let key = pairingKey else {
                    sendJSON(connection: connection, status: "400 Bad Request", json: #"{"error":"bad_request"}"#)
                    return
                }
                messageData = try RemoteAccessEncryption.decrypt(httpBody, using: key)
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let message = try decoder.decode(RemoteMessage.self, from: messageData)
            Task { await onMessageReceived?(message) }
            sendJSON(connection: connection, status: "200 OK", json: #"{"status":"ok"}"#)
        } catch {
            sendJSON(connection: connection, status: "400 Bad Request", json: #"{"error":"decrypt_failed"}"#)
        }
    }

    private func handleAction(params: [String: String], request: String, body: Data, connection: NWConnection) {
        // Same as handleInput — both go through onMessageReceived
        handleInput(params: params, request: request, body: body, connection: connection)
    }

    // MARK: - WebSocket

    private func handleWSListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            Task { @MainActor in
                DiagnosticLogger.shared.log(.info, "WebSocket server ready", source: "RemoteAccessServer")
            }
        case .failed(let error):
            guard !Self.isAddressInUseError(error) else { return }
            Task { @MainActor in
                DiagnosticLogger.shared.log(.error, "WebSocket listener failed", context: error.localizedDescription, source: "RemoteAccessServer")
            }
        default:
            break
        }
    }

    private func handleNewWSConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { await self.wsReadMessage(connection: connection) }
            case .failed, .cancelled:
                Task { await self.wsConnectionClosed(connection: connection) }
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func wsReadMessage(connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            Task {
                if error != nil {
                    await self.wsConnectionClosed(connection: connection)
                    return
                }

                guard let data, !data.isEmpty else {
                    // Keep reading
                    await self.wsReadMessage(connection: connection)
                    return
                }

                await self.handleWSMessage(data: data, connection: connection)
                await self.wsReadMessage(connection: connection)
            }
        }
    }

    private func handleWSMessage(data: Data, connection: NWConnection) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let message = try? decoder.decode(RemoteMessage.self, from: data) else {
            return
        }

        switch message.type {
        case .sendInput, .sendAction:
            // Check if this connection is authenticated
            guard let token = wsConnectionToken(for: connection) else {
                // First message must be a pair request
                return
            }
            if isRateLimited(token: token) { return }
            Task { await onMessageReceived?(message) }

        case .heartbeat:
            if let token = wsConnectionToken(for: connection) {
                lastPollTime[token] = ContinuousClock.now
            }

        case .pair:
            // Client is pairing: payload contains token
            if let pairData = try? decoder.decode(PairingPayload.self, from: message.payload) {
                wsHandlePair(token: pairData.token, mode: pairData.mode, connection: connection)
            }

        case .sessionList:
            break

        default:
            break
        }
    }

    private func wsHandlePair(token: String, mode: String?, connection: NWConnection) {
        guard authenticatedTokens.contains(token) || isValidPairingToken(token) || token == persistedToken else {
            wsSendJSON(connection: connection, json: #"{"error":"invalid_token"}"#)
            return
        }

        if !authenticatedTokens.contains(token),
           authenticatedTokens.count >= Constants.RemoteAccess.maxConcurrentConnections {
            wsSendJSON(connection: connection, json: #"{"error":"max_connections"}"#)
            return
        }

        authenticatedTokens.insert(token)
        tokenModes[token] = (mode == "lan")
        lastPollTime[token] = ContinuousClock.now

        // Store WebSocket connection for push delivery
        wsConnections[token] = connection

        let count = authenticatedTokens.count
        Task {
            await onConnectionCountChanged?(count)
            await MainActor.run {
                DiagnosticLogger.shared.log(.info, "WebSocket client paired", context: "mode=\(mode ?? "unknown"), total=\(count)", source: "RemoteAccessServer")
            }
        }

        wsSendJSON(connection: connection, json: #"{"status":"paired"}"#)
    }

    private func wsConnectionToken(for connection: NWConnection) -> String? {
        for (token, conn) in wsConnections where conn === connection {
            return token
        }
        return nil
    }

    private func wsConnectionClosed(connection: NWConnection) {
        guard let token = wsConnectionToken(for: connection) else { return }
        wsConnections.removeValue(forKey: token)
        authenticatedTokens.remove(token)
        if token != persistedToken {
            pendingEvents.removeValue(forKey: token)
        }
        lastPollTime.removeValue(forKey: token)
        requestTimestamps.removeValue(forKey: token)
        tokenModes.removeValue(forKey: token)

        let count = authenticatedTokens.count
        Task { await onConnectionCountChanged?(count) }
    }

    /// Send a JSON string over WebSocket
    private func wsSendJSON(connection: NWConnection, json: String) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
        connection.send(content: Data(json.utf8), contentContext: context, completion: .contentProcessed { _ in })
    }

    /// Send a RemoteMessage to a specific WebSocket connection
    private func wsSendMessage(_ message: RemoteMessage, to connection: NWConnection, isLAN: Bool, key: SymmetricKey?) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let jsonData = try? encoder.encode(message) else { return }

        let sendData: Data
        if isLAN {
            sendData = jsonData
        } else {
            guard let key, let encrypted = try? RemoteAccessEncryption.encrypt(jsonData, using: key) else { return }
            sendData = encrypted
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: isLAN ? .text : .binary)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
        connection.send(content: sendData, contentContext: context, completion: .contentProcessed { _ in })
    }

    // MARK: - HTTP Helpers

    private static let corsHeaders = "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n"

    private func sendHTTP(connection: NWConnection, status: String, body: String) {
        let bodyData = Data(body.utf8)
        let headers = "HTTP/1.1 \(status)\r\n\(Self.corsHeaders)Content-Type: text/plain\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendJSON(connection: NWConnection, status: String, json: String) {
        let bodyData = Data(json.utf8)
        let headers = "HTTP/1.1 \(status)\r\n\(Self.corsHeaders)Content-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func extractHTTPBody(from request: String, fullData: Data) -> Data? {
        // Find the double CRLF that separates headers from body
        guard let headerEnd = request.range(of: "\r\n\r\n") else { return nil }
        let headerByteCount = request[request.startIndex..<headerEnd.upperBound].utf8.count
        guard fullData.count > headerByteCount else { return nil }
        let bodyBytes = fullData.subdata(in: headerByteCount..<fullData.count)
        // Body is base64-encoded encrypted data — trim whitespace before decoding
        let bodyString = (String(data: bodyBytes, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bodyString.isEmpty else { return nil }
        guard let decoded = Data(base64Encoded: bodyString) else {
            return bodyBytes
        }
        return decoded
    }
}
