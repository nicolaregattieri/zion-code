import XCTest
@testable import Zion

// MARK: - ChatServiceToolLoopTests

@MainActor
final class ChatServiceToolLoopTests: XCTestCase {

    // MARK: - Helpers

    private func makeWorker() -> RepositoryWorker { RepositoryWorker() }
    private func makeAI() -> AIClient { AIClient() }

    private func makeService(
        repoURL: URL,
        streamProvider: @escaping (LocalLLMConfig, AIPromptPayload, Int, String) -> AsyncThrowingStream<String, Error>
    ) -> ChatService {
        let worker = makeWorker()
        let ai = makeAI()
        let builder = ChatContextBuilder(worker: worker)
        let harness = ZionHarness(worker: worker, repoURL: repoURL)
        return ChatService(ai: ai, worker: worker, contextBuilder: builder, harness: harness, streamProvider: streamProvider)
    }

    private func stubStream() -> (LocalLLMConfig, AIPromptPayload, Int, String) -> AsyncThrowingStream<String, Error> {
        return { _, _, _, _ in
            AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("ok")
                continuation.finish()
            }
        }
    }

    // MARK: - test_auto_injection_when_no_tools

    /// provider=.gemini (supportsToolCalling=false), text="show last commit"
    /// Expect: autoInjectedIntent != nil and content starts with fenced block
    func test_auto_injection_when_no_tools() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        UserDefaults.standard.set(true, forKey: "chat.toolsEnabled")
        UserDefaults.standard.set(true, forKey: "chat.autoInject")

        let service = makeService(repoURL: repoURL, streamProvider: stubStream())

        await service.send(
            text: "show last commit",
            provider: .gemini,
            apiKey: "",
            mode: .efficient,
            repoURL: repoURL,
            branch: "main"
        )

        let messages = service.thread.messages
        XCTAssertFalse(messages.isEmpty, "Expected messages to be appended")

        let userMsg = messages.first(where: { $0.role == .user })
        XCTAssertNotNil(userMsg, "Expected a user message")
        XCTAssertNotNil(
            userMsg?.autoInjectedIntent,
            "autoInjectedIntent should be set for intent-matched, tool-incapable provider"
        )
        // Phase 3.5 sticky context: user.content stays clean (just typed text); diff goes to internalContext
        XCTAssertNotNil(
            userMsg?.internalContext,
            "internalContext should be set with fenced diff when injection occurs"
        )
        XCTAssertTrue(
            userMsg?.internalContext?.hasPrefix("```") == true,
            "internalContext should start with fenced block"
        )
    }

    // MARK: - test_no_injection_when_disabled

    /// chat.autoInject=false; intent matches but no injection
    func test_no_injection_when_disabled() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        UserDefaults.standard.set(true, forKey: "chat.toolsEnabled")
        UserDefaults.standard.set(false, forKey: "chat.autoInject")

        let service = makeService(repoURL: repoURL, streamProvider: stubStream())

        await service.send(
            text: "show last commit",
            provider: .gemini,
            apiKey: "",
            mode: .efficient,
            repoURL: repoURL,
            branch: "main"
        )

        let userMsg = service.thread.messages.first(where: { $0.role == .user })
        XCTAssertNil(
            userMsg?.autoInjectedIntent,
            "autoInjectedIntent should be nil when chat.autoInject is false"
        )
        XCTAssertFalse(
            userMsg?.content.hasPrefix("```") == true,
            "Content should not start with fenced block when autoInject is disabled"
        )

        // Reset to default
        UserDefaults.standard.removeObject(forKey: "chat.autoInject")
    }

    // MARK: - test_no_injection_when_tools_capable

    /// provider=.anthropic (supportsToolCalling=true); intent would match but skip injection
    func test_no_injection_when_tools_capable() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        UserDefaults.standard.set(true, forKey: "chat.toolsEnabled")
        UserDefaults.standard.set(true, forKey: "chat.autoInject")

        let service = makeService(repoURL: repoURL, streamProvider: stubStream())

        // Use a non-local provider that has supportsToolCalling == true
        // (anthropic.supportsToolCalling == true per AppEnums task 2)
        await service.send(
            text: "show last commit",
            provider: .anthropic,
            apiKey: "test-key",
            mode: .efficient,
            repoURL: repoURL,
            branch: "main"
        )

        // Phase 3.5: pre-flight intent runs for ALL providers (not gated). Tool loop is Phase 4+.
        // So autoInjectedIntent IS expected to be set when classifier matches.
        let userMsg = service.thread.messages.first(where: { $0.role == .user })
        XCTAssertNotNil(
            userMsg?.autoInjectedIntent,
            "autoInjectedIntent should be set even when provider supports tools (sticky context fires for all)"
        )
    }

    // MARK: - test_new_thread_resets_harness_session

    /// After newThread(), harness sessionReadFiles should be cleared.
    /// Verify: read a file -> edit succeeds -> newThread() -> edit same file without re-reading = readBeforeEdit error
    func test_new_thread_resets_harness_session() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        UserDefaults.standard.set(true, forKey: "chat.allowEdits")
        defer { UserDefaults.standard.removeObject(forKey: "chat.allowEdits") }

        let worker = makeWorker()
        let harness = ZionHarness(worker: worker, repoURL: repoURL)

        // Step 1: Read README.md to register it in sessionReadFiles
        let readCall = ToolCall(id: "1", name: "read", arguments: ["path": repoURL.appendingPathComponent("README.md").path])
        let readResult = await harness.execute(toolCall: readCall)
        XCTAssertFalse(readResult.isError, "Read should succeed: \(readResult.content)")

        // Step 2: Edit should succeed (file was read)
        let editCall = ToolCall(id: "2", name: "edit", arguments: [
            "path": repoURL.appendingPathComponent("README.md").path,
            "edits": [["oldText": "# Test Repo\n", "newText": "# Modified\n"]] as [[String: Any]]
        ])
        let editResult = await harness.execute(toolCall: editCall)
        XCTAssertFalse(editResult.isError, "Edit should succeed after read: \(editResult.content)")

        // Step 3: resetSession() clears sessionReadFiles
        await harness.resetSession()

        // Step 4: Edit again without re-reading — must fail with readBeforeEdit
        // First restore original content so edit can match
        let restoreCall = ToolCall(id: "3", name: "read", arguments: ["path": repoURL.appendingPathComponent("README.md").path])
        _ = await harness.execute(toolCall: restoreCall)
        // Now reset again to simulate what newThread() does
        await harness.resetSession()

        let editAfterReset = ToolCall(id: "4", name: "edit", arguments: [
            "path": repoURL.appendingPathComponent("README.md").path,
            "edits": [["oldText": "# Modified\n", "newText": "# Again\n"]] as [[String: Any]]
        ])
        let resultAfterReset = await harness.execute(toolCall: editAfterReset)
        XCTAssertTrue(
            resultAfterReset.isError,
            "Edit should fail after resetSession() (readBeforeEdit)"
        )
        XCTAssertTrue(
            resultAfterReset.content.contains("readBeforeEdit"),
            "Error should be readBeforeEdit, got: \(resultAfterReset.content)"
        )

        // Step 5: Verify ChatService.newThread() actually calls harness.resetSession()
        // Do this by building a ChatService and verifying newThread() results in cleared state
        let ai = makeAI()
        let builder = ChatContextBuilder(worker: worker)
        let harness2 = ZionHarness(worker: worker, repoURL: repoURL)

        // Read README to register it
        let preRead = ToolCall(id: "5", name: "read", arguments: ["path": repoURL.appendingPathComponent("README.md").path])
        _ = await harness2.execute(toolCall: preRead)

        let service = ChatService(ai: ai, worker: worker, contextBuilder: builder, harness: harness2)
        service.newThread()

        // Give the Task a moment to fire
        try await Task.sleep(nanoseconds: 50_000_000)

        // Now edit without re-reading — should fail
        let editNoRead = ToolCall(id: "6", name: "edit", arguments: [
            "path": repoURL.appendingPathComponent("README.md").path,
            "edits": [["oldText": "# Again\n", "newText": "# Final\n"]] as [[String: Any]]
        ])
        let finalResult = await harness2.execute(toolCall: editNoRead)
        XCTAssertTrue(
            finalResult.isError,
            "Edit should fail after ChatService.newThread() because harness session was reset"
        )
    }
}
