import Foundation

struct CommitStyleProfile: Codable, Equatable {
    let usesConventionalCommits: Bool
    let commonTypes: [String]
    let commonScopes: [String]
    let preferredVerbStyle: String
    let averageTitleLength: Int
}

struct RepoMemorySnapshot: Codable, Equatable {
    let schemaVersion: Int
    let repositoryID: String
    let generatedAt: Date
    let activeBranch: String
    let headShortHash: String
    let commitStyle: CommitStyleProfile
    let moduleHints: [String]
    let branchPatterns: [String]
    let conventions: [String]
    let testMappings: [String: [String]]
    let sensitiveAreas: [String]
}
