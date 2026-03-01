import Foundation

extension RepositoryViewModel {

    // MARK: - Enable / Disable

    func enableRemoteAccess() {
        isMobileAccessEnabled = true
        mobileAccessConnectionState = .starting
        syncRemoteAccessState()

        Task {
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
                isMobileAccessEnabled = false
                syncRemoteAccessState()
            } catch {
                mobileAccessConnectionState = .error(error.localizedDescription)
                isMobileAccessEnabled = false
                syncRemoteAccessState()
                logger.log(.error, "Failed to start remote access", context: error.localizedDescription, source: #function)
            }
        }
    }

    func disableRemoteAccess() {
        isMobileAccessEnabled = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        screenUpdateDebounceTask?.cancel()
        screenUpdateDebounceTask = nil

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

        // Debounce screen updates
        debounceScreenUpdate(for: sessionID)
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
        guard let callback = terminalSendCallbacks[sessionID],
              let data = text.data(using: .utf8) else { return }
        callback(data)
    }

    func handleRemoteAction(sessionID: UUID, action: RemoteAction) {
        guard let callback = terminalSendCallbacks[sessionID] else { return }

        let inputData: Data?
        switch action {
        case .approve:
            inputData = "y\n".data(using: .utf8)
        case .deny:
            inputData = "n\n".data(using: .utf8)
        case .abort:
            inputData = Data([0x03]) // Ctrl+C
        }

        if let data = inputData {
            callback(data)
        }
    }

    // MARK: - Sending Messages

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

    private func debounceScreenUpdate(for sessionID: UUID) {
        screenUpdateDebounceTask?.cancel()
        screenUpdateDebounceTask = Task {
            try? await Task.sleep(nanoseconds: Constants.RemoteAccess.screenUpdateDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await sendScreenUpdate(for: sessionID)
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
        let lines = terminalOutputBuffers[sessionID] ?? []
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
        guard let regex = try? NSRegularExpression(pattern: #"\x1B\[[0-9;]*[a-zA-Z]"#) else {
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
