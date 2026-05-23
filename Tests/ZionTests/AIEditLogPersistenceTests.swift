import XCTest
import Foundation
@testable import Zion

final class AIEditLogPersistenceTests: XCTestCase {

    private func makeStorage() -> ChatStorage {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return ChatStorage(baseDirectory: dir)
    }

    private let repoID = "aieditlogrepo"

    // MARK: - Helper

    private func makeThreadAndSave(in storage: ChatStorage) async throws -> UUID {
        let threadID = UUID()
        let thread = ChatThread(
            id: threadID,
            messages: [],
            createdAt: Date(),
            repoID: repoID,
            title: "Test Thread"
        )
        try await storage.saveThread(thread, repoID: repoID)
        return threadID
    }

    // MARK: - testMessageWithEditBlocksRoundTrips

    func testMessageWithEditBlocksRoundTrips() async throws {
        let storage = makeStorage()
        let threadID = try await makeThreadAndSave(in: storage)

        let block1 = EditBlock(
            id: UUID(),
            path: "Sources/Foo.swift",
            search: "let x = 1",
            replace: "let x = 2"
        )
        let block2 = EditBlock(
            id: UUID(),
            path: "Sources/Bar.swift",
            search: "func foo()",
            replace: "func bar()",
            appliedAt: Date(timeIntervalSince1970: 1_000_000),
            failureReason: nil,
            attemptStrategies: ["exact", "fuzzy"]
        )

        let messageID = UUID()
        let message = ChatMessage(
            id: messageID,
            role: .assistant,
            content: "Here are the edits",
            timestamp: Date(timeIntervalSince1970: 2_000_000),
            editBlocks: [block1, block2]
        )
        try await storage.appendMessage(message, threadID: threadID, repoID: repoID)

        let loaded = try await storage.loadMessages(threadID: threadID, repoID: repoID)
        XCTAssertEqual(loaded.count, 1)

        let loadedMsg = try XCTUnwrap(loaded.first)
        XCTAssertEqual(loadedMsg.id, messageID)

        let loadedBlocks = try XCTUnwrap(loadedMsg.editBlocks)
        XCTAssertEqual(loadedBlocks.count, 2)
        XCTAssertEqual(loadedBlocks[0].id, block1.id)
        XCTAssertEqual(loadedBlocks[0].path, block1.path)
        XCTAssertEqual(loadedBlocks[0].search, block1.search)
        XCTAssertEqual(loadedBlocks[0].replace, block1.replace)
        XCTAssertNil(loadedBlocks[0].appliedAt)
        XCTAssertEqual(loadedBlocks[1].id, block2.id)
        XCTAssertEqual(loadedBlocks[1].path, block2.path)
        XCTAssertEqual(loadedBlocks[1].attemptStrategies, ["exact", "fuzzy"])
        // Date round-trips through TimeInterval lose sub-second precision — compare with tolerance
        XCTAssertEqual(
            loadedBlocks[1].appliedAt?.timeIntervalSince1970 ?? 0,
            1_000_000,
            accuracy: 1.0
        )
    }

    // MARK: - testMessageWithNilEditBlocksRoundTrips

    func testMessageWithNilEditBlocksRoundTrips() async throws {
        let storage = makeStorage()
        let threadID = try await makeThreadAndSave(in: storage)

        let message = ChatMessage(
            id: UUID(),
            role: .user,
            content: "Hello",
            timestamp: Date(),
            editBlocks: nil
        )
        try await storage.appendMessage(message, threadID: threadID, repoID: repoID)

        let loaded = try await storage.loadMessages(threadID: threadID, repoID: repoID)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded.first?.editBlocks)
    }

    // MARK: - testAppendAndLoadAIEditLog

    func testAppendAndLoadAIEditLog() async throws {
        let storage = makeStorage()
        let threadID = try await makeThreadAndSave(in: storage)
        let messageID = UUID()

        let entry1ID = UUID().uuidString
        let entry2ID = UUID().uuidString
        let entry3ID = UUID().uuidString

        try await storage.appendAIEditLog(
            id: entry1ID,
            threadID: threadID,
            messageID: messageID,
            filePath: "Sources/A.swift",
            blockIndex: 0,
            commitSHA: "abc1234",
            repoID: repoID
        )
        // Small sleep to ensure applied_at ordering is deterministic
        try await Task.sleep(nanoseconds: 10_000_000)
        try await storage.appendAIEditLog(
            id: entry2ID,
            threadID: threadID,
            messageID: messageID,
            filePath: "Sources/B.swift",
            blockIndex: 1,
            commitSHA: nil,
            repoID: repoID
        )
        try await Task.sleep(nanoseconds: 10_000_000)
        try await storage.appendAIEditLog(
            id: entry3ID,
            threadID: threadID,
            messageID: messageID,
            filePath: "Sources/C.swift",
            blockIndex: 2,
            commitSHA: "def5678",
            repoID: repoID
        )

        let entries = try await storage.loadAIEditLog(threadID: threadID, repoID: repoID)
        XCTAssertEqual(entries.count, 3)

        XCTAssertEqual(entries[0].id, entry1ID)
        XCTAssertEqual(entries[0].filePath, "Sources/A.swift")
        XCTAssertEqual(entries[0].blockIndex, 0)
        XCTAssertEqual(entries[0].commitSHA, "abc1234")
        XCTAssertNil(entries[0].restoredAt)
        XCTAssertEqual(entries[0].threadID, threadID)
        XCTAssertEqual(entries[0].messageID, messageID)

        XCTAssertEqual(entries[1].id, entry2ID)
        XCTAssertNil(entries[1].commitSHA)

        XCTAssertEqual(entries[2].id, entry3ID)
        XCTAssertEqual(entries[2].commitSHA, "def5678")

        // Verify ascending order by applied_at
        XCTAssertLessThanOrEqual(
            entries[0].appliedAt.timeIntervalSince1970,
            entries[1].appliedAt.timeIntervalSince1970
        )
        XCTAssertLessThanOrEqual(
            entries[1].appliedAt.timeIntervalSince1970,
            entries[2].appliedAt.timeIntervalSince1970
        )
    }

    // MARK: - testAIEditLogEmptyForNewThread

    func testAIEditLogEmptyForNewThread() async throws {
        let storage = makeStorage()
        _ = try await makeThreadAndSave(in: storage)

        let freshThreadID = UUID()
        // No entries appended for this thread
        let entries = try await storage.loadAIEditLog(threadID: freshThreadID, repoID: repoID)
        XCTAssertTrue(entries.isEmpty)
    }
}
