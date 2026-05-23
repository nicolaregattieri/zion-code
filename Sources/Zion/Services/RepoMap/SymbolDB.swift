import Foundation
import GRDB

// MARK: - Row Types

struct SymbolRow: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    let file: String
    let kind: String
    let name: String
    let line: Int
    let col: Int
    let refsJSON: String

    static let databaseTableName = "symbols"

    enum CodingKeys: String, CodingKey {
        case file
        case kind
        case name
        case line
        case col
        case refsJSON = "refs_json"
    }

    var refs: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(refsJSON.utf8))) ?? []
    }

    init(file: String, kind: String, name: String, line: Int, col: Int, refsJSON: String = "[]") {
        self.file = file
        self.kind = kind
        self.name = name
        self.line = line
        self.col = col
        self.refsJSON = refsJSON
    }
}

struct FileRow: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    let path: String
    let lastParsedAt: TimeInterval
    let contentHash: String

    static let databaseTableName = "files"
}

// MARK: - SymbolDB Actor

actor SymbolDB {
    private let dbQueue: DatabaseQueue

    init(path: URL) throws {
        var config = Configuration()
        config.label = "zion.symboldb"
        self.dbQueue = try DatabaseQueue(path: path.path, configuration: config)
        try Self.migrator.migrate(dbQueue)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "files") { t in
                t.column("path", .text).primaryKey()
                t.column("lastParsedAt", .double).notNull()
                t.column("contentHash", .text).notNull()
            }
            try db.create(table: "symbols") { t in
                t.column("file", .text).notNull().indexed()
                t.column("kind", .text).notNull()
                t.column("name", .text).notNull().indexed()
                t.column("line", .integer).notNull()
                t.column("col", .integer).notNull()
                t.column("refs_json", .text).notNull()
            }
        }
        return m
    }

    // MARK: - Public API

    func insertFile(path: String, contentHash: String) async throws {
        let row = FileRow(path: path, lastParsedAt: Date().timeIntervalSinceReferenceDate, contentHash: contentHash)
        try await dbQueue.write { db in
            try row.save(db)
        }
    }

    /// Atomically replaces all symbols for a file.
    func upsertSymbols(_ symbols: [SymbolRow], file: String) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM symbols WHERE file = ?", arguments: [file])
            for symbol in symbols {
                try symbol.insert(db)
            }
        }
    }

    func symbolsForFile(_ path: String) async throws -> [SymbolRow] {
        try await dbQueue.read { db in
            try SymbolRow.filter(Column("file") == path).fetchAll(db)
        }
    }

    func symbolsByName(_ name: String, kind: String? = nil) async throws -> [SymbolRow] {
        try await dbQueue.read { db in
            var request = SymbolRow.filter(Column("name") == name)
            if let kind {
                request = request.filter(Column("kind") == kind)
            }
            return try request.fetchAll(db)
        }
    }

    func allFiles() async throws -> [FileRow] {
        try await dbQueue.read { db in
            try FileRow.fetchAll(db)
        }
    }

    func contentHashFor(_ path: String) async throws -> String? {
        try await dbQueue.read { db in
            try FileRow.filter(Column("path") == path).fetchOne(db)?.contentHash
        }
    }
}
