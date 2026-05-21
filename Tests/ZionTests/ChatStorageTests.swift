import XCTest
import Foundation
@testable import Zion

final class ChatStorageTests: XCTestCase {

    // Each test gets its own isolated temp dir
    private func makeStorage() -> ChatStorage {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return ChatStorage(baseDirectory: dir)
    }

    private let repoID = "testrepo01"

    // MARK: - testSchemaCreatedOnFirstOpen

    func testSchemaCreatedOnFirstOpen() async throws {
        let storage = makeStorage()
        // Trigger DB creation by loading threads (empty result is fine)
        _ = try await storage.loadThreads(repoID: repoID)
        // If we got here without throwing, schema was created successfully
        // Load again to confirm it's stable
        _ = try await storage.loadThreads(repoID: repoID)
    }

    // MARK: - testThreadInsertLoadRoundTrip

    func testThreadInsertLoadRoundTrip() async throws {
        let storage = makeStorage()
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_000_000)
        let thread = ChatThread(
            id: id,
            messages: [],
            createdAt: created,
            repoID: repoID,
            title: "My Thread"
        )

        try await storage.saveThread(thread, repoID: repoID)
        let threads = try await storage.loadThreads(repoID: repoID)

        XCTAssertEqual(threads.count, 1)
        let loaded = try XCTUnwrap(threads.first)
        XCTAssertEqual(loaded.id, id)
        XCTAssertEqual(loaded.title, "My Thread")
        XCTAssertEqual(loaded.repoID, repoID)
        XCTAssertEqual(loaded.createdAt.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - testMessagesPreserveOrder

    func testMessagesPreserveOrder() async throws {
        let storage = makeStorage()
        let threadID = UUID()
        let thread = ChatThread(
            id: threadID,
            messages: [],
            createdAt: Date(),
            repoID: repoID,
            title: "Order Test"
        )
        try await storage.saveThread(thread, repoID: repoID)

        let base = Date(timeIntervalSince1970: 1_000_000)
        let m1 = ChatMessage(id: UUID(), role: .user, content: "first", timestamp: base, isStreaming: false)
        let m2 = ChatMessage(id: UUID(), role: .assistant, content: "second", timestamp: base.addingTimeInterval(1), isStreaming: false)
        let m3 = ChatMessage(id: UUID(), role: .user, content: "third", timestamp: base.addingTimeInterval(2), isStreaming: false)

        try await storage.appendMessage(m1, threadID: threadID, repoID: repoID)
        try await storage.appendMessage(m3, threadID: threadID, repoID: repoID)
        try await storage.appendMessage(m2, threadID: threadID, repoID: repoID)

        let messages = try await storage.loadMessages(threadID: threadID, repoID: repoID)
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0].content, "first")
        XCTAssertEqual(messages[1].content, "second")
        XCTAssertEqual(messages[2].content, "third")
    }

    // MARK: - testDeleteThreadCascadesMessages

    func testDeleteThreadCascadesMessages() async throws {
        let storage = makeStorage()
        let threadID = UUID()
        let thread = ChatThread(
            id: threadID,
            messages: [],
            createdAt: Date(),
            repoID: repoID,
            title: "To Delete"
        )
        try await storage.saveThread(thread, repoID: repoID)

        let msg = ChatMessage(id: UUID(), role: .user, content: "hello", timestamp: Date(), isStreaming: false)
        try await storage.appendMessage(msg, threadID: threadID, repoID: repoID)

        // Confirm message exists
        let before = try await storage.loadMessages(threadID: threadID, repoID: repoID)
        XCTAssertEqual(before.count, 1)

        // Delete thread — cascade should remove messages
        try await storage.deleteThread(threadID, repoID: repoID)

        let afterThreads = try await storage.loadThreads(repoID: repoID)
        XCTAssertTrue(afterThreads.isEmpty)

        let afterMessages = try await storage.loadMessages(threadID: threadID, repoID: repoID)
        XCTAssertTrue(afterMessages.isEmpty)
    }

    // MARK: - testRepoIsolation

    func testRepoIsolation() async throws {
        let storage = makeStorage()
        let repoA = "repoAAAA00000000"
        let repoB = "repoBBBB00000000"

        let thread = ChatThread(
            id: UUID(),
            messages: [],
            createdAt: Date(),
            repoID: repoA,
            title: "Repo A Thread"
        )
        try await storage.saveThread(thread, repoID: repoA)

        let threadsA = try await storage.loadThreads(repoID: repoA)
        XCTAssertEqual(threadsA.count, 1)

        let threadsB = try await storage.loadThreads(repoID: repoB)
        XCTAssertTrue(threadsB.isEmpty)
    }
}
