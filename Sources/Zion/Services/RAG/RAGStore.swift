import Foundation
import SQLite3
import Accelerate
import CryptoKit

// MARK: - RAGStoreError

enum RAGStoreError: Error, Equatable {
    /// Path collides with `ChatStorage`'s `chats/<repoID>.db` namespace.
    case persistencePathReserved(String)
    /// SQLite `open_v2` returned a non-OK code.
    case openFailed(String)
    /// Any prepared statement step / execute failure.
    case queryFailed(String)
    /// On-disk schema version disagreed with `RAGSchema.schemaVersion`.
    case schemaMismatch
    /// Embedding length doesn't match `Constants.RAG.embeddingDim`.
    case embeddingDimMismatch(expected: Int, got: Int)
}

// MARK: - RAGStore

/// Per-repository SQLite store. Phase 5b implementation: system SQLite3
/// (no SwiftPM dep — sidesteps the SQLiteVec amalgamation collision
/// against `ChatStorage`'s `import SQLite3`). Vectors live as BLOB
/// columns of `Float32` arrays; vector search is brute-force cosine via
/// Accelerate (fine at the 6k-chunk working point — see RFC budget).
/// Keyword search uses the macOS built-in FTS5 module.
///
/// Database location: `~/Library/Application Support/Zion/rag/<repoID>.db`.
/// Path safety guard rejects any URL whose computed path falls under
/// `/chats/` so ChatStorage's single-writer contract stays intact.
actor RAGStore {

    let repoURL: URL
    let storePath: URL

    @ObservationIgnored private var db: OpaquePointer? = nil

    init(repoURL: URL) throws {
        self.repoURL = repoURL
        self.storePath = try Self.makeStorePath(for: repoURL)
    }

    // No deinit closer — Swift 6 forbids touching actor-isolated
    // non-Sendable state from a nonisolated deinit. The OS reclaims the
    // sqlite3 handle on process exit; long-running RAGStore instances
    // own their lifecycle via `close()` (call before discard).
    func close() {
        if let handle = db { sqlite3_close_v2(handle) }
        db = nil
    }

    static func makeStorePath(for repoURL: URL) throws -> URL {
        let repoID = ChatStorage.repoID(for: repoURL)
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let path = support
            .appendingPathComponent("Zion", isDirectory: true)
            .appendingPathComponent("rag", isDirectory: true)
            .appendingPathComponent("\(repoID).db")
        if path.path.contains("/chats/") {
            throw RAGStoreError.persistencePathReserved(path.path)
        }
        return path
    }

    /// Opens the DB and runs schema bootstrap / migration. Idempotent.
    func openAndMigrate() throws {
        if db != nil { return }
        try FileManager.default.createDirectory(
            at: storePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var handle: OpaquePointer? = nil
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(storePath.path, &handle, flags, nil) == SQLITE_OK,
              let handle else {
            throw RAGStoreError.openFailed("open_v2 failed for \(storePath.path)")
        }
        db = handle
        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA foreign_keys = ON;")
        // Migrate on schema mismatch — drop + rebuild.
        let onDiskVersion = (try? scalar("SELECT value FROM schema_meta WHERE key = 'schema_version'")) ?? ""
        if onDiskVersion.isEmpty {
            try installSchema()
        } else if onDiskVersion != "\(RAGSchema.schemaVersion)" {
            try dropAndRebuild()
        }
    }

    private func installSchema() throws {
        try exec(RAGSchema.documentsTable)
        try exec(RAGSchema.vectorsTable)
        try exec(RAGSchema.documentsFtsTable)
        try exec(RAGSchema.schemaMetaTable)
        try exec("INSERT INTO schema_meta(key, value) VALUES ('schema_version', '\(RAGSchema.schemaVersion)');")
        try exec("INSERT INTO schema_meta(key, value) VALUES ('embedding_backend', '\(RAGSchema.defaultEmbeddingBackend)');")
    }

    private func dropAndRebuild() throws {
        try exec("DROP TABLE IF EXISTS documents_fts;")
        try exec("DROP TABLE IF EXISTS vectors;")
        try exec("DROP TABLE IF EXISTS documents;")
        try exec("DROP TABLE IF EXISTS schema_meta;")
        try installSchema()
    }

    // MARK: - Writes

    /// Inserts a batch of chunks + their embeddings inside one transaction.
    func insertDocuments(_ chunks: [RAGChunk], embeddings: [[Float]]) throws {
        guard chunks.count == embeddings.count else {
            throw RAGStoreError.queryFailed("chunks/embeddings count mismatch")
        }
        try openAndMigrate()
        try exec("BEGIN IMMEDIATE;")
        do {
            let insertDoc = "INSERT INTO documents(path, chunk_start_ln, chunk_end_ln, content_sha, kind, fallback, indexed_at) VALUES (?, ?, ?, ?, ?, ?, ?);"
            let insertFts = "INSERT INTO documents_fts(rowid, content) VALUES (?, ?);"
            let insertVec = "INSERT INTO vectors(document_id, embedding) VALUES (?, ?);"
            let now = Int(Date().timeIntervalSince1970)
            for (chunk, embedding) in zip(chunks, embeddings) {
                if embedding.count != Constants.RAG.embeddingDim {
                    throw RAGStoreError.embeddingDimMismatch(expected: Constants.RAG.embeddingDim, got: embedding.count)
                }
                let rowid = try insertReturningRowID(insertDoc, bind: { stmt in
                    sqlite3_bind_text(stmt, 1, chunk.path, -1, Self.SQLITE_TRANSIENT)
                    sqlite3_bind_int(stmt, 2, Int32(chunk.startLine))
                    sqlite3_bind_int(stmt, 3, Int32(chunk.endLine))
                    sqlite3_bind_text(stmt, 4, chunk.contentSHA, -1, Self.SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 5, chunk.kind, -1, Self.SQLITE_TRANSIENT)
                    sqlite3_bind_int(stmt, 6, chunk.fallback ? 1 : 0)
                    sqlite3_bind_int(stmt, 7, Int32(now))
                })
                try execBound(insertFts) { stmt in
                    sqlite3_bind_int64(stmt, 1, rowid)
                    sqlite3_bind_text(stmt, 2, chunk.content ?? "", -1, Self.SQLITE_TRANSIENT)
                }
                try execBound(insertVec) { stmt in
                    sqlite3_bind_int64(stmt, 1, rowid)
                    embedding.withUnsafeBufferPointer { buf in
                        sqlite3_bind_blob(stmt, 2, buf.baseAddress, Int32(buf.count * MemoryLayout<Float>.size), Self.SQLITE_TRANSIENT)
                    }
                }
            }
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func deleteByPath(_ path: String) throws {
        try openAndMigrate()
        try exec("BEGIN IMMEDIATE;")
        do {
            try execBound("DELETE FROM documents_fts WHERE rowid IN (SELECT id FROM documents WHERE path = ?);") { stmt in
                sqlite3_bind_text(stmt, 1, path, -1, Self.SQLITE_TRANSIENT)
            }
            try execBound("DELETE FROM vectors WHERE document_id IN (SELECT id FROM documents WHERE path = ?);") { stmt in
                sqlite3_bind_text(stmt, 1, path, -1, Self.SQLITE_TRANSIENT)
            }
            try execBound("DELETE FROM documents WHERE path = ?;") { stmt in
                sqlite3_bind_text(stmt, 1, path, -1, Self.SQLITE_TRANSIENT)
            }
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    // MARK: - Reads

    func chunkCount() throws -> Int {
        try openAndMigrate()
        let raw = try scalar("SELECT COUNT(*) FROM documents;")
        return Int(raw) ?? 0
    }

    /// Brute-force cosine over every row. Fine to ~10k vectors per RFC
    /// budget. Returns top-`limit` ordered by descending similarity.
    func vectorSearch(embedding query: [Float], limit: Int) throws -> [RAGHit] {
        guard query.count == Constants.RAG.embeddingDim else {
            throw RAGStoreError.embeddingDimMismatch(expected: Constants.RAG.embeddingDim, got: query.count)
        }
        try openAndMigrate()
        let sql = """
            SELECT documents.id, documents.path, documents.chunk_start_ln, documents.chunk_end_ln,
                   documents.content_sha, documents.kind, documents.fallback, vectors.embedding
              FROM documents
              JOIN vectors ON vectors.document_id = documents.id;
            """
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RAGStoreError.queryFailed("vectorSearch prepare failed")
        }
        defer { sqlite3_finalize(stmt) }

        let queryNorm = Self.l2Norm(query)
        var heap: [(score: Double, hit: RAGHit)] = []
        heap.reserveCapacity(limit + 1)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = String(cString: sqlite3_column_text(stmt, 1))
            let startLn = Int(sqlite3_column_int(stmt, 2))
            let endLn = Int(sqlite3_column_int(stmt, 3))
            let sha = String(cString: sqlite3_column_text(stmt, 4))
            let kind = String(cString: sqlite3_column_text(stmt, 5))
            let fallback = sqlite3_column_int(stmt, 6) != 0

            let blobBytes = sqlite3_column_bytes(stmt, 7)
            guard blobBytes == Constants.RAG.embeddingDim * MemoryLayout<Float>.size,
                  let blobPtr = sqlite3_column_blob(stmt, 7) else { continue }
            let buffer = UnsafeBufferPointer(
                start: blobPtr.assumingMemoryBound(to: Float.self),
                count: Constants.RAG.embeddingDim
            )
            let candidate = Array(buffer)
            let candNorm = Self.l2Norm(candidate)
            let score = Self.cosineSimilarity(query, candidate, queryNorm: queryNorm, candidateNorm: candNorm)

            let chunk = RAGChunk(
                path: path,
                startLine: startLn,
                endLine: endLn,
                kind: kind,
                contentSHA: sha,
                fallback: fallback
            )
            heap.append((score, RAGHit(chunk: chunk, score: score, source: .vector)))
            heap.sort { $0.score > $1.score }
            if heap.count > limit { heap.removeLast() }
        }
        return heap.map { $0.hit }
    }

    /// FTS5 keyword search via `MATCH`. Returns up to `limit` rows
    /// ordered by FTS5 BM25 rank (lower is more relevant).
    func keywordSearch(query: String, limit: Int) throws -> [RAGHit] {
        try openAndMigrate()
        let sql = """
            SELECT documents.id, documents.path, documents.chunk_start_ln, documents.chunk_end_ln,
                   documents.content_sha, documents.kind, documents.fallback, bm25(documents_fts) as rank
              FROM documents_fts
              JOIN documents ON documents.id = documents_fts.rowid
              WHERE documents_fts MATCH ?
              ORDER BY rank
              LIMIT ?;
            """
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RAGStoreError.queryFailed("keywordSearch prepare failed")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, query, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        var hits: [RAGHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = String(cString: sqlite3_column_text(stmt, 1))
            let startLn = Int(sqlite3_column_int(stmt, 2))
            let endLn = Int(sqlite3_column_int(stmt, 3))
            let sha = String(cString: sqlite3_column_text(stmt, 4))
            let kind = String(cString: sqlite3_column_text(stmt, 5))
            let fallback = sqlite3_column_int(stmt, 6) != 0
            let bm25 = sqlite3_column_double(stmt, 7)
            let chunk = RAGChunk(
                path: path,
                startLine: startLn,
                endLine: endLn,
                kind: kind,
                contentSHA: sha,
                fallback: fallback
            )
            // Invert BM25 so higher = better, matches cosine semantics.
            hits.append(RAGHit(chunk: chunk, score: -bm25, source: .keyword))
        }
        return hits
    }

    // MARK: - SQLite plumbing

    private static let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1)!,
        to: sqlite3_destructor_type.self
    )

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>? = nil
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(err)
            throw RAGStoreError.queryFailed(message)
        }
    }

    private func execBound(_ sql: String, bind: (OpaquePointer) -> Void) throws {
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            throw RAGStoreError.queryFailed("prepare failed for \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw RAGStoreError.queryFailed("step \(rc) for \(sql)")
        }
    }

    private func insertReturningRowID(_ sql: String, bind: (OpaquePointer) -> Void) throws -> Int64 {
        try execBound(sql, bind: bind)
        return sqlite3_last_insert_rowid(db)
    }

    private func scalar(_ sql: String) throws -> String {
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return "" }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW, let cstr = sqlite3_column_text(stmt, 0) {
            return String(cString: cstr)
        }
        return ""
    }

    // MARK: - Math

    private static func l2Norm(_ v: [Float]) -> Float {
        var sum: Float = 0
        vDSP_svesq(v, 1, &sum, vDSP_Length(v.count))
        return sqrt(sum)
    }

    private static func cosineSimilarity(
        _ a: [Float], _ b: [Float],
        queryNorm: Float, candidateNorm: Float
    ) -> Double {
        guard queryNorm > 0, candidateNorm > 0 else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return Double(dot / (queryNorm * candidateNorm))
    }
}

