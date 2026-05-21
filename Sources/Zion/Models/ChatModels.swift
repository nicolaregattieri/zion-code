import Foundation

// MARK: - ChatRole

enum ChatRole: Equatable {
    case user
    case assistant
}

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
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
