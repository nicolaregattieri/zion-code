import XCTest
@testable import Zion

final class ChatModelsTests: XCTestCase {

    func testMessageEquatableRoundTrip() {
        let id = UUID()
        let timestamp = Date()
        let msg1 = ChatMessage(id: id, role: .user, content: "hello", timestamp: timestamp, isStreaming: false)
        let msg2 = ChatMessage(id: id, role: .user, content: "hello", timestamp: timestamp, isStreaming: false)
        XCTAssertEqual(msg1, msg2)

        var msg3 = msg1
        msg3.content = "different"
        XCTAssertNotEqual(msg1, msg3)
    }

    func testMessageIdUnique() {
        let msg1 = ChatMessage(role: .user, content: "a")
        let msg2 = ChatMessage(role: .user, content: "a")
        XCTAssertNotEqual(msg1.id, msg2.id)
    }

    func testThreadEquatableRoundTrip() {
        let id = UUID()
        let createdAt = Date()
        let msg = ChatMessage(id: UUID(), role: .assistant, content: "hi", timestamp: createdAt, isStreaming: false)
        let t1 = ChatThread(id: id, messages: [msg], createdAt: createdAt)
        let t2 = ChatThread(id: id, messages: [msg], createdAt: createdAt)
        XCTAssertEqual(t1, t2)

        var t3 = t1
        t3.messages = []
        XCTAssertNotEqual(t1, t3)
    }
}
