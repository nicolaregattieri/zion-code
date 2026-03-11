import Foundation

enum AIMode: String, CaseIterable, Identifiable {
    case efficient
    case smart
    case bestQuality

    var id: String { rawValue }

    var label: String {
        switch self {
        case .efficient: return L10n("settings.ai.mode.efficient")
        case .smart: return L10n("settings.ai.mode.smart")
        case .bestQuality: return L10n("settings.ai.mode.bestQuality")
        }
    }

    var hint: String {
        switch self {
        case .efficient: return L10n("settings.ai.mode.efficient.hint")
        case .smart: return L10n("settings.ai.mode.smart.hint")
        case .bestQuality: return L10n("settings.ai.mode.bestQuality.hint")
        }
    }
}

enum AITaskLane: String, CaseIterable, Identifiable {
    case cheapSummary
    case general
    case review
    case reasoning
    case transcription

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cheapSummary: return L10n("settings.ai.mapping.cheapSummary")
        case .general: return L10n("settings.ai.mapping.general")
        case .review: return L10n("settings.ai.mapping.review")
        case .reasoning: return L10n("settings.ai.mapping.reasoning")
        case .transcription: return L10n("settings.ai.mapping.transcription")
        }
    }
}

struct AIResolvedModelSelection: Equatable {
    let lane: AITaskLane
    let primaryModelID: String
    let fallbackModelIDs: [String]

    var allCandidateModelIDs: [String] {
        [primaryModelID] + fallbackModelIDs
    }
}
