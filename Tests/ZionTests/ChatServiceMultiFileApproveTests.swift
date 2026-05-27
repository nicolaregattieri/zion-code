import XCTest
@testable import Zion

/// Tests the multi-file approve dispatch: `applyAllEdits(messageID:)` must
/// iterate over every EditBlock and call `applyEditBlock` for each one.
///
/// Strategy: inject 3 EditBlocks onto an assistant message. Call
/// `applyAllEdits(messageID:)`. Since `activeRepoURL` is nil in the test
/// environment, each `applyEditBlock` call returns early without marking a
/// failure, allowing the loop to advance through all three blocks and set the
/// final state to `.done(3)`. This proves the fan-out visits all 3 blocks.
@MainActor
final class ChatServiceMultiFileApproveTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> ChatService {
        let worker = RepositoryWorker()
        let ai = AIClient()
        let builder = ChatContextBuilder(worker: worker)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        let harness = ZionHarness(worker: worker, repoURL: url)
        return ChatService(
            ai: ai,
            worker: worker,
            contextBuilder: builder,
            harness: harness,
            streamProvider: { _, _, _, _ in
                AsyncThrowingStream<String, Error> { $0.finish() }
            }
        )
    }

    private func makeEditBlock(path: String) -> EditBlock {
        EditBlock(path: path, search: "let x = 1", replace: "let x = 2")
    }

    // MARK: - Tests

    /// Posts a synthetic assistant message containing three EditBlocks, invokes
    /// `applyAllEdits(messageID:)`, and asserts the fan-out loop visited all
    /// three blocks (evidenced by `applyAllState == .done(3)`).
    func test_applyAll_fansOutAllEdits() async {
        let service = makeService()
        let threadID = service.activeThreadID

        let blocks = [
            makeEditBlock(path: "Sources/A.swift"),
            makeEditBlock(path: "Sources/B.swift"),
            makeEditBlock(path: "Sources/C.swift")
        ]

        let msgID = UUID()
        let assistantMsg = ChatMessage(
            id: msgID,
            role: .assistant,
            content: "Here are the edits.",
            isStreaming: false,
            editBlocks: blocks
        )

        // Inject thread with the assistant message
        if let idx = service.threads.firstIndex(where: { $0.id == threadID }) {
            service.threads[idx].messages = [assistantMsg]
        } else {
            let thread = ChatThread(id: threadID, messages: [assistantMsg], repoID: "test")
            service.threads = [thread]
        }

        XCTAssertEqual(service.thread.messages.count, 1)
        XCTAssertEqual(service.thread.messages[0].editBlocks?.count, 3)

        // activeRepoURL is nil so each applyEditBlock returns immediately
        // without setting a failureReason; the loop therefore advances through
        // all 3 blocks and sets applyAllState = .done(3).
        await service.applyAllEdits(messageID: msgID)

        // .done(3) is only reachable if the loop iterated all 3 blocks
        XCTAssertEqual(
            service.applyAllState,
            .done(3),
            "Expected applyAllState == .done(3) after fanning out 3 edit blocks; got \(service.applyAllState)"
        )
    }
}
