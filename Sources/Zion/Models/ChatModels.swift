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

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        autoInjectedIntent: String? = nil,
        toolEvents: [ChatToolEvent]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.autoInjectedIntent = autoInjectedIntent
        self.toolEvents = toolEvents
    }
}

// MARK: - ChatThread

struct ChatThread: Identifiable, Equatable {
    let id: UUID
    var messages: [ChatMessage]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        messages: [ChatMessage] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
    }
}
