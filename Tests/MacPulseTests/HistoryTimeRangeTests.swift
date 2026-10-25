import Testing
import Foundation
@testable import MacPulse

@Suite("History Time Range & Aggregation Tests")
struct HistoryTimeRangeTests {
    
    private func createTestDB() -> (DatabaseManager, String) {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-history-\(UUID().uuidString).db").path
        let db = DatabaseManager(databasePath: tempPath)
        return (db, tempPath)
    }
    
    @Test("HistoryTimeRange enum properties and durations")
    func testHistoryTimeRangeProperties() {
        #expect(HistoryView.HistoryTimeRange.sevenDays.numberOfDays == 7)
        #expect(HistoryView.HistoryTimeRange.monthly.numberOfDays == 30)
        #expect(HistoryView.HistoryTimeRange.threeMonths.numberOfDays == 90)
        #expect(HistoryView.HistoryTimeRange.yearly.numberOfDays == 365)
        
        #expect(HistoryView.HistoryTimeRange.sevenDays.badgePrefix == "7D")
        #expect(HistoryView.HistoryTimeRange.monthly.badgePrefix == "30D")
        #expect(HistoryView.HistoryTimeRange.threeMonths.badgePrefix == "3M")
        #expect(HistoryView.HistoryTimeRange.yearly.badgePrefix == "1Y")
    }
    
    @Test("fetchSessionsSince queries accurately across historical time windows")
    func testDatabaseFetchSessionsSinceTimeRange() {
        let (db, path) = createTestDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        let now = Date()
        let day1 = now.addingTimeInterval(-1 * 86400) // 1 day ago (in 7D, 30D, 3M, 1Y)
        let day15 = now.addingTimeInterval(-15 * 86400) // 15 days ago (in 30D, 3M, 1Y)
        let day45 = now.addingTimeInterval(-45 * 86400) // 45 days ago (in 3M, 1Y)
        let day120 = now.addingTimeInterval(-120 * 86400) // 120 days ago (in 1Y only)
        let day400 = now.addingTimeInterval(-400 * 86400) // 400 days ago (outside 1Y)
        
        let dates = [day1, day15, day45, day120, day400]
        for (i, d) in dates.enumerated() {
            let session = UsageSession(
                id: UUID(),
                bootSessionUUID: "TEST-BOOT",
                startTime: d,
                endTime: d.addingTimeInterval(3600),
                durationSeconds: 3600,
                energyWh: Double(i + 1) * 10.0,
                batteryEnergyWh: 0.0,
                bytesDownloaded: Int64((i + 1) * 1_000_000_000), // 1GB to 5GB
                bytesUploaded: 50_000_000,
                endReason: .lidClosed,
                powerQuality: .high,
                detectionConfidence: .hardwareClamshell,
                lastCheckpointTime: d.addingTimeInterval(3600)
            )
            db.insertSession(session)
            db.finalizeSession(session)
        }
        
        // 7-day query
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let sessions7D = db.fetchSessionsSince(date: sevenDaysAgo)
        #expect(sessions7D.count == 1)
        #expect(sessions7D.first?.energyWh == 10.0)
        #expect(sessions7D.first?.bytesDownloaded == 1_000_000_000)
        
        // 30-day query
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let sessions30D = db.fetchSessionsSince(date: thirtyDaysAgo)
        #expect(sessions30D.count == 2)
        
        // 90-day (3 Months) query
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: now)!
        let sessions3M = db.fetchSessionsSince(date: ninetyDaysAgo)
        #expect(sessions3M.count == 3)
        
        // 365-day (1 Year) query
        let oneYearAgo = Calendar.current.date(byAdding: .day, value: -365, to: now)!
        let sessions1Y = db.fetchSessionsSince(date: oneYearAgo)
        #expect(sessions1Y.count == 4)
    }
    
    @Test("HistoryBucketSummary data and screen time calculations")
    func testHistoryBucketSummaryFormatting() {
        let bucket = HistoryBucketSummary(
            id: "2026-10-25",
            date: Date(),
            label: "Sun",
            energyWh: 15.5,
            bytes: 2_500_000_000, // 2.5 GB
            durationSeconds: 5400 // 1h 30m
        )
        
        #expect(bucket.energyWh == 15.5)
        #expect(bucket.dataGB == 2.5)
        #expect(bucket.durationHours == 1.5)
        #expect(bucket.formattedScreenTime == "1 hr 30 min")
        #expect(bucket.formattedValue(for: .energy) == "15.5 Wh")
        #expect(bucket.formattedValue(for: .network) == "2.50 GB")
        #expect(bucket.formattedValue(for: .duration) == "1 hr 30 min")
    }
}
