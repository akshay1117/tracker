import Testing
import Foundation
@testable import MacPulse

@Suite("Session Lifecycle & State Machine Tests")
struct SessionLifecycleTests {
    
    private func createHarness(isLidClosed: Bool = false) -> (
        SessionManager,
        DatabaseManager,
        TestClamshellMonitor,
        TestMonotonicClock,
        String
    ) {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-lifecycle-\(UUID().uuidString).db").path
        let db = DatabaseManager(databasePath: tempPath)
        let clock = TestMonotonicClock(initialTime: 1000.0, initialDate: Date(timeIntervalSince1970: 1700000000))
        let clamshell = TestClamshellMonitor(isLidClosed: isLidClosed)
        let uptime = TestUptimeProvider(testUptime: 5000.0, testBootUUID: "BOOT-123")
        
        let initialPower = PowerSnapshot(
            timestamp: clock.wallClockDate(),
            monotonicTime: clock.now(),
            systemPowerWatts: 10.0,
            isPluggedIn: true,
            isCharging: false,
            isDischarging: false,
            telemetrySource: .appleSiliconPMU,
            confidence: .directHardware,
            quality: .high
        )
        let powerMonitor = TestPowerMonitor(initial: initialPower)
        
        let initialNet = NetworkSnapshot(
            timestamp: clock.wallClockDate(),
            monotonicTime: clock.now(),
            interfaceName: "en0",
            isConnected: true,
            rawBytesIn: 1_000_000,
            rawBytesOut: 500_000,
            downloadSpeedBps: 0.0,
            uploadSpeedBps: 0.0
        )
        let netMonitor = TestNetworkMonitor(initial: initialNet)
        
        let manager = SessionManager(
            database: db,
            powerMonitor: powerMonitor,
            networkMonitor: netMonitor,
            clamshellMonitor: clamshell,
            uptimeProvider: uptime,
            clock: clock
        )
        
        return (manager, db, clamshell, clock, tempPath)
    }
    
    @Test("Starts in active state when lid is open, idle when lid is closed")
    func testInitialLidState() {
        let (openManager, _, _, _, path1) = createHarness(isLidClosed: false)
        defer { try? FileManager.default.removeItem(atPath: path1) }
        #expect(openManager.currentState == .active)
        #expect(openManager.currentSession != nil)
        
        let (closedManager, _, _, _, path2) = createHarness(isLidClosed: true)
        defer { try? FileManager.default.removeItem(atPath: path2) }
        #expect(closedManager.currentState == .idle)
        #expect(closedManager.currentSession == nil)
    }
    
    @Test("Closing lid finalizes session and stops active sampling")
    func testLidCloseFinalizesSession() {
        let (manager, db, clamshell, clock, path) = createHarness(isLidClosed: false)
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        let firstSessionID = manager.currentSession!.id
        
        // Advance time by 10s and tick
        clock.advance(by: 10.0)
        manager.tick()
        #expect(manager.currentSession?.durationSeconds ?? 0 >= 9.9)
        
        // Lid closes
        clamshell.setLidClosed(true)
        manager.tick()
        
        #expect(manager.currentState == .idle)
        #expect(manager.currentSession == nil)
        
        // Verify in DB
        let recents = db.fetchRecentSessions()
        #expect(recents.count == 1)
        #expect(recents.first?.id == firstSessionID)
        #expect(recents.first?.endReason == .lidClosed)
        #expect(recents.first?.endTime != nil)
    }
    
    @Test("Opening lid after closing creates a distinct new session without resetting lifetime stats")
    func testLidReopenCreatesNewSession() {
        let (manager, db, clamshell, clock, path) = createHarness(isLidClosed: false)
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        let session1ID = manager.currentSession!.id
        
        // 1. Close lid
        clamshell.setLidClosed(true)
        manager.tick()
        #expect(manager.currentSession == nil)
        
        // 2. Open lid again
        clock.advance(by: 60.0)
        clamshell.setLidClosed(false)
        manager.tick()
        
        #expect(manager.currentState == .active)
        #expect(manager.currentSession != nil)
        let session2ID = manager.currentSession!.id
        #expect(session1ID != session2ID)
        
        // Lifetime count must have preserved session 1
        let agg = db.fetchAggregateStats()
        #expect(agg.totalSessionsCount == 1)
    }
    
    @Test("Duplicate sleep or wake notifications are idempotent")
    func testDuplicateLifecycleIdempotency() {
        let (manager, _, clamshell, _, path) = createHarness(isLidClosed: false)
        defer { try? FileManager.default.removeItem(atPath: path) }
        
        clamshell.setLidClosed(true)
        manager.handleWillSleep()
        manager.handleWillSleep() // Duplicate call
        #expect(manager.currentState == .idle)
        
        clamshell.setLidClosed(false)
        manager.handleDidWake()
        manager.handleDidWake() // Duplicate call
        #expect(manager.currentState == .active)
    }
    
    @Test("ClamshellOnly policy pauses session during sleep and resumes on wake")
    func testClamshellOnlySleepResume() {
        let (manager, _, clamshell, clock, path) = createHarness(isLidClosed: false)
        defer { try? FileManager.default.removeItem(atPath: path) }
        manager.policy = .clamshellOnly
        
        let sessionID = manager.currentSession!.id
        
        // System sleeps with lid still open (e.g. idle display sleep)
        clamshell.setLidClosed(false)
        manager.handleWillSleep()
        #expect(manager.currentState == .sleeping)
        #expect(manager.currentSession?.id == sessionID)
        
        // Sleep for 1 hour (monotonic clock advances)
        clock.advance(by: 3600.0)
        
        // System wakes with lid still open
        manager.handleDidWake()
        #expect(manager.currentState == .active)
        #expect(manager.currentSession?.id == sessionID)
        
        // Duration should NOT include the 1 hour sleep!
        manager.tick()
        #expect(manager.currentSession!.durationSeconds < 60.0)
    }
    
    @Test("SleepOrClamshell policy finalizes session on sleep")
    func testSleepOrClamshellPolicy() {
        let (manager, db, clamshell, clock, path) = createHarness(isLidClosed: false)
        defer { try? FileManager.default.removeItem(atPath: path) }
        manager.policy = .sleepOrClamshell
        
        let session1ID = manager.currentSession!.id
        
        // System sleeps with lid open
        clamshell.setLidClosed(false)
        manager.handleWillSleep()
        #expect(manager.currentState == .idle)
        #expect(manager.currentSession == nil)
        
        let saved = db.fetchRecentSessions()
        #expect(saved.count == 1)
        #expect(saved.first?.id == session1ID)
        #expect(saved.first?.endReason == .manualSleep)
        
        // System wakes
        clock.advance(by: 10.0)
        manager.handleDidWake()
        #expect(manager.currentState == .active)
        #expect(manager.currentSession?.id != session1ID)
    }
}
