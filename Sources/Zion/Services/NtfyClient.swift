import Foundation
import UserNotifications

enum NtfyEventGroup: String, CaseIterable, Identifiable, Sendable {
    case gitOps = "gitOps"
    case ai = "ai"
    case github = "github"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gitOps: return L10n("ntfy.group.gitOps")
        case .ai: return L10n("ntfy.group.ai")
        case .github: return L10n("ntfy.group.github")
        }
    }

    var icon: String {
        switch self {
        case .gitOps: return "arrow.triangle.branch"
        case .ai: return "sparkles"
        case .github: return "link"
        }
    }
}

enum NtfyEvent: String, CaseIterable, Identifiable, Sendable {
    // Git Ops
    case cloneComplete = "cloneComplete"
    case pushComplete = "pushComplete"
    case pullComplete = "pullComplete"
    case newRemoteCommits = "newRemoteCommits"
    // AI
    case codeReviewComplete = "codeReviewComplete"
    case conflictResolutionReady = "conflictResolutionReady"
    case commitMessageReady = "commitMessageReady"
    case changelogReady = "changelogReady"
    case blameExplanationReady = "blameExplanationReady"
    case diffExplanationReady = "diffExplanationReady"
    case commitSplitReady = "commitSplitReady"
    // GitHub
    case prCreated = "prCreated"
    case prReviewRequested = "prReviewRequested"
    // AI — Branch Review
    case branchReviewComplete = "branchReviewComplete"
    case prAutoReviewComplete = "prAutoReviewComplete"

    var id: String { rawValue }

    var group: NtfyEventGroup {
        switch self {
        case .cloneComplete, .pushComplete, .pullComplete, .newRemoteCommits:
            return .gitOps
        case .codeReviewComplete, .conflictResolutionReady, .commitMessageReady,
             .changelogReady, .blameExplanationReady, .diffExplanationReady, .commitSplitReady,
             .branchReviewComplete, .prAutoReviewComplete:
            return .ai
        case .prCreated, .prReviewRequested:
            return .github
        }
    }

    var label: String {
        switch self {
        case .cloneComplete: return L10n("ntfy.event.cloneComplete")
        case .pushComplete: return L10n("ntfy.event.pushComplete")
        case .pullComplete: return L10n("ntfy.event.pullComplete")
        case .newRemoteCommits: return L10n("ntfy.event.newRemoteCommits")
        case .codeReviewComplete: return L10n("ntfy.event.codeReviewComplete")
        case .conflictResolutionReady: return L10n("ntfy.event.conflictResolutionReady")
        case .commitMessageReady: return L10n("ntfy.event.commitMessageReady")
        case .changelogReady: return L10n("ntfy.event.changelogReady")
        case .blameExplanationReady: return L10n("ntfy.event.blameExplanationReady")
        case .diffExplanationReady: return L10n("ntfy.event.diffExplanationReady")
        case .commitSplitReady: return L10n("ntfy.event.commitSplitReady")
        case .prCreated: return L10n("ntfy.event.prCreated")
        case .prReviewRequested: return L10n("ntfy.event.prReviewRequested")
        case .branchReviewComplete: return L10n("ntfy.event.branchReviewComplete")
        case .prAutoReviewComplete: return L10n("ntfy.event.prAutoReviewComplete")
        }
    }

    var priority: Int {
        switch self {
        case .cloneComplete: return 4
        case .pushComplete: return 3
        case .pullComplete: return 3
        case .newRemoteCommits: return 4
        case .codeReviewComplete: return 4
        case .conflictResolutionReady: return 4
        case .commitMessageReady: return 3
        case .changelogReady: return 3
        case .blameExplanationReady: return 2
        case .diffExplanationReady: return 2
        case .commitSplitReady: return 2
        case .prCreated: return 3
        case .prReviewRequested: return 4
        case .branchReviewComplete: return 4
        case .prAutoReviewComplete: return 4
        }
    }

    var emojiTag: String {
        switch self {
        case .cloneComplete: return "package"
        case .pushComplete: return "rocket"
        case .pullComplete: return "arrow_down"
        case .newRemoteCommits: return "bell"
        case .codeReviewComplete: return "mag"
        case .conflictResolutionReady: return "handshake"
        case .commitMessageReady: return "memo"
        case .changelogReady: return "scroll"
        case .blameExplanationReady: return "detective"
        case .diffExplanationReady: return "books"
        case .commitSplitReady: return "scissors"
        case .prCreated: return "tada"
        case .prReviewRequested: return "eyes"
        case .branchReviewComplete: return "mag"
        case .prAutoReviewComplete: return "mag"
        }
    }

    /// Whether this event should appear in the notification settings UI.
    /// Synchronous events (instant inline results) are hidden — notifications add no value.
    var isUserConfigurable: Bool {
        switch self {
        case .newRemoteCommits,
             .prCreated, .prReviewRequested, .prAutoReviewComplete:
            return true
        case .cloneComplete, .pushComplete, .pullComplete,
             .codeReviewComplete, .branchReviewComplete,
             .commitMessageReady, .changelogReady, .blameExplanationReady,
             .diffExplanationReady, .commitSplitReady, .conflictResolutionReady:
            return false // synchronous — result appears instantly in UI
        }
    }

    var enabledByDefault: Bool {
        switch self {
        case .cloneComplete, .pushComplete, .pullComplete, .newRemoteCommits,
             .codeReviewComplete, .conflictResolutionReady, .prCreated,
             .prReviewRequested, .branchReviewComplete, .prAutoReviewComplete:
            return true
        case .commitMessageReady, .changelogReady, .blameExplanationReady,
             .diffExplanationReady, .commitSplitReady:
            return false
        }
    }

    static var defaultEnabledEvents: [String] {
        allCases.filter(\.enabledByDefault).map(\.rawValue)
    }
}

actor NtfyClient {
    func sendIfEnabled(
        event: NtfyEvent,
        title: String,
        body: String,
        repoName: String
    ) async {
        let defaults = UserDefaults.standard
        let enabledEvents = defaults.stringArray(forKey: "zion.ntfy.enabledEvents") ?? NtfyEvent.defaultEnabledEvents
        guard enabledEvents.contains(event.rawValue) else { return }

        let fullTitle = "Zion: \(title)"
        let fullBody = repoName.isEmpty ? body : "[\(repoName)] \(body)"

        // Always send local macOS notification if enabled
        let localEnabled = defaults.object(forKey: "zion.ntfy.localNotifications") as? Bool ?? true
        if localEnabled {
            await sendLocalNotification(title: fullTitle, body: fullBody)
        }

        // Also send ntfy push if topic is configured
        let topic = defaults.string(forKey: "zion.ntfy.topic") ?? ""
        if !topic.isEmpty {
            let serverURL = defaults.string(forKey: "zion.ntfy.serverURL") ?? "https://ntfy.sh"
            await send(
                serverURL: serverURL,
                topic: topic,
                title: fullTitle,
                body: fullBody,
                priority: event.priority,
                tags: event.emojiTag
            )
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

    /// Write global ntfy config to ~/.config/ntfy/config.json for external tools
    static func writeGlobalConfig(topic: String, serverURL: String) {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ntfy")
        let configFile = configDir.appendingPathComponent("config.json")

        do {
            try FileManager.default.createDirectory(
                at: configDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let config: [String: String] = ["topic": topic, "server": serverURL]
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
        } catch {
            // Non-critical, ignore
        }
    }

    /// Read global ntfy config as fallback
    static func readGlobalConfig() -> (topic: String, serverURL: String)? {
        let configFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ntfy/config.json")
        guard let data = try? Data(contentsOf: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let topic = json["topic"], !topic.isEmpty else {
            return nil
        }
        return (topic: topic, serverURL: json["server"] ?? "https://ntfy.sh")
    }

    /// Generate a secure random topic like `zion-code-3Y3k8If`
    static func generateSecureTopic() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var bytes = [UInt8](repeating: 0, count: 7)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let suffix = String(bytes.map { chars[Int($0) % chars.count] })
        return "zion-code-\(suffix)"
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

        let encodedTopic = rawTopic.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawTopic
        let cleanPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = cleanPath.isEmpty ? "/\(encodedTopic)" : "/\(cleanPath)/\(encodedTopic)"
        return components.url
    }
}
