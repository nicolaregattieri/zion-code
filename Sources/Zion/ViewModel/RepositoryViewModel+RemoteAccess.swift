import AppKit
import Foundation
import CryptoKit
import IOKit.pwr_mgt
@preconcurrency import SwiftTerm

extension RepositoryViewModel {

    // MARK: - Enable / Disable

    func enableRemoteAccess() {
        acquireSleepAssertionIfNeeded()
        isMobileAccessEnabled = true
        observeSystemWake()
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
                            // Fetch per-mode counts from server
                            let lanCount = await server.lanConnectedCount
                            let tunnelCount = await server.tunnelConnectedCount
                            await MainActor.run { [weak self] in
                                guard let self else { return }
                                let shared = RemoteAccessState.shared
                                shared.lanConnectedCount = lanCount
                                shared.tunnelConnectedCount = tunnelCount
                                if count > 0 {
                                    self.mobileAccessConnectionState = .connected(deviceCount: count)
                                    self.ensureRecentProjectsHaveTerminals()
                                } else {
                                    self.mobileAccessConnectionState = .waitingForPairing
                                }
                                self.syncRemoteAccessState()
                            }
                        }
                    )

                    try await server.start(port: Constants.RemoteAccess.defaultPort, key: key)
                }

                // 3. Load or create persisted pairing token
                let pairingToken = await loadOrCreatePairingToken()
                await remoteAccessServer?.setPersistedToken(pairingToken)
                await remoteAccessServer?.addPairingToken(pairingToken)

                let keyBase64 = RemoteAccessEncryption.exportKey(key)

                // 4. Generate LAN QR immediately (only needs local IP)
                let localIP = Self.getLocalIPAddress() ?? "localhost"
                let lanURL = "http://\(localIP):\(Constants.RemoteAccess.defaultPort)"
                mobileAccessLanURL = lanURL
                mobileAccessLanQRImage = QRCodeGenerator.generatePairingQR(
                    tunnelURL: lanURL,
                    keyBase64: keyBase64,
                    pairingToken: pairingToken,
                    lanMode: true,
                    size: Constants.RemoteAccess.qrCodeSize
                )

                mobileAccessConnectionState = .waitingForPairing
                syncRemoteAccessState()
                startHeartbeat()

                // 5. Start tunnel in background (non-blocking, LAN works independently)
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        // Check cloudflared availability
                        let isInstalled = await CloudflareTunnelManager.isCloudflaredInstalled()
                        guard isInstalled else {
                            await MainActor.run {
                                let shared = RemoteAccessState.shared
                                shared.isCloudflaredMissing = true
                            }
                            return
                        }

                        // Reuse tunnel if still alive
                        let tunnelURL: String
                        if let tunnel = await self.tunnelManager, await tunnel.isRunning, let url = await tunnel.currentURL {
                            tunnelURL = url
                        } else {
                            await self.tunnelManager?.stop()
                            let tunnel = CloudflareTunnelManager()
                            await MainActor.run { self.tunnelManager = tunnel }
                            tunnelURL = try await tunnel.start(localPort: Constants.RemoteAccess.defaultPort)
                        }

                        await MainActor.run {
                            self.mobileAccessTunnelURL = tunnelURL
                            self.mobileAccessTunnelQRImage = QRCodeGenerator.generatePairingQR(
                                tunnelURL: tunnelURL,
                                keyBase64: keyBase64,
                                pairingToken: pairingToken,
                                lanMode: false,
                                size: Constants.RemoteAccess.qrCodeSize
                            )
                            self.isTunnelReady = true
                            self.syncRemoteAccessState()
                        }
                    } catch {
                        await MainActor.run {
                            self.logger.log(.warn, "Tunnel failed, LAN still active", context: error.localizedDescription, source: #function)
                        }
                    }
                }

            } catch {
                mobileAccessConnectionState = .error(error.localizedDescription)
                syncRemoteAccessState()
                logger.log(.error, "Failed to start remote access", context: error.localizedDescription, source: #function)
            }
        }
    }

    func disableRemoteAccess() {
        isMobileAccessEnabled = false
        removeSystemWakeObserver()
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
        mobileAccessLanQRImage = nil
        mobileAccessLanURL = ""
        mobileAccessTunnelQRImage = nil
        mobileAccessTunnelURL = ""
        isTunnelReady = false
        terminalOutputBuffers.removeAll()
        terminalLastSentRows.removeAll()
        hasEnsuredRemoteTerminals = false
        PromptDetector.resetDedup()
        syncRemoteAccessState()
    }

    func regeneratePairingKey() {
        RemoteAccessEncryption.deletePairingKey()
        RemoteAccessEncryption.deletePairingToken()
        pairedDevices.removeAll()
        if isMobileAccessEnabled {
            disableRemoteAccess()
            enableRemoteAccess()
        }
    }

    // MARK: - Pairing Token Persistence

    private func loadOrCreatePairingToken() async -> String {
        await Task.detached {
            if let existing = RemoteAccessEncryption.loadPairingToken() {
                return existing
            }
            let newToken = UUID().uuidString
            RemoteAccessEncryption.savePairingToken(newToken)
            return newToken
        }.value
    }

    // MARK: - Auto-Open Terminals for Recent Projects

    /// Ensures each recent project has at least one terminal session so they all
    /// appear in the mobile project nav on first connect.
    /// Opens missing repos silently, then boots headless terminals for any session
    /// whose SwiftUI view hasn't rendered yet (so `terminalForSession` can find them).
    private func ensureRecentProjectsHaveTerminals() {
        // First connect: open repos and boot headless terminals
        if !hasEnsuredRemoteTerminals {
            hasEnsuredRemoteTerminals = true

            let originalURL = repositoryURL
            let reposWithTerminals = Set(
                [repositoryURL].compactMap { $0 } + Array(backgroundRepoStates.keys)
            )

            let missing = recentRepositories.filter { url in
                !reposWithTerminals.contains(url)
                    && FileManager.default.fileExists(atPath: url.path)
            }

            if !missing.isEmpty {
                for url in missing {
                    openRepository(url, silent: true)
                }
                // Switch back to the original repo immediately
                if let originalURL {
                    openRepository(originalURL, silent: true)
                }
            }

            // Boot headless terminals for background sessions whose views haven't rendered
            bootHeadlessTerminals()
        }

        // Always re-send session list and screen snapshots (handles page refresh / re-pair)
        sendSessionList()
        sendAllScreenUpdates()
    }

    /// Creates HeadlessTerminal instances for background repo sessions that don't
    /// have a cached Terminal yet (because SwiftUI hasn't rendered their view).
    private func bootHeadlessTerminals() {
        for (url, state) in backgroundRepoStates {
            for tab in state.terminalTabs {
                for session in tab.allSessions() {
                    // Skip if terminal is already available (view was rendered)
                    if session._cachedView != nil || session._cachedTerminal != nil { continue }

                    let sessionID = session.id
                    let headless = RemoteHeadlessTerminal(
                        sessionID: sessionID,
                        onOutput: { [weak self] sid, data in
                            self?.notifyTerminalOutput(sessionID: sid, data: data)
                        },
                        onEnd: { [weak session] _ in
                            Task { @MainActor in
                                session?.isAlive = false
                            }
                        }
                    )
                    headless.process.startProcess(
                        executable: "/bin/zsh",
                        args: ["-c", "export ZION_TTY=$(tty); exec /bin/zsh -l"],
                        environment: nil,
                        currentDirectory: url.path
                    )
                    session._cachedTerminal = headless.terminal
                    // Keep headless alive by storing on the session bridge
                    session._processBridge = headless
                    session._shellPid = headless.process.shellPid

                    // Bridge input from mobile to headless terminal
                    registerTerminalSendCallback(sessionID: sessionID) { [weak headless] data in
                        headless?.send(data: Array(data)[...])
                    }
                }
            }
        }
    }

    // MARK: - Terminal Output Bridge

    func notifyTerminalOutput(sessionID: UUID, data: Data) {
        guard isMobileAccessEnabled, !data.isEmpty else { return }

        // Mark this session as dirty (has new output since last send)
        terminalOutputBuffers[sessionID] = Data([1])

        // Prompt detection uses stripped text
        if let text = String(data: data, encoding: .utf8) {
            let stripped = stripANSI(text)
            if !stripped.isEmpty, let detection = PromptDetector.detect(in: stripped) {
                sendPromptDetected(sessionID: sessionID, detection: detection)
            }
        }

        // Throttle screen updates (fires immediately, then coalesces)
        throttleScreenUpdate(for: sessionID)
    }

    /// Find the SwiftTerm Terminal instance for a given session ID.
    private func terminalForSession(_ sessionID: UUID) -> SwiftTerm.Terminal? {
        // Check active repo sessions
        for tab in terminalTabs {
            for session in tab.allSessions() where session.id == sessionID {
                return (session._cachedView as? SwiftTerm.TerminalView)?.getTerminal()
                    ?? session._cachedTerminal as? SwiftTerm.Terminal
            }
        }
        // Check background repo sessions
        for (_, state) in backgroundRepoStates {
            for tab in state.terminalTabs {
                for session in tab.allSessions() where session.id == sessionID {
                    return (session._cachedView as? SwiftTerm.TerminalView)?.getTerminal()
                        ?? session._cachedTerminal as? SwiftTerm.Terminal
                }
            }
        }
        return nil
    }

    /// Read the visible terminal screen and serialize as ANSI-formatted text.
    /// Each row includes SGR color/style codes, written as plain lines with \r\n.
    /// The client uses scrollTo(0) + eraseDisplay before writing, so old snapshots
    /// scroll naturally into xterm.js's scrollback buffer (user can scroll up).
    private func serializeTerminalScreen(terminal: SwiftTerm.Terminal) -> Data {
        var output = ""
        let rows = terminal.rows
        let cols = terminal.cols

        for row in 0..<rows {
            guard let line = terminal.getLine(row: row) else {
                output += "\r\n"
                continue
            }
            output += serializeBufferLine(line, cols: cols, terminal: terminal)
            if row < rows - 1 {
                output += "\r\n"
            }
        }

        return Data(output.utf8)
    }

    /// Serialize a single BufferLine as ANSI-formatted text with SGR color codes.
    private func serializeBufferLine(
        _ line: BufferLine,
        cols: Int,
        terminal: SwiftTerm.Terminal
    ) -> String {
        var result = ""
        let trimLen = line.getTrimmedLength()
        var prevAttr = Attribute.empty
        var col = 0
        while col < min(trimLen, cols) {
            let cd = line[col]
            let attr = cd.attribute

            if attr != prevAttr {
                result += sgrSequence(for: attr)
                prevAttr = attr
            }

            let ch = terminal.getCharacter(for: cd)
            if ch == "\0" || ch == "\u{FFFD}" {
                result += " "
            } else {
                result.append(ch)
            }

            let w = max(1, Int(cd.width))
            col += w
        }
        result += "\u{1B}[0m"
        return result
    }

    /// Generate an SGR (Select Graphic Rendition) escape sequence for the given attribute.
    private func sgrSequence(for attr: Attribute) -> String {
        var params: [String] = ["0"] // Reset first

        // Style flags
        if attr.style.contains(.bold) { params.append("1") }
        if attr.style.contains(.dim) { params.append("2") }
        if attr.style.contains(.italic) { params.append("3") }
        if attr.style.contains(.underline) { params.append("4") }
        if attr.style.contains(.blink) { params.append("5") }
        if attr.style.contains(.inverse) { params.append("7") }
        if attr.style.contains(.invisible) { params.append("8") }
        if attr.style.contains(.crossedOut) { params.append("9") }

        // Foreground color
        switch attr.fg {
        case .ansi256(let code):
            if code < 8 {
                params.append("\(30 + Int(code))")
            } else if code < 16 {
                params.append("\(90 + Int(code) - 8)")
            } else {
                params.append("38;5;\(code)")
            }
        case .trueColor(let r, let g, let b):
            params.append("38;2;\(r);\(g);\(b)")
        case .defaultColor, .defaultInvertedColor:
            break // Use default
        }

        // Background color
        switch attr.bg {
        case .ansi256(let code):
            if code < 8 {
                params.append("\(40 + Int(code))")
            } else if code < 16 {
                params.append("\(100 + Int(code) - 8)")
            } else {
                params.append("48;5;\(code)")
            }
        case .trueColor(let r, let g, let b):
            params.append("48;2;\(r);\(g);\(b)")
        case .defaultColor, .defaultInvertedColor:
            break // Use default
        }

        return "\u{1B}[\(params.joined(separator: ";"))m"
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

        // Cap input length to prevent PTY buffer abuse (4 KB covers any reasonable command)
        let maxInputLength = 4096
        let safeText = text.count > maxInputLength ? String(text.prefix(maxInputLength)) : text

        // Reset throttle so the terminal echo fires immediately on the next output,
        // and clear last-sent rows so the diff can't be skipped as "unchanged"
        screenUpdateThrottleDeadlines[sessionID] = nil
        screenUpdateDebounceTasks[sessionID]?.cancel()
        screenUpdateDebounceTasks[sessionID] = nil
        terminalLastSentRows[sessionID] = nil

        // Split text from trailing CR/LF so TUI apps don't treat it as pasted text
        // Send the text content first, then the Enter keystroke after a short delay
        // so the TUI processes the text before receiving the submit key
        let trimmed = safeText.replacingOccurrences(of: "\r", with: "")
                              .replacingOccurrences(of: "\n", with: "")

        let needsEnter = safeText.hasSuffix("\r") || safeText.hasSuffix("\n")

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
        // refreshScreen doesn't need a send callback — handle it before the guard
        if action == .refreshScreen {
            screenUpdateThrottleDeadlines[sessionID] = nil
            screenUpdateDebounceTasks[sessionID]?.cancel()
            screenUpdateDebounceTasks[sessionID] = nil
            terminalLastSentRows[sessionID] = nil
            Task { await sendScreenUpdate(for: sessionID) }
            return
        }

        guard let callback = terminalSendCallbacks[sessionID] else { return }

        // Reset throttle so the terminal response fires immediately,
        // and clear last-sent rows so the diff can't be skipped as "unchanged"
        screenUpdateThrottleDeadlines[sessionID] = nil
        screenUpdateDebounceTasks[sessionID]?.cancel()
        screenUpdateDebounceTasks[sessionID] = nil
        terminalLastSentRows[sessionID] = nil

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
        case .enter:
            inputData = Data([0x0D]) // CR
        case .refreshScreen:
            return // handled above
        }

        if let data = inputData {
            callback(data)
        }
    }

    // MARK: - Sending Messages

    private func sendAllScreenUpdates() {
        // Clear last-sent rows so new client gets a full snapshot
        terminalLastSentRows.removeAll()

        // Collect ALL session IDs — not just those with output buffers,
        // since headless terminals may not have produced output yet
        var allSessionIDs = Set(terminalOutputBuffers.keys)
        for session in terminalSessions {
            allSessionIDs.insert(session.id)
        }
        for (_, state) in backgroundRepoStates {
            for tab in state.terminalTabs {
                for session in tab.allSessions() {
                    allSessionIDs.insert(session.id)
                }
            }
        }

        for sessionID in allSessionIDs {
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

        // Skip if nothing changed (diff produced empty data)
        if payload.data.isEmpty { return }

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
            data: "",
            fullSync: false,
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

    /// Reads the current branch name from `.git/HEAD` without spawning a subprocess.
    private func branchFromGitHead(at repoURL: URL) -> String {
        let headURL = repoURL.appendingPathComponent(".git/HEAD")
        guard let contents = try? String(contentsOf: headURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else {
            return "-"
        }
        // "ref: refs/heads/branch-name" → "branch-name"
        if contents.hasPrefix("ref: refs/heads/") {
            return String(contents.dropFirst("ref: refs/heads/".count))
        }
        // Detached HEAD — return short hash
        return String(contents.prefix(7))
    }

    func buildSessionListPayload() -> SessionListPayload {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let activeRepoName = repositoryURL?.lastPathComponent ?? ""
        let activeBranch = currentBranch.isEmpty ? (repositoryURL.map { branchFromGitHead(at: $0) } ?? "-") : currentBranch

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
                repoName: activeRepoName,
                branchName: activeBranch
            )
        }

        // Background repo sessions
        for (url, state) in backgroundRepoStates {
            let repoName = url.lastPathComponent
            let branch = branchFromGitHead(at: url)
            let bgSessions: [SessionInfo] = state.terminalTabs.flatMap { $0.allSessions() }.map { session in
                SessionInfo(
                    id: session.id,
                    label: session.label,
                    title: session.title,
                    isAlive: session.isAlive,
                    workingDirectory: sanitizePath(session.workingDirectory.path),
                    repoName: repoName,
                    branchName: branch
                )
            }
            allSessions.append(contentsOf: bgSessions)
        }

        return SessionListPayload(sessions: allSessions)
    }

    func buildScreenUpdate(for sessionID: UUID) -> ScreenUpdatePayload {
        guard let terminal = terminalForSession(sessionID) else {
            return ScreenUpdatePayload(
                sessionID: sessionID, data: "", fullSync: true,
                hasPrompt: false, promptText: nil
            )
        }

        // Serialize each row independently for change detection
        let rows = terminal.rows
        let cols = terminal.cols
        var currentRows: [String] = []
        for row in 0..<rows {
            if let line = terminal.getLine(row: row) {
                currentRows.append(serializeBufferLine(line, cols: cols, terminal: terminal))
            } else {
                currentRows.append("")
            }
        }

        // Skip if nothing changed since last send
        if let lastRows = terminalLastSentRows[sessionID], lastRows == currentRows {
            return ScreenUpdatePayload(
                sessionID: sessionID, data: "", fullSync: false,
                hasPrompt: false, promptText: nil
            )
        }

        terminalLastSentRows[sessionID] = currentRows

        // Always send full snapshot — client pushes old content to scrollback
        let output = currentRows.joined(separator: "\r\n")
        return ScreenUpdatePayload(
            sessionID: sessionID,
            data: Data(output.utf8).base64EncodedString(),
            fullSync: true,
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
        shared.lanQRImage = mobileAccessLanQRImage
        shared.lanURL = mobileAccessLanURL
        shared.tunnelQRImage = mobileAccessTunnelQRImage
        shared.tunnelURL = mobileAccessTunnelURL
        shared.isTunnelReady = isTunnelReady
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

    // MARK: - System Wake Recovery

    private func observeSystemWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isMobileAccessEnabled else { return }
                self.restartRemoteAccessAfterWake()
            }
        }
    }

    private func removeSystemWakeObserver() {
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
    }

    private func restartRemoteAccessAfterWake() {
        Task {
            await remoteAccessServer?.stop()
            remoteAccessServer = nil
            await tunnelManager?.stop()
            tunnelManager = nil
            heartbeatTask?.cancel()
            heartbeatTask = nil

            enableRemoteAccess()
        }
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
                isPreventingSleep = true
            }
        }

        // Auto-release after duration (cancel any previous timer first)
        sleepTimerTask?.cancel()
        if let seconds = duration.seconds, seconds > 0 {
            keepAwakeExpiresAt = Date.now.addingTimeInterval(seconds)
            sleepTimerTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                releaseSleepAssertion()
                UserDefaults.standard.set(KeepAwakeDuration.off.rawValue, forKey: "zion.mobileAccess.keepAwakeDuration")
            }
        } else {
            keepAwakeExpiresAt = nil
        }
    }

    func releaseSleepAssertion() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        keepAwakeExpiresAt = nil
        isPreventingSleep = false
        guard sleepAssertionID != 0 else { return }
        IOPMAssertionRelease(sleepAssertionID)
        sleepAssertionID = 0
    }

    // Cached ANSI regex — compiled once, reused on every terminal output
    private static let ansiStripRegex: NSRegularExpression? = {
        // Comprehensive ANSI/VT escape stripping:
        // 1. CSI sequences: ESC [ (with optional ? / >) params letter  (colors, cursor, DEC modes)
        // 2. OSC sequences: ESC ] ... BEL or ESC ] ... ST            (window title, hyperlinks)
        // 3. Character set: ESC ( digit/letter                        (G0/G1 charset)
        // 4. Simple escapes: ESC followed by single char              (save/restore cursor, etc.)
        let pattern = #"\x1B(?:\[[0-9;?]*[ -/]*[A-Z@a-z]|\][^\x07\x1B]*(?:\x07|\x1B\\)?|\([0-9A-B]|[^\[\](])"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    private func stripANSI(_ text: String) -> String {
        guard let regex = Self.ansiStripRegex else { return text }
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

