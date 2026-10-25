import Foundation
import AppKit

/// Independent lifecycle and state machine manager for MacPulse usage sessions.
public final class SessionManager: @unchecked Sendable {
    public enum State: String, Sendable {
        case idle
        case active
        case sleeping
        case recovering
    }
    
    private let lock = NSLock()
    private let db: DatabaseManager
    private let powerMonitor: PowerMonitoring
    private let networkMonitor: NetworkMonitoring
    private let clamshellMonitor: ClamshellMonitoring
    private let uptimeProvider: UptimeProviding
    private let clock: MonotonicClockProvider
    public let appUsageMonitor: AppUsageMonitoring
    
    public var policy: SessionPolicy {
        didSet {
            UserDefaults.standard.set(policy.rawValue, forKey: "MacPulse.SessionPolicy")
        }
    }
    
    // State machine
    public private(set) var currentState: State = .idle
    public private(set) var currentSession: UsageSession?
    public private(set) var lastPowerSnapshot: PowerSnapshot?
    public private(set) var lastNetworkSnapshot: NetworkSnapshot?
    public var currentAppRecords: [AppUsageRecord] {
        appUsageMonitor.currentSessionAppRecords
    }
    
    // Integrators
    private var energyIntegrator = EnergyIntegrator()
    private var networkAccumulator = NetworkAccumulator()
    
    // Timing baselines
    private var lastTickMonotonic: TimeInterval?
    private var lastCheckpointMonotonic: TimeInterval = 0
    private let checkpointIntervalSeconds: TimeInterval = 20.0
    
    // Current boot session UUID
    private var currentBootUUID: String = ""
    
    public init(
        database: DatabaseManager,
        powerMonitor: PowerMonitoring,
        networkMonitor: NetworkMonitoring,
        clamshellMonitor: ClamshellMonitoring,
        uptimeProvider: UptimeProviding,
        clock: MonotonicClockProvider = SystemMonotonicClock(),
        appUsageMonitor: AppUsageMonitoring = SystemAppUsageMonitor()
    ) {
        self.db = database
        self.powerMonitor = powerMonitor
        self.networkMonitor = networkMonitor
        self.clamshellMonitor = clamshellMonitor
        self.uptimeProvider = uptimeProvider
        self.clock = clock
        self.appUsageMonitor = appUsageMonitor
        
        // Restore policy from preferences
        if let savedPolicy = UserDefaults.standard.string(forKey: "MacPulse.SessionPolicy"),
           let p = SessionPolicy(rawValue: savedPolicy) {
            self.policy = p
        } else {
            self.policy = .clamshellOnly
        }
        
        initializeLifecycle()
    }
    
    // MARK: - Startup & Recovery
    
    private func initializeLifecycle() {
        lock.lock()
        defer { lock.unlock() }
        
        currentState = .recovering
        currentBootUUID = uptimeProvider.bootSessionUUID()
        
        // Record boot record in DB
        db.recordBoot(uuid: currentBootUUID, bootTimestamp: uptimeProvider.bootDate())
        
        // Reconcile any orphaned/incomplete session from a previous crash
        let recoveredCount = db.reconcileIncompleteSessions()
        if recoveredCount > 0 {
            print("MacPulse: Reconciled \(recoveredCount) incomplete session(s) from previous run.")
        }
        
        // Determine initial state based on current lid state
        let isLidClosed = clamshellMonitor.isLidClosed()
        if isLidClosed {
            currentState = .idle
            print("MacPulse: Started with lid closed -> Idle state.")
        } else {
            // Lid is open -> start new active session
            startNewSessionInternal(trigger: .hardwareClamshell)
        }
    }
    
    // MARK: - Periodic Tick
    
    /// Called periodically by the timer (every 1s for real-time live updates).
    public func tick() {
        lock.lock()
        defer { lock.unlock() }
        
        let nowMono = clock.now()
        let isLidClosed = clamshellMonitor.isLidClosed()
        
        // Check for lid state transition
        if currentState == .active && isLidClosed {
            print("MacPulse: Lid close detected during active session -> Finalizing session.")
            finalizeActiveSessionInternal(reason: .lidClosed, confidence: .hardwareClamshell)
            currentState = .idle
            return
        } else if currentState == .idle && !isLidClosed {
            print("MacPulse: Lid open detected while idle -> Starting new session.")
            startNewSessionInternal(trigger: .hardwareClamshell)
        }
        
        guard currentState == .active, var session = currentSession else {
            return
        }
        
        // Sample power
        let pSnapshot = powerMonitor.samplePower()
        lastPowerSnapshot = pSnapshot
        energyIntegrator.update(with: pSnapshot)
        
        // Sample network
        let nSnapshot = networkMonitor.sampleNetwork()
        lastNetworkSnapshot = nSnapshot
        
        if nSnapshot.isConnected {
            _ = networkAccumulator.update(
                interface: nSnapshot.interfaceName,
                bytesIn: nSnapshot.rawBytesIn,
                bytesOut: nSnapshot.rawBytesOut,
                monotonicTime: nowMono,
                isConnected: true
            )
        }
        
        // Compute elapsed awake time
        var dt: TimeInterval = 0.0
        if let lastTick = lastTickMonotonic {
            let elapsed = nowMono - lastTick
            if elapsed >= 0.05 && elapsed <= 30.0 {
                dt = elapsed
                session.durationSeconds += dt
            }
        }
        lastTickMonotonic = nowMono
        
        // Update per-application tracking (Screen time, energy, data)
        let appRecords = appUsageMonitor.updateSample(
            elapsedSeconds: (dt > 0 ? dt : 1.0),
            systemPowerWatts: pSnapshot.systemPowerWatts,
            isSystemAwake: (currentState == .active)
        )
        
        // Update session metrics
        session.energyWh = energyIntegrator.systemEnergyWh
        session.batteryEnergyWh = energyIntegrator.batteryEnergyWh
        session.bytesDownloaded = networkAccumulator.bytesDownloaded
        session.bytesUploaded = networkAccumulator.bytesUploaded
        session.lastCheckpointTime = clock.wallClockDate()
        currentSession = session
        
        // Periodic checkpoint
        if (nowMono - lastCheckpointMonotonic) >= checkpointIntervalSeconds {
            lastCheckpointMonotonic = nowMono
            db.checkpointSession(session)
            db.saveAppUsageRecords(sessionId: session.id, records: appRecords)
        }
    }
    
    // MARK: - Session Control (Internal, assumes lock held)
    
    private func startNewSessionInternal(trigger: SessionDetectionConfidence) {
        let startTime = clock.wallClockDate()
        let nowMono = clock.now()
        
        energyIntegrator.resetAll()
        networkAccumulator.resetAll()
        appUsageMonitor.resetCurrentSession()
        lastTickMonotonic = nowMono
        lastCheckpointMonotonic = nowMono
        
        // Prime initial sample
        let pSnapshot = powerMonitor.samplePower()
        lastPowerSnapshot = pSnapshot
        energyIntegrator.update(with: pSnapshot)
        
        let nSnapshot = networkMonitor.sampleNetwork()
        lastNetworkSnapshot = nSnapshot
        if nSnapshot.isConnected {
            networkAccumulator.update(
                interface: nSnapshot.interfaceName,
                bytesIn: nSnapshot.rawBytesIn,
                bytesOut: nSnapshot.rawBytesOut,
                monotonicTime: nowMono,
                isConnected: true
            )
        }
        
        let session = UsageSession(
            bootSessionUUID: currentBootUUID,
            startTime: startTime,
            endTime: nil,
            durationSeconds: 0.0,
            energyWh: 0.0,
            batteryEnergyWh: 0.0,
            bytesDownloaded: 0,
            bytesUploaded: 0,
            endReason: .unknown,
            powerQuality: pSnapshot.quality,
            detectionConfidence: trigger,
            lastCheckpointTime: startTime
        )
        
        currentSession = session
        currentState = .active
        db.insertSession(session)
        print("MacPulse: Started new session \(session.id).")
    }
    
    private func finalizeActiveSessionInternal(reason: SessionEndReason, confidence: SessionDetectionConfidence) {
        guard var session = currentSession else { return }
        
        let endTime = clock.wallClockDate()
        session.endTime = endTime
        session.endReason = reason
        session.detectionConfidence = confidence
        session.energyWh = energyIntegrator.systemEnergyWh
        session.batteryEnergyWh = energyIntegrator.batteryEnergyWh
        session.bytesDownloaded = networkAccumulator.bytesDownloaded
        session.bytesUploaded = networkAccumulator.bytesUploaded
        session.lastCheckpointTime = endTime
        
        db.finalizeSession(session)
        db.saveAppUsageRecords(sessionId: session.id, records: appUsageMonitor.currentSessionAppRecords)
        currentSession = nil
        energyIntegrator.resetBaseline()
        networkAccumulator.resetBaseline()
        lastTickMonotonic = nil
        print("MacPulse: Finalized session \(session.id) (\(reason.displayTitle)). Duration: \(session.formattedDuration), Energy: \(String(format: "%.2f Wh", session.energyWh))")
    }
    
    // MARK: - External Lifecycle Events
    
    public func handleWillSleep() {
        lock.lock()
        defer { lock.unlock() }
        
        guard currentState == .active else { return }
        
        let isLidClosed = clamshellMonitor.isLidClosed()
        
        if isLidClosed {
            // Genuine lid close triggered sleep
            finalizeActiveSessionInternal(reason: .lidClosed, confidence: .hardwareClamshell)
            currentState = .idle
        } else {
            // Lid is still open (e.g. manual Apple Menu Sleep, or idle sleep with lid open)
            switch policy {
            case .clamshellOnly:
                // Policy says do NOT end session on sleep if lid remains open. Pause tracking.
                if let session = currentSession {
                    db.checkpointSession(session)
                }
                energyIntegrator.resetBaseline()
                networkAccumulator.resetBaseline()
                lastTickMonotonic = nil
                currentState = .sleeping
                print("MacPulse: System sleeping (lid open) -> Session paused.")
                
            case .sleepOrClamshell:
                // Policy says any sleep ends the session
                finalizeActiveSessionInternal(reason: .manualSleep, confidence: .workspaceNotification)
                currentState = .idle
            }
        }
    }
    
    public func handleDidWake() {
        lock.lock()
        defer { lock.unlock() }
        
        let isLidClosed = clamshellMonitor.isLidClosed()
        let nowMono = clock.now()
        
        if isLidClosed {
            // Clamshell mode wake with external monitor
            if currentState == .sleeping {
                // If lid was closed while sleeping, finalize now
                finalizeActiveSessionInternal(reason: .lidClosed, confidence: .hardwareClamshell)
                currentState = .idle
            }
        } else {
            // Lid is open
            if currentState == .sleeping && currentSession != nil {
                // Resume existing session
                currentState = .active
                lastTickMonotonic = nowMono
                energyIntegrator.resetBaseline()
                networkAccumulator.resetBaseline()
                print("MacPulse: System woke (lid open) -> Resumed session.")
            } else if currentState == .idle || currentSession == nil {
                // Start new session
                startNewSessionInternal(trigger: .hardwareClamshell)
            }
        }
    }
    
    public func handleWillTerminate() {
        lock.lock()
        defer { lock.unlock() }
        
        if currentState == .active {
            finalizeActiveSessionInternal(reason: .appQuit, confidence: .workspaceNotification)
        }
    }
    
    public func resetCurrentSession() {
        lock.lock()
        defer { lock.unlock() }
        startNewSessionInternal(trigger: .workspaceNotification)
    }
}
