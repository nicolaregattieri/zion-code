import Foundation

/// Phase 6 — auto-context wiring on ChatService. Exposes the trio of
/// state writers (`refreshPendingContext`, `removePendingContext`,
/// `consumePendingContext`) so the composer pipeline and the chip row
/// stay in sync.
@MainActor
extension ChatService {

    /// Recompute the pending auto-context list for the current draft.
    /// Called on composer-text settle. Returns immediately when the
    /// feature flag is off or the locator is empty.
    func refreshPendingContext(for message: String) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.pendingContextHits = []
            self.isPendingContextLoading = false
            return
        }
        // Synchronous skip check — avoids the 150ms skeleton flash on
        // every keystroke that maps to a meta phrase.
        if ChatContextAutoInjector.skipReason(for: trimmed) != nil {
            self.pendingContextHits = []
            self.isPendingContextLoading = false
            return
        }
        self.isPendingContextLoading = true
        let tier: ChatContextAutoInjector.Tier = Self.tier(for: AIProvider(rawValue: UserDefaults.standard.string(forKey: UserDefaultsKeys.AI.provider) ?? "") ?? .none)
        let mentions = self.pendingMentionedPaths
        let injector = ChatContextAutoInjector()
        let payload = await injector.resolve(message: trimmed, tier: tier, mentionedPaths: mentions)
        self.pendingContextHits = payload.hits
        self.isPendingContextLoading = false
    }

    /// User dismissed a chip — drop it from the pending list so it does
    /// not land in the upcoming request.
    func removePendingContext(_ hit: RAGHit) {
        self.pendingContextHits.removeAll { $0.chunk.contentSHA == hit.chunk.contentSHA }
    }

    /// Snapshot + clear the pending context. Called from the send path
    /// right before the request body is built so the chip row blanks
    /// at the same moment the message leaves the composer.
    func consumePendingContext() -> ChatContextAutoInjector.Payload {
        let hits = self.pendingContextHits
        self.pendingContextHits = []
        self.isPendingContextLoading = false
        let tokens = hits.reduce(0) { sum, hit in
            sum + ChatContextAutoInjector.estimateChunkTokens(hit.chunk)
        }
        return ChatContextAutoInjector.Payload(
            hits: hits, estimatedTokens: tokens, truncated: false, skippedReason: nil
        )
    }

    /// Provider-tier mapping for the budget cap. Local LLMs and the
    /// cheap hosted tiers (Haiku, GPT-4o-mini) share the cheap budget;
    /// Opus / Sonnet 4+ / GPT-5 / Gemini Pro share the expensive one.
    static func tier(for provider: AIProvider) -> ChatContextAutoInjector.Tier {
        switch provider {
        case .anthropic, .openai, .gemini:
            return .expensive
        case .auto, .none, .local, .claudeCLI, .codexCLI:
            return .cheap
        }
    }
}
