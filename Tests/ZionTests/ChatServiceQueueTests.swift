import XCTest
@testable import Zion

@MainActor
final class ChatServiceQueueTests: XCTestCase {

    // MARK: - Fixtures

    /// Manually-controlled stream provider — yields nothing until `continuation`
    /// is finished by the test. Lets us hold a stream "open" while we call
    /// send() a second time to assert queueing behaviour.
    private func makeService(_ block: (@Sendable () -> Void)? = nil) -> ChatService {
        let worker = RepositoryWorker()
        let ai = AIClient()
        let builder = ChatContextBuilder(worker: worker)
        let harness = ZionHarness(worker: worker, repoURL: URL(fileURLWithPath: NSTemporaryDirectory()))
        return ChatService(
            ai: ai,
            worker: worker,
            contextBuilder: builder,
            harness: harness,
            streamProvider: { _, _, _, _ in
                AsyncThrowingStream<String, Error> { continuation in
                    // Never finishes — caller cancels via task or stop()
                    if let cb = block { cb() }
                }
            }
        )
    }

    // MARK: - Tests

    /// stop() must clear the queue AND surface a transient notice telling the
    /// user how many messages got dropped — silent destruction of typed
    /// input was the prior bug.
    func testStopClearsQueueAndSurfacesNotice() async throws {
        let svc = makeService()

        // Seed the queue directly so the test doesn't depend on a running
        // streamProvider — exercise the cleanup contract directly.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        let id = svc.activeThreadID
        svc.pendingQueueByThread[id] = [
            ChatService.PendingMessage(
                text: "queued one", provider: .none, apiKey: "",
                mode: .efficient, repoURL: url, branch: "main",
                modelOverride: nil
            ),
            ChatService.PendingMessage(
                text: "queued two", provider: .none, apiKey: "",
                mode: .efficient, repoURL: url, branch: "main",
                modelOverride: nil
            )
        ]

        svc.stop()

        XCTAssertEqual(svc.activePendingQueueCount, 0)
        XCTAssertNil(svc.pendingQueueByThread[id])
        XCTAssertNotNil(svc.transientNotice, "stop should announce the dropped queue")
    }

    /// dropPendingMessage removes a single entry without touching the rest.
    func testDropPendingMessageRemovesOne() {
        let svc = makeService()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        let id = svc.activeThreadID
        let keep = ChatService.PendingMessage(
            text: "keep", provider: .none, apiKey: "",
            mode: .efficient, repoURL: url, branch: "main",
            modelOverride: nil
        )
        let drop = ChatService.PendingMessage(
            text: "drop", provider: .none, apiKey: "",
            mode: .efficient, repoURL: url, branch: "main",
            modelOverride: nil
        )
        svc.pendingQueueByThread[id] = [keep, drop]

        svc.dropPendingMessage(id: drop.id)

        XCTAssertEqual(svc.activePendingQueueCount, 1)
        XCTAssertEqual(svc.pendingQueueByThread[id]?.first?.text, "keep")
    }

    /// stripEditBlockMarkers must remove raw aider-style markers but leave
    /// the surrounding prose intact, so the chat does not double-render the
    /// structured EditBlock card AND the raw text (#38).
    func testStripEditBlockMarkersRemovesRawBlocks() {
        let input = """
        Sure, here are three updates.

        <<<<<<< SEARCH: a.txt
        old
        =======
        new
        >>>>>>> REPLACE

        Done.
        """
        let stripped = ChatService.stripEditBlockMarkers(from: input)
        XCTAssertFalse(stripped.contains("<<<<<<<"))
        XCTAssertFalse(stripped.contains(">>>>>>>"))
        XCTAssertTrue(stripped.contains("Sure, here are three updates."))
        XCTAssertTrue(stripped.contains("Done."))
    }

    /// Edit markers nested inside a code fence are documentation, not edits.
    /// They must NOT be stripped.
    func testStripEditBlockMarkersSkipsFencedExamples() {
        let input = """
        Here is the format we use:

        ```
        <<<<<<< SEARCH: example.txt
        old
        =======
        new
        >>>>>>> REPLACE
        ```

        Now an actual edit:

        <<<<<<< SEARCH: real.txt
        actual_old
        =======
        actual_new
        >>>>>>> REPLACE
        """
        let stripped = ChatService.stripEditBlockMarkers(from: input)
        // Fenced example survives
        XCTAssertTrue(stripped.contains("example.txt"))
        // Real edit gets stripped
        XCTAssertFalse(stripped.contains("real.txt"))
        XCTAssertFalse(stripped.contains("actual_old"))
    }
}
