import Foundation
import SQLite3

final class QuotaStore {
    private var db: OpaquePointer?

    init(path: String = QuotaStore.defaultPath) throws {
        if path != ":memory:" {
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw QuotaStoreError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        try createTable()
    }

    deinit {
        sqlite3_close(db)
    }

    static var defaultPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ClaudeQuotaMenubar/quota.db").path
    }

    private func createTable() throws {
        let sql = """
            CREATE TABLE IF NOT EXISTS usage_samples (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                five_hour_util REAL,
                five_hour_resets_at TEXT,
                seven_day_util REAL,
                seven_day_resets_at TEXT,
                opus_util REAL,
                sonnet_util REAL
            );
            CREATE INDEX IF NOT EXISTS idx_timestamp ON usage_samples(timestamp);
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw QuotaStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func insert(_ sample: UsageSample) throws {
        let sql = """
            INSERT INTO usage_samples (timestamp, five_hour_util, five_hour_resets_at,
                seven_day_util, seven_day_resets_at, opus_util, sonnet_util)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw QuotaStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let iso = ISO8601DateFormatter()
        sqlite3_bind_text(stmt, 1, (iso.string(from: sample.timestamp) as NSString).utf8String, -1, nil)
        bindOptionalDouble(stmt, 2, sample.fiveHourUtil)
        bindOptionalText(stmt, 3, sample.fiveHourResetsAt)
        bindOptionalDouble(stmt, 4, sample.sevenDayUtil)
        bindOptionalText(stmt, 5, sample.sevenDayResetsAt)
        bindOptionalDouble(stmt, 6, sample.opusUtil)
        bindOptionalDouble(stmt, 7, sample.sonnetUtil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw QuotaStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func fetchLatest() throws -> UsageSample? {
        let sql = "SELECT * FROM usage_samples ORDER BY timestamp DESC LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw QuotaStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readRow(stmt)
    }

    func fetchSamples(since date: Date) throws -> [UsageSample] {
        let sql = "SELECT * FROM usage_samples WHERE timestamp >= ? ORDER BY timestamp ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw QuotaStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let iso = ISO8601DateFormatter()
        sqlite3_bind_text(stmt, 1, (iso.string(from: date) as NSString).utf8String, -1, nil)

        var results: [UsageSample] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(readRow(stmt))
        }
        return results
    }

    func fetchSampleClosestTo(date: Date) throws -> UsageSample? {
        let sql = """
            SELECT * FROM usage_samples
            ORDER BY ABS(julianday(timestamp) - julianday(?))
            LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw QuotaStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let iso = ISO8601DateFormatter()
        sqlite3_bind_text(stmt, 1, (iso.string(from: date) as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readRow(stmt)
    }

    @discardableResult
    func purgeOlderThan(days: Int) throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        let iso = ISO8601DateFormatter()
        let sql = "DELETE FROM usage_samples WHERE timestamp < ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw QuotaStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (iso.string(from: cutoff) as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw QuotaStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        return Int(sqlite3_changes(db))
    }

    // MARK: - Helpers

    private func readRow(_ stmt: OpaquePointer?) -> UsageSample {
        let iso = ISO8601DateFormatter()
        return UsageSample(
            id: sqlite3_column_int64(stmt, 0),
            timestamp: iso.date(from: readText(stmt, 1) ?? "") ?? Date(),
            fiveHourUtil: readOptionalDouble(stmt, 2),
            fiveHourResetsAt: readText(stmt, 3),
            sevenDayUtil: readOptionalDouble(stmt, 4),
            sevenDayResetsAt: readText(stmt, 5),
            opusUtil: readOptionalDouble(stmt, 6),
            sonnetUtil: readOptionalDouble(stmt, 7)
        )
    }

    private func readText(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: cStr)
    }

    private func readOptionalDouble(_ stmt: OpaquePointer?, _ col: Int32) -> Double? {
        if sqlite3_column_type(stmt, col) == SQLITE_NULL { return nil }
        return sqlite3_column_double(stmt, col)
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer?, _ idx: Int32, _ value: Double?) {
        if let v = value {
            sqlite3_bind_double(stmt, idx, v)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let v = value {
            sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }
}

enum QuotaStoreError: Error {
    case openFailed(String)
    case queryFailed(String)
}
