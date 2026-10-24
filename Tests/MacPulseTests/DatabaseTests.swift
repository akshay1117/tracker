import Testing
import Foundation
@testable import MacPulse

@Suite("Database & Persistence Tests")
struct DatabaseTests {
    
    private func createTestDB() -> (DatabaseManager, String) {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).db").path
        let db = DatabaseManager(databasePath: tempPath)
        return (db, tempPath)
    }
    
    @Test("Schema initialization and version migration")
    func testSchemaInit() {
        let (db, path) = createTestDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        let stats = db.fetchAggregateStats()
        #expect(stats.totalSessionsCount == 0)
        #expect(stats.lifetimeEnergyWh == 0.0)
        #expect(stats.lifetimeBytesDownloaded == 0)
    }
    
    @Test("Session lifecycle: insert, checkpoint, finalize")
    func testSessionLifecyclePersistence() {
        let (db, path) = createTestDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        let sessionID = UUID()
        let start = Date(timeIntervalSince1970: 1700000000)
        
        var session = UsageSession(
            id: sessionID,
            bootSessionUUID: "TEST-BOOT-UUID",
            startTime: start,
            endTime: nil,
            durationSeconds: 10.0,
            energyWh: 0.05,
            batteryEnergyWh: 0.0,
            bytesDownloaded: 1024,
            bytesUploaded: 512,
            endReason: .unknown,
            powerQuality: .high,
            detectionConfidence: .hardwareClamshell,
            lastCheckpointTime: start
        )
        
        db.insertSession(session)
        
        // Checkpoint update
        session.durationSeconds = 60.0
        session.energyWh = 0.25
        session.bytesDownloaded = 10_000
        session.lastCheckpointTime = start.addingTimeInterval(60)
        db.checkpointSession(session)
        
        // Finalize
        session.endTime = start.addingTimeInterval(60)
        session.endReason = .lidClosed
        db.finalizeSession(session)
        
        // Verify in DB
        let recents = db.fetchRecentSessions(limit: 10)
        #expect(recents.count == 1)
        let saved = recents.first!
        #expect(saved.id == sessionID)
        #expect(saved.endReason == .lidClosed)
        #expect(saved.durationSeconds == 60.0)
        #expect(saved.energyWh == 0.25)
        #expect(saved.bytesDownloaded == 10_000)
        
        // Verify aggregate statistics updated atomically
        let agg = db.fetchAggregateStats()
        #expect(agg.totalSessionsCount == 1)
        #expect(agg.lifetimeEnergyWh == 0.25)
        #expect(agg.lifetimeBytesDownloaded == 10_000)
        #expect(agg.lifetimeAwakeSeconds == 60.0)
    }
    
    @Test("Crash recovery reconciles incomplete sessions safely")
    func testCrashRecovery() {
        let (db, path) = createTestDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        let sessionID = UUID()
        let start = Date(timeIntervalSince1970: 1700000000)
        
        let session = UsageSession(
            id: sessionID,
            bootSessionUUID: "TEST-BOOT-UUID",
            startTime: start,
            endTime: nil, // Simulates an active session interrupted by a crash or power cut
            durationSeconds: 120.0,
            energyWh: 1.5,
            batteryEnergyWh: 0.0,
            bytesDownloaded: 50_000,
            bytesUploaded: 20_000,
            endReason: .unknown,
            powerQuality: .high,
            detectionConfidence: .hardwareClamshell,
            lastCheckpointTime: start.addingTimeInterval(120)
        )
        db.insertSession(session)
        
        // Reconcile
        let recoveredCount = db.reconcileIncompleteSessions()
        #expect(recoveredCount == 1)
        
        let recents = db.fetchRecentSessions(limit: 10)
        #expect(recents.count == 1)
        let recovered = recents.first!
        #expect(recovered.endReason == .crashRecovered)
        #expect(recovered.detectionConfidence == .recoveredCheckpoint)
        #expect(recovered.endTime != nil)
        
        // Verify aggregate stats took in the recovered session
        let agg = db.fetchAggregateStats()
        #expect(agg.totalSessionsCount == 1)
        #expect(agg.lifetimeEnergyWh == 1.5)
        #expect(agg.lifetimeBytesDownloaded == 50_000)
    }
    
    @Test("CSV and JSON Export formatting")
    func testDataExport() throws {
        let session = UsageSession(
            bootSessionUUID: "TEST-BOOT-UUID",
            startTime: Date(timeIntervalSince1970: 1700000000),
            endTime: Date(timeIntervalSince1970: 1700003600),
            durationSeconds: 3600.0,
            energyWh: 15.0,
            batteryEnergyWh: 0.0,
            bytesDownloaded: 1_000_000,
            bytesUploaded: 500_000,
            endReason: .lidClosed,
            powerQuality: .high,
            detectionConfidence: .hardwareClamshell
        )
        let stats = AggregateStats(
            lifetimeEnergyWh: 15.0,
            lifetimeBatteryEnergyWh: 0.0,
            lifetimeBytesDownloaded: 1_000_000,
            lifetimeBytesUploaded: 500_000,
            lifetimeAwakeSeconds: 3600.0,
            totalSessionsCount: 1
        )
        
        let csv = DataExporter.exportCSV(sessions: [session], aggregateStats: stats)
        #expect(csv.contains("SessionID,BootUUID,StartTime"))
        #expect(csv.contains("TEST-BOOT-UUID"))
        #expect(csv.contains("LidClosed"))
        
        let json = try DataExporter.exportJSON(sessions: [session], aggregateStats: stats)
        #expect(json.contains("TEST-BOOT-UUID"))
        #expect(json.contains("lifetimeEnergyWh"))
    }
    
    @Test("Reset all history wipes database cleanly")
    func testResetAllHistory() {
        let (db, path) = createTestDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        let session = UsageSession(
            bootSessionUUID: "TEST-BOOT-UUID",
            startTime: Date(),
            endTime: Date(),
            durationSeconds: 100.0,
            energyWh: 5.0,
            bytesDownloaded: 200,
            bytesUploaded: 100,
            endReason: .lidClosed
        )
        db.insertSession(session)
        db.finalizeSession(session)
        
        #expect(db.fetchRecentSessions().count == 1)
        #expect(db.fetchAggregateStats().totalSessionsCount == 1)
        
        db.resetAllHistory()
        
        #expect(db.fetchRecentSessions().isEmpty)
        let wipedStats = db.fetchAggregateStats()
        #expect(wipedStats.totalSessionsCount == 0)
        #expect(wipedStats.lifetimeEnergyWh == 0.0)
        #expect(wipedStats.lifetimeBytesDownloaded == 0)
    }
}
