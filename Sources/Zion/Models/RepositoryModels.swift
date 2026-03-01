import Foundation
import SwiftUI

// MARK: - Recovery Snapshots

enum RecoverySnapshotSource: String, CaseIterable, Sendable {
    case activeStash
    case danglingSnapshot

    var l10nKey: String {
        switch self {
        case .activeStash: return "recovery.source.activeStash"
        case .danglingSnapshot: return "recovery.source.danglingSnapshot"
        }
    }
}

struct RecoverySnapshot: Identifiable, Hashable, Sendable {
    let hash: String
    let shortHash: String
    let reference: String?
    let subject: String
    let date: Date
    let source: RecoverySnapshotSource

    var id: String { hash + "::" + (reference ?? "dangling") }
    var isZionManaged: Bool {
        subject.contains("zion-safety-") || subject.contains("zion-transfer-") || subject.contains("zion-pre-")
    }
}

// MARK: - Submodules

struct SubmoduleInfo: Identifiable {
    let name: String
    let path: String
    let url: String
    let hash: String
    let status: SubmoduleStatus
    var id: String { path }

    enum SubmoduleStatus {
        case upToDate, modified, uninitialized

        var label: String {
            switch self {
            case .upToDate: return L10n("OK")
            case .modified: return L10n("Modificado")
            case .uninitialized: return L10n("Nao inicializado")
            }
        }

        var icon: String {
            switch self {
            case .upToDate: return "checkmark.circle.fill"
            case .modified: return "exclamationmark.circle.fill"
            case .uninitialized: return "circle.dashed"
            }
        }

        var color: Color {
            switch self {
            case .upToDate: return DesignSystem.Colors.success
            case .modified: return DesignSystem.Colors.warning
            case .uninitialized: return .secondary
            }
        }
    }
}

// MARK: - Repository Statistics

struct RepositoryStats {
    let totalCommits: Int
    let totalBranches: Int
    let totalTags: Int
    let contributors: [ContributorStat]
    let languageBreakdown: [LanguageStat]
    let firstCommitDate: Date?
    let lastCommitDate: Date?
}

struct ContributorStat: Identifiable {
    let name: String
    let email: String
    let commitCount: Int
    var id: String { email }
}

struct LanguageStat: Identifiable {
    let language: String
    let fileCount: Int
    let percentage: Double
    var id: String { language }
}

// MARK: - Background Repo State

struct BackgroundRepoState {
    var terminalTabs: [TerminalPaneNode]
    var activeTabID: UUID?
    var focusedSessionID: UUID?
    var fileWatcher: FileWatcher
    var monitorTask: Task<Void, Never>?
}
