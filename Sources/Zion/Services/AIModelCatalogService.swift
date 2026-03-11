import Foundation

enum AIModelCatalogService {
    static func selection(for provider: AIProvider, mode: AIMode, lane: AITaskLane) -> AIResolvedModelSelection {
        switch provider {
        case .openai:
            return openAISelection(mode: mode, lane: lane)
        case .anthropic:
            return anthropicSelection(mode: mode, lane: lane)
        case .gemini:
            return geminiSelection(mode: mode, lane: lane)
        case .none:
            return AIResolvedModelSelection(lane: lane, primaryModelID: "", fallbackModelIDs: [])
        }
    }

    static func mappingRows(for provider: AIProvider, mode: AIMode) -> [(lane: AITaskLane, modelID: String)] {
        AITaskLane.allCases.map { lane in
            let selection = selection(for: provider, mode: mode, lane: lane)
            return (lane, selection.primaryModelID)
        }
    }

    private static func openAISelection(mode: AIMode, lane: AITaskLane) -> AIResolvedModelSelection {
        let efficientChat = "gpt-4o-mini"
        let smartChat = "gpt-5-mini"
        let premiumChat = "gpt-5.1"

        switch lane {
        case .cheapSummary:
            return makeSelection(lane: lane, primary: efficientChat, fallbacks: [smartChat, premiumChat])
        case .general:
            switch mode {
            case .efficient: return makeSelection(lane: lane, primary: efficientChat, fallbacks: [smartChat, premiumChat])
            case .smart: return makeSelection(lane: lane, primary: smartChat, fallbacks: [efficientChat, premiumChat])
            case .bestQuality: return makeSelection(lane: lane, primary: premiumChat, fallbacks: [smartChat, efficientChat])
            }
        case .review, .reasoning:
            switch mode {
            case .efficient: return makeSelection(lane: lane, primary: efficientChat, fallbacks: [smartChat, premiumChat])
            case .smart: return makeSelection(lane: lane, primary: smartChat, fallbacks: [efficientChat, premiumChat])
            case .bestQuality: return makeSelection(lane: lane, primary: premiumChat, fallbacks: [smartChat, efficientChat])
            }
        case .transcription:
            return makeSelection(lane: lane, primary: "whisper-1", fallbacks: [])
        }
    }

    private static func anthropicSelection(mode: AIMode, lane: AITaskLane) -> AIResolvedModelSelection {
        let efficientChat = "claude-3-5-haiku-20241022"
        let smartChat = "claude-sonnet-4-0"
        let premiumChat = "claude-opus-4-1"

        switch lane {
        case .cheapSummary:
            return makeSelection(lane: lane, primary: efficientChat, fallbacks: [smartChat, premiumChat])
        case .general:
            switch mode {
            case .efficient: return makeSelection(lane: lane, primary: efficientChat, fallbacks: [smartChat, premiumChat])
            case .smart: return makeSelection(lane: lane, primary: smartChat, fallbacks: [efficientChat, premiumChat])
            case .bestQuality: return makeSelection(lane: lane, primary: premiumChat, fallbacks: [smartChat, efficientChat])
            }
        case .review, .reasoning:
            switch mode {
            case .efficient: return makeSelection(lane: lane, primary: efficientChat, fallbacks: [smartChat, premiumChat])
            case .smart: return makeSelection(lane: lane, primary: smartChat, fallbacks: [efficientChat, premiumChat])
            case .bestQuality: return makeSelection(lane: lane, primary: premiumChat, fallbacks: [smartChat, efficientChat])
            }
        case .transcription:
            return makeSelection(lane: lane, primary: efficientChat, fallbacks: [smartChat])
        }
    }

    private static func geminiSelection(mode: AIMode, lane: AITaskLane) -> AIResolvedModelSelection {
        let efficientChat = "gemini-2.5-flash-lite"
        let smartChat = "gemini-2.5-flash"
        let premiumChat = "gemini-2.5-pro"

        switch lane {
        case .cheapSummary:
            return makeSelection(lane: lane, primary: efficientChat, fallbacks: [smartChat, premiumChat])
        case .general:
            switch mode {
            case .efficient: return makeSelection(lane: lane, primary: efficientChat, fallbacks: [smartChat, premiumChat])
            case .smart: return makeSelection(lane: lane, primary: smartChat, fallbacks: [efficientChat, premiumChat])
            case .bestQuality: return makeSelection(lane: lane, primary: premiumChat, fallbacks: [smartChat, efficientChat])
            }
        case .review, .reasoning:
            switch mode {
            case .efficient: return makeSelection(lane: lane, primary: efficientChat, fallbacks: [smartChat, premiumChat])
            case .smart: return makeSelection(lane: lane, primary: smartChat, fallbacks: [efficientChat, premiumChat])
            case .bestQuality: return makeSelection(lane: lane, primary: premiumChat, fallbacks: [smartChat, efficientChat])
            }
        case .transcription:
            return makeSelection(lane: lane, primary: efficientChat, fallbacks: [smartChat])
        }
    }

    private static func makeSelection(lane: AITaskLane, primary: String, fallbacks: [String]) -> AIResolvedModelSelection {
        AIResolvedModelSelection(
            lane: lane,
            primaryModelID: primary,
            fallbackModelIDs: Array(NSOrderedSet(array: fallbacks).array as? [String] ?? [])
        )
    }
}
