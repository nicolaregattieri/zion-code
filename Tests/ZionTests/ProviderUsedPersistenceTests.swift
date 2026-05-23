import XCTest
import Foundation
@testable import Zion

final class ProviderUsedPersistenceTests: XCTestCase {

    private func makeStorage() -> ChatStorage {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return ChatStorage(baseDirectory: dir)
    }

    private let repoID = "providerusedrepo"

    // MARK: - Helper

    private func makeThread(in storage: ChatStorage) async throws -> UUID {
        let threadID = UUID()
        let thread = ChatThread(
            id: threadID,
            messages: [],
            createdAt: Date(),
            repoID: repoID,
            title: "Provider Test Thread"
        )
        try await storage.saveThread(thread, repoID: repoID)
        return threadID
    }

    // MARK: - testRoundTripWithProviderUsed

    func testRoundTripWithProviderUsed() async throws {
        let storage = makeStorage()
        let threadID = try await makeThread(in: storage)

        let messageID = UUID()
        let message = ChatMessage(
            id: messageID,
            role: .assistant,
            content: "Hello from anthropic",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            providerUsed: "anthropic"
        )
        try await storage.appendMessage(message, threadID: threadID, repoID: repoID)

        let loaded = try await storage.loadMessages(threadID: threadID, repoID: repoID)
        XCTAssertEqual(loaded.count, 1)

        let loadedMsg = try XCTUnwrap(loaded.first)
        XCTAssertEqual(loadedMsg.id, messageID)
        XCTAssertEqual(loadedMsg.providerUsed, "anthropic")
    }

    // MARK: - testRoundTripNilProviderUsed

    func testRoundTripNilProviderUsed() async throws {
        let storage = makeStorage()
        let threadID = try await makeThread(in: storage)

        let messageID = UUID()
        let message = ChatMessage(
            id: messageID,
            role: .user,
            content: "Just a user message",
            timestamp: Date(timeIntervalSince1970: 1_700_000_001),
            providerUsed: nil
        )
        try await storage.appendMessage(message, threadID: threadID, repoID: repoID)

        let loaded = try await storage.loadMessages(threadID: threadID, repoID: repoID)
        XCTAssertEqual(loaded.count, 1)

        let loadedMsg = try XCTUnwrap(loaded.first)
        XCTAssertEqual(loadedMsg.id, messageID)
        XCTAssertNil(loadedMsg.providerUsed)
    }
}
