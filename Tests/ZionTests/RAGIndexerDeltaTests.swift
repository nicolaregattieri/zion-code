import XCTest
@testable import Zion

/// Phase 5f — incremental delta tests for `RAGIndexer.processDelta`.
/// Verifies path scoping (repo-relative), ignore-list filtering, and
/// delete-then-insert semantics for renames.
final class RAGIndexerDeltaTests: XCTestCase {

    private func makeIndexer() throws -> (RAGIndexer, URL, RAGStore) {
        let repo = URL(fileURLWithPath: "/tmp/zion-delta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let store = try RAGStore(repoURL: repo)
        let embedder = NLContextualEmbeddingProvider()
        let indexer = RAGIndexer(store: store, embedder: embedder)
        return (indexer, repo, store)
    }

    func test_processDelta_skipsIgnoredDirs() async throws {
        let (indexer, repo, store) = try makeIndexer()
        let gitDir = repo.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        let gitFile = gitDir.appendingPathComponent("HEAD.swift")
        try "// noop".write(to: gitFile, atomically: true, encoding: .utf8)
        await indexer.processDelta(paths: [gitFile.path], repoURL: repo)
        let count = try await store.chunkCount()
        XCTAssertEqual(count, 0, "ignored-dir files must never enter the store")
        await store.close()
        try? FileManager.default.removeItem(at: repo)
    }

    func test_processDelta_skipsPathsOutsideRepo() async throws {
        let (indexer, repo, store) = try makeIndexer()
        await indexer.processDelta(paths: ["/etc/hosts.swift"], repoURL: repo)
        let count = try await store.chunkCount()
        XCTAssertEqual(count, 0)
        await store.close()
        try? FileManager.default.removeItem(at: repo)
    }

    func test_processDelta_deletePath_clearsRows() async throws {
        let (indexer, repo, store) = try makeIndexer()
        let chunk = RAGChunk(path: "Foo.swift", startLine: 1, endLine: 5, kind: "function", contentSHA: "x", fallback: false, content: "x")
        let embedding = [Float](repeating: 0.1, count: Constants.RAG.embeddingDim)
        try await store.insertDocuments([chunk], embeddings: [embedding])
        let preCount = try await store.chunkCount()
        XCTAssertEqual(preCount, 1)

        let ghost = repo.appendingPathComponent("Foo.swift")
        await indexer.processDelta(paths: [ghost.path], repoURL: repo)
        let postCount = try await store.chunkCount()
        XCTAssertEqual(postCount, 0, "Delta on a vanished file must clear its rows")

        await store.close()
        try? FileManager.default.removeItem(at: repo)
    }
}
