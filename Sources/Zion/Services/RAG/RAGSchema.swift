import Foundation

// MARK: - RAGSchema

/// DDL for the per-repo RAG SQLite database. Phase 5b uses the macOS
/// system SQLite directly (no SwiftPM dep) and stores embeddings as a
/// plain BLOB column of float32 bytes. Phase 5c may swap the vector
/// column for the `sqlite-vec` `vec0` virtual table once the build-
/// system collision against `ChatStorage`'s `import SQLite3` is
/// resolved (load sqlite-vec as a runtime extension via
/// `sqlite3_load_extension` or upstream a build flag).
///
/// FTS5 is built into the macOS-shipped SQLite, so the keyword side
/// works today without any vendored binary.
enum RAGSchema {

    /// Bump on any DDL change that requires a full rebuild.
    static let schemaVersion: Int = 1

    /// Embedding backend identifier persisted in `schema_meta`. Used to
    /// drop-and-rebuild when the backend changes (e.g., a future swap
    /// from NLContextualEmbedding-512 to Qodo-1536).
    static let defaultEmbeddingBackend: String = "nl-contextual-latin-512"

    /// Main document metadata table.
    static let documentsTable: String = """
        CREATE TABLE IF NOT EXISTS documents (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            path            TEXT    NOT NULL,
            chunk_start_ln  INTEGER NOT NULL,
            chunk_end_ln    INTEGER NOT NULL,
            content_sha     TEXT    NOT NULL,
            kind            TEXT    NOT NULL,
            fallback        INTEGER NOT NULL DEFAULT 0,
            indexed_at      INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_documents_path ON documents(path);
        CREATE INDEX IF NOT EXISTS idx_documents_sha ON documents(content_sha);
        """

    /// Vector table — Phase 5b stores embeddings as a raw BLOB column
    /// (float32 little-endian, length = `Constants.RAG.embeddingDim *
    /// 4` bytes). Phase 5c may swap this for `vec0` once SQLiteVec is
    /// unblocked.
    static let vectorsTable: String = """
        CREATE TABLE IF NOT EXISTS vectors (
            document_id INTEGER PRIMARY KEY,
            embedding   BLOB    NOT NULL,
            FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
        );
        """

    /// FTS5 virtual table over chunk content. Macos-shipped SQLite has
    /// the fts5 module compiled in by default.
    static let documentsFtsTable: String = """
        CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
            content,
            tokenize='unicode61',
            content_rowid='id'
        );
        """

    /// Metadata table — `schema_version` + `embedding_backend`.
    static let schemaMetaTable: String = """
        CREATE TABLE IF NOT EXISTS schema_meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
}
