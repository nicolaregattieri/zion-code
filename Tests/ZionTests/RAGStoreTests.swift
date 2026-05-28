import XCTest
@testable import Zion

/// Phase 5b — RAGStore end-to-end IO against the system SQLite. Uses
/// a per-test repo URL so the path-derived `<repoID>.db` does not
/// collide with the user's real RAG cache.
final class RAGStoreTests: XCTestCase {

    private func makeStore() throws -> (RAGStore, URL) {
        let repo = URL(fileURLWithPath: "/tmp/zion-test-\(UUID().uuidString)")
        let store = try RAGStore(repoURL: repo)
        return (store, repo)
    }

    func test_init_computesPerRepoPath() async throws {
        let (store, _) = try makeStore()
        let path = await store.storePath.path
        XCTAssertTrue(path.contains("/Zion/rag/"))
        XCTAssertTrue(path.hasSuffix(".db"))
        await store.close()
    }

    func test_open_createsSchemaWithFts5() async throws {
        let (store, _) = try makeStore()
        defer { Task { await store.close() } }
        try await store.openAndMigrate()
        let count = try await store.chunkCount()
        XCTAssertEqual(count, 0)
    }

    func test_insertAndCount_roundTrip() async throws {
        let (store, _) = try makeStore()
        defer { Task { await store.close() } }
        let chunk = RAGChunk(
            path: "Foo.swift",
            startLine: 1,
            endLine: 10,
            kind: "function",
            contentSHA: "abc123",
            fallback: false,
            content: "func token expiry handling"
        )
        let embedding = [Float](repeating: 0.1, count: Constants.RAG.embeddingDim)
        try await store.insertDocuments([chunk], embeddings: [embedding])
        let count = try await store.chunkCount()
        XCTAssertEqual(count, 1)
    }

    func test_deleteByPath_removesAllRows() async throws {
        let (store, _) = try makeStore()
        defer { Task { await store.close() } }
        let chunk = RAGChunk(
            path: "Foo.swift", startLine: 1, endLine: 10,
            kind: "function", contentSHA: "x", fallback: false, content: "x"
        )
        let embedding = [Float](repeating: 0.1, count: Constants.RAG.embeddingDim)
        try await store.insertDocuments([chunk], embeddings: [embedding])
        try await store.deleteByPath("Foo.swift")
        let count = try await store.chunkCount()
        XCTAssertEqual(count, 0)
    }

    func test_vectorSearch_returnsTopByCosine() async throws {
        let (store, _) = try makeStore()
        defer { Task { await store.close() } }

        let dim = Constants.RAG.embeddingDim
        let aligned = [Float](repeating: 1.0, count: dim)
        let orthogonal = (0..<dim).map { Float($0 % 2 == 0 ? 1 : -1) }
        let chunk1 = RAGChunk(path: "a.swift", startLine: 1, endLine: 5, kind: "fn", contentSHA: "1", fallback: false, content: "x")
        let chunk2 = RAGChunk(path: "b.swift", startLine: 1, endLine: 5, kind: "fn", contentSHA: "2", fallback: false, content: "x")
        try await store.insertDocuments([chunk1, chunk2], embeddings: [aligned, orthogonal])

        let hits = try await store.vectorSearch(embedding: aligned, limit: 2)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits.first?.chunk.path, "a.swift")
        XCTAssertGreaterThan(hits[0].score, hits[1].score)
    }

    func test_keywordSearch_returnsFts5Matches() async throws {
        let (store, _) = try makeStore()
        defer { Task { await store.close() } }
        let chunks = [
            RAGChunk(path: "a.swift", startLine: 1, endLine: 5, kind: "fn", contentSHA: "1", fallback: false, content: "function that handles token expiry"),
            RAGChunk(path: "b.swift", startLine: 1, endLine: 5, kind: "fn", contentSHA: "2", fallback: false, content: "unrelated network code"),
        ]
        let dim = Constants.RAG.embeddingDim
        let dummyEmbedding = [Float](repeating: 0.0, count: dim)
        try await store.insertDocuments(chunks, embeddings: [dummyEmbedding, dummyEmbedding])

        let hits = try await store.keywordSearch(query: "token", limit: 5)
        XCTAssertEqual(hits.first?.chunk.path, "a.swift")
    }
}
