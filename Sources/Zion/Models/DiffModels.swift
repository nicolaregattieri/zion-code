import Foundation
import SwiftUI

// MARK: - Diff Hunks & Lines

struct DiffHunk: Identifiable {
    let id = UUID()
    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]
}

struct DiffLine: Identifiable {
    let id = UUID()
    let type: LineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?

    enum LineType {
        case context, addition, deletion
    }
}

struct FileDiff: Identifiable {
    let id = UUID()
    let oldPath: String
    let newPath: String
    let headerLines: [String]
    let hunks: [DiffHunk]
}

// MARK: - Diff Explanation

enum DiffExplanationDepth: String, CaseIterable, Identifiable {
    case quick, detailed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .quick: return L10n("settings.diff.depth.quick")
        case .detailed: return L10n("settings.diff.depth.detailed")
        }
    }
}

struct DiffExplanation: Sendable {
    let intent: String
    let risks: String
    let narrative: String
    let severity: DiffExplanationSeverity

    enum DiffExplanationSeverity: String, Sendable {
        case safe, moderate, risky

        var color: Color {
            switch self {
            case .safe: return DesignSystem.Colors.success
            case .moderate: return DesignSystem.Colors.warning
            case .risky: return DesignSystem.Colors.destructive
            }
        }

        var label: String {
            switch self {
            case .safe: return L10n("diff.severity.safe")
            case .moderate: return L10n("diff.severity.moderate")
            case .risky: return L10n("diff.severity.risky")
            }
        }
    }
}
