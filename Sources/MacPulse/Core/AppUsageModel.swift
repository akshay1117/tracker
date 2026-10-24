import Foundation
import AppKit

/// Represents an application's resource usage including screen-on time, energy consumption, and network data usage.
public struct AppUsageRecord: Identifiable, Codable, Sendable, Equatable {
    public var id: String { bundleIdentifier.isEmpty ? appName : bundleIdentifier }
    
    /// Bundle identifier (e.g. "com.apple.Safari", "com.brave.Browser").
    public let bundleIdentifier: String
    
    /// Human-readable display name of the application.
    public var appName: String
    
    /// Screen-on time (foreground active duration) in seconds.
    public var screenOnTimeSeconds: TimeInterval
    
    /// Total CPU time consumed (user + system) in seconds.
    public var cpuTimeSeconds: TimeInterval
    
    /// Integrated energy consumption in Watt-hours (Wh).
    public var energyWh: Double
    
    /// Instantaneous or recent energy impact / CPU utilization score (0-100+).
    public var energyImpact: Double
    
    /// Network bytes downloaded by this application.
    public var bytesDownloaded: Int64
    
    /// Network bytes uploaded by this application.
    public var bytesUploaded: Int64
    
    /// Whether this application is currently frontmost on screen.
    public var isFrontmost: Bool
    
    /// Whether this application is currently running on the system.
    public var isRunning: Bool
    
    /// Last update timestamp.
    public var lastUpdated: Date
    
    public init(
        bundleIdentifier: String,
        appName: String,
        screenOnTimeSeconds: TimeInterval = 0,
        cpuTimeSeconds: TimeInterval = 0,
        energyWh: Double = 0,
        energyImpact: Double = 0,
        bytesDownloaded: Int64 = 0,
        bytesUploaded: Int64 = 0,
        isFrontmost: Bool = false,
        isRunning: Bool = true,
        lastUpdated: Date = Date()
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.screenOnTimeSeconds = screenOnTimeSeconds
        self.cpuTimeSeconds = cpuTimeSeconds
        self.energyWh = energyWh
        self.energyImpact = energyImpact
        self.bytesDownloaded = bytesDownloaded
        self.bytesUploaded = bytesUploaded
        self.isFrontmost = isFrontmost
        self.isRunning = isRunning
        self.lastUpdated = lastUpdated
    }
    
    public var totalCombinedBytes: Int64 {
        bytesDownloaded + bytesUploaded
    }
    
    public var dataUsageGB: Double {
        Double(totalCombinedBytes) / Double(UnitFormatter.Thresholds.bytesPerGB)
    }
    
    public var formattedDataUsageGB: String {
        UnitFormatter.formatDataSize(bytes: totalCombinedBytes)
    }
    
    public var formattedEnergyWh: String {
        UnitFormatter.formatEnergy(wattHours: energyWh)
    }
    
    public var screenOnTimeHours: Double {
        screenOnTimeSeconds / Double(UnitFormatter.Thresholds.secondsPerHour)
    }
    
    /// Formatted screen on time.
    public var formattedScreenOnTime: String {
        UnitFormatter.formatDuration(seconds: screenOnTimeSeconds)
    }
    
    /// Formatted screen on time strictly in magnitude-based format.
    public var formattedScreenTimeHoursAndMinutes: String {
        UnitFormatter.formatDuration(seconds: screenOnTimeSeconds)
    }
    
    /// Formatted energy string.
    public var formattedEnergy: String {
        UnitFormatter.formatEnergy(wattHours: energyWh)
    }
    
    /// Formatted data usage string (e.g. "↓ 42 MB  ↑ 3 MB").
    public var formattedDataUsage: String {
        let down = UnitFormatter.formatDataSize(bytes: bytesDownloaded)
        let up = UnitFormatter.formatDataSize(bytes: bytesUploaded)
        return "↓ \(down)  ↑ \(up)"
    }
    
    public var formattedTotalBytes: String {
        UnitFormatter.formatDataSize(bytes: totalCombinedBytes)
    }
    
    public static func formatHoursAndMinutes(_ seconds: TimeInterval) -> String {
        UnitFormatter.formatDuration(seconds: seconds)
    }
    
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        UnitFormatter.formatDuration(seconds: seconds)
    }
}

/// Sort options for application usage views.
public enum AppUsageSortOption: String, CaseIterable, Identifiable, Sendable {
    case screenTime = "Screen Time"
    case energy = "Energy Use"
    case dataUsage = "Total Data"
    case download = "Download"
    case upload = "Upload"
    case name = "Name"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .screenTime: return "display"
        case .energy: return "bolt.fill"
        case .dataUsage: return "arrow.up.arrow.down"
        case .download: return "arrow.down"
        case .upload: return "arrow.up"
        case .name: return "textformat"
        }
    }
}
