import Foundation
import GRDB

actor SpendLedger {
    static let defaultPath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".zion/spend.sqlite")

    private let dbQueue: DatabaseQueue

    init(path: URL = SpendLedger.defaultPath) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.label = "zion.spend"
        self.dbQueue = try DatabaseQueue(path: path.path, configuration: config)
        try Self.migrator.migrate(dbQueue)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "spend_ledger") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("ts", .double).notNull()  // Unix epoch
                t.column("provider", .text).notNull().indexed()
                t.column("model", .text).notNull()
                t.column("input_tokens", .integer).notNull()
                t.column("output_tokens", .integer).notNull()
                t.column("cache_read_tokens", .integer).notNull()
                t.column("usd_cost", .double).notNull()
                t.column("billing_mode", .text).notNull()
            }
        }
        return m
    }

    /// Records one provider response in the ledger.
    func append(_ row: ProviderSpendRow, at timestamp: Date = Date()) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO spend_ledger (ts, provider, model, input_tokens, output_tokens, cache_read_tokens, usd_cost, billing_mode)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                timestamp.timeIntervalSince1970,
                row.provider,
                row.model,
                row.inputTokens,
                row.outputTokens,
                row.cacheReadTokens,
                row.usdCost,
                row.billingMode.rawValue
            ])
        }
    }

    /// Returns aggregate per provider+model for the calendar month of `referenceDate`.
    func monthlyTotals(forMonth referenceDate: Date) async throws -> [ProviderSpendRow] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate))!
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!

        return try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT provider, model,
                       SUM(input_tokens) as input_tokens,
                       SUM(output_tokens) as output_tokens,
                       SUM(cache_read_tokens) as cache_read_tokens,
                       SUM(usd_cost) as usd_cost,
                       billing_mode
                FROM spend_ledger
                WHERE ts >= ? AND ts < ?
                GROUP BY provider, model
                ORDER BY usd_cost DESC
            """, arguments: [monthStart.timeIntervalSince1970, monthEnd.timeIntervalSince1970])

            return rows.map { row in
                ProviderSpendRow(
                    provider: row["provider"],
                    model: row["model"],
                    inputTokens: row["input_tokens"],
                    outputTokens: row["output_tokens"],
                    cacheReadTokens: row["cache_read_tokens"],
                    usdCost: row["usd_cost"],
                    billingMode: BillingMode(rawValue: row["billing_mode"]) ?? .api
                )
            }
        }
    }
}
