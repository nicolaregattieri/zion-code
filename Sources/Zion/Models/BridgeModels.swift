import Foundation

enum BridgeTarget: String, CaseIterable, Codable, Identifiable {
    case claude
    case codex
    case gemini

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: return L10n("bridge.target.claude")
        case .codex: return L10n("bridge.target.codex")
        case .gemini: return L10n("bridge.target.gemini")
        }
    }
}

enum BridgeItemKind: String, CaseIterable, Codable, Identifiable {
    case guidance
    case rule
    case skill
    case command
    case hook

    var id: String { rawValue }

    var label: String {
        switch self {
        case .guidance: return L10n("bridge.kind.guidance")
        case .rule: return L10n("bridge.kind.rule")
        case .skill: return L10n("bridge.kind.skill")
        case .command: return L10n("bridge.kind.command")
        case .hook: return L10n("bridge.kind.hook")
        }
    }
}

enum BridgeCompatibility: String, Codable, Identifiable {
    case native
    case adapted
    case unsupported

    var id: String { rawValue }

    var label: String {
        switch self {
        case .native: return L10n("bridge.compatibility.native")
        case .adapted: return L10n("bridge.compatibility.adapted")
        case .unsupported: return L10n("bridge.compatibility.unsupported")
        }
    }
}

struct BridgeItem: Codable, Equatable, Identifiable {
    let id: UUID
    var kind: BridgeItemKind
    var slug: String
    var title: String
    var summary: String
    var content: String
    var sourceHint: String?

    init(
        id: UUID = UUID(),
        kind: BridgeItemKind,
        slug: String,
        title: String,
        summary: String,
        content: String,
        sourceHint: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.slug = slug
        self.title = title
        self.summary = summary
        self.content = content
        self.sourceHint = sourceHint
    }
}

struct BridgeManifest: Codable, Equatable {
    var version: Int = 1
    var enabledTargets: [BridgeTarget] = BridgeTarget.allCases
    var lastImportedTarget: BridgeTarget?
    var updatedAt: Date = Date()
}

struct BridgeProjectState: Equatable {
    var exists: Bool
    var manifest: BridgeManifest
    var items: [BridgeItem]
    var warnings: [String]

    static let empty = BridgeProjectState(
        exists: false,
        manifest: BridgeManifest(),
        items: [],
        warnings: []
    )

    var itemCount: Int { items.count }

    func items(of kind: BridgeItemKind) -> [BridgeItem] {
        items.filter { $0.kind == kind }
    }
}

enum BridgeSyncOperationKind: String, Codable, Identifiable {
    case create
    case update
    case remove
    case noop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .create: return L10n("bridge.operation.create")
        case .update: return L10n("bridge.operation.update")
        case .remove: return L10n("bridge.operation.remove")
        case .noop: return L10n("bridge.operation.noop")
        }
    }
}

struct BridgeSyncOperation: Equatable, Identifiable {
    let id: UUID
    var target: BridgeTarget
    var relativePath: String
    var kind: BridgeSyncOperationKind
    var compatibility: BridgeCompatibility
    var detail: String
    var renderedContent: String?

    init(
        id: UUID = UUID(),
        target: BridgeTarget,
        relativePath: String,
        kind: BridgeSyncOperationKind,
        compatibility: BridgeCompatibility,
        detail: String,
        renderedContent: String? = nil
    ) {
        self.id = id
        self.target = target
        self.relativePath = relativePath
        self.kind = kind
        self.compatibility = compatibility
        self.detail = detail
        self.renderedContent = renderedContent
    }
}

struct BridgeSyncPreview: Equatable {
    var target: BridgeTarget
    var operations: [BridgeSyncOperation]
    var warnings: [String]

    var actionableOperations: [BridgeSyncOperation] {
        operations.filter { $0.kind != .noop }
    }
}
