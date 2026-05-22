import Foundation

// MARK: - ChatPlanStep

struct ChatPlanStep: Codable, Equatable {
    var commitMessage: String?
    var filePaths: [String]
    var summary: String

    init(commitMessage: String? = nil, filePaths: [String] = [], summary: String = "") {
        self.commitMessage = commitMessage
        self.filePaths = filePaths
        self.summary = summary
    }
}

// MARK: - ChatPlan

struct ChatPlan: Codable, Equatable {
    var id: UUID
    var rawXML: String
    var steps: [ChatPlanStep]

    init(id: UUID = UUID(), rawXML: String = "", steps: [ChatPlanStep] = []) {
        self.id = id
        self.rawXML = rawXML
        self.steps = steps
    }
}
