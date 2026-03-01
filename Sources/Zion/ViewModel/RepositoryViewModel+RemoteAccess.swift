import Foundation
import CryptoKit
import IOKit.pwr_mgt

extension RepositoryViewModel {

    // MARK: - Enable / Disable

    func enableRemoteAccess() {
        acquireSleepAssertionIfNeeded()
        isMobileAccessEnabled = true
        mobileAccessConnectionState = .starting
        syncRemoteAccessState()

        Task {
            do {
                // 1. Generate or load pairing key (detached to avoid blocking MainActor
                //    if macOS shows a Keychain authorization dialog)
                let key: SymmetricKey = await Task.detached {
                    if let existing = RemoteAccessEncryption.loadPairingKey() {
                        return existing
                    }
                    let newKey = RemoteAccessEncryption.generatePairingKey()
                    RemoteAccessEncryption.savePairingKey(newKey)
                    return newKey
                }.value

                // 2. Start HTTP server (reuse if already running)
                if remoteAccessServer == nil {
                    let server = RemoteAccessServer()
                    remoteAccessServer = server

                    await server.setCallbacks(
                        onMessage: { [weak self] message in
                            await self?.handleRemoteMessage(message)
                        },
                        onConnectionCount: { [weak self] count in
                            await MainActor.run { [weak self] in
                                guard let self else { return }
                                // Skip connection updates during active mode switch
                                if self.isSwitchingMode { return }
                                if count > 0 {
                                    self.mobileAccessConnectionState = .connected(deviceCount: count)
                                    self.ensureRecentProjectsHaveTerminals()
                                    self.sendSessionList()
                                    self.sendAllScreenUpdates()
                                } else {
                                    self.mobileAccessConnectionState = .waitingForPairing
                                }
                                self.syncRemoteAccessState()
                            }
                        }
                    )

                    try await server.start(port: Constants.RemoteAccess.defaultPort, key: key, lanMode: isMobileAccessLANMode)
                }

                // 3. Resolve tunnel URL
                let tunnelURL = try await resolveTunnelURL()
                mobileAccessTunnelURL = tunnelURL

                // 4. Generate pairing token and QR code
                let pairingToken = UUID().uuidString
                await remoteAccessServer?.addPairingToken(pairingToken)

                let keyBase64 = RemoteAccessEncryption.exportKey(key)
                mobileAccessQRImage = QRCodeGenerator.generatePairingQR(
                    tunnelURL: tunnelURL,
                    keyBase64: keyBase64,
                    pairingToken: pairingToken,
                    lanMode: isMobileAccessLANMode,
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

    /// Resolve tunnel URL: reuse existing Cloudflare tunnel if alive, or use LAN IP
    private func resolveTunnelURL() async throws -> String {
        if isMobileAccessLANMode {
            // LAN mode: keep tunnel alive for quick switch-back, just use local IP
            let localIP = Self.getLocalIPAddress() ?? "localhost"
            return "http://\(localIP):\(Constants.RemoteAccess.defaultPort)"
        }

        // Cloudflare mode: reuse tunnel if still alive
        if let tunnel = tunnelManager, await tunnel.isRunning, let url = await tunnel.currentURL {
            return url
        }

        // Need a new tunnel
        await tunnelManager?.stop()
        let tunnel = CloudflareTunnelManager()
        tunnelManager = tunnel
        return try await tunnel.start(localPort: Constants.RemoteAccess.defaultPort)
    }

    func disableRemoteAccess() {
        isMobileAccessEnabled = false
        releaseSleepAssertion()
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
        hasEnsuredRemoteTerminals = false
        PromptDetector.resetDedup()
        syncRemoteAccessState()
    }

    /// Switch between LAN and Cloudflare mode without restarting the HTTP server
    func switchRemoteAccessMode() {
        guard isMobileAccessEnabled, remoteAccessServer != nil else { return }

        // Clear stale QR/URL immediately so the UI doesn't flash old values
        mobileAccessConnectionState = .starting
        mobileAccessQRImage = nil
        mobileAccessTunnelURL = ""
        isSwitchingMode = true
        syncRemoteAccessState()

        Task {
            defer { isSwitchingMode = false }

            do {
                // Disconnect all clients — they need to re-pair with the new URL
                await remoteAccessServer?.disconnectAll()

                // Update server's LAN mode flag (no restart needed)
                await remoteAccessServer?.setLANMode(isMobileAccessLANMode)

                // Resolve new tunnel URL with timeout so .starting doesn't persist forever
                let tunnelURL = try await withThrowingTaskGroup(of: String.self) { group in
                    group.addTask { try await self.resolveTunnelURL() }
                    group.addTask {
                        try await Task.sleep(nanoseconds: Constants.RemoteAccess.tunnelURLTimeoutNanoseconds)
                        throw CancellationError()
                    }
                    guard let result = try await group.next() else {
                        throw CancellationError()
                    }
                    group.cancelAll()
                    return result
                }
                mobileAccessTunnelURL = tunnelURL

                // Regenerate QR with new URL but reuse key
                guard let key = RemoteAccessEncryption.loadPairingKey() else {
                    mobileAccessConnectionState = .error(L10n("mobile.access.error.keyNotFound"))
                    syncRemoteAccessState()
                    return
                }
                let pairingToken = UUID().uuidString
                await remoteAccessServer?.addPairingToken(pairingToken)

                let keyBase64 = RemoteAccessEncryption.exportKey(key)
                mobileAccessQRImage = QRCodeGenerator.generatePairingQR(
                    tunnelURL: tunnelURL,
                    keyBase64: keyBase64,
                    pairingToken: pairingToken,
                    lanMode: isMobileAccessLANMode,
                    size: Constants.RemoteAccess.qrCodeSize
                )

                mobileAccessConnectionState = .waitingForPairing
                syncRemoteAccessState()

            } catch is CancellationError {
                mobileAccessConnectionState = .error(L10n("mobile.access.error.timeout"))
                syncRemoteAccessState()
            } catch {
                mobileAccessConnectionState = .error(error.localizedDescription)
                syncRemoteAccessState()
            }
        }
    }

    func regeneratePairingKey() {
        RemoteAccessEncryption.deletePairingKey()
        pairedDevices.removeAll()
        if isMobileAccessEnabled {
            disableRemoteAccess()
            enableRemoteAccess()
        }
    }

    // MARK: - Auto-Open Terminals for Recent Projects

    /// Ensures each recent project has at least one terminal session so they all
    /// appear in the mobile project nav on first connect.
    private func ensureRecentProjectsHaveTerminals() {
        guard !hasEnsuredRemoteTerminals else { return }
        hasEnsuredRemoteTerminals = true

        let originalURL = repositoryURL
        let reposWithTerminals = Set(
            [repositoryURL].compactMap { $0 } + Array(backgroundRepoStates.keys)
        )

        let missing = recentRepositories.filter { url in
            !reposWithTerminals.contains(url)
                && FileManager.default.fileExists(atPath: url.path)
        }

        guard !missing.isEmpty else { return }

        // Snapshot recents order — openRepository moves repos to front
        let savedOrder = recentRepositories

        for url in missing {
            openRepository(url)
        }

        // Switch back to the original repo
        if let originalURL {
            openRepository(originalURL)
        }

        // Restore original order
        recentRepositories = savedOrder
        if let encoded = try? JSONEncoder().encode(savedOrder) {
            recentReposData = encoded
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
        // Send the text content first, then the Enter keystroke after a short delay
        // so the TUI processes the text before receiving the submit key
        let trimmed = text.replacingOccurrences(of: "\r", with: "")
                         .replacingOccurrences(of: "\n", with: "")

        let needsEnter = text.hasSuffix("\r") || text.hasSuffix("\n")

        if !trimmed.isEmpty, let textData = trimmed.data(using: .utf8) {
            callback(textData)
        }

        // Send Enter as a separate write after a delay (CR = what real keyboard sends)
        // The 50ms gap lets TUI apps (Claude, Gemini, Aider) process the text input
        // before the submit keystroke arrives, preventing "paste with newline" behavior
        if needsEnter {
            Task {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if let enterData = "\r".data(using: .utf8) {
                    callback(enterData)
                }
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
        case .ctrlc:
            inputData = Data([0x03])
        case .ctrld:
            inputData = Data([0x04])
        case .escape:
            inputData = Data([0x1B])
        case .tab:
            inputData = Data([0x09])
        case .arrowUp:
            inputData = Data([0x1B, 0x5B, 0x41]) // ESC[A
        case .arrowDown:
            inputData = Data([0x1B, 0x5B, 0x42]) // ESC[B
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
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let activeRepoName = repositoryURL?.lastPathComponent ?? ""

        func sanitizePath(_ path: String) -> String {
            path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        }

        // Active repo sessions
        var allSessions: [SessionInfo] = terminalSessions.map { session in
            SessionInfo(
                id: session.id,
                label: session.label,
                title: session.title,
                isAlive: session.isAlive,
                workingDirectory: sanitizePath(session.workingDirectory.path),
                repoName: activeRepoName
            )
        }

        // Background repo sessions
        for (url, state) in backgroundRepoStates {
            let repoName = url.lastPathComponent
            let bgSessions: [SessionInfo] = state.terminalTabs.flatMap { $0.allSessions() }.map { session in
                SessionInfo(
                    id: session.id,
                    label: session.label,
                    title: session.title,
                    isAlive: session.isAlive,
                    workingDirectory: sanitizePath(session.workingDirectory.path),
                    repoName: repoName
                )
            }
            allSessions.append(contentsOf: bgSessions)
        }

        return SessionListPayload(sessions: allSessions)
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
        shared.isLANMode = isMobileAccessLANMode
    }

    // MARK: - Helpers

    static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let sa = ptr.pointee.ifa_addr.pointee
            guard sa.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            // Prefer en0 (Wi-Fi) or en1 (Ethernet)
            guard name.hasPrefix("en") else { continue }
            var addr = ptr.pointee.ifa_addr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(&addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(decoding: hostname.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
                if !ip.hasPrefix("127.") {
                    address = ip
                    break
                }
            }
        }
        return address
    }

    // MARK: - Sleep Assertion

    func acquireSleepAssertionIfNeeded() {
        let raw = UserDefaults.standard.string(forKey: "zion.mobileAccess.keepAwakeDuration") ?? "off"
        let duration = KeepAwakeDuration(rawValue: raw) ?? .off

        guard duration != .off else {
            releaseSleepAssertion()
            return
        }

        // Acquire assertion if not already held
        if sleepAssertionID == 0 {
            var assertionID: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Zion Remote Access server is active" as CFString,
                &assertionID
            )
            if result == kIOReturnSuccess {
                sleepAssertionID = assertionID
            }
        }

        // Auto-release after duration (cancel any previous timer first)
        sleepTimerTask?.cancel()
        if let seconds = duration.seconds, seconds > 0 {
            sleepTimerTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                releaseSleepAssertion()
            }
        }
    }

    func releaseSleepAssertion() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        guard sleepAssertionID != 0 else { return }
        IOPMAssertionRelease(sleepAssertionID)
        sleepAssertionID = 0
    }

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
