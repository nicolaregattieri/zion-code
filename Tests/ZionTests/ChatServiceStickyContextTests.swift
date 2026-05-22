import XCTest
@testable import Zion

@MainActor
final class ChatServiceStickyContextTests: XCTestCase {

    func test_internalContext_persists_on_user_message_when_intent_fires() throws {
        var msg = ChatMessage(role: .user, content: "hi", internalContext: "```\ndiff body\n```")
        XCTAssertNotNil(msg.internalContext)
        XCTAssertTrue(msg.internalContext!.contains("diff body"))
        msg.internalContext = nil
        XCTAssertNil(msg.internalContext)
    }

    func test_message_without_intent_has_nil_internalContext_by_default() {
        let msg = ChatMessage(role: .user, content: "random text")
        XCTAssertNil(msg.internalContext)
        XCTAssertNil(msg.autoInjectedIntent)
    }

    func test_thread_carries_message_with_internalContext() {
        var thread = ChatThread()
        thread.messages.append(ChatMessage(role: .user, content: "show last commit", internalContext: "```\ngit show output\n```"))
        thread.messages.append(ChatMessage(role: .assistant, content: "Here is what changed..."))
        thread.messages.append(ChatMessage(role: .user, content: "show me a function"))

        // Look up most recent user message that has internalContext (mimics ChatService sticky lookup)
        let sticky = thread.messages.reversed().first(where: { $0.role == .user && $0.internalContext != nil })?.internalContext
        XCTAssertNotNil(sticky)
        XCTAssertTrue(sticky!.contains("git show output"))
    }
}
