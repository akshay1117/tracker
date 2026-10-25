import Foundation

/// Represents a distinct usage session beginning when the lid opens and ending when the lid closes or system sleeps.
public struct UsageSession: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    /// Boot identifier (from kern.bootsessionuuid) to link this session to its boot epoch.
    public let bootSessionUUID: String
    
    /// Wall-clock date when session started.
    public let startTime: Date
    /// Wall-clock date when session concluded (nil if active).
    public var endTime: Date?
    
    /// Active monotonic awake duration in seconds (excluding sleep intervals).
    public var durationSeconds: TimeInterval
    
    /// Total system energy consumed during this session in Watt-hours.
    public var energyWh: Double
    /// Total battery energy discharged during this session in Watt-hours.
    public var batteryEnergyWh: Double
    
    /// Wi-Fi bytes downloaded during this session.
    public var bytesDownloaded: Int64
    /// Wi-Fi bytes uploaded during this session.
    public var bytesUploaded: Int64
    
    /// Reason the session ended.
    public var endReason: SessionEndReason
    /// Assessment of power measurement quality.
    public var powerQuality: PowerQuality
    /// Confidence tier of session boundary detection.
    public var detectionConfidence: SessionDetectionConfidence
    
    /// Last checkpoint timestamp for crash recovery.
    public var lastCheckpointTime: Date
    
    public init(
        id: UUID = UUID(),
        bootSessionUUID: String,
        startTime: Date,
        endTime: Date? = nil,
        durationSeconds: TimeInterval = 0.0,
        energyWh: Double = 0.0,
        batteryEnergyWh: Double = 0.0,
        bytesDownloaded: Int64 = 0,
        bytesUploaded: Int64 = 0,
        endReason: SessionEndReason = .unknown,
        powerQuality: PowerQuality = .high,
        detectionConfidence: SessionDetectionConfidence = .hardwareClamshell,
        lastCheckpointTime: Date? = nil
    ) {
        self.id = id
        self.bootSessionUUID = bootSessionUUID
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.energyWh = energyWh
        self.batteryEnergyWh = batteryEnergyWh
        self.bytesDownloaded = bytesDownloaded
        self.bytesUploaded = bytesUploaded
        self.endReason = endReason
        self.powerQuality = powerQuality
        self.detectionConfidence = detectionConfidence
        self.lastCheckpointTime = lastCheckpointTime ?? startTime
    }
    
    public var isActive: Bool {
        endTime == nil
    }
    
    public var totalCombinedBytes: Int64 {
        bytesDownloaded + bytesUploaded
    }
    
    public var totalCombinedGB: Double {
        Double(totalCombinedBytes) / Double(UnitFormatter.Thresholds.bytesPerGB)
    }
    
    public var formattedDataGB: String {
        UnitFormatter.formatDataSize(bytes: totalCombinedBytes)
    }
    
    public var formattedEnergy: String {
        UnitFormatter.formatEnergy(wattHours: energyWh)
    }
    
    /// Formatted duration string according to magnitude rules.
    public var formattedDuration: String {
        UnitFormatter.formatDuration(seconds: durationSeconds)
    }
    
    /// Formatted duration strictly formatted via UnitFormatter.
    public var formattedDurationHoursAndMinutes: String {
        UnitFormatter.formatDuration(seconds: durationSeconds)
    }
    
    public static func formatHoursAndMinutes(_ seconds: TimeInterval) -> String {
        UnitFormatter.formatDuration(seconds: seconds)
    }
    
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        UnitFormatter.formatDuration(seconds: seconds)
    }
}

/// A record representing a continuous system boot interval.
public struct BootRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: String // BootSessionUUID
    public let bootTimestamp: Date
    public let firstSeen: Date
    public var lastSeen: Date
    
    public init(id: String, bootTimestamp: Date, firstSeen: Date, lastSeen: Date) {
        self.id = id
        self.bootTimestamp = bootTimestamp
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}

/// Lifetime aggregated totals preserved across all sessions and reboots.
public struct AggregateStats: Codable, Sendable, Equatable {
    public var lifetimeEnergyWh: Double
    public var lifetimeBatteryEnergyWh: Double
    public var lifetimeBytesDownloaded: Int64
    public var lifetimeBytesUploaded: Int64
    public var lifetimeAwakeSeconds: TimeInterval
    public var totalSessionsCount: Int
    
    public init(
        lifetimeEnergyWh: Double = 0.0,
        lifetimeBatteryEnergyWh: Double = 0.0,
        lifetimeBytesDownloaded: Int64 = 0,
        lifetimeBytesUploaded: Int64 = 0,
        lifetimeAwakeSeconds: TimeInterval = 0.0,
        totalSessionsCount: Int = 0
    ) {
        self.lifetimeEnergyWh = lifetimeEnergyWh
        self.lifetimeBatteryEnergyWh = lifetimeBatteryEnergyWh
        self.lifetimeBytesDownloaded = lifetimeBytesDownloaded
        self.lifetimeBytesUploaded = lifetimeBytesUploaded
        self.lifetimeAwakeSeconds = lifetimeAwakeSeconds
        self.totalSessionsCount = totalSessionsCount
    }
    
    public var lifetimeTotalBytes: Int64 {
        lifetimeBytesDownloaded + lifetimeBytesUploaded
    }
    
    public var formattedLifetimeEnergy: String {
        UnitFormatter.formatEnergy(wattHours: lifetimeEnergyWh)
    }
    
    public var formattedLifetimeData: String {
        UnitFormatter.formatDataSize(bytes: lifetimeTotalBytes)
    }
    
    public var formattedLifetimeAwake: String {
        UnitFormatter.formatDuration(seconds: lifetimeAwakeSeconds)
    }
    
    /// Combines completed historical stats with an in-progress active session.
    public func combined(with session: UsageSession?) -> AggregateStats {
        guard let session = session, session.endTime == nil else { return self }
        return AggregateStats(
            lifetimeEnergyWh: self.lifetimeEnergyWh + session.energyWh,
            lifetimeBatteryEnergyWh: self.lifetimeBatteryEnergyWh + session.batteryEnergyWh,
            lifetimeBytesDownloaded: self.lifetimeBytesDownloaded + session.bytesDownloaded,
            lifetimeBytesUploaded: self.lifetimeBytesUploaded + session.bytesUploaded,
            lifetimeAwakeSeconds: self.lifetimeAwakeSeconds + session.durationSeconds,
            totalSessionsCount: self.totalSessionsCount + 1
        )
    }
}
