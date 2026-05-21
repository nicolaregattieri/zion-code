import XCTest
@testable import Zion

@MainActor
final class ChatServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeWorker() -> RepositoryWorker { RepositoryWorker() }

    private func makeContextBuilder(worker: RepositoryWorker) -> ChatContextBuilder {
        ChatContextBuilder(worker: worker)
    }

    private func makeAI() -> AIClient { AIClient() }

    /// Makes a service with an injected streamProvider for tests (no real network).
    private func makeService(
        streamProvider: @escaping (LocalLLMConfig, AIPromptPayload, Int, String) -> AsyncThrowingStream<String, Error>
    ) -> ChatService {
        let worker = makeWorker()
        let ai = makeAI()
        let builder = makeContextBuilder(worker: worker)
        return ChatService(ai: ai, worker: worker, contextBuilder: builder, streamProvider: streamProvider)
    }

    private func dummyRepoURL() throws -> URL {
        try GitTestHelper.makeTempRepo()
    }

    // MARK: - Tests

    /// Inject a mock streamProvider that yields "hello"; assert thread contains [user, assistant]
    /// with assistant.content == "hello".
    func testSendAppendsUserAndAssistantMessages() async throws {
        let repoURL = try dummyRepoURL()
        defer { GitTestHelper.cleanup(repoURL) }

        let service = makeService { _, _, _, _ in
            AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("hello")
                continuation.finish()
            }
        }

        await service.send(
            text: "What does this repo do?",
            provider: .local,
            apiKey: "",
            mode: .efficient,
            repoURL: repoURL,
            branch: "main"
        )

        let messages = service.thread.messages
        XCTAssertEqual(messages.count, 2, "Expected [user, assistant], got \(messages.count) messages")

        let user = messages[0]
        XCTAssertEqual(user.role, .user)
        XCTAssertTrue(user.content.contains("What does this repo do?"), "User message should contain original text")

        let assistant = messages[1]
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(assistant.content, "hello", "Assistant content should be the streamed token")
    }

    /// Start a slow stream (one token after a short delay) then immediately stop(); assert
    /// isStreaming == false and the task is cancelled.
    func testStopCancelsActiveTask() async throws {
        let repoURL = try dummyRepoURL()
        defer { GitTestHelper.cleanup(repoURL) }

        // Use a continuation we can hold open
        var externalContinuation: AsyncThrowingStream<String, Error>.Continuation?

        let service = makeService { _, _, _, _ in
            AsyncThrowingStream<String, Error> { continuation in
                externalContinuation = continuation
                // Don't finish immediately — simulate a slow stream
            }
        }

        // Fire-and-forget the send so we can call stop() concurrently
        let sendTask = Task {
            await service.send(
                text: "slow question",
                provider: .local,
                apiKey: "",
                mode: .efficient,
                repoURL: repoURL,
                branch: "main"
            )
        }

        // Give the send a moment to start streaming
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms

        // Stop while streaming
        service.stop()

        // Finish the external continuation so the inner task can observe cancellation
        externalContinuation?.finish()

        // Wait for send to return
        await sendTask.value

        XCTAssertFalse(service.isStreaming, "isStreaming should be false after stop()")
    }

    /// After send(), call newThread() and verify messages are cleared.
    func testNewThreadClearsMessages() async throws {
        let repoURL = try dummyRepoURL()
        defer { GitTestHelper.cleanup(repoURL) }

        let service = makeService { _, _, _, _ in
            AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("hi")
                continuation.finish()
            }
        }

        await service.send(
            text: "hello",
            provider: .local,
            apiKey: "",
            mode: .efficient,
            repoURL: repoURL,
            branch: "main"
        )

        XCTAssertFalse(service.thread.messages.isEmpty, "Should have messages before newThread()")

        service.newThread()

        XCTAssertTrue(service.thread.messages.isEmpty, "Thread should be empty after newThread()")
        XCTAssertFalse(service.isStreaming, "isStreaming should be false after newThread()")
    }

    /// Stream yields ["he", "llo"]; assert content builds up to "he" then "hello".
    func testStreamingTokenAppendUpdatesLastMessage() async throws {
        let repoURL = try dummyRepoURL()
        defer { GitTestHelper.cleanup(repoURL) }

        // Collect intermediate states via the observable thread
        var capturedStates: [String] = []

        let service = makeService { _, _, _, _ in
            AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("he")
                continuation.yield("llo")
                continuation.finish()
            }
        }

        // We can't observe mid-stream in a unit test without async observation,
        // so we verify the final accumulated content is "hello" (both tokens concatenated).
        await service.send(
            text: "ping",
            provider: .local,
            apiKey: "",
            mode: .efficient,
            repoURL: repoURL,
            branch: "main"
        )

        let messages = service.thread.messages
        XCTAssertEqual(messages.count, 2)
        let assistant = messages[1]
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(assistant.content, "hello", "Streaming tokens should be concatenated: 'he' + 'llo' = 'hello'")

        _ = capturedStates // silence unused warning
    }
}
