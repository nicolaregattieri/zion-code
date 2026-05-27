import Foundation
import CryptoKit
import SQLite3

// sqliteTransient is not exported as a constant in Swift's SQLite3 overlay
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - ChatStorageError

enum ChatStorageError: Error {
    case sqlite(code: Int32, message: String)
}

// MARK: - AIEditLogEntry

struct AIEditLogEntry: Identifiable, Equatable, Codable {
    let id: String
    let threadID: UUID
    let messageID: UUID
    let filePath: String
    let blockIndex: Int
    let appliedAt: Date
    let commitSHA: String?
    let restoredAt: Date?
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
        // Normalize against path-encoding variants that would otherwise produce
        // different hashes for the same logical repository: trailing slashes
        // and symlink prefixes (e.g. /var → /private/var on macOS). Without
        // this collapse, the same repo can hash to two distinct IDs and
        // orphan threads in a parallel per-repo DB.
        var path = url.resolvingSymlinksInPath().standardizedFileURL.path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        let data = Data(path.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func loadThreads(repoID: String) async throws -> [ChatThread] {
        let db = try connection(for: repoID)
        let sql = """
            SELECT id, title, created_at, updated_at, cli_session_id, cli_session_provider,
                   total_cost_usd, total_input_tokens, total_output_tokens
            FROM threads
            WHERE repo_id = ?
            ORDER BY updated_at DESC;
            """
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
            let cliSessionID: String? = sqlite3_column_type(stmt, 4) == SQLITE_NULL
                ? nil : String(cString: sqlite3_column_text(stmt, 4))
            let cliSessionProvider: String? = sqlite3_column_type(stmt, 5) == SQLITE_NULL
                ? nil : String(cString: sqlite3_column_text(stmt, 5))
            let totalCost = sqlite3_column_double(stmt, 6)
            let totalInputTokens = Int(sqlite3_column_int64(stmt, 7))
            let totalOutputTokens = Int(sqlite3_column_int64(stmt, 8))
            guard let id = UUID(uuidString: idStr) else { continue }
            threads.append(ChatThread(
                id: id,
                messages: [],
                createdAt: Date(timeIntervalSince1970: createdAt),
                repoID: repoID,
                title: title,
                cliSessionID: cliSessionID,
                cliSessionProvider: cliSessionProvider,
                totalCostUSD: totalCost,
                totalInputTokens: totalInputTokens,
                totalOutputTokens: totalOutputTokens
            ))
        }
        return threads
    }

    func saveThread(_ thread: ChatThread, repoID: String) async throws {
        let db = try connection(for: repoID)
        let sql = """
            INSERT INTO threads (id, repo_id, title, created_at, updated_at,
                                 cli_session_id, cli_session_provider, total_cost_usd,
                                 total_input_tokens, total_output_tokens)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              title = excluded.title,
              updated_at = excluded.updated_at,
              cli_session_id = excluded.cli_session_id,
              cli_session_provider = excluded.cli_session_provider,
              total_cost_usd = excluded.total_cost_usd,
              total_input_tokens = excluded.total_input_tokens,
              total_output_tokens = excluded.total_output_tokens;
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
        if let sid = thread.cliSessionID {
            sqlite3_bind_text(stmt, 6, sid, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        if let prov = thread.cliSessionProvider {
            sqlite3_bind_text(stmt, 7, prov, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        sqlite3_bind_double(stmt, 8, thread.totalCostUSD)
        sqlite3_bind_int64(stmt, 9, Int64(thread.totalInputTokens))
        sqlite3_bind_int64(stmt, 10, Int64(thread.totalOutputTokens))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw sqliteError(db)
        }
    }

    func loadMessages(threadID: UUID, repoID: String) async throws -> [ChatMessage] {
        let db = try connection(for: repoID)
        let sql = """
            SELECT m.id, m.role, m.content, m.created_at, m.is_streaming, m.plan_json,
                   m.edit_blocks_json, m.provider_used, m.attachments_json
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
            let plan: ChatPlan? = sqlite3_column_type(stmt, 5) != SQLITE_NULL
                ? (sqlite3_column_text(stmt, 5).flatMap { ptr -> ChatPlan? in
                    let jsonStr = String(cString: ptr)
                    guard let data = jsonStr.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode(ChatPlan.self, from: data)
                })
                : nil
            let editBlocks: [EditBlock]? = sqlite3_column_type(stmt, 6) != SQLITE_NULL
                ? (sqlite3_column_text(stmt, 6).flatMap { ptr -> [EditBlock]? in
                    let jsonStr = String(cString: ptr)
                    guard let data = jsonStr.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode([EditBlock].self, from: data)
                })
                : nil
            let providerUsed: String? = sqlite3_column_type(stmt, 7) != SQLITE_NULL
                ? sqlite3_column_text(stmt, 7).map { String(cString: $0) }
                : nil
            let attachments: [ChatAttachment] = sqlite3_column_type(stmt, 8) != SQLITE_NULL
                ? (sqlite3_column_text(stmt, 8).flatMap { ptr -> [ChatAttachment]? in
                    let jsonStr = String(cString: ptr)
                    guard let data = jsonStr.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode([ChatAttachment].self, from: data)
                }) ?? []
                : []

            guard let id = UUID(uuidString: idStr) else { continue }
            let role: ChatRole = roleStr == "assistant" ? .assistant : .user

            messages.append(ChatMessage(
                id: id,
                role: role,
                content: content,
                timestamp: Date(timeIntervalSince1970: createdAt),
                isStreaming: isStreaming,
                plan: plan,
                editBlocks: editBlocks,
                providerUsed: providerUsed,
                attachments: attachments
            ))
        }
        return messages
    }

    func appendMessage(_ message: ChatMessage, threadID: UUID, repoID: String) async throws {
        let db = try connection(for: repoID)
        let sql = """
            INSERT INTO messages (id, thread_id, role, content, created_at, is_streaming,
                                  plan_json, edit_blocks_json, provider_used, attachments_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
        if let plan = message.plan,
           let data = try? JSONEncoder().encode(plan),
           let jsonStr = String(data: data, encoding: .utf8) {
            sqlite3_bind_text(stmt, 7, jsonStr, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        if let blocks = message.editBlocks,
           let data = try? JSONEncoder().encode(blocks),
           let jsonStr = String(data: data, encoding: .utf8) {
            sqlite3_bind_text(stmt, 8, jsonStr, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        if let provider = message.providerUsed {
            sqlite3_bind_text(stmt, 9, provider, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        if !message.attachments.isEmpty,
           let data = try? JSONEncoder().encode(message.attachments),
           let jsonStr = String(data: data, encoding: .utf8) {
            sqlite3_bind_text(stmt, 10, jsonStr, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 10)
        }

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
        let sql = """
            UPDATE messages SET content = ?, is_streaming = ?, plan_json = ?,
                                edit_blocks_json = ?, provider_used = ?
            WHERE id = ?;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError(db)
        }
        defer { sqlite3_finalize(stmt) }

        let idStr = message.id.uuidString
        sqlite3_bind_text(stmt, 1, message.content, -1, sqliteTransient)
        sqlite3_bind_int(stmt, 2, message.isStreaming ? 1 : 0)
        if let plan = message.plan,
           let data = try? JSONEncoder().encode(plan),
           let jsonStr = String(data: data, encoding: .utf8) {
            sqlite3_bind_text(stmt, 3, jsonStr, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        if let blocks = message.editBlocks,
           let data = try? JSONEncoder().encode(blocks),
           let jsonStr = String(data: data, encoding: .utf8) {
            sqlite3_bind_text(stmt, 4, jsonStr, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        if let provider = message.providerUsed {
            sqlite3_bind_text(stmt, 5, provider, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_bind_text(stmt, 6, idStr, -1, sqliteTransient)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw sqliteError(db)
        }
    }

    func appendAIEditLog(
        id: String,
        threadID: UUID,
        messageID: UUID,
        filePath: String,
        blockIndex: Int,
        commitSHA: String?,
        repoID: String
    ) async throws {
        let db = try connection(for: repoID)
        let sql = """
            INSERT INTO aiedit_log
                (id, thread_id, message_id, file_path, block_index, applied_at, commit_sha)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError(db)
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, threadID.uuidString, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, messageID.uuidString, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 4, filePath, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 5, Int64(blockIndex))
        sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)
        if let sha = commitSHA {
            sqlite3_bind_text(stmt, 7, sha, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 7)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw sqliteError(db)
        }
    }

    func loadAIEditLog(threadID: UUID, repoID: String) async throws -> [AIEditLogEntry] {
        let db = try connection(for: repoID)
        let sql = """
            SELECT id, thread_id, message_id, file_path, block_index, applied_at, commit_sha,
                   restored_at
            FROM aiedit_log
            WHERE thread_id = ?
            ORDER BY applied_at ASC;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError(db)
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, threadID.uuidString, -1, sqliteTransient)

        var entries: [AIEditLogEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entryID = String(cString: sqlite3_column_text(stmt, 0))
            let threadIDStr = String(cString: sqlite3_column_text(stmt, 1))
            let messageIDStr = String(cString: sqlite3_column_text(stmt, 2))
            let filePath = String(cString: sqlite3_column_text(stmt, 3))
            let blockIndex = Int(sqlite3_column_int64(stmt, 4))
            let appliedAt = sqlite3_column_double(stmt, 5)
            let commitSHA: String? = sqlite3_column_type(stmt, 6) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 6))
                : nil
            let restoredAt: Double? = sqlite3_column_type(stmt, 7) != SQLITE_NULL
                ? sqlite3_column_double(stmt, 7)
                : nil

            guard let tid = UUID(uuidString: threadIDStr),
                  let mid = UUID(uuidString: messageIDStr) else { continue }

            entries.append(AIEditLogEntry(
                id: entryID,
                threadID: tid,
                messageID: mid,
                filePath: filePath,
                blockIndex: blockIndex,
                appliedAt: Date(timeIntervalSince1970: appliedAt),
                commitSHA: commitSHA,
                restoredAt: restoredAt.map { Date(timeIntervalSince1970: $0) }
            ))
        }
        return entries
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

        // v2 migration: CLI session resume + cumulative subscription cost.
        // sqlite3 ALTER TABLE ADD COLUMN errors if the column already exists,
        // so we swallow that specific error. Any other failure still throws.
        try? exec(db: db, sql: "ALTER TABLE threads ADD COLUMN cli_session_id TEXT NULL;")
        try? exec(db: db, sql: "ALTER TABLE threads ADD COLUMN cli_session_provider TEXT NULL;")
        try? exec(db: db, sql: "ALTER TABLE threads ADD COLUMN total_cost_usd REAL DEFAULT 0;")
        try? exec(db: db, sql: "ALTER TABLE threads ADD COLUMN total_input_tokens INTEGER DEFAULT 0;")
        try? exec(db: db, sql: "ALTER TABLE threads ADD COLUMN total_output_tokens INTEGER DEFAULT 0;")

        // v3 migration: ChatPlan structured plan attached to messages.
        try? exec(db: db, sql: "ALTER TABLE messages ADD COLUMN plan_json TEXT NULL;")

        // v4 migration: EditBlocks JSON column on messages.
        try? exec(db: db, sql: "ALTER TABLE messages ADD COLUMN edit_blocks_json TEXT NULL;")

        // v5 migration: provider_used column on messages.
        try? exec(db: db, sql: "ALTER TABLE messages ADD COLUMN provider_used TEXT NULL;")

        // v6 migration: attachments JSON (images, PDFs, etc.) on messages.
        try? exec(db: db, sql: "ALTER TABLE messages ADD COLUMN attachments_json TEXT NULL;")

        // v4 migration: AI edit log table.
        try? exec(db: db, sql: """
            CREATE TABLE IF NOT EXISTS aiedit_log (
              id TEXT PRIMARY KEY,
              thread_id TEXT NOT NULL,
              message_id TEXT NOT NULL,
              file_path TEXT NOT NULL,
              block_index INTEGER NOT NULL,
              applied_at REAL NOT NULL,
              commit_sha TEXT,
              restored_at REAL
            );
            """)
        try? exec(db: db, sql: """
            CREATE INDEX IF NOT EXISTS idx_aiedit_log_thread
            ON aiedit_log(thread_id, applied_at);
            """)
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
