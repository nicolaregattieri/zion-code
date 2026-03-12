import Foundation

enum BridgeTarget: String, CaseIterable, Codable, Identifiable {
    case claude
    case codex
    case gemini
    case cursor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: return L10n("bridge.target.claude")
        case .codex: return L10n("bridge.target.codex")
        case .gemini: return L10n("bridge.target.gemini")
        case .cursor: return L10n("bridge.target.cursor")
        }
    }
}

enum BridgeArtifactKind: String, Codable, CaseIterable {
    case guidance
    case rule
    case command
    case skill

    var label: String {
        switch self {
        case .guidance: return L10n("bridge.kind.guidance")
        case .rule: return L10n("bridge.kind.rule")
        case .command: return L10n("bridge.kind.command")
        case .skill: return L10n("bridge.kind.skill")
        }
    }
}

struct BridgeArtifact: Identifiable, Codable, Hashable {
    let sourceTarget: BridgeTarget
    let relativePath: String
    let kind: BridgeArtifactKind
    let slug: String
    let title: String
    let summary: String
    let content: String
    let homeTarget: BridgeTarget
    let homeRelativePath: String

    var id: String { "\(sourceTarget.rawValue):\(relativePath)" }
}

enum BridgeMappingKind: String, Codable, CaseIterable {
    case knownMirror
    case inferredMirror
    case newImport
    case manualReview
    case unsupported

    var label: String {
        switch self {
        case .knownMirror: return L10n("bridge.mapping.knownMirror")
        case .inferredMirror: return L10n("bridge.mapping.inferredMirror")
        case .newImport: return L10n("bridge.mapping.newImport")
        case .manualReview: return L10n("bridge.mapping.manualReview")
        case .unsupported: return L10n("bridge.mapping.unsupported")
        }
    }
}

enum BridgeSyncActionKind: String, Codable, CaseIterable {
    case noop
    case create
    case update
    case manualReview
    case unsupported

    var label: String {
        switch self {
        case .noop: return L10n("bridge.operation.noop")
        case .create: return L10n("bridge.operation.create")
        case .update: return L10n("bridge.operation.update")
        case .manualReview: return L10n("bridge.operation.review")
        case .unsupported: return L10n("bridge.operation.unsupported")
        }
    }
}

enum BridgeConfidence: String, Codable, CaseIterable {
    case high
    case medium
    case low

    var label: String {
        switch self {
        case .high: return L10n("bridge.confidence.high")
        case .medium: return L10n("bridge.confidence.medium")
        case .low: return L10n("bridge.confidence.low")
        }
    }
}

struct BridgeMappingRow: Identifiable, Codable, Hashable {
    let sourceArtifact: BridgeArtifact
    let destinationTarget: BridgeTarget
    let destinationRelativePath: String?
    let mappingKind: BridgeMappingKind
    let action: BridgeSyncActionKind
    let confidence: BridgeConfidence
    let reason: String
    let sourcePreview: String
    let destinationPreview: String
    let renderedContent: String?

    var id: String {
        "\(sourceArtifact.id)->\(destinationTarget.rawValue):\(destinationRelativePath ?? "none")"
    }

    var isSyncable: Bool {
        action == .create || action == .update
    }
}

struct BridgeMigrationSummary: Codable, Hashable {
    let knownMirrors: Int
    let updates: Int
    let newImports: Int
    let needsReview: Int
    let unsupported: Int
}

struct BridgeMigrationAnalysis: Identifiable, Codable, Hashable {
    let sourceTarget: BridgeTarget
    let destinationTarget: BridgeTarget
    let rows: [BridgeMappingRow]
    let warnings: [String]
    let generatedAt: Date

    var id: String { "\(sourceTarget.rawValue)->\(destinationTarget.rawValue)" }

    var syncableRows: [BridgeMappingRow] {
        rows.filter(\.isSyncable)
    }

    var summary: BridgeMigrationSummary {
        BridgeMigrationSummary(
            knownMirrors: rows.filter { $0.mappingKind == .knownMirror }.count,
            updates: rows.filter { $0.action == .create || $0.action == .update }.count,
            newImports: rows.filter { $0.mappingKind == .newImport }.count,
            needsReview: rows.filter { $0.mappingKind == .manualReview || $0.action == .manualReview }.count,
            unsupported: rows.filter { $0.mappingKind == .unsupported || $0.action == .unsupported }.count
        )
    }
}

struct BridgeToolDetection: Identifiable, Codable, Hashable {
    let target: BridgeTarget
    let isDetected: Bool
    let detail: String

    var id: String { target.id }
}

struct BridgeProjectState: Codable, Hashable {
    let detections: [BridgeToolDetection]
    let warnings: [String]

    static let empty = BridgeProjectState(detections: [], warnings: [])

    func detection(for target: BridgeTarget) -> BridgeToolDetection? {
        detections.first(where: { $0.target == target })
    }
}

struct BridgeMirrorRecord: Codable, Hashable {
    let sourceTarget: BridgeTarget
    let destinationTarget: BridgeTarget
    let sourceRelativePath: String
    let destinationRelativePath: String
    let mappingKind: BridgeMappingKind
    let confidence: BridgeConfidence
    let sourceHash: String
    let destinationHash: String
    let updatedAt: Date
}

struct BridgeMirrorMatrix: Codable, Hashable {
    var records: [BridgeMirrorRecord]

    static let empty = BridgeMirrorMatrix(records: [])
}
