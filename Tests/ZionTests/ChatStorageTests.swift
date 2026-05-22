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

// MARK: - ChatPlanPersistenceTests

final class ChatPlanPersistenceTests: XCTestCase {

    private func makeStorage() -> ChatStorage {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return ChatStorage(baseDirectory: dir)
    }

    private let repoID = "plantestrepo01"

    func testChatPlanRoundTripViaAppendMessage() async throws {
        let storage = makeStorage()
        let threadID = UUID()
        let thread = ChatThread(
            id: threadID,
            messages: [],
            createdAt: Date(),
            repoID: repoID,
            title: "Plan Round-Trip Thread"
        )
        try await storage.saveThread(thread, repoID: repoID)

        let plan = ChatPlan(
            id: UUID(),
            rawXML: "<plan><step>do something</step></plan>",
            steps: [
                ChatPlanStep(commitMessage: "feat: add foo", filePaths: ["Sources/Foo.swift", "Tests/FooTests.swift"], summary: "Add Foo feature"),
                ChatPlanStep(commitMessage: nil, filePaths: [], summary: "Cleanup")
            ]
        )
        let message = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "Here is the plan.",
            timestamp: Date(timeIntervalSince1970: 2_000_000),
            isStreaming: false,
            plan: plan
        )

        try await storage.appendMessage(message, threadID: threadID, repoID: repoID)

        let loaded = try await storage.loadMessages(threadID: threadID, repoID: repoID)
        XCTAssertEqual(loaded.count, 1)
        let loadedMsg = try XCTUnwrap(loaded.first)
        XCTAssertEqual(loadedMsg.id, message.id)
        XCTAssertEqual(loadedMsg.content, message.content)
        let loadedPlan = try XCTUnwrap(loadedMsg.plan)
        XCTAssertEqual(loadedPlan, plan)
        XCTAssertEqual(loadedPlan.id, plan.id)
        XCTAssertEqual(loadedPlan.rawXML, plan.rawXML)
        XCTAssertEqual(loadedPlan.steps.count, 2)
        XCTAssertEqual(loadedPlan.steps[0].commitMessage, "feat: add foo")
        XCTAssertEqual(loadedPlan.steps[0].filePaths, ["Sources/Foo.swift", "Tests/FooTests.swift"])
        XCTAssertEqual(loadedPlan.steps[0].summary, "Add Foo feature")
        XCTAssertNil(loadedPlan.steps[1].commitMessage)
    }

    func testMessageWithNilPlanRoundTrips() async throws {
        let storage = makeStorage()
        let threadID = UUID()
        let thread = ChatThread(
            id: threadID,
            messages: [],
            createdAt: Date(),
            repoID: repoID,
            title: "No Plan Thread"
        )
        try await storage.saveThread(thread, repoID: repoID)

        let message = ChatMessage(
            id: UUID(),
            role: .user,
            content: "No plan here.",
            timestamp: Date(timeIntervalSince1970: 3_000_000),
            isStreaming: false
        )
        try await storage.appendMessage(message, threadID: threadID, repoID: repoID)

        let loaded = try await storage.loadMessages(threadID: threadID, repoID: repoID)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded.first?.plan)
    }
}
