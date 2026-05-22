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

    init(
        id: UUID = UUID(),
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        repoID: String = "",
        title: String = ChatThread.defaultTitle()
    ) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
        self.repoID = repoID
        self.title = title
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
