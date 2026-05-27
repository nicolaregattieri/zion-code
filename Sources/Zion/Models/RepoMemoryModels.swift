import Foundation

// MARK: - Schema version

private let currentSchemaVersion = 2

// MARK: - CommitStyleProfile

struct CommitStyleProfile: Codable, Equatable {
    let usesConventionalCommits: Bool
    let commonTypes: [String]
    let commonScopes: [String]
    let preferredVerbStyle: String
    let averageTitleLength: Int
}

// MARK: - RepoMemorySnapshot

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
    /// Top-ranked symbols surfaced from the repo, used for context injection.
    let topSymbols: [SymbolEntry]

    init(
        schemaVersion: Int = currentSchemaVersion,
        repositoryID: String,
        generatedAt: Date,
        activeBranch: String,
        headShortHash: String,
        commitStyle: CommitStyleProfile,
        moduleHints: [String],
        branchPatterns: [String],
        conventions: [String],
        testMappings: [String: [String]],
        sensitiveAreas: [String],
        topSymbols: [SymbolEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.repositoryID = repositoryID
        self.generatedAt = generatedAt
        self.activeBranch = activeBranch
        self.headShortHash = headShortHash
        self.commitStyle = commitStyle
        self.moduleHints = moduleHints
        self.branchPatterns = branchPatterns
        self.conventions = conventions
        self.testMappings = testMappings
        self.sensitiveAreas = sensitiveAreas
        self.topSymbols = topSymbols
    }

    /// A blank snapshot used as a safe default or placeholder.
    static let empty = RepoMemorySnapshot(
        repositoryID: "",
        generatedAt: Date(timeIntervalSince1970: 0),
        activeBranch: "",
        headShortHash: "",
        commitStyle: CommitStyleProfile(
            usesConventionalCommits: false,
            commonTypes: [],
            commonScopes: [],
            preferredVerbStyle: "",
            averageTitleLength: 0
        ),
        moduleHints: [],
        branchPatterns: [],
        conventions: [],
        testMappings: [:],
        sensitiveAreas: [],
        topSymbols: []
    )
}
