import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func sqliteBindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
    _ = value.withCString { cString in
        sqlite3_bind_text(statement, index, cString, -1, sqliteTransient)
    }
}

struct ProviderSnapshotRow {
    let provider: Provider
    let displayName: String
    let costUSD: Double?
    let deltaDayUSD: Double?
    let rateLimit5h: Double?
    let rateLimit1w: Double?
    let capturedAt: Date?
}

enum DatabaseError: Error {
    case sqlite(message: String)
    case invalidPayload(String)
}

actor UsageDatabase {
    private let db: OpaquePointer

    init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var rawDB: OpaquePointer?
        if sqlite3_open(databaseURL.path, &rawDB) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(rawDB))
            sqlite3_close(rawDB)
            throw DatabaseError.sqlite(message: message)
        }

        guard let rawDB else {
            throw DatabaseError.sqlite(message: "Failed to open database")
        }

        db = rawDB

        try Self.exec(db: db, sql: "PRAGMA journal_mode=WAL;")
        try Self.exec(db: db, sql: "PRAGMA foreign_keys=ON;")
        try Self.migrate(db: db)
        try Self.seedProviders(db: db)
    }

    deinit {
        sqlite3_close(db)
    }

    private static func migrate(db: OpaquePointer) throws {
        try exec(
            db: db,
            sql:
            """
            CREATE TABLE IF NOT EXISTS provider_accounts (
              id TEXT PRIMARY KEY,
              provider TEXT NOT NULL UNIQUE,
              display_name TEXT NOT NULL,
              enabled INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            """
        )

        try exec(
            db: db,
            sql:
            """
            CREATE TABLE IF NOT EXISTS usage_snapshots (
              id TEXT PRIMARY KEY,
              provider TEXT NOT NULL,
              captured_at TEXT NOT NULL,
              cost_usd REAL NOT NULL,
              delta_day_usd REAL NOT NULL,
              rate_limit_5h REAL,
              rate_limit_1w REAL,
              parser_version TEXT NOT NULL,
              source_url TEXT NOT NULL,
              raw_json TEXT NOT NULL,
              created_at TEXT NOT NULL
            );
            """
        )

        try exec(
            db: db,
            sql:
            """
            CREATE TABLE IF NOT EXISTS sync_runs (
              id TEXT PRIMARY KEY,
              started_at TEXT NOT NULL,
              finished_at TEXT NOT NULL,
              status TEXT NOT NULL,
              error_code TEXT,
              error_message TEXT
            );
            """
        )
    }

    private static func seedProviders(db: OpaquePointer) throws {
        let now = ISO8601DateFormatter.defaultFormatter.string(from: Date())
        for provider in Provider.allCases where provider != .antigravity {
            let sql =
                "INSERT OR IGNORE INTO provider_accounts (id, provider, display_name, enabled, created_at, updated_at) VALUES (?, ?, ?, 1, ?, ?);"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.sqlite(message: String(cString: sqlite3_errmsg(db)))
            }

            guard let statement else {
                throw DatabaseError.sqlite(message: "Failed to prepare seed statement")
            }
            defer { sqlite3_finalize(statement) }

            sqliteBindText(statement, 1, UUID().uuidString)
            sqliteBindText(statement, 2, provider.rawValue)
            sqliteBindText(statement, 3, provider.displayName)
            sqliteBindText(statement, 4, now)
            sqliteBindText(statement, 5, now)

            if sqlite3_step(statement) != SQLITE_DONE {
                throw DatabaseError.sqlite(message: String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    @discardableResult
    func insertUsageSnapshot(message: NativeMessageV1, rawJSON: String) throws -> String {
        guard
            message.type == "usage_snapshot",
            let provider = message.provider,
            let capturedAt = message.capturedAt,
            let metrics = message.metrics,
            let parserVersion = message.parserVersion,
            let sourceURL = message.sourceURL
        else {
            throw DatabaseError.invalidPayload("usage_snapshot payload is incomplete")
        }

        guard provider.matchesUsageURL(sourceURL) else {
            throw DatabaseError.invalidPayload("source_url does not match provider usage URL: \(sourceURL.absoluteString)")
        }

        let id = UUID().uuidString
        let now = ISO8601DateFormatter.defaultFormatter.string(from: Date())

        let insertSQL =
            """
            INSERT INTO usage_snapshots (
              id, provider, captured_at, cost_usd, delta_day_usd,
              rate_limit_5h, rate_limit_1w,
              parser_version, source_url, raw_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        let statement = try prepare(insertSQL)
        defer { sqlite3_finalize(statement) }

        sqliteBindText(statement, 1, id)
        sqliteBindText(statement, 2, provider.rawValue)
        sqliteBindText(statement, 3, ISO8601DateFormatter.defaultFormatter.string(from: capturedAt))
        sqlite3_bind_double(statement, 4, metrics.costUSD)
        sqlite3_bind_double(statement, 5, metrics.deltaDayUSD)

        if let rate5h = metrics.rateLimit5h {
            sqlite3_bind_double(statement, 6, rate5h)
        } else {
            sqlite3_bind_null(statement, 6)
        }

        if let rate1w = metrics.rateLimit1w {
            sqlite3_bind_double(statement, 7, rate1w)
        } else {
            sqlite3_bind_null(statement, 7)
        }

        sqliteBindText(statement, 8, parserVersion)
        sqliteBindText(statement, 9, sourceURL.absoluteString)
        sqliteBindText(statement, 10, rawJSON)
        sqliteBindText(statement, 11, now)

        if sqlite3_step(statement) != SQLITE_DONE {
            throw DatabaseError.sqlite(message: String(cString: sqlite3_errmsg(db)))
        }

        try insertSyncRun(
            status: "success",
            errorCode: nil,
            errorMessage: nil
        )

        return id
    }

    func insertSyncRun(status: String, errorCode: SyncErrorCode?, errorMessage: String?) throws {
        let now = ISO8601DateFormatter.defaultFormatter.string(from: Date())
        let statement = try prepare(
            "INSERT INTO sync_runs (id, started_at, finished_at, status, error_code, error_message) VALUES (?, ?, ?, ?, ?, ?);"
        )
        defer { sqlite3_finalize(statement) }

        sqliteBindText(statement, 1, UUID().uuidString)
        sqliteBindText(statement, 2, now)
        sqliteBindText(statement, 3, now)
        sqliteBindText(statement, 4, status)

        if let errorCode {
            sqliteBindText(statement, 5, errorCode.rawValue)
        } else {
            sqlite3_bind_null(statement, 5)
        }

        if let errorMessage {
            sqliteBindText(statement, 6, errorMessage)
        } else {
            sqlite3_bind_null(statement, 6)
        }

        if sqlite3_step(statement) != SQLITE_DONE {
            throw DatabaseError.sqlite(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    func fetchLatestRows() throws -> [ProviderSnapshotRow] {
        let sql =
            """
            SELECT p.provider,
                   p.display_name,
                   s.cost_usd,
                   s.delta_day_usd,
                   s.rate_limit_5h,
                   s.rate_limit_1w,
                   s.captured_at
            FROM provider_accounts p
            LEFT JOIN usage_snapshots s
              ON s.id = (
                SELECT us.id
                FROM usage_snapshots us
                WHERE us.provider = p.provider
                ORDER BY us.captured_at DESC
                LIMIT 1
              )
            WHERE p.enabled = 1
            ORDER BY p.provider ASC;
            """

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var rows: [ProviderSnapshotRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let providerCString = sqlite3_column_text(statement, 0),
                let displayNameCString = sqlite3_column_text(statement, 1),
                let provider = Provider(rawValue: String(cString: providerCString))
            else {
                continue
            }

            let displayName = String(cString: displayNameCString)
            let costUSD = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 2)
            let deltaDayUSD = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3)
            let rateLimit5h = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 4)
            let rateLimit1w = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 5)

            var capturedAt: Date?
            if let capturedCString = sqlite3_column_text(statement, 6) {
                let value = String(cString: capturedCString)
                capturedAt = ISO8601DateFormatter.withFractional.date(from: value)
                    ?? ISO8601DateFormatter.defaultFormatter.date(from: value)
            }

            rows.append(
                ProviderSnapshotRow(
                    provider: provider,
                    displayName: displayName,
                    costUSD: costUSD,
                    deltaDayUSD: deltaDayUSD,
                    rateLimit5h: rateLimit5h,
                    rateLimit1w: rateLimit1w,
                    capturedAt: capturedAt
                )
            )
        }

        return rows
    }

    private static func exec(db: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(errorMessage)
            throw DatabaseError.sqlite(message: message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw DatabaseError.sqlite(message: String(cString: sqlite3_errmsg(db)))
        }

        guard let statement else {
            throw DatabaseError.sqlite(message: "Failed to prepare statement")
        }
        return statement
    }
}
