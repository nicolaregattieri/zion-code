import CryptoKit
import Foundation
import Network

actor RemoteAccessServer {
    private var listener: NWListener?
    private var pairingKey: SymmetricKey?
    private var validPairingTokens: [String: ContinuousClock.Instant] = [:]  // token → creation time
    private var authenticatedTokens: Set<String> = []
    private static let tokenTTL = Duration.seconds(Constants.RemoteAccess.pairingTokenTTLSeconds)
    private var connectionCount: Int = 0
    private var isLANMode: Bool = false

    // Pending events queue per token (consumed on poll)
    private var pendingEvents: [String: [RemoteMessage]] = [:]

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

    // MARK: - Lifecycle

    func start(port: UInt16, key: SymmetricKey, lanMode: Bool = false) throws {
        pairingKey = key
        isLANMode = lanMode

        let parameters = NWParameters.tcp
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
        startDisconnectChecker()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        disconnectCheckTask?.cancel()
        disconnectCheckTask = nil
        authenticatedTokens.removeAll()
        validPairingTokens.removeAll()
        pendingEvents.removeAll()
        requestTimestamps.removeAll()
        lastPollTime.removeAll()
    }

    func addPairingToken(_ token: String) {
        validPairingTokens.removeAll()
        validPairingTokens[token] = ContinuousClock.now
    }

    /// Disconnect all authenticated clients (used when switching modes)
    func disconnectAll() {
        authenticatedTokens.removeAll()
        pendingEvents.removeAll()
        lastPollTime.removeAll()
        requestTimestamps.removeAll()
        let count = 0
        Task { await onConnectionCountChanged?(count) }
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
            pendingEvents.removeValue(forKey: token)
            lastPollTime.removeValue(forKey: token)
            requestTimestamps.removeValue(forKey: token)
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
            var queue = pendingEvents[token] ?? []
            queue.append(message)
            // Keep last N events to prevent memory growth
            if queue.count > Constants.RemoteAccess.maxScreenUpdateLines {
                queue = Array(queue.suffix(Constants.RemoteAccess.maxScreenUpdateLines))
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
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-cache\r\n\r\n"
        var responseData = Data(headers.utf8)
        responseData.append(body)
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Update LAN mode without restarting the server
    func setLANMode(_ enabled: Bool) {
        isLANMode = enabled
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

        // Already authenticated — allow re-pair (e.g., browser refresh)
        guard authenticatedTokens.contains(token) || isValidPairingToken(token) else {
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

        guard let key = pairingKey else {
            sendJSON(connection: connection, status: "500 Internal Server Error", json: #"{"error":"no_key"}"#)
            return
        }

        // Track last poll time for disconnect detection
        lastPollTime[token] = ContinuousClock.now

        // Drain pending events
        let events = pendingEvents[token] ?? []
        pendingEvents[token] = []

        // Encode events (encrypted in tunnel mode, plaintext in LAN mode)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if isLANMode {
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

        guard let key = pairingKey,
              let httpBody = extractHTTPBody(from: request, fullData: body) else {
            sendJSON(connection: connection, status: "400 Bad Request", json: #"{"error":"bad_request"}"#)
            return
        }

        do {
            let messageData: Data
            if isLANMode {
                // LAN mode: body is plain JSON (base64-encoded by extractHTTPBody, or raw)
                messageData = httpBody
            } else {
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

    // MARK: - HTTP Helpers

    private func sendHTTP(connection: NWConnection, status: String, body: String) {
        let bodyData = Data(body.utf8)
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: text/plain\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendJSON(connection: NWConnection, status: String, json: String) {
        let bodyData = Data(json.utf8)
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
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
