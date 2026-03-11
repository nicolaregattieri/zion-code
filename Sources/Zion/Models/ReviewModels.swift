import Foundation
import SwiftUI

// MARK: - AI Review Findings

struct ReviewFinding: Identifiable {
    let id = UUID()
    let severity: ReviewSeverity
    let file: String
    let message: String
    let evidence: String?
    let testImpact: String?

    init(
        severity: ReviewSeverity,
        file: String,
        message: String,
        evidence: String? = nil,
        testImpact: String? = nil
    ) {
        self.severity = severity
        self.file = file
        self.message = message
        self.evidence = ReviewFinding.normalizedOptionalText(evidence)
        self.testImpact = ReviewFinding.normalizedOptionalText(testImpact)
    }

    enum ReviewSeverity: String {
        case critical, warning, suggestion

        var color: Color {
            switch self {
            case .critical: return DesignSystem.Colors.destructive
            case .warning: return DesignSystem.Colors.warning
            case .suggestion: return DesignSystem.Colors.info
            }
        }

        var icon: String {
            switch self {
            case .critical: return "exclamationmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .suggestion: return "lightbulb.fill"
            }
        }

        var label: String {
            switch self {
            case .critical: return L10n("Critico")
            case .warning: return L10n("Aviso")
            case .suggestion: return L10n("Sugestao")
            }
        }
    }

    var hasEvidence: Bool { evidence != nil }
    var hasTestImpact: Bool { testImpact != nil }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "-" else { return nil }
        return trimmed
    }
}

struct CommitSuggestion: Identifiable {
    let id = UUID()
    let message: String
    let files: [String]
}

// MARK: - Code Review

struct CodeReviewFile: Identifiable {
    let id = UUID()
    let path: String
    let status: FileChangeStatus
    let additions: Int
    let deletions: Int
    var findings: [ReviewFinding] = []
    var explanation: DiffExplanation?
    var diff: String = ""
    var hunks: [DiffHunk] = []
    var isReviewed: Bool = false
    var inlineComments: [PRComment] = []
}

enum FileChangeStatus: String, Sendable {
    case added, modified, deleted, renamed

    var icon: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .added: return DesignSystem.Colors.fileAdded
        case .modified: return DesignSystem.Colors.fileModified
        case .deleted: return DesignSystem.Colors.fileDeleted
        case .renamed: return DesignSystem.Colors.fileRenamed
        }
    }

    var label: String {
        switch self {
        case .added: return L10n("file.status.added")
        case .modified: return L10n("file.status.modified")
        case .deleted: return L10n("file.status.deleted")
        case .renamed: return L10n("file.status.renamed")
        }
    }
}

struct CodeReviewStats {
    let totalFiles: Int
    let totalAdditions: Int
    let totalDeletions: Int
    let commitCount: Int
    let criticalCount: Int
    let warningCount: Int
    let suggestionCount: Int

    var overallRisk: DiffExplanation.DiffExplanationSeverity {
        if criticalCount > 0 { return .risky }
        if warningCount > 2 { return .moderate }
        return .safe
    }
}

// MARK: - PR Review Queue

enum PRReviewStatus: String, Sendable {
    case pending, reviewing, reviewed, clean

    var label: String {
        switch self {
        case .pending: return L10n("pr.status.pending")
        case .reviewing: return L10n("pr.status.reviewing")
        case .reviewed: return L10n("pr.status.reviewed")
        case .clean: return L10n("pr.status.clean")
        }
    }

    var color: Color {
        switch self {
        case .pending: return .secondary
        case .reviewing: return DesignSystem.Colors.info
        case .reviewed: return DesignSystem.Colors.warning
        case .clean: return DesignSystem.Colors.success
        }
    }
}

struct PRReviewItem: Identifiable {
    let pr: GitHubPRInfo
    var status: PRReviewStatus = .pending
    var findings: [ReviewFinding] = []
    var reviewedAt: Date?
    var id: Int { pr.id }

    var severitySummary: String {
        let critical = findings.filter { $0.severity == .critical }.count
        let warning = findings.filter { $0.severity == .warning }.count
        if critical > 0 { return "\(critical) critical" }
        if warning > 0 { return "\(warning) warn" }
        if findings.isEmpty && status == .reviewed { return L10n("pr.status.clean") }
        return ""
    }
}
