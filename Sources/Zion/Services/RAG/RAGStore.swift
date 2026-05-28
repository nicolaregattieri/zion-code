import Foundation
import CryptoKit

// MARK: - RAGStoreError

enum RAGStoreError: Error, Equatable {
    /// The requested path collides with ChatStorage's chats/<repoID>.db namespace.
    case persistencePathReserved(String)
    /// Phase 5 SQLiteVec integration deferred to Phase 5b — see file header.
    case notImplemented
    /// Schema version on disk does not match `RAGSchema.schemaVersion`.
    case schemaMismatch
}

// MARK: - RAGStore (Phase 5a stub)

/// Per-repository SQLite store backed by sqlite-vec for vector similarity search.
///
/// **Phase 5a ships this as a stub.** The vendored
/// `jkrukowski/SQLiteVec` amalgamation (`CSQLiteVec/sqlite3ext.h`)
/// redefines `sqlite3_api_routines` and clashes with the system SQLite
/// that `ChatStorage.swift` already links via `import SQLite3`. Until
/// we either load sqlite-vec as a runtime extension on the system
/// sqlite3 OR the bindings expose a flag to skip the bundled
/// amalgamation, this actor returns `RAGStoreError.notImplemented`
/// from every IO method so the rest of Phase 5 (chunker, embedding
/// provider, mention resolver, settings UI) compiles in isolation.
///
/// The schema constants in `RAGSchema.swift` are intentionally kept so
/// that the Phase 5b implementation can drop in without churning the
/// public surface here.
///
/// Database location (Phase 5b): `~/Library/Application Support/Zion/rag/<repoID>.db`.
actor RAGStore {

    let repoURL: URL
    let storePath: URL

    init(repoURL: URL) throws {
        self.repoURL = repoURL
        self.storePath = try Self.makeStorePath(for: repoURL)
    }

    /// Reuses `ChatStorage.repoID(for:)` for the per-repo hash so the
    /// chat DB, the repo-map JSON, and the RAG DB all key off the same
    /// fingerprint for a given repository URL. Rejects any path under
    /// the chats DB directory to keep `ChatStorage`'s single-writer
    /// contract intact.
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

    /// Phase 5b: open the DB, load sqlite-vec, create tables, validate
    /// `schema_meta`. Today: no-op so callers can be wired without
    /// crashing.
    func openAndMigrate() async throws { /* notImplemented */ }

    func insertDocuments(_ chunks: [RAGChunk], embeddings: [[Float]]) async throws {
        _ = chunks
        _ = embeddings
        throw RAGStoreError.notImplemented
    }

    func deleteByPath(_ path: String) async throws {
        _ = path
        throw RAGStoreError.notImplemented
    }

    func vectorSearch(embedding: [Float], limit: Int) async throws -> [RAGHit] {
        _ = embedding
        _ = limit
        throw RAGStoreError.notImplemented
    }

    func keywordSearch(query: String, limit: Int) async throws -> [RAGHit] {
        _ = query
        _ = limit
        throw RAGStoreError.notImplemented
    }

    func chunkCount() async throws -> Int { 0 }
}
