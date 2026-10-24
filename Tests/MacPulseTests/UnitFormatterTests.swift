import Testing
import Foundation
@testable import MacPulse

@Suite("Dynamic Unit Conversion & Formatter Tests")
struct UnitFormatterTests {
    
    // MARK: - 1. Wi-Fi Data Usage Acceptance Tests
    
    @Test("Wi-Fi Data Usage dynamic conversion: MB to GB threshold")
    func testDataUsageFormatting() {
        // 0 MB displays as 0 MB
        #expect(UnitFormatter.formatDataSize(bytes: 0) == "0 MB")
        
        // 125 MB displays as 125 MB
        #expect(UnitFormatter.formatDataSize(bytes: 125_000_000) == "125 MB")
        
        // 999 MB displays as 999 MB (Acceptance Test)
        #expect(UnitFormatter.formatDataSize(bytes: 999_000_000) == "999 MB")
        
        // 1,000 MB displays as 1.00 GB (Acceptance Test)
        #expect(UnitFormatter.formatDataSize(bytes: 1_000_000_000) == "1.00 GB")
        
        // 1,250 MB displays as 1.25 GB
        #expect(UnitFormatter.formatDataSize(bytes: 1_250_000_000) == "1.25 GB")
        
        // 10,000 MB displays as 10.00 GB
        #expect(UnitFormatter.formatDataSize(bytes: 10_000_000_000) == "10.00 GB")
        
        // Safe handling of negative / zero
        #expect(UnitFormatter.formatDataSize(bytes: -100) == "0 MB")
    }
    
    // MARK: - 2. Power and Energy Acceptance Tests
    
    @Test("Instantaneous Power remains in W and never converts to kW")
    func testPowerFormatting() {
        // Instantaneous power: 3.8 W displays as 3.8 W
        #expect(UnitFormatter.formatPower(watts: 3.8) == "3.8 W")
        
        // Instantaneous power: 125 W displays as 125 W
        #expect(UnitFormatter.formatPower(watts: 125.0) == "125 W")
        
        // 0 W
        #expect(UnitFormatter.formatPower(watts: 0.0) == "0 W")
        
        // Safe handling of invalid / negative readings
        #expect(UnitFormatter.formatPower(watts: -1.0) == "– W")
        #expect(UnitFormatter.formatPower(watts: Double.nan) == "– W")
    }
    
    @Test("Accumulated Energy dynamic conversion: Wh to kWh threshold")
    func testEnergyFormatting() {
        // 450 Wh displays as 450 Wh
        #expect(UnitFormatter.formatEnergy(wattHours: 450.0) == "450 Wh")
        
        // 999 Wh displays as 999 Wh (Acceptance Test)
        #expect(UnitFormatter.formatEnergy(wattHours: 999.0) == "999 Wh")
        
        // 1,000 Wh displays as 1.00 kWh (Acceptance Test)
        #expect(UnitFormatter.formatEnergy(wattHours: 1_000.0) == "1.00 kWh")
        
        // 1,250 Wh displays as 1.25 kWh
        #expect(UnitFormatter.formatEnergy(wattHours: 1_250.0) == "1.25 kWh")
        
        // 10,000 Wh displays as 10.00 kWh
        #expect(UnitFormatter.formatEnergy(wattHours: 10_000.0) == "10.00 kWh")
        
        // Zero / negative handling
        #expect(UnitFormatter.formatEnergy(wattHours: 0.0) == "0 Wh")
        #expect(UnitFormatter.formatEnergy(wattHours: -5.0) == "0 Wh")
    }
    
    // MARK: - 3. Screen Time and Duration Acceptance Tests
    
    @Test("Elapsed time magnitude-based formatting and non-premature rounding")
    func testDurationFormatting() {
        // 35 seconds displays as 35 sec
        #expect(UnitFormatter.formatDuration(seconds: 35) == "35 sec")
        
        // 45 seconds displays as 45 sec
        #expect(UnitFormatter.formatDuration(seconds: 45) == "45 sec")
        
        // 1 minute displays as 1 min
        #expect(UnitFormatter.formatDuration(seconds: 60) == "1 min")
        
        // 35 minutes displays as 35 min
        #expect(UnitFormatter.formatDuration(seconds: 35 * 60) == "35 min")
        
        // 59 minutes displays as 59 min
        #expect(UnitFormatter.formatDuration(seconds: 59 * 60) == "59 min")
        
        // CRITICAL ACCEPTANCE TEST: 59 minutes and 59 seconds does not display as 1 hour!
        let fiftyNineMinsFiftyNineSecs = (59 * 60) + 59 // 3599 seconds
        let formatted = UnitFormatter.formatDuration(seconds: TimeInterval(fiftyNineMinsFiftyNineSecs))
        #expect(formatted == "59 min")
        #expect(formatted != "1 hr")
        
        // 1 hour displays as 1 hr
        #expect(UnitFormatter.formatDuration(seconds: 3600) == "1 hr")
        
        // 2 hours 30 minutes displays as 2 hr 30 min
        #expect(UnitFormatter.formatDuration(seconds: (2 * 3600) + (30 * 60)) == "2 hr 30 min")
        
        // 23 hours displays as 23 hr
        #expect(UnitFormatter.formatDuration(seconds: 23 * 3600) == "23 hr")
        
        // CRITICAL ACCEPTANCE TEST: 24 hours displays as 1 day
        #expect(UnitFormatter.formatDuration(seconds: 24 * 3600) == "1 day")
        
        // 2 days 5 hours displays as 2 days 5 hr
        #expect(UnitFormatter.formatDuration(seconds: (2 * 86400) + (5 * 3600)) == "2 days 5 hr")
        
        // Zero / negative handling
        #expect(UnitFormatter.formatDuration(seconds: 0) == "0 sec")
        #expect(UnitFormatter.formatDuration(seconds: -10) == "0 sec")
    }
    
    // MARK: - 4. Live Network Speed Tests
    
    @Test("Live network speed dynamic conversion: KB/s to MB/s threshold")
    func testNetworkSpeedFormatting() {
        // Under 1,000 KB/s uses KB/s
        #expect(UnitFormatter.formatNetworkSpeed(bytesPerSecond: 0) == "0 KB/s")
        #expect(UnitFormatter.formatNetworkSpeed(bytesPerSecond: 125_000) == "125 KB/s")
        #expect(UnitFormatter.formatNetworkSpeed(bytesPerSecond: 999_000) == "999 KB/s")
        
        // At or above 1,000 KB/s (1,000,000 B/s), switches to MB/s
        #expect(UnitFormatter.formatNetworkSpeed(bytesPerSecond: 1_000_000) == "1.00 MB/s")
        #expect(UnitFormatter.formatNetworkSpeed(bytesPerSecond: 1_250_000) == "1.25 MB/s")
        #expect(UnitFormatter.formatNetworkSpeed(bytesPerSecond: 10_000_000) == "10.00 MB/s")
    }
    
    // MARK: - 5. Data Storage Integrity Tests
    
    @Test("Changing display units never alters underlying stored totals")
    func testUnderlyingStorageIntegrity() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-storage-integrity-\(UUID().uuidString).db").path
        let db = DatabaseManager(databasePath: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }
        
        let session = UsageSession(
            bootSessionUUID: "BOOT-123",
            startTime: Date(timeIntervalSince1970: 1000),
            durationSeconds: 86400, // 24 hours
            energyWh: 1250.0,       // 1,250 Wh -> Formats as 1.25 kWh
            batteryEnergyWh: 0.0,
            bytesDownloaded: 1_000_000_000, // 1,000 MB -> Formats as 1.00 GB
            bytesUploaded: 250_000_000      // 250 MB
        )
        
        db.insertSession(session)
        let fetched = db.fetchRecentSessions(limit: 1).first
        
        #expect(fetched != nil)
        // Underlying stored database records MUST preserve exact base units
        #expect(fetched?.durationSeconds == 86400.0)
        #expect(fetched?.energyWh == 1250.0)
        #expect(fetched?.bytesDownloaded == 1_000_000_000)
        #expect(fetched?.bytesUploaded == 250_000_000)
        #expect(fetched?.totalCombinedBytes == 1_250_000_000)
        
        // Formatted display values adapt dynamically
        #expect(fetched?.formattedDuration == "1 day")
        #expect(fetched?.formattedEnergy == "1.25 kWh")
        #expect(fetched?.formattedDataGB == "1.25 GB")
    }
    
    @Test("Historical records use the exact same formatting rules as live measurements")
    func testHistoricalFormattingConsistency() {
        let session = UsageSession(
            bootSessionUUID: "BOOT-HIST",
            startTime: Date(timeIntervalSince1970: 5000),
            durationSeconds: 3599, // 59m 59s
            energyWh: 999.0,       // 999 Wh
            batteryEnergyWh: 0.0,
            bytesDownloaded: 999_000_000, // 999 MB
            bytesUploaded: 0
        )
        
        // Format from session model properties
        #expect(session.formattedDuration == "59 min")
        #expect(session.formattedEnergy == "999 Wh")
        #expect(session.formattedDataGB == "999 MB")
        
        // Format from UnitFormatter directly
        #expect(UnitFormatter.formatDuration(seconds: session.durationSeconds) == "59 min")
        #expect(UnitFormatter.formatEnergy(wattHours: session.energyWh) == "999 Wh")
        #expect(UnitFormatter.formatDataSize(bytes: session.totalCombinedBytes) == "999 MB")
    }
}
