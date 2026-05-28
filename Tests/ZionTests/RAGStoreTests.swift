import XCTest
@testable import Zion

/// Phase 5a — RAGStore IO is deferred behind a stub (SQLiteVec C symbol
/// collision against the system SQLite that ChatStorage already links).
/// These tests pin the surface that DOES ship: path computation +
/// notImplemented throwing. Phase 5b replaces them with the full schema
/// + vec / fts5 / migration suite.
final class RAGStoreTests: XCTestCase {

    func test_init_computesPerRepoPath() async throws {
        let repo = URL(fileURLWithPath: "/tmp/zion-test-\(UUID().uuidString)")
        let store = try RAGStore(repoURL: repo)
        let path = await store.storePath.path
        XCTAssertTrue(path.contains("/Zion/rag/"))
        XCTAssertTrue(path.hasSuffix(".db"))
    }

    func test_methods_throwNotImplemented_inStubPhase() async throws {
        let repo = URL(fileURLWithPath: "/tmp/zion-test-\(UUID().uuidString)")
        let store = try RAGStore(repoURL: repo)
        do {
            try await store.insertDocuments([], embeddings: [])
            XCTFail("expected notImplemented")
        } catch RAGStoreError.notImplemented {
            // ok
        }
        let count = try await store.chunkCount()
        XCTAssertEqual(count, 0)
    }
}
