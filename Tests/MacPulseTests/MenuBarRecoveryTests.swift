import Testing
import Foundation
import AppKit
@testable import MacPulse

@Suite("Menu Bar Icon & Recovery Tests")
@MainActor
struct MenuBarRecoveryTests {
    
    private func createTestDB() -> (DatabaseManager, String) {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovery-test-\(UUID().uuidString).db").path
        let db = DatabaseManager(databasePath: tempPath)
        return (db, tempPath)
    }
    
    @Test("Status Bar Controller recreation is safe and idempotent")
    func testStatusBarRecreationIdempotent() {
        let (db, path) = createTestDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        let state = AppState(database: db)
        let controller = StatusBarController(appState: state)
        
        // Recreate multiple times in rapid succession
        controller.recreateStatusItem()
        controller.recreateStatusItem()
        controller.recreateStatusItem()
        controller.ensureStatusItemVisible()
        
        #expect(state.showInMenuBar == true)
    }
    
    @Test("Menu bar restoration does not alter persistent database records or statistics")
    func testRestorationPreservesData() {
        let (db, path) = createTestDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        let sessionId = UUID()
        let session = UsageSession(
            id: sessionId,
            bootSessionUUID: "BOOT-TEST",
            startTime: Date(timeIntervalSince1970: 1000),
            endTime: Date(timeIntervalSince1970: 1300),
            durationSeconds: 300.0,
            energyWh: 2.0,
            batteryEnergyWh: 0.0,
            bytesDownloaded: 50_000_000,
            bytesUploaded: 10_000_000,
            endReason: .lidClosed
        )
        
        db.insertSession(session)
        db.finalizeSession(session)
        
        let testClamshell = TestClamshellMonitor(isLidClosed: true)
        let testManager = SessionManager(
            database: db,
            powerMonitor: TestPowerMonitor(),
            networkMonitor: TestNetworkMonitor(),
            clamshellMonitor: testClamshell,
            uptimeProvider: TestUptimeProvider()
        )
        let state = AppState(database: db, sessionManager: testManager)
        
        // Before restoration check
        #expect(state.aggregateStats.lifetimeEnergyWh == 2.0)
        #expect(state.aggregateStats.lifetimeBytesDownloaded == 50_000_000)
        
        // Simulate user clicking "Restore Menu Bar Icon"
        var resetCalled = false
        state.onResetMenuBar = {
            resetCalled = true
        }
        
        state.resetMenuBarPosition()
        
        // Verify callback was executed
        #expect(resetCalled == true)
        #expect(state.showInMenuBar == true)
        
        // Verify database and aggregate records are completely untouched
        let postAgg = db.fetchAggregateStats()
        #expect(postAgg.lifetimeEnergyWh == 2.0)
        #expect(postAgg.lifetimeBytesDownloaded == 50_000_000)
        #expect(postAgg.lifetimeBytesUploaded == 10_000_000)
        #expect(postAgg.lifetimeAwakeSeconds == 300.0)
        #expect(postAgg.totalSessionsCount == 1)
        
        let sessions = db.fetchRecentSessions(limit: 10)
        #expect(sessions.contains(where: { $0.id == sessionId }))
    }
    
    @Test("Toggling showInMenuBar setting updates visibility without losing state")
    func testShowInMenuBarToggle() {
        let (db, path) = createTestDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        let state = AppState(database: db)
        let controller = StatusBarController(appState: state)
        
        state.showInMenuBar = false
        controller.updateStatusItemDisplay()
        
        #expect(state.showInMenuBar == false)
        
        state.showInMenuBar = true
        controller.ensureStatusItemVisible()
        
        #expect(state.showInMenuBar == true)
    }
}
