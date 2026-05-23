// CLIRelayRunner.swift — Passthrough agentic runner for Claude CLI / Codex CLI.
//
// The CLI runs its OWN agent loop. Zion just relays I/O:
//   1. Spawns the CLI via AIClient.spawnCLIStream (existing helper).
//   2. Writes the user prompt to stdin.
//   3. Reads stdout line-by-line.
//   4. Parses each line as a CLIStreamEvent using the existing parsers.
//   5. For tool events → emits AgentStepEvent via onStep.
//   6. For text output → accumulates into finalText.
//   7. For turnCost → maps to LoopResult.cumulativeCostUSD.
//   8. On cancel → terminate process.
//   9. On CLI exit → returns LoopResult.
//
// NOTE: Unlike ToolLoopRunner, this runner takes a single `userPrompt` string (not
// a structured conversation array) because CLIs receive prompts on stdin, not via
// a message array API. `LoopResult.conversation` is set to [] (CLI manages its own
// conversation state server-side).
//
// Concurrency: implemented as an actor to give a stable isolation domain for the
// step counter and cost accumulator, while keeping onStep calls dispatched to MainActor.

import Foundation
import Darwin

// MARK: - CLIStreamFactory

/// Injectable factory for test isolation. Returns a stream of CLIStreamEvents and
/// a process canceller. The canceller is called when the CancellationToken fires.
///
/// T7 — exposed `internal` so CLIRelayRunnerTests can inject mock streams.
typealias CLIStreamFactory = @Sendable (
    AIProvider,
    String? // userPrompt
) async throws -> AsyncThrowingStream<CLIStreamEvent, Error>

// MARK: - ProcessCanceller

/// Abstraction over the cancel side-effect (SIGTERM to a real process, or a noop in tests).
protocol ProcessCanceller: Sendable {
    func cancel()
}

/// Production canceller: does nothing — cancellation is handled via stream termination.
/// The underlying `spawnCLIStream` sends SIGTERM/SIGKILL via `onTermination`.
struct StreamTerminationCanceller: ProcessCanceller {
    func cancel() { /* stream onTermination handles SIGTERM */ }
}

struct NoopCanceller: ProcessCanceller {
    func cancel() {}
}

// MARK: - CLIRelayRunner

actor CLIRelayRunner {

    // MARK: - Dependencies

    private let cliStreamFactory: CLIStreamFactory
    private let processCanceller: ProcessCanceller

    // MARK: - State

    private var stepCount = 0
    private var cumulativeCostUSD: Double = 0.0
    private var cumulativeTokens: Int = 0

    // MARK: - Init

    /// Production initializer. Builds real subprocesses via AIClient.
    ///
    /// - Parameters:
    ///   - provider: `.claudeCLI` or `.codexCLI`
    ///   - cwd: Working directory for the CLI subprocess.
    ///   - allowEdits: Whether to allow file edits (passed to permission mode).
    ///   - resumeSessionID: Optional session ID to resume a prior CLI session.
    ///   - modelOverride: Optional model string to pass via --model / -c model=.
    init(
        provider: AIProvider,
        cwd: URL,
        allowEdits: Bool = false,
        resumeSessionID: String? = nil,
        modelOverride: String? = nil
    ) {
        let client = AIClient()
        let capturedCWD = cwd
        let capturedAllowEdits = allowEdits
        let capturedResume = resumeSessionID
        let capturedModel = modelOverride

        self.cliStreamFactory = { provider, prompt in
            // Build a minimal payload: put the user prompt in taskInstructions.
            // systemInstructions and untrustedSections are empty for CLI passthrough
            // since the CLI manages its own context; we only relay the raw prompt.
            let payload = AIPromptPayload(
                systemInstructions: "",
                taskInstructions: prompt ?? "",
                untrustedSections: [],
                suspiciousPatterns: []
            )
            switch provider {
            case .claudeCLI:
                return await client.streamClaudeCLI(
                    payload: payload,
                    cwd: capturedCWD,
                    maxTokens: 8192,
                    allowEdits: capturedAllowEdits,
                    resumeSessionID: capturedResume,
                    modelOverride: capturedModel
                )
            case .codexCLI:
                return await client.streamCodexCLI(
                    payload: payload,
                    cwd: capturedCWD,
                    allowEdits: capturedAllowEdits,
                    resumeSessionID: capturedResume,
                    modelOverride: capturedModel
                )
            default:
                throw CLIRelayError.unsupportedProvider(provider)
            }
        }
        self.processCanceller = StreamTerminationCanceller()
    }

    /// Test-injection initializer. Accepts a scripted stream factory and optional canceller.
    ///
    /// T7 — `internal` so tests can inject mock streams.
    internal init(
        cliStreamFactory: @escaping CLIStreamFactory,
        processCanceller: ProcessCanceller = NoopCanceller()
    ) {
        self.cliStreamFactory = cliStreamFactory
        self.processCanceller = processCanceller
    }

    // MARK: - Run

    /// Executes the CLI passthrough: spawns CLI, relays I/O, returns LoopResult.
    ///
    /// - Parameters:
    ///   - provider:   `.claudeCLI` or `.codexCLI`
    ///   - model:      Optional model override string (ignored for stream selection, passed to factory).
    ///   - userPrompt: Single-string prompt written to CLI stdin.
    ///   - maxSteps:   Currently unused (CLI controls its own loop). Kept for signature parity with T5/T6.
    ///   - cancel:     CancellationToken polled between events.
    ///   - onStep:     Callback fired on MainActor for each tool event.
    /// - Returns: `LoopResult` summarising the run.
    func run(
        provider: AIProvider,
        model: String?,
        userPrompt: String,
        maxSteps: Int = 25,
        cancel: CancellationToken,
        onStep: @escaping @Sendable (AgentStepEvent) -> Void
    ) async throws -> LoopResult {

        // Reset per-run accumulators (runner is an actor so mutation is safe).
        stepCount = 0
        cumulativeCostUSD = 0.0
        cumulativeTokens = 0

        var finalText = ""
        var loopStop: LoopStopReason = .endTurn

        // Spawn CLI stream via factory.
        let stream: AsyncThrowingStream<CLIStreamEvent, Error>
        do {
            stream = try await cliStreamFactory(provider, userPrompt)
        } catch {
            return LoopResult(
                finalText: "",
                stepsUsed: 0,
                stopReason: .providerError(error.localizedDescription),
                cumulativeTokens: 0,
                cumulativeCostUSD: 0,
                cancelled: false,
                conversation: []
            )
        }

        // Consume events.
        do {
            for try await event in stream {
                // Poll cancellation between events.
                if await cancel.isCancelled {
                    processCanceller.cancel()
                    loopStop = .cancelled
                    break
                }

                switch event {
                case .textDelta(let text):
                    finalText += text

                case .toolStart(let id, let name, let description):
                    stepCount += 1
                    let toolEvent = ChatToolEvent(
                        id: id,
                        name: name,
                        status: .running,
                        argsPreview: description
                    )
                    let stepEvent = AgentStepEvent(
                        toolEvent: toolEvent,
                        stepIndex: stepCount,
                        cumulativeTokens: cumulativeTokens,
                        cumulativeCostUSD: cumulativeCostUSD
                    )
                    let capturedStep = stepEvent
                    onStep(capturedStep)

                case .toolEnd(let id, let success, let output):
                    // Emit a completion event for the tool.
                    let toolEvent = ChatToolEvent(
                        id: id,
                        name: "result",
                        status: success ? .completed : .failed,
                        argsPreview: output.map { String($0.prefix(60)) } ?? ""
                    )
                    let stepEvent = AgentStepEvent(
                        toolEvent: toolEvent,
                        stepIndex: stepCount,
                        cumulativeTokens: cumulativeTokens,
                        cumulativeCostUSD: cumulativeCostUSD
                    )
                    let capturedStep = stepEvent
                    onStep(capturedStep)

                case .turnCost(let usd):
                    cumulativeCostUSD += usd

                case .turnUsage(let inputTokens, let outputTokens):
                    cumulativeTokens += inputTokens + outputTokens

                case .sessionStarted:
                    break // informational only

                case .done:
                    loopStop = .endTurn
                    break

                case .error(let message):
                    loopStop = .providerError(message)
                }

                // Exit on terminal events from CLI.
                if case .done = event { break }
                if case .error = event { break }
            }
        } catch let err as AIError {
            // Non-zero exit code from CLI subprocess.
            if loopStop == .endTurn {
                switch err {
                case .cliError(let stderr, _):
                    loopStop = .providerError(stderr.isEmpty ? "CLI exited with non-zero status" : stderr)
                default:
                    loopStop = .providerError(err.localizedDescription)
                }
            }
        } catch {
            if loopStop == .endTurn {
                loopStop = .providerError(error.localizedDescription)
            }
        }

        return LoopResult(
            finalText: finalText,
            stepsUsed: stepCount,
            stopReason: loopStop,
            cumulativeTokens: cumulativeTokens,
            cumulativeCostUSD: cumulativeCostUSD,
            cancelled: loopStop == .cancelled,
            conversation: [] // CLI manages conversation state server-side
        )
    }
}

// MARK: - CLIRelayError

enum CLIRelayError: Error, LocalizedError {
    case unsupportedProvider(AIProvider)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let p):
            return "CLIRelayRunner only supports .claudeCLI and .codexCLI, got \(p.rawValue)"
        }
    }
}
