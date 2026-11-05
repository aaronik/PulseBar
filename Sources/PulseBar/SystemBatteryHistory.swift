import Foundation
import SQLite3

// PowerLog is an undocumented macOS implementation detail. Never create or modify
// its database, and treat all schema or permission failures as an ordinary fallback.
enum SystemBatteryHistory {
    static let databasePath = "/var/db/powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL"

    static func read(now: Date = Date(), path: String = databasePath) -> [BatteryPoint]? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 50)
        // The current macOS schema uses Unix timestamps and battery percent 0...100.
        let sql = """
            SELECT timestamp, Level, IsCharging
            FROM PLBatteryAgent_EventBackward_BatteryUI
            WHERE timestamp >= ? AND timestamp <= ? AND Level BETWEEN 0 AND 100
            ORDER BY timestamp DESC LIMIT 600
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, now.addingTimeInterval(-48 * 60 * 60).timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)

        var points: [BatteryPoint] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            if result != SQLITE_ROW { return nil }
            let timestamp = sqlite3_column_double(statement, 0)
            let level = sqlite3_column_double(statement, 1) / 100
            guard timestamp.isFinite, level.isFinite else { continue }
            let charging = sqlite3_column_int(statement, 2) != 0
            points.append(BatteryPoint(timestamp: Date(timeIntervalSince1970: timestamp),
                                       level: level, isCharging: charging,
                                       isPluggedIn: charging))
        }
        return points.reversed()
    }
}
