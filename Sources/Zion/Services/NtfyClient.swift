import Foundation
import UserNotifications

enum NtfyEventGroup: String, CaseIterable, Identifiable, Sendable {
    case gitOps = "gitOps"
    case ai = "ai"
    case github = "github"
    case mobileRemote = "mobileRemote"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gitOps: return L10n("ntfy.group.gitOps")
        case .ai: return L10n("ntfy.group.ai")
        case .github: return L10n("ntfy.group.pullRequests")
        case .mobileRemote: return L10n("ntfy.group.mobileRemote")
        }
    }

    var icon: String {
        switch self {
        case .gitOps: return "arrow.triangle.branch"
        case .ai: return "sparkles"
        case .github: return "link"
        case .mobileRemote: return "iphone.and.arrow.forward"
        }
    }
}

enum NtfyEvent: String, CaseIterable, Identifiable, Sendable {
    // Git Ops
    case cloneComplete = "cloneComplete"
    case newRemoteCommits = "newRemoteCommits"
    // Pull Requests
    case prCreated = "prCreated"
    case prReviewRequested = "prReviewRequested"
    case prMergedOrClosed = "prMergedOrClosed"
    // AI
    case prAutoReviewComplete = "prAutoReviewComplete"
    // Terminal
    case terminalPromptDetected = "terminalPromptDetected"
    // System
    case operationComplete = "operationComplete"

    var id: String { rawValue }

    var group: NtfyEventGroup {
        switch self {
        case .cloneComplete, .newRemoteCommits:
            return .gitOps
        case .prAutoReviewComplete:
            return .ai
        case .prCreated, .prReviewRequested, .prMergedOrClosed:
            return .github
        case .terminalPromptDetected:
            return .mobileRemote
        case .operationComplete:
            return .gitOps
        }
    }

    var label: String {
        switch self {
        case .cloneComplete: return L10n("ntfy.event.cloneComplete")
        case .newRemoteCommits: return L10n("ntfy.event.newRemoteCommits")
        case .prCreated: return L10n("ntfy.event.prCreated")
        case .prReviewRequested: return L10n("ntfy.event.prReviewRequested")
        case .prMergedOrClosed: return L10n("ntfy.event.prMergedOrClosed")
        case .prAutoReviewComplete: return L10n("ntfy.event.prAutoReviewComplete")
        case .terminalPromptDetected: return L10n("ntfy.event.terminalPromptDetected")
        case .operationComplete: return L10n("ntfy.event.operationComplete")
        }
    }

    var priority: Int {
        switch self {
        case .cloneComplete: return 4
        case .newRemoteCommits: return 4
        case .prCreated: return 3
        case .prReviewRequested: return 4
        case .prMergedOrClosed: return 3
        case .prAutoReviewComplete: return 4
        case .terminalPromptDetected: return 5
        case .operationComplete: return 3
        }
    }

    var emojiTag: String {
        switch self {
        case .cloneComplete: return "package"
        case .newRemoteCommits: return "bell"
        case .prCreated: return "tada"
        case .prReviewRequested: return "eyes"
        case .prMergedOrClosed: return "checkered_flag"
        case .prAutoReviewComplete: return "mag"
        case .terminalPromptDetected: return "bell"
        case .operationComplete: return "white_check_mark"
        }
    }

    /// Whether this event should appear in the notification settings UI.
    /// Synchronous events (instant inline results) are hidden -- notifications add no value.
    var isUserConfigurable: Bool {
        switch self {
        case .newRemoteCommits,
             .prCreated, .prReviewRequested, .prMergedOrClosed, .prAutoReviewComplete,
             .terminalPromptDetected, .operationComplete:
            return true
        case .cloneComplete:
            return false // synchronous -- result appears instantly in UI
        }
    }

    var enabledByDefault: Bool {
        switch self {
        case .cloneComplete, .newRemoteCommits,
             .prCreated, .prReviewRequested, .prMergedOrClosed, .prAutoReviewComplete:
            return true
        case .terminalPromptDetected, .operationComplete:
            return false
        }
    }

    /// Whether this event should only be delivered as a local macOS notification (never remote).
    var isLocalOnly: Bool {
        switch self {
        case .operationComplete: return true
        default: return false
        }
    }

    static var defaultEnabledEvents: [String] {
        allCases.filter(\.enabledByDefault).map(\.rawValue)
    }
}

actor NtfyClient {
    struct DeliveryPlan: Equatable {
        let eventEnabled: Bool
        let deliverLocal: Bool
        let deliverRemote: Bool
        let topic: String
        let serverURL: String

        var shouldSendAnything: Bool {
            eventEnabled && (deliverLocal || deliverRemote)
        }
    }

    // MARK: - Retry Queue (Phase 2C)

    private struct RetryItem {
        let event: NtfyEvent
        let title: String
        let body: String
        let serverURL: String
        let topic: String
        let priority: Int
        let tags: String
        let timestamp: Date
        var attemptCount: Int
    }

    private static let maxRetryQueueSize = 10
    private static let maxRetryAttempts = 3
    private static let retryItemMaxAge: TimeInterval = 3600 // 1 hour

    private var retryQueue: [RetryItem] = []

    // MARK: - Batch Buffer (Phase 2D)

    private static let batchWindowSeconds: UInt64 = 30

    private var batchBuffer: [RetryItem] = []
    private var batchFlushTask: Task<Void, Never>?

    private static var prEvents: Set<NtfyEvent> {
        [.prCreated, .prReviewRequested]
    }

    static func deliveryPlan(
        event: NtfyEvent,
        defaults: UserDefaults = .standard
    ) -> DeliveryPlan {
        let enabledEvents = defaults.stringArray(forKey: UserDefaultsKeys.Ntfy.enabledEvents) ?? NtfyEvent.defaultEnabledEvents
        let eventEnabled = enabledEvents.contains(event.rawValue)
        let localEnabled = defaults.object(forKey: UserDefaultsKeys.Ntfy.localNotifications) as? Bool ?? false
        let remoteEnabled = defaults.object(forKey: UserDefaultsKeys.Ntfy.enabled) as? Bool ?? false
        let topic = defaults.string(forKey: UserDefaultsKeys.Ntfy.topic) ?? ""
        let serverURL = defaults.string(forKey: UserDefaultsKeys.Ntfy.serverURL) ?? "https://ntfy.sh"

        return DeliveryPlan(
            eventEnabled: eventEnabled,
            deliverLocal: localEnabled && eventEnabled,
            deliverRemote: remoteEnabled && !topic.isEmpty && eventEnabled,
            topic: topic,
            serverURL: serverURL
        )
    }

    func sendIfEnabled(
        event: NtfyEvent,
        title: String,
        body: String,
        repoName: String
    ) async {
        let plan = Self.deliveryPlan(event: event)
        guard plan.shouldSendAnything else { return }

        let fullTitle = "Zion: \(title)"
        let fullBody = repoName.isEmpty ? body : "[\(repoName)] \(body)"

        if plan.deliverLocal {
            await sendLocalNotification(title: fullTitle, body: fullBody)
        }

        // Local-only events (e.g., operationComplete) skip remote delivery
        guard !event.isLocalOnly else { return }

        if plan.deliverRemote {
            // PR events get batched (Phase 2D), everything else sends immediately
            if Self.prEvents.contains(event) {
                bufferPREvent(
                    event: event,
                    title: fullTitle,
                    body: fullBody,
                    serverURL: plan.serverURL,
                    topic: plan.topic,
                    priority: event.priority,
                    tags: event.emojiTag
                )
            } else {
                let success = await send(
                    serverURL: plan.serverURL,
                    topic: plan.topic,
                    title: fullTitle,
                    body: fullBody,
                    priority: event.priority,
                    tags: event.emojiTag
                )

                if success {
                    await flushRetryQueue()
                } else {
                    enqueueForRetry(
                        event: event,
                        title: fullTitle,
                        body: fullBody,
                        serverURL: plan.serverURL,
                        topic: plan.topic,
                        priority: event.priority,
                        tags: event.emojiTag
                    )
                }
            }
        }
    }

    private func sendLocalNotification(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    // MARK: - Retry Logic (Phase 2C)

    private func enqueueForRetry(
        event: NtfyEvent,
        title: String,
        body: String,
        serverURL: String,
        topic: String,
        priority: Int,
        tags: String
    ) {
        guard retryQueue.count < Self.maxRetryQueueSize else { return }

        let item = RetryItem(
            event: event,
            title: title,
            body: body,
            serverURL: serverURL,
            topic: topic,
            priority: priority,
            tags: tags,
            timestamp: Date(),
            attemptCount: 1
        )
        retryQueue.append(item)
    }

    func retryPendingNotifications() async {
        await flushRetryQueue()
    }

    private func flushRetryQueue() async {
        let now = Date()

        // Drop expired items (older than 1 hour)
        retryQueue.removeAll { now.timeIntervalSince($0.timestamp) > Self.retryItemMaxAge }

        guard !retryQueue.isEmpty else { return }

        var remaining: [RetryItem] = []

        for var item in retryQueue {
            let success = await send(
                serverURL: item.serverURL,
                topic: item.topic,
                title: item.title,
                body: item.body,
                priority: item.priority,
                tags: item.tags
            )

            if !success {
                item.attemptCount += 1
                if item.attemptCount <= Self.maxRetryAttempts {
                    remaining.append(item)
                }
            }
        }

        retryQueue = remaining
    }

    // MARK: - PR Event Batching (Phase 2D)

    private func bufferPREvent(
        event: NtfyEvent,
        title: String,
        body: String,
        serverURL: String,
        topic: String,
        priority: Int,
        tags: String
    ) {
        let item = RetryItem(
            event: event,
            title: title,
            body: body,
            serverURL: serverURL,
            topic: topic,
            priority: priority,
            tags: tags,
            timestamp: Date(),
            attemptCount: 0
        )
        batchBuffer.append(item)

        // Cancel existing flush timer and start a new one
        batchFlushTask?.cancel()
        batchFlushTask = Task {
            try? await Task.sleep(nanoseconds: Self.batchWindowSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self.flushBatchBuffer()
        }
    }

    private func flushBatchBuffer() async {
        guard !batchBuffer.isEmpty else { return }

        let items = batchBuffer
        batchBuffer.removeAll()
        batchFlushTask = nil

        if items.count == 1 {
            // Single item: send as-is
            let item = items[0]
            let success = await send(
                serverURL: item.serverURL,
                topic: item.topic,
                title: item.title,
                body: item.body,
                priority: item.priority,
                tags: item.tags
            )

            if !success {
                enqueueForRetry(
                    event: item.event,
                    title: item.title,
                    body: item.body,
                    serverURL: item.serverURL,
                    topic: item.topic,
                    priority: item.priority,
                    tags: item.tags
                )
            } else {
                await flushRetryQueue()
            }
        } else {
            // Multiple items: send as summary
            let summaryTitle = "Zion: \(items.count) new PR events"
            let summaryBody = items.map(\.body).joined(separator: ", ")
            // Use the first item's connection details and highest priority
            let firstItem = items[0]
            let maxPriority = items.map(\.priority).max() ?? 3

            let success = await send(
                serverURL: firstItem.serverURL,
                topic: firstItem.topic,
                title: summaryTitle,
                body: summaryBody,
                priority: maxPriority,
                tags: "tada"
            )

            if !success {
                // Enqueue the summary as a single retry item
                enqueueForRetry(
                    event: .prCreated,
                    title: summaryTitle,
                    body: summaryBody,
                    serverURL: firstItem.serverURL,
                    topic: firstItem.topic,
                    priority: maxPriority,
                    tags: "tada"
                )
            } else {
                await flushRetryQueue()
            }
        }
    }

    func sendTest(serverURL: String, topic: String) async -> Bool {
        await send(
            serverURL: serverURL,
            topic: topic,
            title: "Zion: Test Notification",
            body: "If you see this, ntfy is configured correctly!",
            priority: 3,
            tags: "white_check_mark"
        )
    }

    @discardableResult
    private func send(
        serverURL: String,
        topic: String,
        title: String,
        body: String,
        priority: Int,
        tags: String
    ) async -> Bool {
        let resolvedURL: URL?
        let loggingContext: String
        if let strictURL = Self.buildNtfyURL(serverURL: serverURL, topic: topic) {
            resolvedURL = strictURL
            loggingContext = strictURL.absoluteString
        } else if let fallbackURL = Self.buildLegacyCompatibleURL(serverURL: serverURL, topic: topic) {
            resolvedURL = fallbackURL
            loggingContext = fallbackURL.absoluteString
            await MainActor.run {
                DiagnosticLogger.shared.log(.warn, "Using legacy ntfy URL normalization", context: loggingContext, source: "NtfyClient.send")
            }
        } else {
            await MainActor.run {
                DiagnosticLogger.shared.log(.error, "Invalid ntfy server/topic configuration", context: "\(serverURL) | \(topic)", source: "NtfyClient.send")
            }
            return false
        }
        guard let url = resolvedURL else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue(title, forHTTPHeaderField: "Title")
        request.setValue("\(priority)", forHTTPHeaderField: "Priority")
        request.setValue(tags, forHTTPHeaderField: "Tags")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let success = httpResponse?.statusCode == 200
            if !success {
                await MainActor.run {
                    DiagnosticLogger.shared.log(.warn, "ntfy response: \(httpResponse?.statusCode ?? -1)", context: loggingContext, source: "NtfyClient.send")
                }
            }
            return success
        } catch {
            await MainActor.run {
                DiagnosticLogger.shared.log(.error, "ntfy send failed: \(error.localizedDescription)", context: loggingContext, source: "NtfyClient.send")
            }
            return false
        }
    }

    /// Generate a secure random topic like `zion-code-3Y3k8If`
    /// Uses rejection sampling to avoid modulo bias (62 chars, reject bytes >= 248).
    static func generateSecureTopic() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let maxUnbiased: UInt8 = 247 // 248 = 62*4, reject 248-255 for uniform distribution
        var result = [Character]()
        result.reserveCapacity(7)
        while result.count < 7 {
            var byte: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            if byte <= maxUnbiased {
                result.append(chars[Int(byte) % chars.count])
            }
        }
        return "zion-code-\(String(result))"
    }

    static func validateTopic(_ topic: String) -> Bool {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(of: #"^[A-Za-z0-9._-]{1,64}$"#, options: .regularExpression) != nil
    }

    static func validateServerURL(_ serverURL: String) -> Bool {
        guard let components = URLComponents(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        // Reject URLs with embedded credentials (userinfo)
        if components.user != nil || components.password != nil {
            return false
        }
        return true
    }

    static func buildNtfyURL(serverURL: String, topic: String) -> URL? {
        let trimmedServer = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validateServerURL(trimmedServer), validateTopic(trimmedTopic),
              var components = URLComponents(string: trimmedServer) else {
            return nil
        }

        let encodedTopic = trimmedTopic.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmedTopic
        let cleanPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = cleanPath.isEmpty ? "/\(encodedTopic)" : "/\(cleanPath)/\(encodedTopic)"
        return components.url
    }

    private static func buildLegacyCompatibleURL(serverURL: String, topic: String) -> URL? {
        let rawServer = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rawTopic.isEmpty else { return nil }

        let serverWithScheme: String
        if rawServer.contains("://") {
            serverWithScheme = rawServer
        } else {
            serverWithScheme = "https://\(rawServer)"
        }

        guard var components = URLComponents(string: serverWithScheme),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        // Reject URLs with embedded credentials (userinfo)
        guard components.user == nil, components.password == nil else { return nil }

        let encodedTopic = rawTopic.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawTopic
        let cleanPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = cleanPath.isEmpty ? "/\(encodedTopic)" : "/\(cleanPath)/\(encodedTopic)"
        return components.url
    }
}
