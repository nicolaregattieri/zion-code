import Foundation

// MARK: - RAGSchema

/// DDL constants and schema metadata for the per-repo RAG SQLite database.
enum RAGSchema {

    // MARK: - Version

    /// Current schema version. Bump this when DDL changes require a full rebuild.
    static let schemaVersion: Int = 1

    /// Identifier for the embedding backend stored in schema_meta.
    /// Used to detect when the model changes and a full re-index is needed.
    static let embeddingBackend: String = "apple-512"

    // MARK: - Table names

    static let documentsTable: String = "documents"
    static let vectorsTable: String = "vec_embeddings"
    static let ftsTable: String = "documents_fts"
    static let metaTable: String = "schema_meta"

    // MARK: - DDL

    /// Main document metadata table.
    static let createDocuments: String = """
        CREATE TABLE IF NOT EXISTS \(documentsTable) (
            id              INTEGER PRIMARY KEY,
            path            TEXT    NOT NULL,
            chunk_start_ln  INTEGER NOT NULL,
            chunk_end_ln    INTEGER NOT NULL,
            content_sha     TEXT    NOT NULL,
            kind            TEXT    NOT NULL,
            fallback        INTEGER NOT NULL DEFAULT 0,
            indexed_at      INTEGER NOT NULL
        );
        """

    /// Index on path for fast per-file delete / lookup.
    static let createDocumentsPathIndex: String = """
        CREATE INDEX IF NOT EXISTS idx_documents_path
        ON \(documentsTable)(path);
        """

    /// vec0 virtual table — stores float[N] embeddings keyed by document_id.
    static var createVectors: String {
        """
        CREATE VIRTUAL TABLE IF NOT EXISTS \(vectorsTable)
        USING vec0(
            document_id INTEGER PRIMARY KEY,
            embedding   FLOAT[\(Constants.RAG.embeddingDim)]
        );
        """
    }

    /// FTS5 virtual table over document content for keyword search.
    ///
    /// Content is stored externally in `documents`; we use the content= option
    /// so the FTS index can be kept in sync via triggers or explicit inserts.
    static let createFTS: String = """
        CREATE VIRTUAL TABLE IF NOT EXISTS \(ftsTable)
        USING fts5(
            content,
            content=\(documentsTable),
            content_rowid=id,
            tokenize='unicode61'
        );
        """

    /// Schema version / embedding backend registry.
    static let createMeta: String = """
        CREATE TABLE IF NOT EXISTS \(metaTable) (
            key     TEXT PRIMARY KEY,
            value   TEXT NOT NULL
        );
        """

    /// SQL to seed the meta table on first creation.
    static func insertMetaSQL(version: Int, backend: String) -> String {
        """
        INSERT OR IGNORE INTO \(metaTable) (key, value)
        VALUES
            ('schema_version', '\(version)'),
            ('embedding_backend', '\(backend)');
        """
    }

    // MARK: - Queries

    static let selectSchemaVersion: String = """
        SELECT value FROM \(metaTable) WHERE key = 'schema_version';
        """

    static let selectEmbeddingBackend: String = """
        SELECT value FROM \(metaTable) WHERE key = 'embedding_backend';
        """
}
