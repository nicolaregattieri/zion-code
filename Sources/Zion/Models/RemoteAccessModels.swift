import Foundation

// MARK: - Wire Protocol

enum RemoteMessageType: String, Codable, Sendable {
    case sessionList
    case screenUpdate
    case promptDetected
    case sendInput
    case sendAction
    case heartbeat
}

struct RemoteMessage: Codable, Sendable {
    let type: RemoteMessageType
    let sessionID: UUID?
    let payload: Data
    let timestamp: Date
}

struct SessionInfo: Codable, Sendable {
    let id: UUID
    let label: String
    let title: String
    let isAlive: Bool
    let workingDirectory: String
}

struct SessionListPayload: Codable, Sendable {
    let sessions: [SessionInfo]
}

struct ScreenUpdatePayload: Codable, Sendable {
    let sessionID: UUID
    let lines: [String]
    let totalRows: Int
    let totalCols: Int
    let hasPrompt: Bool
    let promptText: String?
}

struct SendInputPayload: Codable, Sendable {
    let text: String
}

enum RemoteAction: String, Codable, Sendable {
    case approve
    case deny
    case abort
}

struct SendActionPayload: Codable, Sendable {
    let action: RemoteAction
}

// MARK: - Device Pairing

struct PairedDevice: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let pairedAt: Date
    var lastSeen: Date
}

// MARK: - Connection State

enum RemoteAccessConnectionState: Sendable {
    case disabled
    case starting
    case waitingForPairing
    case connected(deviceCount: Int)
    case error(String)
}
