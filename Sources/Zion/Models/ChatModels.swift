import Foundation

// MARK: - ChatRole

enum ChatRole: Equatable {
    case user
    case assistant
}

// MARK: - ToolEventStatus

enum ToolEventStatus: String, Codable {
    case pending, running, completed, failed
}

// MARK: - ChatToolEvent

struct ChatToolEvent: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    var status: ToolEventStatus
    let argsPreview: String
    /// Truncated stdout/result string captured from the tool's terminating event.
    /// Bound to 1024 chars upstream in the parser so persisted messages stay small.
    var output: String? = nil
}

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    var autoInjectedIntent: String? = nil
    var toolEvents: [ChatToolEvent]? = nil
    /// Hidden context attached to a user message (e.g. auto-injected git diff). Sent to model in payload but NOT displayed in bubble. Carried forward to subsequent turns until classifier fires a different intent.
    var internalContext: String? = nil

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        autoInjectedIntent: String? = nil,
        toolEvents: [ChatToolEvent]? = nil,
        internalContext: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.autoInjectedIntent = autoInjectedIntent
        self.toolEvents = toolEvents
        self.internalContext = internalContext
    }
}

// MARK: - ChatThread

struct ChatThread: Identifiable, Equatable {
    let id: UUID
    var messages: [ChatMessage]
    let createdAt: Date
    var repoID: String
    var title: String
    /// Captured from the CLI provider's first event of the previous turn so the
    /// next turn can resume the same server-side session
    /// (`claude --resume <id>` / `codex exec resume <id>`).
    /// Provider-specific: cleared whenever the user switches providers.
    var cliSessionID: String? = nil
    var cliSessionProvider: String? = nil
    /// Sum of `total_cost_usd` reported by the CLI on each turn's terminating
    /// event. Codex Plus is unmetered → stays 0.
    var totalCostUSD: Double = 0

    init(
        id: UUID = UUID(),
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        repoID: String = "",
        title: String = ChatThread.defaultTitle(),
        cliSessionID: String? = nil,
        cliSessionProvider: String? = nil,
        totalCostUSD: Double = 0
    ) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
        self.repoID = repoID
        self.title = title
        self.cliSessionID = cliSessionID
        self.cliSessionProvider = cliSessionProvider
        self.totalCostUSD = totalCostUSD
    }

    static func defaultTitle(date: Date = Date()) -> String {
        String(format: L10n("chat.thread.untitled"), DateFormatter.chatThreadShort.string(from: date))
    }
}

// MARK: - DateFormatter + ChatThread

private extension DateFormatter {
    static let chatThreadShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
