import Foundation
import SwiftUI

struct RebaseItem: Identifiable {
    let id = UUID()
    let hash: String
    let shortHash: String
    let subject: String
    var action: RebaseAction = .pick
}

enum RebaseAction: String, CaseIterable, Identifiable {
    case pick, reword, edit, squash, fixup, drop
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pick: return "pick"
        case .reword: return "reword"
        case .edit: return "edit"
        case .squash: return "squash"
        case .fixup: return "fixup"
        case .drop: return "drop"
        }
    }
    var icon: String {
        switch self {
        case .pick: return "checkmark.circle"
        case .reword: return "pencil.circle"
        case .edit: return "pause.circle"
        case .squash: return "arrow.triangle.merge"
        case .fixup: return "arrow.triangle.merge"
        case .drop: return "trash.circle"
        }
    }
    var color: Color {
        switch self {
        case .pick: return DesignSystem.Colors.success
        case .reword: return DesignSystem.Colors.info
        case .edit: return DesignSystem.Colors.warning
        case .squash: return DesignSystem.Colors.ai
        case .fixup: return DesignSystem.Colors.ai
        case .drop: return DesignSystem.Colors.destructive
        }
    }
}
