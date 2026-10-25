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
    @Published public var isPopoverOpen: Bool = false {
        didSet {
            adjustTimerFrequency()
        }
    }
    
    // Live menu bar title
    @Published public var statusItemTitle: String = "MacPulse"
    
    // Timers
    private var sampleTimer: Timer?
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
    
    private func startTimer(interval: TimeInterval) {
        sampleTimer?.invalidate()
        currentTimerInterval = interval
        sampleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performTick()
            }
        }
        RunLoop.main.add(sampleTimer!, forMode: .common)
    }
    
    private func adjustTimerFrequency() {
        // Continuous 1.0s interval for real-time live metric refreshes
        let targetInterval: TimeInterval = 1.0
        if targetInterval != currentTimerInterval {
            startTimer(interval: targetInterval)
        }
    }
    
    private var tickCount: Int = 0

    public func performTick() {
        sessionManager.tick()
        refreshLiveMetrics()
        tickCount += 1
        if tickCount >= 20 {
            tickCount = 0
            refreshHistoricalData()
        }
        updateMenuBarText()
    }
    
    /// Ultra-fast 1-second in-memory refresh for live telemetry (0ms SQLite overhead)
    public func refreshLiveMetrics() {
        self.currentSession = sessionManager.currentSession
        self.lastPower = sessionManager.lastPowerSnapshot
        self.lastNetwork = sessionManager.lastNetworkSnapshot
        self.currentAppUsage = sessionManager.currentAppRecords
    }
    
    /// Refreshes historical stats from SQLite database (runs periodically or on explicit user action)
    public func refreshHistoricalData() {
        self.aggregateStats = database.fetchAggregateStats()
        self.recentSessions = database.fetchRecentSessions(limit: 50)
        self.lifetimeAppUsage = database.fetchLifetimeAppUsage()
    }
    
    /// Full refresh of both live and historical records
    public func refreshData() {
        refreshLiveMetrics()
        refreshHistoricalData()
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
                self?.sampleTimer?.invalidate()
                self?.sessionManager.handleWillSleep()
                self?.refreshData()
            }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sessionManager.handleDidWake()
                self?.refreshData()
                self?.adjustTimerFrequency()
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
        sessionManager.appUsageMonitor.resetCurrentSession()
        refreshData()
    }
}
