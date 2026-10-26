import Foundation
import SwiftUI
import ServiceManagement
import AppKit

/// Observable state model bridging the core session engine and SwiftUI views.
@MainActor
public final class AppState: ObservableObject {
    public enum MenuBarMode: String, CaseIterable, Identifiable, Codable {
        case powerOnly = "PowerOnly"
        case networkOnly = "NetworkOnly"
        case compactCombined = "CompactCombined"
        case iconOnly = "IconOnly"
        
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .powerOnly: return "Power Only"
            case .networkOnly: return "Network Speed Only"
            case .compactCombined: return "Compact Combined"
            case .iconOnly: return "Icon Only"
            }
        }
    }
    
    // Core engine
    public let database: DatabaseManager
    public let sessionManager: SessionManager
    public let uptimeProvider: UptimeProviding
    
    // Published live UI metrics
    @Published public var currentSession: UsageSession?
    @Published public var lastPower: PowerSnapshot?
    @Published public var lastNetwork: NetworkSnapshot?
    @Published public var aggregateStats: AggregateStats = AggregateStats()
    @Published public var recentSessions: [UsageSession] = []
    @Published public var currentAppUsage: [AppUsageRecord] = []
    @Published public var lifetimeAppUsage: [AppUsageRecord] = []
    
    // Internal historical baselines from SQLite
    private var historicalAggregateStats: AggregateStats = AggregateStats()
    private var historicalLifetimeAppUsage: [AppUsageRecord] = []
    
    // Preferences
    @Published public var showInMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showInMenuBar, forKey: "MacPulse.ShowInMenuBar")
        }
    }
    
    @Published public var menuBarMode: MenuBarMode {
        didSet {
            UserDefaults.standard.set(menuBarMode.rawValue, forKey: "MacPulse.MenuBarMode")
            updateMenuBarText()
        }
    }
    
    @Published public var sessionPolicy: SessionPolicy {
        didSet {
            sessionManager.policy = sessionPolicy
        }
    }
    
    @Published public var showInDock: Bool {
        didSet {
            UserDefaults.standard.set(showInDock, forKey: "MacPulse.ShowInDock")
            updateActivationPolicy()
        }
    }
    
    public var onResetMenuBar: (() -> Void)?
    public var onVerifyMenuBar: (() -> Void)?
    
    public func resetMenuBarPosition() {
        showInMenuBar = true
        onResetMenuBar?()
        performTick()
    }
    
    @Published public var isLaunchAtLoginEnabled: Bool = false
    @Published public var isWindowOpen: Bool = false {
        didSet {
            sessionManager.appUsageMonitor.isUIVisible = isUIVisible
            if isWindowOpen {
                refreshData()
                adjustTimerFrequency()
            }
        }
    }
    @Published public var isPopoverOpen: Bool = false {
        didSet {
            sessionManager.appUsageMonitor.isUIVisible = isUIVisible
            if isPopoverOpen {
                refreshData()
                adjustTimerFrequency()
            }
        }
    }
    
    public var isUIVisible: Bool {
        isPopoverOpen || isWindowOpen
    }
    
    // Live menu bar title
    @Published public var statusItemTitle: String = "MacPulse"
    
    // Timers
    private var sampleTimer: DispatchSourceTimer?
    private var currentTimerInterval: TimeInterval = 1.0
    
    public init(
        database: DatabaseManager = DatabaseManager(),
        sessionManager: SessionManager? = nil,
        uptimeProvider: UptimeProviding = SystemUptimeProvider()
    ) {
        self.database = database
        self.uptimeProvider = uptimeProvider
        
        // Restore preferences
        let savedShowInMenuBar = UserDefaults.standard.object(forKey: "MacPulse.ShowInMenuBar") as? Bool ?? true
        self.showInMenuBar = savedShowInMenuBar
        
        let savedMode = UserDefaults.standard.string(forKey: "MacPulse.MenuBarMode")
        self.menuBarMode = savedMode.flatMap(MenuBarMode.init) ?? .iconOnly
        
        let savedShowInDock = UserDefaults.standard.object(forKey: "MacPulse.ShowInDock") as? Bool ?? true
        self.showInDock = savedShowInDock
        
        let manager = sessionManager ?? SessionManager(
            database: database,
            powerMonitor: SystemPowerMonitor(),
            networkMonitor: SystemNetworkMonitor(),
            clamshellMonitor: SystemClamshellMonitor(),
            uptimeProvider: uptimeProvider
        )
        self.sessionManager = manager
        self.sessionPolicy = manager.policy
        
        checkLaunchAtLoginStatus()
        updateActivationPolicy()
        performTick()
        refreshData()
        startTimer(interval: 1.0)
        registerSleepWakeNotifications()
    }
    
    public func updateActivationPolicy() {
        if showInDock {
            NSApplication.shared.setActivationPolicy(.regular)
        } else {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
    
    // MARK: - Sampling & Timer Management
    
    private func startTimer(interval: TimeInterval = 1.0) {
        stopTimer()
        currentTimerInterval = interval
        let timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.performTick()
        }
        timer.resume()
        self.sampleTimer = timer
    }
    
    private func stopTimer() {
        if let timer = sampleTimer {
            timer.cancel()
            sampleTimer = nil
        }
    }
    
    private func adjustTimerFrequency() {
        // Continuous 1.0s interval for real-time live metric refreshes
        let targetInterval: TimeInterval = 1.0
        if sampleTimer == nil || targetInterval != currentTimerInterval {
            startTimer(interval: targetInterval)
        }
    }
    
    private var tickCount: Int = 0

    public func performTick() {
        sessionManager.tick()
        refreshLiveMetrics()
        if isUIVisible {
            tickCount += 1
            if tickCount >= 20 {
                tickCount = 0
                refreshHistoricalData()
            }
        }
        updateMenuBarText()
    }
    
    /// Ultra-fast 1-second in-memory refresh for live telemetry (0ms SQLite overhead)
    public func refreshLiveMetrics() {
        self.currentSession = sessionManager.currentSession
        self.lastPower = sessionManager.lastPowerSnapshot
        self.lastNetwork = sessionManager.lastNetworkSnapshot
        if isUIVisible {
            self.currentAppUsage = sessionManager.currentAppRecords
            updateAggregateAndLifetimeStats()
        } else {
            self.aggregateStats = historicalAggregateStats.combined(with: currentSession)
        }
    }
    
    /// Refreshes historical stats from SQLite database (runs periodically or on explicit user action)
    public func refreshHistoricalData() {
        self.historicalAggregateStats = database.fetchAggregateStats()
        self.recentSessions = database.fetchRecentSessions(limit: 50)
        self.historicalLifetimeAppUsage = database.fetchLifetimeAppUsage(excludingSessionId: currentSession?.id)
        updateAggregateAndLifetimeStats()
    }
    
    /// Full refresh of both live and historical records
    public func refreshData() {
        self.currentSession = sessionManager.currentSession
        self.lastPower = sessionManager.lastPowerSnapshot
        self.lastNetwork = sessionManager.lastNetworkSnapshot
        self.currentAppUsage = sessionManager.currentAppRecords
        refreshHistoricalData()
    }
    
    /// Combines completed historical stats with active session deltas in real-time
    private func updateAggregateAndLifetimeStats() {
        self.aggregateStats = historicalAggregateStats.combined(with: currentSession)
        self.lifetimeAppUsage = computeCombinedLifetimeAppUsage()
    }
    
    private func computeCombinedLifetimeAppUsage() -> [AppUsageRecord] {
        var map: [String: AppUsageRecord] = [:]
        
        for r in historicalLifetimeAppUsage {
            map[r.bundleIdentifier] = r
        }
        
        for cur in currentAppUsage {
            if var existing = map[cur.bundleIdentifier] {
                existing.screenOnTimeSeconds += cur.screenOnTimeSeconds
                existing.cpuTimeSeconds += cur.cpuTimeSeconds
                existing.energyWh += cur.energyWh
                existing.energyImpact = max(existing.energyImpact, cur.energyImpact)
                existing.bytesDownloaded += cur.bytesDownloaded
                existing.bytesUploaded += cur.bytesUploaded
                existing.isRunning = cur.isRunning
                existing.isFrontmost = cur.isFrontmost
                existing.lastUpdated = max(existing.lastUpdated, cur.lastUpdated)
                map[cur.bundleIdentifier] = existing
            } else {
                map[cur.bundleIdentifier] = cur
            }
        }
        
        return Array(map.values).sorted { $0.screenOnTimeSeconds > $1.screenOnTimeSeconds }
    }
    
    // MARK: - Menu Bar Display Formatter
    
    public func updateMenuBarText() {
        let p = lastPower
        let n = lastNetwork
        
        switch menuBarMode {
        case .powerOnly:
            if let watts = p?.systemPowerWatts, watts.isFinite && watts >= 0 {
                statusItemTitle = UnitFormatter.formatPower(watts: watts)
            } else if let bWatts = p?.batteryPowerWatts, bWatts.isFinite && bWatts > 0 {
                statusItemTitle = UnitFormatter.formatPower(watts: bWatts)
            } else {
                statusItemTitle = "– W"
            }
            
        case .networkOnly:
            if let down = n?.downloadSpeedBps, down > 0 {
                statusItemTitle = UnitFormatter.formatNetworkSpeed(bytesPerSecond: down)
            } else {
                statusItemTitle = "0 KB/s"
            }
            
        case .compactCombined:
            let powerStr: String
            if let watts = p?.systemPowerWatts, watts.isFinite && watts >= 0 {
                powerStr = UnitFormatter.formatPower(watts: watts)
            } else if let bWatts = p?.batteryPowerWatts, bWatts.isFinite && bWatts > 0 {
                powerStr = UnitFormatter.formatPower(watts: bWatts)
            } else {
                powerStr = "– W"
            }
            
            let netStr: String
            if let down = n?.downloadSpeedBps, down > 0 {
                netStr = "↓" + UnitFormatter.formatNetworkSpeed(bytesPerSecond: down)
            } else {
                netStr = "↓0 KB/s"
            }
            statusItemTitle = "\(powerStr)  \(netStr)"
            
        case .iconOnly:
            statusItemTitle = ""
        }
    }
    
    // MARK: - Uptime Helpers
    
    /// Current system boot uptime formatted via UnitFormatter.
    public var formattedSystemUptime: String {
        UnitFormatter.formatDuration(seconds: uptimeProvider.currentBootUptime())
    }
    
    /// Total tracked active uptime across all sessions formatted via UnitFormatter.
    public var formattedLifetimeAwake: String {
        UnitFormatter.formatDuration(seconds: aggregateStats.lifetimeAwakeSeconds)
    }
    
    // MARK: - Sleep & Wake Observation
    
    private func registerSleepWakeNotifications() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopTimer()
                self?.sessionManager.handleWillSleep()
                self?.refreshData()
            }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sessionManager.handleDidWake()
                self?.refreshData()
                self?.startTimer(interval: 1.0)
            }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.startTimer(interval: 1.0)
                self?.performTick()
            }
        }
    }
    
    // MARK: - Launch At Login (SMAppService)
    
    private func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            isLaunchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }
    
    public func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                isLaunchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
            } catch {
                print("MacPulse: Failed to set launch at login: \(error)")
                isLaunchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
            }
        }
    }
    
    // MARK: - Export & Reset
    
    public func exportData(asJSON: Bool) -> URL? {
        let allSessions = database.fetchRecentSessions(limit: 1000)
        let stats = aggregateStats
        
        let tempDir = FileManager.default.temporaryDirectory
        let filename = asJSON ? "MacPulse-Export-\(Int(Date().timeIntervalSince1970)).json" : "MacPulse-Export-\(Int(Date().timeIntervalSince1970)).csv"
        let fileURL = tempDir.appendingPathComponent(filename)
        
        do {
            if asJSON {
                let jsonStr = try DataExporter.exportJSON(sessions: allSessions, aggregateStats: stats, appUsage: lifetimeAppUsage)
                try jsonStr.write(to: fileURL, atomically: true, encoding: .utf8)
            } else {
                let csvStr = DataExporter.exportCSV(sessions: allSessions, aggregateStats: stats, appUsage: lifetimeAppUsage)
                try csvStr.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            return fileURL
        } catch {
            print("MacPulse: Export failed: \(error)")
            return nil
        }
    }
    
    public func resetAllHistory() {
        database.resetAllHistory()
        sessionManager.resetCurrentSession()
        self.historicalAggregateStats = AggregateStats()
        self.historicalLifetimeAppUsage = []
        refreshData()
    }
}
