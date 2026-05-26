import Foundation

/// One-shot LLM post-processing for dictated text. Apple Speech (the default
/// engine for the chat composer mic) handles single-language audio reasonably
/// well but stumbles on bilingual flows — Brazilian developers naturally
/// switch between Portuguese narration and English technical terms ("vou
/// fazer um pull request no branch master", "use o `print` para debug"), and
/// the raw transcript ends up with phonetically-coerced English words.
///
/// This service routes the raw transcript through the user's already-configured
/// AI provider with a short system prompt to clean the transcription. It runs
/// only when `chat.dictation.polish` is enabled (default true). On any error
/// the raw text is returned untouched.
enum DictationPolishService {

    static let settingsKey = "chat.dictation.polish"

    static var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: settingsKey) as? Bool) ?? true
    }

    /// Polish a raw dictation result. Returns the (possibly cleaned) text.
    /// Always returns at least the original transcript — never throws.
    static func polish(rawText: String, repoURL: URL?) async -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !trimmed.isEmpty else { return trimmed }

        let providerRaw = UserDefaults.standard.string(forKey: UserDefaultsKeys.AI.provider)
            ?? AIProvider.none.rawValue
        var provider = AIProvider(rawValue: providerRaw) ?? .none

        // `.auto` and `.none` cannot be called directly. Pick a concrete
        // provider that has a key/binary available. For `.auto` we ask the
        // orchestrator (cheapSummary lane), for `.none` we just give up.
        if provider == .auto {
            let orchestrator = ProviderOrchestrator()
            provider = await orchestrator.resolve(lane: .cheapSummary, requested: .auto)
        }
        guard provider != .none, provider != .auto else { return trimmed }

        let apiKey = AIClient.loadAPIKey(for: provider) ?? ""

        let payload = AIPromptPayload(
            systemInstructions: systemPrompt,
            taskInstructions: "## Raw dictation transcript\n\n\(trimmed)\n\n## Polished output",
            untrustedSections: [],
            suspiciousPatterns: [],
            cwd: repoURL
        )

        let client = AIClient()
        do {
            let result = try await client.call(
                payload: payload,
                provider: provider,
                apiKey: apiKey,
                maxTokens: max(64, min(1024, trimmed.count * 2)),
                lane: .cheapSummary,
                mode: .efficient
            )
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? trimmed : cleaned
        } catch {
            return trimmed
        }
    }

    private static let systemPrompt = """
    You polish dictated developer speech into clean text for a chat composer.

    Rules:
    - Fix obvious transcription mistakes using software-development context (e.g. "pull request", "branch master", "merge conflict", function/class/file names that match common English programming vocabulary).
    - Preserve mixed-language input as-is. If the speaker mixes Portuguese narration and English technical terms, keep both: do NOT translate the Portuguese into English or vice versa.
    - Restore punctuation and capitalization where missing. Keep the speaker's tone (informal / formal) intact.
    - Do NOT add new ideas, expand bullet points, or fabricate context the speaker did not say.
    - Output ONLY the polished text. No preamble, no quotes around the result, no markdown decoration.
    """
}
