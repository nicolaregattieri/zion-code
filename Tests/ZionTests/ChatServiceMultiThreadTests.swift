import XCTest
@testable import Zion

@MainActor
final class ChatServiceMultiThreadTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempStorage() -> ChatStorage {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-multithread-\(UUID().uuidString)", isDirectory: true)
        return ChatStorage(baseDirectory: dir)
    }

    private func makeService(storage: ChatStorage? = nil, repoID: String = "test-repo") -> ChatService {
        let worker = RepositoryWorker()
        let ai = AIClient()
        let builder = ChatContextBuilder(worker: worker)
        return ChatService(
            ai: ai,
            worker: worker,
            contextBuilder: builder,
            streamProvider: { _, _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield("ok")
                    continuation.finish()
                }
            },
            storage: storage,
            repoID: repoID
        )
    }

    // MARK: - testCreateThreadAppendsAndActivates

    func testCreateThreadAppendsAndActivates() async throws {
        let svc = makeService()

        // Ensure we start with at least one thread
        let initialCount = svc.threads.count
        let initialID = svc.activeThreadID

        svc.createThread()

        XCTAssertEqual(svc.threads.count, initialCount + 1, "createThread should append one thread")
        XCTAssertNotEqual(svc.activeThreadID, initialID, "activeThreadID should change after createThread")
        XCTAssertEqual(svc.threads.first?.id, svc.activeThreadID, "New thread should be at front and active")
    }

    // MARK: - testSelectThreadSwapsActive

    func testSelectThreadSwapsActive() async throws {
        let svc = makeService()

        // Create two threads
        svc.createThread()
        let firstID = svc.activeThreadID

        svc.createThread()
        let secondID = svc.activeThreadID
        XCTAssertNotEqual(firstID, secondID)

        // Select first
        svc.selectThread(firstID)
        XCTAssertEqual(svc.activeThreadID, firstID, "selectThread should activate the chosen thread")

        // Select second
        svc.selectThread(secondID)
        XCTAssertEqual(svc.activeThreadID, secondID)
    }

    // MARK: - testDeleteActiveThreadSelectsNextOrCreates

    func testDeleteActiveThreadSelectsNextOrCreates() async throws {
        let svc = makeService()

        // Start with one thread (created by default from makeService calling createThread
        // internally if threads is empty — but actually ChatService starts empty without storage.
        // Create two threads manually.)
        svc.createThread()
        let t1 = svc.activeThreadID

        svc.createThread()
        let t2 = svc.activeThreadID

        XCTAssertEqual(svc.threads.count, 2)

        // Delete active (t2); should switch to t1
        svc.deleteThread(t2)
        XCTAssertEqual(svc.threads.count, 1)
        XCTAssertEqual(svc.activeThreadID, t1, "Deleting active thread should switch to next available")

        // Delete last thread; should create a new one
        svc.deleteThread(t1)
        XCTAssertEqual(svc.threads.count, 1, "Deleting last thread should create a replacement")
        XCTAssertNotEqual(svc.activeThreadID, t1, "New thread should have a fresh ID")
    }

    // MARK: - testRenameThreadUpdatesTitle

    func testRenameThreadUpdatesTitle() async throws {
        let svc = makeService()
        svc.createThread()
        let id = svc.activeThreadID

        svc.renameThread(id, title: "My Conversation")

        let t = svc.threads.first { $0.id == id }
        XCTAssertEqual(t?.title, "My Conversation", "renameThread should update the thread title")
    }

    // MARK: - testInitLoadsPersistedThreads

    func testInitLoadsPersistedThreads() async throws {
        let storage = makeTempStorage()
        let repoID = "persist-test-repo"

        // Pre-populate storage with a thread
        let existing = ChatThread(id: UUID(), messages: [], createdAt: Date(), repoID: repoID, title: "Saved Thread")
        try await storage.saveThread(existing, repoID: repoID)

        // Create a service pointing to same storage
        let worker = RepositoryWorker()
        let ai = AIClient()
        let builder = ChatContextBuilder(worker: worker)
        let svc = ChatService(
            ai: ai,
            worker: worker,
            contextBuilder: builder,
            storage: storage,
            repoID: repoID
        )

        // Give the init Task time to complete
        try await Task.sleep(nanoseconds: 200_000_000) // 200 ms

        XCTAssertFalse(svc.threads.isEmpty, "Service should load persisted threads on init")
        let titles = svc.threads.map { $0.title }
        XCTAssertTrue(titles.contains("Saved Thread"), "Persisted thread title should be loaded. Got: \(titles)")
    }

    // MARK: - testThreadComputedPropertyBackCompat

    func testThreadComputedPropertyBackCompat() async throws {
        let svc = makeService()
        svc.createThread()

        // `thread` computed property should return the active thread
        let activeThread = svc.thread
        XCTAssertEqual(activeThread.id, svc.activeThreadID, "`thread` computed property should return the active thread")

        // Setting via computed property should update threads array
        var modified = activeThread
        modified.title = "Modified"
        svc.thread = modified

        XCTAssertEqual(svc.threads.first { $0.id == svc.activeThreadID }?.title, "Modified",
                       "`thread` setter should update threads array")
    }
}
