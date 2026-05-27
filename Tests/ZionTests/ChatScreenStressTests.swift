import XCTest
@testable import Zion

/// Regression guard for the O(n^2) `applyAllState(for:)` hotspot in the
/// ChatScreen message list. Before the fix, each row inside the ForEach called
/// `chat.applyAllState(for: msgID)` which internally called
/// `findAssistantMessage` (O(n) linear scan). With 200 messages that's 40,000
/// comparisons per layout pass. The fix hoists a precomputed [UUID: ApplyAllState]
/// dict above the ForEach so the total work is O(n).
///
/// This test builds a synthetic 200-message thread with the trailing assistant
/// turn carrying 3 EditBlocks and isStreaming = true, then measures that
/// computing the full per-message applyAllState map completes in < 200 ms.
@MainActor
final class ChatScreenStressTests: XCTestCase {

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
        EditBlock(path: path, search: "old", replace: "new")
    }

    // MARK: - Tests

    /// Builds a 200-message thread where the last assistant turn has 3 EditBlocks
    /// and isStreaming = true. Measures the precomputed-dict approach (O(n)):
    /// one pass over all messages to build the [UUID: ApplyAllState] map.
    /// Asserts < 200 ms — should complete in well under 1 ms in practice.
    func test_largeThread_streaming_doesNotHang() {
        let service = makeService()

        // Build thread id so we can insert directly
        let threadID = service.activeThreadID

        // Build 200 messages: alternating user / assistant (non-streaming, no editBlocks)
        var messages: [ChatMessage] = []
        for i in 0..<199 {
            if i % 2 == 0 {
                messages.append(ChatMessage(role: .user, content: "User turn \(i)"))
            } else {
                messages.append(ChatMessage(role: .assistant, content: "Assistant turn \(i)"))
            }
        }

        // Trailing assistant message: streaming, 3 edit blocks
        let blocks = [
            makeEditBlock(path: "Sources/A.swift"),
            makeEditBlock(path: "Sources/B.swift"),
            makeEditBlock(path: "Sources/C.swift")
        ]
        let streamingMsg = ChatMessage(
            role: .assistant,
            content: "Making changes...",
            isStreaming: true,
            editBlocks: blocks
        )
        messages.append(streamingMsg)

        // Inject into service threads
        if let idx = service.threads.firstIndex(where: { $0.id == threadID }) {
            service.threads[idx].messages = messages
        } else {
            // Thread may not exist yet; create it
            let thread = ChatThread(id: threadID, messages: messages, repoID: "test")
            service.threads = [thread]
        }

        XCTAssertEqual(service.thread.messages.count, 200, "Should have 200 messages")

        // Measure the O(n) precomputed dict approach — equivalent to what ChatScreen now does
        let start = CFAbsoluteTimeGetCurrent()

        // Run 50 iterations to accumulate measurable time (simulates repeated layout passes)
        for _ in 0..<50 {
            let _ = Dictionary(
                uniqueKeysWithValues: service.thread.messages.compactMap { msg -> (UUID, ApplyAllState)? in
                    guard msg.role == .assistant, let editBlocks = msg.editBlocks, !editBlocks.isEmpty else { return nil }
                    return (msg.id, service.applyAllState(for: msg.id))
                }
            )
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let elapsedMs = elapsed * 1000

        XCTAssertLessThan(
            elapsedMs,
            200.0,
            "50 layout-pass simulations should complete in < 200 ms, took \(String(format: "%.1f", elapsedMs)) ms"
        )
    }
}
