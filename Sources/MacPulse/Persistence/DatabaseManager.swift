import Foundation
import SQLite3

/// Thread-safe SQLite persistence manager for MacPulse.
public final class DatabaseManager: @unchecked Sendable {
    public static let currentSchemaVersion: Int32 = 2
    
    private let dbQueue = DispatchQueue(label: "com.macpulse.database", qos: .utility)
    private var db: OpaquePointer?
    private let databasePath: String
    
    public init(databasePath: String? = nil) {
        if let path = databasePath {
            self.databasePath = path
        } else {
            let fallbackUrl = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fallbackUrl
            let appDir = appSupport.appendingPathComponent("MacPulse", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            self.databasePath = appDir.appendingPathComponent("macpulse.db").path
        }
        
        openAndMigrate()
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Connection & Migrations
    
    private func openAndMigrate() {
        dbQueue.sync {
            if sqlite3_open(databasePath, &db) != SQLITE_OK {
                print("MacPulse: Failed to open SQLite database at \(databasePath)")
                return
            }
            
            // Enable WAL mode for high concurrency & low write overhead
            execRaw("PRAGMA journal_mode = WAL;")
            execRaw("PRAGMA synchronous = NORMAL;")
            
            let currentVersion = getSchemaVersion()
            if currentVersion < Self.currentSchemaVersion {
                migrate(from: currentVersion, to: Self.currentSchemaVersion)
            }
            syncAggregateStatsWithCompletedSessionsInternal()
        }
    }
    
    private func getSchemaVersion() -> Int32 {
        var version: Int32 = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                version = sqlite3_column_int(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)
        return version
    }
    
    private func setSchemaVersion(_ version: Int32) {
        execRaw("PRAGMA user_version = \(version);")
    }
    
    private func migrate(from oldVersion: Int32, to newVersion: Int32) {
        execRaw("BEGIN TRANSACTION;")
        
        if oldVersion < 1 {
            // Initial schema
            execRaw("""
            CREATE TABLE IF NOT EXISTS app_metadata (
                key TEXT PRIMARY KEY,
                value TEXT,
                updated_at REAL
            );
            
            CREATE TABLE IF NOT EXISTS boot_records (
                boot_uuid TEXT PRIMARY KEY,
                boot_timestamp REAL,
                first_seen REAL,
                last_seen REAL
            );
            
            CREATE TABLE IF NOT EXISTS usage_sessions (
                id TEXT PRIMARY KEY,
                boot_uuid TEXT NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL,
                duration_seconds REAL NOT NULL,
                energy_wh REAL NOT NULL,
                battery_energy_wh REAL NOT NULL,
                bytes_down INTEGER NOT NULL,
                bytes_up INTEGER NOT NULL,
                end_reason TEXT NOT NULL,
                power_quality TEXT NOT NULL,
                detection_confidence TEXT NOT NULL,
                last_checkpoint_time REAL NOT NULL
            );
            
            CREATE INDEX IF NOT EXISTS idx_sessions_start_time ON usage_sessions(start_time);
            CREATE INDEX IF NOT EXISTS idx_sessions_boot_uuid ON usage_sessions(boot_uuid);
            
            CREATE TABLE IF NOT EXISTS aggregate_stats (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                lifetime_energy_wh REAL NOT NULL,
                lifetime_battery_wh REAL NOT NULL,
                lifetime_bytes_down INTEGER NOT NULL,
                lifetime_bytes_up INTEGER NOT NULL,
                lifetime_awake_seconds REAL NOT NULL,
                total_sessions_count INTEGER NOT NULL
            );
            
            INSERT OR IGNORE INTO aggregate_stats (id, lifetime_energy_wh, lifetime_battery_wh, lifetime_bytes_down, lifetime_bytes_up, lifetime_awake_seconds, total_sessions_count)
            VALUES (1, 0.0, 0.0, 0, 0, 0.0, 0);
            
            CREATE TABLE IF NOT EXISTS power_samples (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT,
                timestamp REAL,
                watts REAL,
                source TEXT
            );
            
            CREATE TABLE IF NOT EXISTS network_samples (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT,
                timestamp REAL,
                down_bps REAL,
                up_bps REAL,
                iface TEXT
            );
            """)
        }
        
        if oldVersion < 2 {
            // Version 2: Per-application tracking for Screen-on time, Energy use, and Data usage
            execRaw("""
            CREATE TABLE IF NOT EXISTS app_usage_records (
                session_id TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                app_name TEXT NOT NULL,
                screen_on_seconds REAL NOT NULL,
                cpu_time_seconds REAL NOT NULL,
                energy_wh REAL NOT NULL,
                energy_impact REAL NOT NULL,
                bytes_down INTEGER NOT NULL,
                bytes_up INTEGER NOT NULL,
                last_updated REAL NOT NULL,
                PRIMARY KEY (session_id, bundle_id)
            );
            
            CREATE INDEX IF NOT EXISTS idx_app_usage_session ON app_usage_records(session_id);
            CREATE INDEX IF NOT EXISTS idx_app_usage_bundle ON app_usage_records(bundle_id);
            
            CREATE TABLE IF NOT EXISTS lifetime_app_usage (
                bundle_id TEXT PRIMARY KEY,
                app_name TEXT NOT NULL,
                total_screen_on_seconds REAL NOT NULL,
                total_cpu_time_seconds REAL NOT NULL,
                total_energy_wh REAL NOT NULL,
                total_bytes_down INTEGER NOT NULL,
                total_bytes_up INTEGER NOT NULL,
                last_seen REAL NOT NULL
            );
            """)
        }
        
        setSchemaVersion(newVersion)
        execRaw("COMMIT;")
    }
    
    @discardableResult
    private func execRaw(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            if let err = err {
                print("SQLite error: \(String(cString: err))")
                sqlite3_free(err)
            }
            return false
        }
        return true
    }
    
    // MARK: - Boot Records
    
    public func recordBoot(uuid: String, bootTimestamp: Date) {
        dbQueue.sync {
            let sql = """
            INSERT INTO boot_records (boot_uuid, boot_timestamp, first_seen, last_seen)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(boot_uuid) DO UPDATE SET last_seen = ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                let now = Date().timeIntervalSince1970
                sqlite3_bind_text(stmt, 1, (uuid as NSString).utf8String, -1, nil)
                sqlite3_bind_double(stmt, 2, bootTimestamp.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 3, now)
                sqlite3_bind_double(stmt, 4, now)
                sqlite3_bind_double(stmt, 5, now)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    // MARK: - Sessions & Checkpoints
    
    public func insertSession(_ session: UsageSession) {
        dbQueue.sync {
            let sql = """
            INSERT INTO usage_sessions (
                id, boot_uuid, start_time, end_time, duration_seconds,
                energy_wh, battery_energy_wh, bytes_down, bytes_up,
                end_reason, power_quality, detection_confidence, last_checkpoint_time
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindSession(session, to: stmt)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    public func checkpointSession(_ session: UsageSession) {
        dbQueue.sync {
            let sql = """
            UPDATE usage_sessions SET
                duration_seconds = ?,
                energy_wh = ?,
                battery_energy_wh = ?,
                bytes_down = ?,
                bytes_up = ?,
                last_checkpoint_time = ?
            WHERE id = ? AND end_time IS NULL;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, session.durationSeconds)
                sqlite3_bind_double(stmt, 2, session.energyWh)
                sqlite3_bind_double(stmt, 3, session.batteryEnergyWh)
                sqlite3_bind_int64(stmt, 4, session.bytesDownloaded)
                sqlite3_bind_int64(stmt, 5, session.bytesUploaded)
                sqlite3_bind_double(stmt, 6, session.lastCheckpointTime.timeIntervalSince1970)
                sqlite3_bind_text(stmt, 7, (session.id.uuidString as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    public func finalizeSession(_ session: UsageSession) {
        dbQueue.sync {
            execRaw("BEGIN TRANSACTION;")
            
            // 1. Update session row
            let updateSql = """
            UPDATE usage_sessions SET
                end_time = ?,
                duration_seconds = ?,
                energy_wh = ?,
                battery_energy_wh = ?,
                bytes_down = ?,
                bytes_up = ?,
                end_reason = ?,
                power_quality = ?,
                detection_confidence = ?,
                last_checkpoint_time = ?
            WHERE id = ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, updateSql, -1, &stmt, nil) == SQLITE_OK {
                let endTimestamp = (session.endTime ?? Date()).timeIntervalSince1970
                sqlite3_bind_double(stmt, 1, endTimestamp)
                sqlite3_bind_double(stmt, 2, session.durationSeconds)
                sqlite3_bind_double(stmt, 3, session.energyWh)
                sqlite3_bind_double(stmt, 4, session.batteryEnergyWh)
                sqlite3_bind_int64(stmt, 5, session.bytesDownloaded)
                sqlite3_bind_int64(stmt, 6, session.bytesUploaded)
                sqlite3_bind_text(stmt, 7, (session.endReason.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 8, (session.powerQuality.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 9, (session.detectionConfidence.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_double(stmt, 10, session.lastCheckpointTime.timeIntervalSince1970)
                sqlite3_bind_text(stmt, 11, (session.id.uuidString as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            
            // 2. Increment lifetime aggregate totals atomically
            let aggSql = """
            UPDATE aggregate_stats SET
                lifetime_energy_wh = lifetime_energy_wh + ?,
                lifetime_battery_wh = lifetime_battery_wh + ?,
                lifetime_bytes_down = lifetime_bytes_down + ?,
                lifetime_bytes_up = lifetime_bytes_up + ?,
                lifetime_awake_seconds = lifetime_awake_seconds + ?,
                total_sessions_count = total_sessions_count + 1
            WHERE id = 1;
            """
            var aggStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, aggSql, -1, &aggStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(aggStmt, 1, session.energyWh)
                sqlite3_bind_double(aggStmt, 2, session.batteryEnergyWh)
                sqlite3_bind_int64(aggStmt, 3, session.bytesDownloaded)
                sqlite3_bind_int64(aggStmt, 4, session.bytesUploaded)
                sqlite3_bind_double(aggStmt, 5, session.durationSeconds)
                sqlite3_step(aggStmt)
            }
            sqlite3_finalize(aggStmt)
            
            execRaw("COMMIT;")
        }
    }
    
    // MARK: - Crash Recovery
    
    /// Reconciles any unfinished session left open by an abnormal app exit or crash.
    /// Closes it safely using the last checkpointed stats without duplicating counts.
    public func reconcileIncompleteSessions() -> Int {
        dbQueue.sync {
            var incompleteSessions: [UsageSession] = []
            let selectSql = "SELECT * FROM usage_sessions WHERE end_time IS NULL;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selectSql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let session = parseSessionRow(stmt) {
                        incompleteSessions.append(session)
                    }
                }
            }
            sqlite3_finalize(stmt)
            
            for var session in incompleteSessions {
                session.endTime = session.lastCheckpointTime
                session.endReason = .crashRecovered
                session.detectionConfidence = .recoveredCheckpoint
                finalizeSessionInternal(session)
            }
            
            return incompleteSessions.count
        }
    }
    
    private func finalizeSessionInternal(_ session: UsageSession) {
        execRaw("BEGIN TRANSACTION;")
        let updateSql = """
        UPDATE usage_sessions SET
            end_time = ?,
            end_reason = ?,
            detection_confidence = ?
        WHERE id = ?;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSql, -1, &stmt, nil) == SQLITE_OK {
            let endTimestamp = (session.endTime ?? session.lastCheckpointTime).timeIntervalSince1970
            sqlite3_bind_double(stmt, 1, endTimestamp)
            sqlite3_bind_text(stmt, 2, (session.endReason.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (session.detectionConfidence.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (session.id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        // Add to aggregate totals
        let aggSql = """
        UPDATE aggregate_stats SET
            lifetime_energy_wh = lifetime_energy_wh + ?,
            lifetime_battery_wh = lifetime_battery_wh + ?,
            lifetime_bytes_down = lifetime_bytes_down + ?,
            lifetime_bytes_up = lifetime_bytes_up + ?,
            lifetime_awake_seconds = lifetime_awake_seconds + ?,
            total_sessions_count = total_sessions_count + 1
        WHERE id = 1;
        """
        var aggStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, aggSql, -1, &aggStmt, nil) == SQLITE_OK {
            sqlite3_bind_double(aggStmt, 1, session.energyWh)
            sqlite3_bind_double(aggStmt, 2, session.batteryEnergyWh)
            sqlite3_bind_int64(aggStmt, 3, session.bytesDownloaded)
            sqlite3_bind_int64(aggStmt, 4, session.bytesUploaded)
            sqlite3_bind_double(aggStmt, 5, session.durationSeconds)
            sqlite3_step(aggStmt)
        }
        sqlite3_finalize(aggStmt)
        
        execRaw("COMMIT;")
    }
    
    // MARK: - Queries
    
    public func fetchAggregateStats() -> AggregateStats {
        dbQueue.sync {
            var stats = AggregateStats()
            let sql = "SELECT lifetime_energy_wh, lifetime_battery_wh, lifetime_bytes_down, lifetime_bytes_up, lifetime_awake_seconds, total_sessions_count FROM aggregate_stats WHERE id = 1;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    stats.lifetimeEnergyWh = sqlite3_column_double(stmt, 0)
                    stats.lifetimeBatteryEnergyWh = sqlite3_column_double(stmt, 1)
                    stats.lifetimeBytesDownloaded = sqlite3_column_int64(stmt, 2)
                    stats.lifetimeBytesUploaded = sqlite3_column_int64(stmt, 3)
                    stats.lifetimeAwakeSeconds = sqlite3_column_double(stmt, 4)
                    stats.totalSessionsCount = Int(sqlite3_column_int(stmt, 5))
                }
            }
            sqlite3_finalize(stmt)
            return stats
        }
    }
    /// Ensures aggregate_stats table accurately reflects the sum of all completed sessions
    /// in case of un-reconciled crashes or legacy migrations.
    public func syncAggregateStatsWithCompletedSessions() {
        dbQueue.sync {
            syncAggregateStatsWithCompletedSessionsInternal()
        }
    }
    
    private func syncAggregateStatsWithCompletedSessionsInternal() {
        let countSql = "SELECT COUNT(*) FROM usage_sessions WHERE end_time IS NOT NULL;"
        var countStmt: OpaquePointer?
        var completedCount = 0
        if sqlite3_prepare_v2(db, countSql, -1, &countStmt, nil) == SQLITE_OK {
            if sqlite3_step(countStmt) == SQLITE_ROW {
                completedCount = Int(sqlite3_column_int(countStmt, 0))
            }
        }
        sqlite3_finalize(countStmt)
        
        guard completedCount > 0 else { return }
        
        let checkAggSql = "SELECT total_sessions_count FROM aggregate_stats WHERE id = 1;"
        var checkStmt: OpaquePointer?
        var aggCount = 0
        if sqlite3_prepare_v2(db, checkAggSql, -1, &checkStmt, nil) == SQLITE_OK {
            if sqlite3_step(checkStmt) == SQLITE_ROW {
                aggCount = Int(sqlite3_column_int(checkStmt, 0))
            }
        }
        sqlite3_finalize(checkStmt)
        
        if aggCount == 0 && completedCount > 0 {
            let sumSql = """
            SELECT 
                COALESCE(SUM(energy_wh), 0.0),
                COALESCE(SUM(battery_energy_wh), 0.0),
                COALESCE(SUM(bytes_down), 0),
                COALESCE(SUM(bytes_up), 0),
                COALESCE(SUM(duration_seconds), 0.0)
            FROM usage_sessions
            WHERE end_time IS NOT NULL;
            """
            var sumStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sumSql, -1, &sumStmt, nil) == SQLITE_OK {
                if sqlite3_step(sumStmt) == SQLITE_ROW {
                    let energy = sqlite3_column_double(sumStmt, 0)
                    let battEnergy = sqlite3_column_double(sumStmt, 1)
                    let bytesDown = sqlite3_column_int64(sumStmt, 2)
                    let bytesUp = sqlite3_column_int64(sumStmt, 3)
                    let duration = sqlite3_column_double(sumStmt, 4)
                    
                    let updateSql = """
                    UPDATE aggregate_stats SET
                        lifetime_energy_wh = ?,
                        lifetime_battery_wh = ?,
                        lifetime_bytes_down = ?,
                        lifetime_bytes_up = ?,
                        lifetime_awake_seconds = ?,
                        total_sessions_count = ?
                    WHERE id = 1;
                    """
                    var uStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, updateSql, -1, &uStmt, nil) == SQLITE_OK {
                        sqlite3_bind_double(uStmt, 1, energy)
                        sqlite3_bind_double(uStmt, 2, battEnergy)
                        sqlite3_bind_int64(uStmt, 3, bytesDown)
                        sqlite3_bind_int64(uStmt, 4, bytesUp)
                        sqlite3_bind_double(uStmt, 5, duration)
                        sqlite3_bind_int(uStmt, 6, Int32(completedCount))
                        sqlite3_step(uStmt)
                    }
                    sqlite3_finalize(uStmt)
                }
            }
            sqlite3_finalize(sumStmt)
        }
    }
    
    public func fetchRecentSessions(limit: Int = 50, offset: Int = 0) -> [UsageSession] {
        dbQueue.sync {
            var sessions: [UsageSession] = []
            let sql = """
            SELECT * FROM usage_sessions
            ORDER BY start_time DESC
            LIMIT ? OFFSET ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(limit))
                sqlite3_bind_int(stmt, 2, Int32(offset))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let session = parseSessionRow(stmt) {
                        sessions.append(session)
                    }
                }
            }
            sqlite3_finalize(stmt)
            return sessions
        }
    }
    
    public func fetchSessionsSince(date: Date) -> [UsageSession] {
        dbQueue.sync {
            var sessions: [UsageSession] = []
            let sql = """
            SELECT * FROM usage_sessions
            WHERE start_time >= ?
            ORDER BY start_time ASC;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let session = parseSessionRow(stmt) {
                        sessions.append(session)
                    }
                }
            }
            sqlite3_finalize(stmt)
            return sessions
        }
    }
    
    // MARK: - Maintenance & Reset
    
    public func resetAllHistory() {
        dbQueue.sync {
            execRaw("BEGIN TRANSACTION;")
            execRaw("DELETE FROM usage_sessions;")
            execRaw("DELETE FROM boot_records;")
            execRaw("DELETE FROM power_samples;")
            execRaw("DELETE FROM network_samples;")
            execRaw("DELETE FROM app_usage_records;")
            execRaw("DELETE FROM lifetime_app_usage;")
            execRaw("""
            UPDATE aggregate_stats SET
                lifetime_energy_wh = 0.0,
                lifetime_battery_wh = 0.0,
                lifetime_bytes_down = 0,
                lifetime_bytes_up = 0,
                lifetime_awake_seconds = 0.0,
                total_sessions_count = 0
            WHERE id = 1;
            """)
            execRaw("COMMIT;")
            execRaw("VACUUM;")
        }
    }
    
    // MARK: - App Usage Persistence
    
    public func saveAppUsageRecords(sessionId: UUID, records: [AppUsageRecord]) {
        guard !records.isEmpty else { return }
        dbQueue.sync {
            execRaw("BEGIN TRANSACTION;")
            
            let sessionSql = """
            INSERT INTO app_usage_records (
                session_id, bundle_id, app_name, screen_on_seconds, cpu_time_seconds,
                energy_wh, energy_impact, bytes_down, bytes_up, last_updated
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id, bundle_id) DO UPDATE SET
                app_name = excluded.app_name,
                screen_on_seconds = excluded.screen_on_seconds,
                cpu_time_seconds = excluded.cpu_time_seconds,
                energy_wh = excluded.energy_wh,
                energy_impact = excluded.energy_impact,
                bytes_down = excluded.bytes_down,
                bytes_up = excluded.bytes_up,
                last_updated = excluded.last_updated;
            """
            
            var sStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sessionSql, -1, &sStmt, nil) == SQLITE_OK {
                for r in records {
                    sqlite3_bind_text(sStmt, 1, (sessionId.uuidString as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(sStmt, 2, (r.bundleIdentifier as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(sStmt, 3, (r.appName as NSString).utf8String, -1, nil)
                    sqlite3_bind_double(sStmt, 4, r.screenOnTimeSeconds)
                    sqlite3_bind_double(sStmt, 5, r.cpuTimeSeconds)
                    sqlite3_bind_double(sStmt, 6, r.energyWh)
                    sqlite3_bind_double(sStmt, 7, r.energyImpact)
                    sqlite3_bind_int64(sStmt, 8, r.bytesDownloaded)
                    sqlite3_bind_int64(sStmt, 9, r.bytesUploaded)
                    sqlite3_bind_double(sStmt, 10, r.lastUpdated.timeIntervalSince1970)
                    
                    sqlite3_step(sStmt)
                    sqlite3_reset(sStmt)
                }
            }
            sqlite3_finalize(sStmt)
            
            execRaw("COMMIT;")
        }
    }
    
    public func fetchAppUsage(sessionId: UUID) -> [AppUsageRecord] {
        dbQueue.sync {
            var records: [AppUsageRecord] = []
            let sql = """
            SELECT bundle_id, app_name, screen_on_seconds, cpu_time_seconds,
                   energy_wh, energy_impact, bytes_down, bytes_up, last_updated
            FROM app_usage_records
            WHERE session_id = ?
            ORDER BY screen_on_seconds DESC;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (sessionId.uuidString as NSString).utf8String, -1, nil)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let bId = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                    let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? bId
                    let screenOn = sqlite3_column_double(stmt, 2)
                    let cpuSec = sqlite3_column_double(stmt, 3)
                    let energy = sqlite3_column_double(stmt, 4)
                    let impact = sqlite3_column_double(stmt, 5)
                    let down = sqlite3_column_int64(stmt, 6)
                    let up = sqlite3_column_int64(stmt, 7)
                    let updated = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
                    
                    records.append(AppUsageRecord(
                        bundleIdentifier: bId,
                        appName: name,
                        screenOnTimeSeconds: screenOn,
                        cpuTimeSeconds: cpuSec,
                        energyWh: energy,
                        energyImpact: impact,
                        bytesDownloaded: down,
                        bytesUploaded: up,
                        isFrontmost: false,
                        lastUpdated: updated
                    ))
                }
            }
            sqlite3_finalize(stmt)
            return records
        }
    }
    
    public func fetchLifetimeAppUsage(excludingSessionId: UUID? = nil) -> [AppUsageRecord] {
        dbQueue.sync {
            var records: [AppUsageRecord] = []
            let whereClause = excludingSessionId != nil ? "WHERE session_id != ?" : ""
            let sql = """
            SELECT bundle_id, app_name,
                   SUM(screen_on_seconds) as total_screen_on,
                   SUM(cpu_time_seconds) as total_cpu,
                   SUM(energy_wh) as total_energy,
                   MAX(energy_impact) as max_impact,
                   SUM(bytes_down) as total_down,
                   SUM(bytes_up) as total_up,
                   MAX(last_updated) as latest_update
            FROM app_usage_records
            \(whereClause)
            GROUP BY bundle_id
            ORDER BY total_screen_on DESC;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if let exId = excludingSessionId {
                    sqlite3_bind_text(stmt, 1, (exId.uuidString as NSString).utf8String, -1, nil)
                }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let bId = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                    let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? bId
                    let screenOn = sqlite3_column_double(stmt, 2)
                    let cpuSec = sqlite3_column_double(stmt, 3)
                    let energy = sqlite3_column_double(stmt, 4)
                    let impact = sqlite3_column_double(stmt, 5)
                    let down = sqlite3_column_int64(stmt, 6)
                    let up = sqlite3_column_int64(stmt, 7)
                    let updated = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
                    
                    records.append(AppUsageRecord(
                        bundleIdentifier: bId,
                        appName: name,
                        screenOnTimeSeconds: screenOn,
                        cpuTimeSeconds: cpuSec,
                        energyWh: energy,
                        energyImpact: impact,
                        bytesDownloaded: down,
                        bytesUploaded: up,
                        isFrontmost: false,
                        lastUpdated: updated
                    ))
                }
            }
            sqlite3_finalize(stmt)
            return records
        }
    }
    
    // MARK: - Row Helpers
    
    private func bindSession(_ session: UsageSession, to stmt: OpaquePointer?) {
        sqlite3_bind_text(stmt, 1, (session.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (session.bootSessionUUID as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 3, session.startTime.timeIntervalSince1970)
        if let end = session.endTime {
            sqlite3_bind_double(stmt, 4, end.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_double(stmt, 5, session.durationSeconds)
        sqlite3_bind_double(stmt, 6, session.energyWh)
        sqlite3_bind_double(stmt, 7, session.batteryEnergyWh)
        sqlite3_bind_int64(stmt, 8, session.bytesDownloaded)
        sqlite3_bind_int64(stmt, 9, session.bytesUploaded)
        sqlite3_bind_text(stmt, 10, (session.endReason.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 11, (session.powerQuality.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 12, (session.detectionConfidence.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 13, session.lastCheckpointTime.timeIntervalSince1970)
    }
    
    private func parseSessionRow(_ stmt: OpaquePointer?) -> UsageSession? {
        guard let idText = sqlite3_column_text(stmt, 0),
              let uuid = UUID(uuidString: String(cString: idText)),
              let bootText = sqlite3_column_text(stmt, 1) else {
            return nil
        }
        let bootUUID = String(cString: bootText)
        let startTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
        
        var endTime: Date? = nil
        if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
            endTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        }
        
        let duration = sqlite3_column_double(stmt, 4)
        let energyWh = sqlite3_column_double(stmt, 5)
        let batteryWh = sqlite3_column_double(stmt, 6)
        let bytesDown = sqlite3_column_int64(stmt, 7)
        let bytesUp = sqlite3_column_int64(stmt, 8)
        
        let reasonStr = sqlite3_column_text(stmt, 9).map { String(cString: $0) } ?? ""
        let reason = SessionEndReason(rawValue: reasonStr) ?? .unknown
        
        let qualityStr = sqlite3_column_text(stmt, 10).map { String(cString: $0) } ?? ""
        let quality = PowerQuality(rawValue: qualityStr) ?? .moderate
        
        let confStr = sqlite3_column_text(stmt, 11).map { String(cString: $0) } ?? ""
        let confidence = SessionDetectionConfidence(rawValue: confStr) ?? .fallbackHeuristic
        
        let checkpoint = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 12))
        
        return UsageSession(
            id: uuid,
            bootSessionUUID: bootUUID,
            startTime: startTime,
            endTime: endTime,
            durationSeconds: duration,
            energyWh: energyWh,
            batteryEnergyWh: batteryWh,
            bytesDownloaded: bytesDown,
            bytesUploaded: bytesUp,
            endReason: reason,
            powerQuality: quality,
            detectionConfidence: confidence,
            lastCheckpointTime: checkpoint
        )
    }
}
