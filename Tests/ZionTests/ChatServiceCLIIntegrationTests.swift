import XCTest
@testable import Zion

// MARK: - ChatServiceCLIIntegrationTests

@MainActor
final class ChatServiceCLIIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private func makeWorker() -> RepositoryWorker { RepositoryWorker() }
    private func makeAI() -> AIClient { AIClient() }

    private func makeService(
        repoURL: URL,
        cliStream: @escaping @Sendable (AIPromptPayload, URL) -> AsyncThrowingStream<CLIStreamEvent, Error>
    ) -> ChatService {
        let worker = makeWorker()
        let ai = makeAI()
        let builder = ChatContextBuilder(worker: worker)
        let harness = ZionHarness(worker: worker, repoURL: repoURL)
        return ChatService(
            ai: ai,
            worker: worker,
            contextBuilder: builder,
            harness: harness,
            cliStreamProvider: cliStream
        )
    }

    private func dummyRepoURL() throws -> URL {
        try GitTestHelper.makeTempRepo()
    }

    // MARK: - testTextDeltasAppendToAssistant

    /// Stream yields [.textDelta("hello "), .textDelta("world"), .done].
    /// After consumption the assistant message content must equal "hello world".
    func testTextDeltasAppendToAssistant() async throws {
        let repoURL = try dummyRepoURL()
        defer { GitTestHelper.cleanup(repoURL) }

        let service = makeService(repoURL: repoURL) { _, _ in
            AsyncThrowingStream<CLIStreamEvent, Error> { continuation in
                continuation.yield(.textDelta("hello "))
                continuation.yield(.textDelta("world"))
                continuation.yield(.done)
                continuation.finish()
            }
        }

        await service.send(
            text: "say hello",
            provider: .claudeCLI,
            apiKey: "",
            mode: .efficient,
            repoURL: repoURL,
            branch: "main"
        )

        let messages = service.thread.messages
        XCTAssertEqual(messages.count, 2, "Expected [user, assistant]")
        let assistant = messages.last
        XCTAssertEqual(assistant?.role, .assistant)
        XCTAssertEqual(assistant?.content, "hello world", "Deltas must be concatenated")
    }

    // MARK: - testToolEventsPopulated

    /// Stream yields [.toolStart, .textDelta, .toolEnd].
    /// After .toolStart, pendingToolEvents must have a .running entry.
    /// After .toolEnd, the entry must be .completed.
    func testToolEventsPopulated() async throws {
        let repoURL = try dummyRepoURL()
        defer { GitTestHelper.cleanup(repoURL) }

        let toolID = "tool-abc-123"
        var capturedRunning: [ChatToolEvent] = []
        var capturedCompleted: [ChatToolEvent] = []

        // We need to capture state mid-stream. Use a semaphore-style continuation approach:
        // Drive the stream manually via an actor.
        let bridge = StreamBridge()

        let service = makeService(repoURL: repoURL) { _, _ in
            AsyncThrowingStream<CLIStreamEvent, Error> { continuation in
                Task {
                    await bridge.setContinuation(continuation)
                }
            }
        }

        // Start send() in the background
        let sendTask = Task { @MainActor in
            await service.send(
                text: "do some work",
                provider: .claudeCLI,
                apiKey: "",
                mode: .efficient,
                repoURL: repoURL,
                branch: "main"
            )
        }

        // Wait for the continuation to be registered
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms

        // Yield toolStart
        await bridge.yield(.toolStart(id: toolID, name: "read_file", description: "Reading main.swift"))
        try await Task.sleep(nanoseconds: 50_000_000)
        capturedRunning = service.pendingToolEvents

        // Yield textDelta + toolEnd
        await bridge.yield(.textDelta("done"))
        await bridge.yield(.toolEnd(id: toolID, success: true, output: nil))
        try await Task.sleep(nanoseconds: 50_000_000)
        capturedCompleted = service.pendingToolEvents

        await bridge.yield(.done)
        await bridge.finish()

        await sendTask.value

        // Assertions
        XCTAssertEqual(capturedRunning.count, 1, "One tool event expected while running")
        XCTAssertEqual(capturedRunning.first?.id, toolID)
        XCTAssertEqual(capturedRunning.first?.status, .running)

        XCTAssertEqual(capturedCompleted.first?.status, .completed, "Event should be .completed after toolEnd(success:true)")
    }

    // MARK: - testToolEventsCleanedAfterDelay

    /// After toolEnd, pendingToolEvents must be empty after Constants.Timing.toolEventCleanupDelay + 0.5s.
    func testToolEventsCleanedAfterDelay() async throws {
        let repoURL = try dummyRepoURL()
        defer { GitTestHelper.cleanup(repoURL) }

        let toolID = "cleanup-tool"

        let service = makeService(repoURL: repoURL) { _, _ in
            AsyncThrowingStream<CLIStreamEvent, Error> { continuation in
                continuation.yield(.toolStart(id: toolID, name: "write_file", description: "Writing"))
                continuation.yield(.toolEnd(id: toolID, success: true, output: nil))
                continuation.yield(.done)
                continuation.finish()
            }
        }

        await service.send(
            text: "do cleanup test",
            provider: .claudeCLI,
            apiKey: "",
            mode: .efficient,
            repoURL: repoURL,
            branch: "main"
        )

        // Wait for cleanup delay + buffer
        let waitNanos = UInt64((Constants.Timing.toolEventCleanupDelay + 0.5) * 1_000_000_000)
        try await Task.sleep(nanoseconds: waitNanos)

        XCTAssertTrue(service.pendingToolEvents.isEmpty, "pendingToolEvents must be empty after cleanup delay")
    }

    // MARK: - testLateEventsDiscarded

    /// Events yielded after .done are discarded — pendingToolEvents stays empty.
    func testLateEventsDiscarded() async throws {
        let repoURL = try dummyRepoURL()
        defer { GitTestHelper.cleanup(repoURL) }

        let bridge = StreamBridge()

        let service = makeService(repoURL: repoURL) { _, _ in
            AsyncThrowingStream<CLIStreamEvent, Error> { continuation in
                Task {
                    await bridge.setContinuation(continuation)
                }
            }
        }

        let sendTask = Task { @MainActor in
            await service.send(
                text: "late event test",
                provider: .claudeCLI,
                apiKey: "",
                mode: .efficient,
                repoURL: repoURL,
                branch: "main"
            )
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        // Send .done first
        await bridge.yield(.done)
        try await Task.sleep(nanoseconds: 30_000_000)

        // Now send a tool start — this is a "late" event after .done
        await bridge.yield(.toolStart(id: "late-tool", name: "exec", description: "late"))
        await bridge.finish()

        await sendTask.value

        XCTAssertTrue(service.pendingToolEvents.isEmpty, "Late events after .done must be discarded")
    }

    func testResumedSessionDoesNotResendPriorRenderedHistory() async throws {
        let repoURL = try dummyRepoURL()
        defer { GitTestHelper.cleanup(repoURL) }

        let recorder = PayloadRecorder()
        let service = makeService(repoURL: repoURL) { payload, _ in
            AsyncThrowingStream<CLIStreamEvent, Error> { continuation in
                Task {
                    await recorder.record(payload)
                    continuation.yield(.sessionStarted(id: "session-1"))
                    continuation.yield(.textDelta("ok"))
                    continuation.yield(.done)
                    continuation.finish()
                }
            }
        }

        await service.send(
            text: "first question with expensive history",
            provider: .claudeCLI,
            apiKey: "",
            mode: .efficient,
            repoURL: repoURL,
            branch: "main"
        )
        await service.send(
            text: "second question only",
            provider: .claudeCLI,
            apiKey: "",
            mode: .efficient,
            repoURL: repoURL,
            branch: "main"
        )

        let submitted = await recorder.messages()
        XCTAssertEqual(submitted.count, 2)
        XCTAssertTrue(submitted[0].contains("first question with expensive history"))
        XCTAssertTrue(submitted[1].contains("second question only"))
        XCTAssertFalse(submitted[1].contains("first question with expensive history"))
        XCTAssertFalse(submitted[1].contains("## Conversation so far"))
    }
}

// MARK: - StreamBridge

/// Actor that bridges yielding CLIStreamEvents from test code into an AsyncThrowingStream.
private actor StreamBridge {
    private var continuation: AsyncThrowingStream<CLIStreamEvent, Error>.Continuation?

    func setContinuation(_ c: AsyncThrowingStream<CLIStreamEvent, Error>.Continuation) {
        continuation = c
    }

    func yield(_ event: CLIStreamEvent) {
        continuation?.yield(event)
    }

    func finish() {
        continuation?.finish()
    }
}

private actor PayloadRecorder {
    private var submittedMessages: [String] = []

    func record(_ payload: AIPromptPayload) {
        let message = payload.untrustedSections.first(where: { $0.kind == "user_message" })?.content ?? ""
        submittedMessages.append(message)
    }

    func messages() -> [String] {
        submittedMessages
    }
}
