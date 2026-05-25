import Foundation

/// Picks a `SmartAutoTier` for a user message. Pluggable behind a protocol so we
/// can swap the default heuristic for an LLM-backed classifier without touching
/// the orchestrator or ChatService.
protocol AutoTriageClassifier: Sendable {
    func classify(_ text: String) async -> SmartAutoTier
}

/// Pure-Swift heuristic triage. Zero latency, zero cost. Covers the obvious 70%
/// of turns (greetings, code fences, file paths, deep-reasoning keywords) and
/// returns `.medium` as the safe default for ambiguous text.
///
/// Strategy (most specific first):
///   1. Empty / very short greeting          → easy
///   2. Reasoning keywords OR long question  → hard
///   3. Review/audit keywords                → hard
///   4. Code signals (fence / path / @file)  → medium
///   5. Short conversational fragment        → easy
///   6. Default                              → medium
///
/// An LLM-backed classifier (P15.5) will subclass / wrap this — the heuristic
/// stays as the cheap fast-path so trivial cases skip the model call.
struct HeuristicTriageClassifier: AutoTriageClassifier {

    func classify(_ raw: String) async -> SmartAutoTier {
        Self.classifySync(raw)
    }

    /// Sync variant — heuristic is pure CPU, exposed for live-preview chips
    /// that need a tier on every keystroke without semaphores or Task hops.
    static func classifySync(_ raw: String) -> SmartAutoTier {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .easy }

        let lower = text.lowercased()

        if matchesReasoning(lower, length: text.count) { return .hard }
        if matchesReview(lower)                         { return .hard }
        if matchesCodeSignal(text)                       { return .medium }
        if isShortConversational(text)                   { return .easy }
        return .medium
    }

    // MARK: - Heuristics

    private static let reasoningMarkers: [String] = [
        "why ", "por que ", "porque ", "por qué ",
        "explain ", "explica ", "explique ",
        "design ", "architecture", "arquitetura", "arquitectura",
        "trade-off", "tradeoff", "trade off",
        "best practice", "boas práticas", "boas praticas",
        "refactor", "refatora", "refactore", "redesign",
        "compare ", "compara ", "which is better", "qual é melhor",
        // Planning / feature work — multi-step tasks belong on the hard tier.
        // Use leading-space prefix so "do a plan", "the plan", "make plan" all
        // match without false-positives on "plane", "planning", "complain".
        " plan", "plano ", "planeje", "planejar", "planejamento",
        "planea", "planear",   // ES
        "design a ", "designa ", "elabore ",
        " feature", "new feature", "nova feature", "spec ",
        "implement ", "implementa", "implemente", "implementar",
        " build ", "construa ", "construir"
    ]

    private static let reviewMarkers: [String] = [
        "review", "revisa", "revise", "audit", "audita",
        "code review", "check this", "find bugs", "encontra bugs"
    ]

    private static func matchesReasoning(_ lower: String, length: Int) -> Bool {
        // Marker list uses leading-space prefixes (" plan", " feature", etc.)
        // to avoid false positives like "complain"/"airplane". Also accept the
        // marker when it sits at the start of the message (no preceding space).
        if Self.reasoningMarkers.contains(where: { marker in
            if lower.contains(marker) { return true }
            if marker.hasPrefix(" ") {
                let bare = String(marker.dropFirst())
                return lower.hasPrefix(bare)
            }
            return false
        }) { return true }
        return length > 280 && lower.contains("?")
    }

    private static func matchesReview(_ lower: String) -> Bool {
        Self.reviewMarkers.contains { lower.contains($0) }
    }

    private static let slashRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(?m)^\s*/(diff|log|status|file|commit)(\s|$)"#)
    }()

    private static let fileExtRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"[A-Za-z0-9_./-]+\.(swift|ts|tsx|js|jsx|py|rb|go|rs|java|kt|md|json|yaml|yml|sh)\b"#)
    }()

    private static func matchesCodeSignal(_ text: String) -> Bool {
        if text.contains("```") { return true }
        if text.contains("@file ") || text.contains("@folder ") || text.contains("@selection") { return true }
        let nsRange = NSRange(text.startIndex..., in: text)
        if Self.slashRegex.firstMatch(in: text, options: [], range: nsRange) != nil { return true }
        if Self.fileExtRegex.firstMatch(in: text, options: [], range: nsRange) != nil { return true }
        return false
    }

    private static func isShortConversational(_ text: String) -> Bool {
        let length = text.count
        if length >= 80 { return false }
        let words = text.split { $0.isWhitespace }.count
        return words <= 10
    }
}

// MARK: - SmartAutoTriage

/// Façade combining a classifier + the tier table. Given a message and an
/// already-resolved provider, returns the recommended (tier, modelID) for that
/// turn. The orchestrator stays in charge of provider eligibility; this just
/// picks the cheapest/fastest model that fits the request inside that provider.
struct SmartAutoTriage {

    let classifier: AutoTriageClassifier
    let tierTable: SmartAutoTierTable

    init(
        classifier: AutoTriageClassifier = HeuristicTriageClassifier(),
        tierTable: SmartAutoTierTable = .default
    ) {
        self.classifier = classifier
        self.tierTable = tierTable
    }

    struct Decision: Equatable {
        let tier: SmartAutoTier
        let modelID: String?   // nil → fall back to catalog default for provider
    }

    /// Classify the message and pick the per-provider model. `provider` is the
    /// concrete provider already resolved by the orchestrator (never `.auto`).
    func decide(text: String, provider: AIProvider) async -> Decision {
        let tier = await classifier.classify(text)
        let model = tierTable.modelID(provider: provider, tier: tier)
        return Decision(tier: tier, modelID: model)
    }
}
