import Foundation

/// An immutable, timestamped snapshot of Mac system and battery power telemetry.
public struct PowerSnapshot: Codable, Sendable, Equatable {
    /// Wall-clock timestamp when sample was gathered.
    public let timestamp: Date
    /// Monotonic timestamp in seconds (for elapsed duration calculation).
    public let monotonicTime: TimeInterval
    
    /// Estimated or measured total system power draw in watts.
    public let systemPowerWatts: Double?
    /// Instantaneous battery draw in watts (positive if discharging, negative if charging).
    public let batteryPowerWatts: Double?
    /// Battery pack voltage in volts.
    public let batteryVoltageVolts: Double?
    /// Battery pack current in amperes (signed).
    public let batteryCurrentAmperes: Double?
    /// Battery state of charge percentage (0-100).
    public let batteryPercent: Int?
    
    /// True if connected to an external power adapter.
    public let isPluggedIn: Bool
    /// True if battery is currently charging from external power.
    public let isCharging: Bool
    /// True if battery is supplying power to system.
    public let isDischarging: Bool
    /// External adapter rated wattage, if reported by power source.
    public let adapterWatts: Double?
    
    /// Hardware or subsystem source of the reading.
    public let telemetrySource: TelemetrySource
    /// Confidence tier of the power figure.
    public let confidence: PowerConfidence
    /// Quality assessment of this reading.
    public let quality: PowerQuality
    
    public init(
        timestamp: Date,
        monotonicTime: TimeInterval,
        systemPowerWatts: Double?,
        batteryPowerWatts: Double? = nil,
        batteryVoltageVolts: Double? = nil,
        batteryCurrentAmperes: Double? = nil,
        batteryPercent: Int? = nil,
        isPluggedIn: Bool,
        isCharging: Bool,
        isDischarging: Bool,
        adapterWatts: Double? = nil,
        telemetrySource: TelemetrySource,
        confidence: PowerConfidence,
        quality: PowerQuality
    ) {
        self.timestamp = timestamp
        self.monotonicTime = monotonicTime
        self.systemPowerWatts = systemPowerWatts
        self.batteryPowerWatts = batteryPowerWatts
        self.batteryVoltageVolts = batteryVoltageVolts
        self.batteryCurrentAmperes = batteryCurrentAmperes
        self.batteryPercent = batteryPercent
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.isDischarging = isDischarging
        self.adapterWatts = adapterWatts
        self.telemetrySource = telemetrySource
        self.confidence = confidence
        self.quality = quality
    }
    
    /// Formatted display string for primary wattage (e.g. "3.8 W", "125 W" or "– W").
    public var formattedPowerWatts: String {
        if let watts = systemPowerWatts, watts.isFinite, watts >= 0 {
            return UnitFormatter.formatPower(watts: watts)
        } else if let bWatts = batteryPowerWatts, bWatts.isFinite, bWatts > 0 {
            return UnitFormatter.formatPower(watts: bWatts)
        } else {
            return "– W"
        }
    }
    
    /// Indicates whether the snapshot contains a usable, positive power reading.
    public var hasValidPower: Bool {
        if let watts = systemPowerWatts, watts.isFinite, watts >= 0 {
            return true
        }
        if let bWatts = batteryPowerWatts, bWatts.isFinite, bWatts > 0 {
            return true
        }
        return false
    }
}
