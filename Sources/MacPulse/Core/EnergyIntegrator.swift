import Foundation

/// Integrates discrete power snapshots into cumulative energy (Wh) using the trapezoidal rule.
public struct EnergyIntegrator: Sendable {
    /// Maximum allowed delta in seconds between samples before the interval is rejected as a discontinuity/sleep.
    public static let maxValidIntervalSeconds: TimeInterval = 30.0
    /// Minimum allowed delta in seconds to avoid division-by-zero or micro jitter.
    public static let minValidIntervalSeconds: TimeInterval = 0.05
    /// Maximum plausible wattage for an Apple Silicon MacBook Air (M4).
    public static let maxPlausibleWatts: Double = 150.0

    /// Accumulated total system energy consumed in Watt-hours (Wh).
    public private(set) var systemEnergyWh: Double = 0.0
    /// Accumulated battery energy discharged in Watt-hours (Wh).
    public private(set) var batteryEnergyWh: Double = 0.0
    
    /// The most recent accepted power snapshot.
    public private(set) var lastSnapshot: PowerSnapshot?
    
    /// Count of successfully integrated samples.
    public private(set) var integratedSampleCount: Int = 0
    /// Count of rejected/dropped intervals (e.g. sleep gaps or invalid values).
    public private(set) var rejectedIntervalCount: Int = 0

    public init(initialSystemWh: Double = 0.0, initialBatteryWh: Double = 0.0) {
        self.systemEnergyWh = initialSystemWh
        self.batteryEnergyWh = initialBatteryWh
    }
    
    /// Adds a new power snapshot and integrates energy over the elapsed interval if valid.
    /// Returns the incremental system energy added in Wh.
    @discardableResult
    public mutating func update(with snapshot: PowerSnapshot) -> Double {
        guard let previous = lastSnapshot else {
            // First sample sets the baseline
            lastSnapshot = snapshot
            return 0.0
        }
        
        let dt = snapshot.monotonicTime - previous.monotonicTime
        lastSnapshot = snapshot
        
        // Interval sanity checks
        guard dt >= Self.minValidIntervalSeconds && dt <= Self.maxValidIntervalSeconds else {
            rejectedIntervalCount += 1
            return 0.0
        }
        
        var incrementalSystemWh = 0.0
        
        // 1. System power integration
        if let pWatts = previous.systemPowerWatts,
           let cWatts = snapshot.systemPowerWatts,
           pWatts.isFinite && cWatts.isFinite &&
           pWatts >= 0 && cWatts >= 0 &&
           pWatts <= Self.maxPlausibleWatts && cWatts <= Self.maxPlausibleWatts {
            let avgWatts = (pWatts + cWatts) / 2.0
            let stepWh = (avgWatts * dt) / 3600.0
            systemEnergyWh += stepWh
            incrementalSystemWh = stepWh
        }
        
        // 2. Battery power integration (discharge only)
        if let pBat = previous.batteryPowerWatts,
           let cBat = snapshot.batteryPowerWatts,
           pBat.isFinite && cBat.isFinite &&
           pBat > 0 && cBat > 0 &&
           pBat <= Self.maxPlausibleWatts && cBat <= Self.maxPlausibleWatts {
            let avgBatWatts = (pBat + cBat) / 2.0
            let stepBatWh = (avgBatWatts * dt) / 3600.0
            batteryEnergyWh += stepBatWh
        }
        
        integratedSampleCount += 1
        return incrementalSystemWh
    }
    
    /// Resets the baseline without clearing accumulated energy (e.g. after waking from sleep).
    public mutating func resetBaseline() {
        lastSnapshot = nil
    }
    
    /// Resets all counters and baselines to zero.
    public mutating func resetAll() {
        systemEnergyWh = 0.0
        batteryEnergyWh = 0.0
        lastSnapshot = nil
        integratedSampleCount = 0
        rejectedIntervalCount = 0
    }
    
    /// Sets the accumulated values (e.g. after restoring from checkpoint).
    public mutating func restore(systemWh: Double, batteryWh: Double) {
        self.systemEnergyWh = systemWh
        self.batteryEnergyWh = batteryWh
        self.lastSnapshot = nil
    }
}
