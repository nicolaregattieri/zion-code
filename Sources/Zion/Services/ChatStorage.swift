import Foundation
import CryptoKit
import SQLite3

// sqliteTransient is not exported as a constant in Swift's SQLite3 overlay
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - ChatStorageError

enum ChatStorageError: Error {
    case sqlite(code: Int32, message: String)
}

// MARK: - ChatStorage

actor ChatStorage {

    // MARK: - Properties

    private let baseDirectory: URL
    nonisolated(unsafe) private var connections: [String: OpaquePointer] = [:]

    // MARK: - Init

    init(baseDirectory: URL? = nil) {
        if let base = baseDirectory {
            self.baseDirectory = base
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.baseDirectory = appSupport.appendingPathComponent("Zion", isDirectory: true)
        }
    }

    // MARK: - Public API

    static func repoID(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let data = Data(path.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func loadThreads(repoID: String) async throws -> [ChatThread] {
        let db = try connection(for: repoID)
        let sql = "SELECT id, title, created_at, updated_at FROM threads WHERE repo_id = ? ORDER BY updated_at DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError(db)
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, repoID, -1, sqliteTransient)

        var threads: [ChatThread] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = String(cString: sqlite3_column_text(stmt, 0))
            let title = String(cString: sqlite3_column_text(stmt, 1))
            let createdAt = sqlite3_column_double(stmt, 2)
            guard let id = UUID(uuidString: idStr) else { continue }
            threads.append(ChatThread(
                id: id,
                messages: [],
                createdAt: Date(timeIntervalSince1970: createdAt),
                repoID: repoID,
                title: title
            ))
        }
        return threads
    }

    func saveThread(_ thread: ChatThread, repoID: String) async throws {
        let db = try connection(for: repoID)
        let sql = """
            INSERT INTO threads (id, repo_id, title, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              title = excluded.title,
              updated_at = excluded.updated_at;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError(db)
        }
        defer { sqlite3_finalize(stmt) }

        let idStr = thread.id.uuidString
        let now = Date().timeIntervalSince1970
        sqlite3_bind_text(stmt, 1, idStr, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, repoID, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, thread.title, -1, sqliteTransient)
        sqlite3_bind_double(stmt, 4, thread.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 5, now)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw sqliteError(db)
        }
    }

    func loadMessages(threadID: UUID, repoID: String) async throws -> [ChatMessage] {
        let db = try connection(for: repoID)
        let sql = """
            SELECT m.id, m.role, m.content, m.created_at, m.is_streaming
            FROM messages m
            JOIN threads t ON t.id = m.thread_id
            WHERE m.thread_id = ? AND t.repo_id = ?
            ORDER BY m.created_at ASC;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError(db)
        }
        defer { sqlite3_finalize(stmt) }

        let threadIDStr = threadID.uuidString
        sqlite3_bind_text(stmt, 1, threadIDStr, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, repoID, -1, sqliteTransient)

        var messages: [ChatMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = String(cString: sqlite3_column_text(stmt, 0))
            let roleStr = String(cString: sqlite3_column_text(stmt, 1))
            let content = String(cString: sqlite3_column_text(stmt, 2))
            let createdAt = sqlite3_column_double(stmt, 3)
            let isStreaming = sqlite3_column_int(stmt, 4) != 0

            guard let id = UUID(uuidString: idStr) else { continue }
            let role: ChatRole = roleStr == "assistant" ? .assistant : .user

            messages.append(ChatMessage(
                id: id,
                role: role,
                content: content,
                timestamp: Date(timeIntervalSince1970: createdAt),
                isStreaming: isStreaming
            ))
        }
        return messages
    }

    func appendMessage(_ message: ChatMessage, threadID: UUID, repoID: String) async throws {
        let db = try connection(for: repoID)
        let sql = """
            INSERT INTO messages (id, thread_id, role, content, created_at, is_streaming)
            VALUES (?, ?, ?, ?, ?, ?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError(db)
        }
        defer { sqlite3_finalize(stmt) }

        let idStr = message.id.uuidString
        let threadIDStr = threadID.uuidString
        let roleStr = message.role == .assistant ? "assistant" : "user"
        sqlite3_bind_text(stmt, 1, idStr, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, threadIDStr, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, roleStr, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 4, message.content, -1, sqliteTransient)
        sqlite3_bind_double(stmt, 5, message.timestamp.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 6, message.isStreaming ? 1 : 0)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw sqliteError(db)
        }

        // Update thread updated_at
        let updateSQL = "UPDATE threads SET updated_at = ? WHERE id = ?;"
        var updateStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(updateStmt) }
            sqlite3_bind_double(updateStmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(updateStmt, 2, threadIDStr, -1, sqliteTransient)
            sqlite3_step(updateStmt)
        }
    }

    func updateMessage(_ message: ChatMessage, repoID: String) async throws {
        let db = try connection(for: repoID)
        let sql = "UPDATE messages SET content = ?, is_streaming = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError(db)
        }
        defer { sqlite3_finalize(stmt) }

        let idStr = message.id.uuidString
        sqlite3_bind_text(stmt, 1, message.content, -1, sqliteTransient)
        sqlite3_bind_int(stmt, 2, message.isStreaming ? 1 : 0)
        sqlite3_bind_text(stmt, 3, idStr, -1, sqliteTransient)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw sqliteError(db)
        }
    }

    func deleteThread(_ id: UUID, repoID: String) async throws {
        let db = try connection(for: repoID)
        let sql = "DELETE FROM threads WHERE id = ? AND repo_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError(db)
        }
        defer { sqlite3_finalize(stmt) }

        let idStr = id.uuidString
        sqlite3_bind_text(stmt, 1, idStr, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, repoID, -1, sqliteTransient)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw sqliteError(db)
        }
    }

    func renameThread(_ id: UUID, title: String, repoID: String) async throws {
        let db = try connection(for: repoID)
        let sql = "UPDATE threads SET title = ?, updated_at = ? WHERE id = ? AND repo_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError(db)
        }
        defer { sqlite3_finalize(stmt) }

        let idStr = id.uuidString
        sqlite3_bind_text(stmt, 1, title, -1, sqliteTransient)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, idStr, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 4, repoID, -1, sqliteTransient)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw sqliteError(db)
        }
    }

    // MARK: - Private

    private func connection(for repoID: String) throws -> OpaquePointer {
        if let existing = connections[repoID] {
            return existing
        }

        let chatsDir = baseDirectory.appendingPathComponent("chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)

        let dbURL = chatsDir.appendingPathComponent("\(repoID).db")
        var db: OpaquePointer?
        let result = sqlite3_open(dbURL.path, &db)
        guard result == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw ChatStorageError.sqlite(code: result, message: msg)
        }

        try applySchema(db: db)
        connections[repoID] = db
        return db
    }

    private func applySchema(db: OpaquePointer) throws {
        let pragmaSQL = "PRAGMA foreign_keys = ON;"
        try exec(db: db, sql: pragmaSQL)

        let threadsSQL = """
            CREATE TABLE IF NOT EXISTS threads (
              id TEXT PRIMARY KEY,
              repo_id TEXT NOT NULL,
              title TEXT NOT NULL,
              created_at REAL NOT NULL,
              updated_at REAL NOT NULL
            );
            """
        try exec(db: db, sql: threadsSQL)

        let messagesSQL = """
            CREATE TABLE IF NOT EXISTS messages (
              id TEXT PRIMARY KEY,
              thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
              role TEXT NOT NULL,
              content TEXT NOT NULL,
              created_at REAL NOT NULL,
              is_streaming INTEGER NOT NULL DEFAULT 0
            );
            """
        try exec(db: db, sql: messagesSQL)

        let indexSQL = """
            CREATE INDEX IF NOT EXISTS idx_messages_thread_created
            ON messages(thread_id, created_at);
            """
        try exec(db: db, sql: indexSQL)
    }

    private func exec(db: OpaquePointer, sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errmsg)
        if result != SQLITE_OK {
            let msg = errmsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errmsg)
            throw ChatStorageError.sqlite(code: result, message: msg)
        }
    }

    private func sqliteError(_ db: OpaquePointer) -> ChatStorageError {
        let code = sqlite3_errcode(db)
        let msg = String(cString: sqlite3_errmsg(db))
        return ChatStorageError.sqlite(code: code, message: msg)
    }
}
