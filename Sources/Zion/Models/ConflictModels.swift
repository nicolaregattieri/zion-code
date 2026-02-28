import Foundation

// MARK: - Conflict Resolution

struct ConflictFile: Identifiable, Hashable {
    let path: String
    var isResolved: Bool = false
    var id: String { path }
}

struct ConflictRegion: Identifiable {
    let id = UUID()
    let oursLines: [String]
    let theirsLines: [String]
    let oursLabel: String
    let theirsLabel: String
    var choice: ConflictChoice = .undecided

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ConflictRegion, rhs: ConflictRegion) -> Bool { lhs.id == rhs.id }
}

enum ConflictChoice: Equatable {
    case undecided, ours, theirs, both, bothReverse, custom(String)
}

/// A block in a conflict file — either context (non-conflicting) or a conflict region
enum ConflictBlock: Identifiable {
    case context([String])
    case conflict(ConflictRegion)

    var id: String {
        switch self {
        case .context(let lines): return "ctx-\(lines.hashValue)"
        case .conflict(let region): return region.id.uuidString
        }
    }
}
