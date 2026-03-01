import Foundation

extension RepositoryViewModel {

    // MARK: - Enable / Disable

    func enableRemoteAccess() {
        isMobileAccessEnabled = true
        mobileAccessConnectionState = .starting
        syncRemoteAccessState()

        Task {
            // Clean up any existing server/tunnel before starting fresh
            await remoteAccessServer?.stop()
            remoteAccessServer = nil
            await tunnelManager?.stop()
            tunnelManager = nil

            do {
                // 1. Generate or load pairing key
                let key = RemoteAccessEncryption.loadPairingKey() ?? {
                    let newKey = RemoteAccessEncryption.generatePairingKey()
                    RemoteAccessEncryption.savePairingKey(newKey)
                    return newKey
                }()

                // 2. Start WebSocket server
                let server = RemoteAccessServer()
                remoteAccessServer = server

                await server.setCallbacks(
                    onMessage: { [weak self] message in
                        await self?.handleRemoteMessage(message)
                    },
                    onConnectionCount: { [weak self] count in
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            if count > 0 {
                                self.mobileAccessConnectionState = .connected(deviceCount: count)
                                // Send session list + current screen state so the phone has data immediately
                                self.sendSessionList()
                                self.sendAllScreenUpdates()
                            } else {
                                self.mobileAccessConnectionState = .waitingForPairing
                            }
                            self.syncRemoteAccessState()
                        }
                    }
                )

                try await server.start(port: Constants.RemoteAccess.defaultPort, key: key)

                // 3. Start Cloudflare tunnel
                let tunnel = CloudflareTunnelManager()
                tunnelManager = tunnel
                let tunnelURL = try await tunnel.start(localPort: Constants.RemoteAccess.defaultPort)
                mobileAccessTunnelURL = tunnelURL

                // 4. Generate pairing token and QR code
                let pairingToken = UUID().uuidString
                await server.addPairingToken(pairingToken)

                let keyBase64 = RemoteAccessEncryption.exportKey(key)
                mobileAccessQRImage = QRCodeGenerator.generatePairingQR(
                    tunnelURL: tunnelURL,
                    keyBase64: keyBase64,
                    pairingToken: pairingToken,
                    size: Constants.RemoteAccess.qrCodeSize
                )

                mobileAccessConnectionState = .waitingForPairing
                syncRemoteAccessState()
                startHeartbeat()

            } catch let error as CloudflareTunnelManager.TunnelError where error == .cloudflaredNotFound {
                mobileAccessConnectionState = .error(L10n("mobile.access.cloudflared.notFound"))
                syncRemoteAccessState()
            } catch {
                mobileAccessConnectionState = .error(error.localizedDescription)
                syncRemoteAccessState()
                logger.log(.error, "Failed to start remote access", context: error.localizedDescription, source: #function)
            }
        }
    }

    func disableRemoteAccess() {
        isMobileAccessEnabled = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        screenUpdateDebounceTasks.values.forEach { $0.cancel() }
        screenUpdateDebounceTasks.removeAll()
        screenUpdateThrottleDeadlines.removeAll()

        Task {
            await remoteAccessServer?.stop()
            remoteAccessServer = nil
            await tunnelManager?.stop()
            tunnelManager = nil
        }

        mobileAccessConnectionState = .disabled
        mobileAccessTunnelURL = ""
        mobileAccessQRImage = nil
        terminalOutputBuffers.removeAll()
        PromptDetector.resetDedup()
        syncRemoteAccessState()
    }

    func regeneratePairingKey() {
        RemoteAccessEncryption.deletePairingKey()
        pairedDevices.removeAll()
        if isMobileAccessEnabled {
            disableRemoteAccess()
            enableRemoteAccess()
        }
    }

    // MARK: - Terminal Output Bridge

    func notifyTerminalOutput(sessionID: UUID, data: Data) {
        guard isMobileAccessEnabled else { return }

        // Convert to string, strip ANSI codes, append to ring buffer
        guard let text = String(data: data, encoding: .utf8) else { return }
        let stripped = stripANSI(text)
        guard !stripped.isEmpty else { return }

        let lines = stripped.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var buffer = terminalOutputBuffers[sessionID] ?? []
        buffer.append(contentsOf: lines)
        if buffer.count > Constants.RemoteAccess.maxScreenUpdateLines {
            buffer = Array(buffer.suffix(Constants.RemoteAccess.maxScreenUpdateLines))
        }
        terminalOutputBuffers[sessionID] = buffer

        // Detect prompts
        if let detection = PromptDetector.detect(in: stripped) {
            sendPromptDetected(sessionID: sessionID, detection: detection)
        }

        // Throttle screen updates (fires immediately, then coalesces)
        throttleScreenUpdate(for: sessionID)
    }

    // MARK: - Remote Message Handling

    private func handleRemoteMessage(_ message: RemoteMessage) async {
        await MainActor.run { [weak self] in
            guard let self else { return }

            switch message.type {
            case .sendInput:
                guard let sessionID = message.sessionID else { return }
                if let payload = try? JSONDecoder().decode(SendInputPayload.self, from: message.payload) {
                    self.handleRemoteInput(sessionID: sessionID, text: payload.text)
                }

            case .sendAction:
                guard let sessionID = message.sessionID else { return }
                if let payload = try? JSONDecoder().decode(SendActionPayload.self, from: message.payload) {
                    self.handleRemoteAction(sessionID: sessionID, action: payload.action)
                }

            case .sessionList:
                self.sendSessionList()

            case .heartbeat:
                break // Just keeps connection alive

            default:
                break
            }
        }
    }

    private func handleRemoteInput(sessionID: UUID, text: String) {
        guard let callback = terminalSendCallbacks[sessionID] else { return }

        // Split text from trailing CR/LF so TUI apps don't treat it as pasted text
        // Send the text content first, then the Enter keystroke separately
        let trimmed = text.replacingOccurrences(of: "\r", with: "")
                         .replacingOccurrences(of: "\n", with: "")

        if !trimmed.isEmpty, let textData = trimmed.data(using: .utf8) {
            callback(textData)
        }

        // Send Enter as a separate write (CR = what real keyboard sends)
        if text.hasSuffix("\r") || text.hasSuffix("\n") {
            if let enterData = "\r".data(using: .utf8) {
                callback(enterData)
            }
        }
    }

    func handleRemoteAction(sessionID: UUID, action: RemoteAction) {
        guard let callback = terminalSendCallbacks[sessionID] else { return }

        let inputData: Data?
        switch action {
        case .approve:
            inputData = "y\r".data(using: .utf8)
        case .deny:
            inputData = "n\r".data(using: .utf8)
        case .abort:
            inputData = Data([0x03]) // Ctrl+C
        }

        if let data = inputData {
            callback(data)
        }
    }

    // MARK: - Sending Messages

    private func sendAllScreenUpdates() {
        for sessionID in terminalOutputBuffers.keys {
            Task { await sendScreenUpdate(for: sessionID) }
        }
    }

    private func sendSessionList() {
        let payload = buildSessionListPayload()
        guard let payloadData = try? JSONEncoder().encode(payload) else { return }

        let message = RemoteMessage(
            type: .sessionList,
            sessionID: nil,
            payload: payloadData,
            timestamp: Date()
        )

        Task {
            await remoteAccessServer?.broadcast(message)
        }
    }

    private func throttleScreenUpdate(for sessionID: UUID) {
        let now = ContinuousClock.now
        let cooldown = Duration.nanoseconds(Constants.RemoteAccess.screenUpdateDebounceNanoseconds)

        // If we're past the throttle deadline, fire immediately (leading edge)
        if let deadline = screenUpdateThrottleDeadlines[sessionID], now < deadline {
            // Still in cooldown — schedule a trailing-edge fire (cancel previous pending)
            screenUpdateDebounceTasks[sessionID]?.cancel()
            screenUpdateDebounceTasks[sessionID] = Task {
                try? await Task.sleep(until: deadline, clock: .continuous)
                guard !Task.isCancelled else { return }
                screenUpdateThrottleDeadlines[sessionID] = ContinuousClock.now + cooldown
                await sendScreenUpdate(for: sessionID)
            }
        } else {
            // No active cooldown — fire immediately and set deadline
            screenUpdateThrottleDeadlines[sessionID] = now + cooldown
            screenUpdateDebounceTasks[sessionID]?.cancel()
            screenUpdateDebounceTasks[sessionID] = nil
            Task { await sendScreenUpdate(for: sessionID) }
        }
    }

    private func sendScreenUpdate(for sessionID: UUID) async {
        let payload = buildScreenUpdate(for: sessionID)
        guard let payloadData = try? JSONEncoder().encode(payload) else { return }

        let message = RemoteMessage(
            type: .screenUpdate,
            sessionID: sessionID,
            payload: payloadData,
            timestamp: Date()
        )

        await remoteAccessServer?.broadcast(message)
    }

    private func sendPromptDetected(sessionID: UUID, detection: PromptDetector.Detection) {
        let repoName = repositoryURL?.lastPathComponent ?? ""

        // Send via ntfy push if phone is not connected
        let isPhoneConnected: Bool
        if case .connected = mobileAccessConnectionState {
            isPhoneConnected = true
        } else {
            isPhoneConnected = false
        }

        if !isPhoneConnected {
            Task {
                await ntfyClient.sendIfEnabled(
                    event: .terminalPromptDetected,
                    title: L10n("ntfy.event.terminalPromptDetected"),
                    body: detection.promptText,
                    repoName: repoName
                )
            }
        }

        // Also send via WebSocket
        let promptPayload = ScreenUpdatePayload(
            sessionID: sessionID,
            lines: terminalOutputBuffers[sessionID] ?? [],
            totalRows: 0,
            totalCols: 0,
            hasPrompt: true,
            promptText: detection.promptText
        )
        guard let payloadData = try? JSONEncoder().encode(promptPayload) else { return }

        let message = RemoteMessage(
            type: .promptDetected,
            sessionID: sessionID,
            payload: payloadData,
            timestamp: Date()
        )

        Task {
            await remoteAccessServer?.broadcast(message)
        }
    }

    // MARK: - Payload Builders

    func buildSessionListPayload() -> SessionListPayload {
        let sessions = terminalSessions.map { session in
            SessionInfo(
                id: session.id,
                label: session.label,
                title: session.title,
                isAlive: session.isAlive,
                workingDirectory: session.workingDirectory.path
            )
        }
        return SessionListPayload(sessions: sessions)
    }

    func buildScreenUpdate(for sessionID: UUID) -> ScreenUpdatePayload {
        // Read directly from the terminal's rendered buffer (properly decoded, no ANSI codes)
        let lines: [String]
        if let reader = terminalScreenReaders[sessionID] {
            lines = reader()
        } else {
            lines = terminalOutputBuffers[sessionID] ?? []
        }
        return ScreenUpdatePayload(
            sessionID: sessionID,
            lines: Array(lines.suffix(Constants.RemoteAccess.maxScreenUpdateLines)),
            totalRows: 0,
            totalCols: 0,
            hasPrompt: false,
            promptText: nil
        )
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Constants.RemoteAccess.heartbeatIntervalNanoseconds)
                if Task.isCancelled { break }

                let message = RemoteMessage(
                    type: .heartbeat,
                    sessionID: nil,
                    payload: Data(),
                    timestamp: Date()
                )
                await remoteAccessServer?.broadcast(message)
            }
        }
    }

    // MARK: - State Sync

    private func syncRemoteAccessState() {
        let shared = RemoteAccessState.shared
        shared.connectionState = mobileAccessConnectionState
        shared.tunnelURL = mobileAccessTunnelURL
        shared.qrImage = mobileAccessQRImage
    }

    // MARK: - Helpers

    private func stripANSI(_ text: String) -> String {
        // Comprehensive ANSI/VT escape stripping:
        // 1. CSI sequences: ESC [ (with optional ? / >) params letter  (colors, cursor, DEC modes)
        // 2. OSC sequences: ESC ] ... BEL or ESC ] ... ST            (window title, hyperlinks)
        // 3. Character set: ESC ( digit/letter                        (G0/G1 charset)
        // 4. Simple escapes: ESC followed by single char              (save/restore cursor, etc.)
        let pattern = #"\x1B(?:\[[0-9;?]*[ -/]*[A-Z@a-z]|\][^\x07\x1B]*(?:\x07|\x1B\\)?|\([0-9A-B]|[^\[\](])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
    }
}

// MARK: - RemoteAccessServer callback helpers

extension RemoteAccessServer {
    func setCallbacks(
        onMessage: @escaping @Sendable (RemoteMessage) async -> Void,
        onConnectionCount: @escaping @Sendable (Int) async -> Void
    ) {
        self.onMessageReceived = onMessage
        self.onConnectionCountChanged = onConnectionCount
    }
}
