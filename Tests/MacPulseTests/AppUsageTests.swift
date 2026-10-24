import Testing
import Foundation
@testable import MacPulse

@Suite("App Usage Tracking & Persistence Tests")
struct AppUsageTests {
    
    private func createTestDB() -> (DatabaseManager, String) {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-app-usage-\(UUID().uuidString).db").path
        let db = DatabaseManager(databasePath: tempPath)
        return (db, tempPath)
    }
    
    @Test("AppUsageRecord formatting and computed metrics")
    func testAppUsageModelFormatting() {
        let record = AppUsageRecord(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            screenOnTimeSeconds: 3665, // 1h 1m 5s
            cpuTimeSeconds: 120.5,
            energyWh: 1.452,
            energyImpact: 14.8,
            bytesDownloaded: 104_857_600, // 100 MB
            bytesUploaded: 5_242_880,     // 5 MB
            isFrontmost: true
        )
        
        #expect(record.bundleIdentifier == "com.apple.Safari")
        #expect(record.appName == "Safari")
        #expect(record.isFrontmost == true)
        #expect(record.totalCombinedBytes == 110_100_480)
        #expect(record.formattedScreenOnTime.contains("1 hr"))
        #expect(record.formattedEnergy.contains("1.45 Wh"))
        #expect(record.formattedDataUsage.contains("105 MB"))
    }
    
    @Test("App usage persistence and session query")
    func testAppUsagePersistence() {
        let (db, path) = createTestDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        let sessionId = UUID()
        let app1 = AppUsageRecord(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            screenOnTimeSeconds: 120,
            cpuTimeSeconds: 15.0,
            energyWh: 0.15,
            energyImpact: 8.5,
            bytesDownloaded: 50_000,
            bytesUploaded: 10_000
        )
        let app2 = AppUsageRecord(
            bundleIdentifier: "com.apple.Terminal",
            appName: "Terminal",
            screenOnTimeSeconds: 45,
            cpuTimeSeconds: 4.0,
            energyWh: 0.04,
            energyImpact: 2.1,
            bytesDownloaded: 2_000,
            bytesUploaded: 1_000
        )
        
        db.saveAppUsageRecords(sessionId: sessionId, records: [app1, app2])
        
        let fetched = db.fetchAppUsage(sessionId: sessionId)
        #expect(fetched.count == 2)
        
        let safari = fetched.first(where: { $0.bundleIdentifier == "com.apple.Safari" })
        #expect(safari != nil)
        #expect(safari?.screenOnTimeSeconds == 120)
        #expect(safari?.bytesDownloaded == 50_000)
        #expect(safari?.bytesUploaded == 10_000)
    }
    
    @Test("App usage lifetime aggregation across multiple sessions")
    func testLifetimeAppAggregation() {
        let (db, path) = createTestDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        let session1 = UUID()
        let session2 = UUID()
        
        let appSession1 = AppUsageRecord(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            screenOnTimeSeconds: 100,
            cpuTimeSeconds: 10.0,
            energyWh: 0.10,
            energyImpact: 5.0,
            bytesDownloaded: 1_000,
            bytesUploaded: 500
        )
        let appSession2 = AppUsageRecord(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            screenOnTimeSeconds: 200,
            cpuTimeSeconds: 20.0,
            energyWh: 0.20,
            energyImpact: 10.0,
            bytesDownloaded: 2_000,
            bytesUploaded: 1_000
        )
        
        db.saveAppUsageRecords(sessionId: session1, records: [appSession1])
        db.saveAppUsageRecords(sessionId: session2, records: [appSession2])
        
        let lifetime = db.fetchLifetimeAppUsage()
        #expect(lifetime.count == 1)
        
        let safariTotal = lifetime.first!
        #expect(safariTotal.bundleIdentifier == "com.apple.Safari")
        #expect(safariTotal.screenOnTimeSeconds == 300) // 100 + 200
        #expect(safariTotal.bytesDownloaded == 3_000)   // 1000 + 2000
        #expect(safariTotal.bytesUploaded == 1_500)     // 500 + 1000
        #expect(abs(safariTotal.energyWh - 0.30) < 0.001)
    }
    
    @Test("Reset all history cleans app usage tables")
    func testResetClearsAppUsage() {
        let (db, path) = createTestDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        let sessionId = UUID()
        let app = AppUsageRecord(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            screenOnTimeSeconds: 50,
            cpuTimeSeconds: 5.0,
            energyWh: 0.05,
            energyImpact: 2.0,
            bytesDownloaded: 100,
            bytesUploaded: 50
        )
        db.saveAppUsageRecords(sessionId: sessionId, records: [app])
        #expect(db.fetchAppUsage(sessionId: sessionId).count == 1)
        
        db.resetAllHistory()
        #expect(db.fetchAppUsage(sessionId: sessionId).isEmpty)
        #expect(db.fetchLifetimeAppUsage().isEmpty)
    }
}
