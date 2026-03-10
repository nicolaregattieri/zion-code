import Foundation
import SwiftUI

// MARK: - Graph Lane Models

struct LaneEdge: Hashable, Sendable {
    let from: Int
    let to: Int
    let colorKey: Int
}

struct LaneColor: Hashable, Sendable {
    let lane: Int
    let colorKey: Int
}

struct ParsedCommit: Hashable, Sendable {
    let hash: String
    let parents: [String]
    let author: String
    let email: String
    let date: Date
    let subject: String
    let decorations: [String]
}

// MARK: - Commit

struct Commit: Identifiable, Hashable, Sendable {
    let id: String
    let shortHash: String
    let parents: [String]
    let author: String
    let email: String
    let date: Date
    let subject: String
    let decorations: [String]
    let lane: Int
    let nodeColorKey: Int
    let incomingLanes: [Int]
    let outgoingLanes: [Int]
    let laneColors: [LaneColor]
    let outgoingEdges: [LaneEdge]
    var insertions: Int?
    var deletions: Int?
}

struct AIHistorySearchCandidate: Hashable, Sendable {
    let fullHash: String
    let shortHash: String
    let subject: String
    let author: String
    let dateText: String
    let files: [String]
}

struct AIHistorySearchMatch: Identifiable, Hashable, Sendable {
    let hash: String
    let reason: String

    var id: String { hash.lowercased() }
}

struct AIHistorySearchResult: Hashable, Sendable {
    let answer: String
    let matches: [AIHistorySearchMatch]
}

// MARK: - Branch & Remote

struct BranchInfo: Identifiable, Hashable, Sendable {
    let name: String
    let fullRef: String
    let head: String
    let upstream: String
    let committerDate: Date
    let isRemote: Bool
    var id: String { name }
    var shortHead: String { String(head.prefix(8)) }
}

struct BranchTreeNode: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let branchName: String?
    let children: [BranchTreeNode]
    var isGroup: Bool { branchName == nil }
    var outlineChildren: [BranchTreeNode]? { children.isEmpty ? nil : children }
}

struct RemoteInfo: Identifiable, Hashable, Sendable {
    let name: String
    let url: String
    var id: String { name }
}

// MARK: - Auth

struct GitAuthContext: Sendable {
    let operationLabel: String
    let commandSummary: String
    let remoteURL: String
    let host: String
    let usernameHint: String?
    let errorMessage: String
    let isAzureDevOps: Bool
}

enum GitAuthPromptResult: Sendable {
    case cancelled
    case provided(username: String, secret: String)
}

// MARK: - Reflog

struct ReflogEntry: Identifiable {
    let id = UUID()
    let hash: String
    let shortHash: String
    let refName: String
    let action: String
    let message: String
    let detail: String
    let branch: String
    let date: Date
    let relativeDate: String

    /// Derive a human-readable explanation from the raw reflog message.
    static func humanDetail(from message: String, action: String) -> String {
        let msg = message.trimmingCharacters(in: .whitespaces)

        switch action.lowercased() {
        case "commit", "commit (initial)":
            if let idx = msg.range(of: ": ") {
                return String(msg[idx.upperBound...])
            }
            return msg

        case "commit (amend)":
            if let idx = msg.range(of: ": ") {
                return "Amended: \(msg[idx.upperBound...])"
            }
            return "Amended last commit"

        case "checkout":
            if let fromRange = msg.range(of: "moving from "),
               let toRange = msg.range(of: " to ", range: fromRange.upperBound..<msg.endIndex) {
                let from = msg[fromRange.upperBound..<toRange.lowerBound]
                let to = msg[toRange.upperBound...]
                return "\(from) → \(to)"
            }
            return msg

        case "reset":
            if msg.contains("moving to HEAD") {
                return "Discarded staged changes"
            } else if let toRange = msg.range(of: "moving to ") {
                let target = msg[toRange.upperBound...]
                let short = target.count > 10 ? String(target.prefix(8)) + "…" : String(target)
                return "Moved HEAD to \(short)"
            }
            return msg

        case "pull":
            return "Pulled remote changes"

        case "merge":
            if let idx = msg.range(of: ": ") {
                return "Merged \(msg[idx.upperBound...])"
            }
            return msg

        case "rebase":
            if msg.contains("(finish)") { return "Rebase completed" }
            if msg.contains("(start)") { return "Rebase started" }
            return "Rebased current branch"

        case "cherry-pick":
            if let idx = msg.range(of: ": ") {
                return String(msg[idx.upperBound...])
            }
            return msg

        case "clone":
            return "Cloned repository"

        default:
            if let idx = msg.range(of: ": ") {
                return String(msg[idx.upperBound...])
            }
            return msg
        }
    }

    /// Parse the destination branch from a checkout reflog message.
    static func parseCheckoutBranches(from message: String) -> (from: String, to: String)? {
        guard let fromRange = message.range(of: "moving from "),
              let toRange = message.range(of: " to ", range: fromRange.upperBound..<message.endIndex) else {
            return nil
        }
        let from = String(message[fromRange.upperBound..<toRange.lowerBound])
        let to = String(message[toRange.upperBound...])
        return (from, to)
    }

    /// Tooltip explaining what this action type means.
    static func tooltip(for action: String) -> String? {
        switch action.lowercased() {
        case "reset":
            return "git reset — moved HEAD to a different commit"
        case "rebase":
            return "git rebase — replayed commits onto a new base"
        case "cherry-pick":
            return "git cherry-pick — applied a commit from another branch"
        case "merge":
            return "git merge — combined branch histories"
        case "checkout":
            return "git checkout — switched branches"
        default:
            return nil
        }
    }
}

// MARK: - Tags

enum TagType: String, CaseIterable, Identifiable, Sendable {
    case lightweight
    case annotated
    case signed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lightweight: return L10n("tag.detail.type.lightweight")
        case .annotated: return L10n("tag.detail.type.annotated")
        case .signed: return L10n("tag.detail.type.signed")
        }
    }
}

struct TagInfo: Identifiable, Sendable {
    let name: String
    let type: TagType
    let message: String
    let tagger: String
    let date: Date?
    var id: String { name }
}
