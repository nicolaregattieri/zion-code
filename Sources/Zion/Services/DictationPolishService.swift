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
    /// `localeIdentifier` is the Apple Speech locale used to capture the
    /// transcript (e.g. "pt-BR"). When supplied, it is injected into the
    /// system prompt so weaker instruction-following models (Qwen-Coder,
    /// small Llama variants) do not silently translate the output.
    static func polish(rawText: String, repoURL: URL?, localeIdentifier: String? = nil) async -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !trimmed.isEmpty else { return trimmed }

        let providerRaw = UserDefaults.standard.string(forKey: UserDefaultsKeys.AI.provider)
            ?? AIProvider.none.rawValue
        var provider = AIProvider(rawValue: providerRaw) ?? .none

        // codexCLI exec mode does not expose a `--system-prompt` replace flag,
        // so we can't run it isolated for polish. Skip it during auto-route
        // so the chain falls through to a raw-API provider instead.
        let polishUnfriendly: Set<AIProvider> = [.codexCLI]

        // `.auto` and `.none` cannot be called directly. Pick a concrete
        // provider that has a key/binary available. For `.auto` we ask the
        // orchestrator (cheapSummary lane), for `.none` we just give up.
        if provider == .auto || polishUnfriendly.contains(provider) {
            let orchestrator = ProviderOrchestrator()
            var attempt = await orchestrator.resolve(lane: .cheapSummary, requested: .auto)
            var guardCount = 0
            while polishUnfriendly.contains(attempt), guardCount < 3 {
                await orchestrator.markRateLimited(attempt, retryAfter: 60)
                attempt = await orchestrator.resolve(lane: .cheapSummary, requested: .auto)
                guardCount += 1
            }
            provider = attempt
        }
        await DiagnosticLogger.shared.log(
            .info,
            "polish.provider resolved=\(provider.rawValue) rawChars=\(trimmed.count)",
            source: "DictationPolishService.polish"
        )
        guard provider != .none, provider != .auto, !polishUnfriendly.contains(provider) else {
            await DiagnosticLogger.shared.log(
                .warn,
                "polish.skip no eligible provider (resolved=\(provider.rawValue))",
                source: "DictationPolishService.polish"
            )
            return trimmed
        }

        // Compose the effective system prompt with an explicit
        // language-preservation directive when the caller supplied a locale.
        // Forces small / code-tuned models to keep output in PT-BR (or
        // whatever locale Apple used) instead of silently translating to EN.
        let effectiveSystemPrompt: String
        if let loc = localeIdentifier, !loc.isEmpty {
            effectiveSystemPrompt = systemPrompt + """


            ## CRITICAL LANGUAGE RULE
            The dictation was captured with locale `\(loc)`. The polished
            output MUST be written in the same language as the input. If the
            input is Portuguese, the output is Portuguese. NEVER translate
            to English (or any other language). Mixed-language input stays
            mixed exactly as the speaker said it.
            """
        } else {
            effectiveSystemPrompt = systemPrompt
        }

        let started = Date()
        let cleaned: String
        if provider == .claudeCLI {
            // CLI providers must use the dedicated one-shot subprocess path so
            // they don't load CLAUDE.md / MCP / edit-harness and end up
            // answering the dictation conversationally.
            guard let polished = await polishViaClaudeCLI(text: trimmed, systemPromptOverride: effectiveSystemPrompt) else {
                await DiagnosticLogger.shared.log(
                    .error,
                    "polish.error provider=claudeCLI subprocess returned nil",
                    source: "DictationPolishService.polish"
                )
                return trimmed
            }
            cleaned = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if provider == .codexCLI {
            // Codex CLI does not expose a --system-prompt replace flag in
            // exec mode, so we can't safely isolate it from the project
            // session. Bail.
            await DiagnosticLogger.shared.log(
                .warn,
                "polish.skip codexCLI cannot run isolated one-shot polish",
                source: "DictationPolishService.polish"
            )
            return trimmed
        } else {
            // Raw-API path with one-shot fallback: if the first attempt
            // fails with a connection error (typical when local server is
            // down but `isConnected(.local)` still says true from a stale
            // health stamp), mark it rate-limited and try the next
            // eligible provider once.
            let apiKey = AIClient.loadAPIKey(for: provider) ?? ""
            let payload = AIPromptPayload(
                systemInstructions: effectiveSystemPrompt,
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
                cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                await DiagnosticLogger.shared.log(
                    .error,
                    "polish.error provider=\(provider.rawValue) error=\(String(describing: error))",
                    source: "DictationPolishService.polish"
                )
                // Mark the failing provider rate-limited (short cooldown,
                // in-process only) and ask the orchestrator for the next
                // eligible candidate.
                let orchestrator = ProviderOrchestrator()
                await orchestrator.markRateLimited(provider, retryAfter: 60)
                var fallback = await orchestrator.resolve(lane: .cheapSummary, requested: .auto)
                var guardCount = 0
                while polishUnfriendly.contains(fallback), guardCount < 3 {
                    await orchestrator.markRateLimited(fallback, retryAfter: 60)
                    fallback = await orchestrator.resolve(lane: .cheapSummary, requested: .auto)
                    guardCount += 1
                }
                guard fallback != .none, fallback != provider else {
                    await DiagnosticLogger.shared.log(
                        .warn,
                        "polish.fallback chain exhausted — returning raw",
                        source: "DictationPolishService.polish"
                    )
                    return trimmed
                }
                await DiagnosticLogger.shared.log(
                    .info,
                    "polish.fallback from=\(provider.rawValue) to=\(fallback.rawValue)",
                    source: "DictationPolishService.polish"
                )
                if fallback == .claudeCLI {
                    guard let polished = await polishViaClaudeCLI(text: trimmed, systemPromptOverride: effectiveSystemPrompt) else {
                        return trimmed
                    }
                    cleaned = polished.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    let fbKey = AIClient.loadAPIKey(for: fallback) ?? ""
                    do {
                        let result = try await client.call(
                            payload: payload,
                            provider: fallback,
                            apiKey: fbKey,
                            maxTokens: max(64, min(1024, trimmed.count * 2)),
                            lane: .cheapSummary,
                            mode: .efficient
                        )
                        cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    } catch {
                        await DiagnosticLogger.shared.log(
                            .error,
                            "polish.fallback.error provider=\(fallback.rawValue) error=\(String(describing: error))",
                            source: "DictationPolishService.polish"
                        )
                        return trimmed
                    }
                }
            }
        }
        let dur = Int(Date().timeIntervalSince(started) * 1000)
        await DiagnosticLogger.shared.log(
            .info,
            "polish.done provider=\(provider.rawValue) dur=\(dur)ms outChars=\(cleaned.count) changed=\(cleaned != trimmed)",
            source: "DictationPolishService.polish"
        )
        return cleaned.isEmpty ? trimmed : cleaned
    }

    /// Spawns `claude -p` in **isolated** mode (no project CLAUDE.md, no MCP
    /// config, no edit-harness, no session resume) with the polish system
    /// prompt overridden. Returns nil on subprocess failure.
    private static func polishViaClaudeCLI(text: String, systemPromptOverride: String? = nil) async -> String? {
        let discovery = CLIDiscoveryService()
        let status = await discovery.status(for: CLITool.claude)
        guard status.installed, let toolPath = status.path else { return nil }

        let process = Process()
        process.executableURL = toolPath
        process.arguments = [
            "-p", "-",
            "--system-prompt", systemPromptOverride ?? systemPrompt,
            "--output-format", "text",
            "--permission-mode", "default"
        ]
        // Run from /tmp so the CLI does not auto-load the project's CLAUDE.md.
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            // Feed the dictation transcript on stdin.
            stdinPipe.fileHandleForWriting.write(Data(text.utf8))
            try? stdinPipe.fileHandleForWriting.close()
        } catch {
            return nil
        }

        // Hard timeout — polish should finish in seconds.
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                return nil
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw.isEmpty ? nil : raw
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
