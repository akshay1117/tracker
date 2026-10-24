import Foundation

/// Reusable centralized dynamic unit formatting engine for MacPulse.
///
/// Implements strict decimal unit conversion, non-premature rounding, and magnitude-based formatting.
///
/// Conversion Rules:
/// 1. Wi-Fi Data Usage:
///    - Threshold: Switch from MB to GB at 1,000 MB.
///    - Base: Decimal (1 GB = 1,000 MB = 1,000,000,000 bytes).
///    - Example: 0 MB, 125 MB, 999 MB, 1.00 GB, 1.25 GB, 10.00 GB.
/// 2. Network Speed:
///    - Threshold: Switch from KB/s to MB/s at 1,000 KB/s.
///    - Base: Decimal (1 KB/s = 1,000 B/s, 1 MB/s = 1,000,000 B/s).
/// 3. Power and Energy:
///    - Power remains in W (e.g., 3.8 W, 125 W). Never kW.
///    - Energy switches from Wh to kWh at 1,000 Wh (e.g., 450 Wh, 999 Wh, 1.00 kWh, 1.25 kWh).
/// 4. Duration:
///    - < 1 min: seconds ("35 sec")
///    - < 1 hr: minutes ("1 min", "59 min"). 59m 59s never rounds to 1 hr.
///    - < 24 hr: hours and minutes ("1 hr", "2 hr 30 min", "23 hr").
///    - >= 24 hr: days and hours ("1 day", "2 days 5 hr").
public enum UnitFormatter {
    
    // MARK: - Centralized Conversion Thresholds
    
    public enum Thresholds {
        public static let bytesPerKB: Int64 = 1_000
        public static let bytesPerMB: Int64 = 1_000_000
        public static let bytesPerGB: Int64 = 1_000_000_000
        
        /// Data threshold: 1,000 MB = 1,000,000,000 bytes -> Switch to GB
        public static let dataUsageGBThresholdBytes: Int64 = 1_000_000_000
        
        /// Network speed threshold: 1,000 KB/s = 1,000,000 B/s -> Switch to MB/s
        public static let networkSpeedMBThresholdBps: Double = 1_000_000.0
        
        /// Energy threshold: 1,000 Wh -> Switch to kWh
        public static let energyKWhThresholdWh: Double = 1_000.0
        
        public static let secondsPerMinute: Int = 60
        public static let secondsPerHour: Int = 3_600
        public static let secondsPerDay: Int = 86_400
    }
    
    // MARK: - 1. Wi-Fi Data Usage
    
    /// Formats raw byte count dynamically according to magnitude.
    ///
    /// - Displays in MB initially.
    /// - Switches to GB only when data reaches 1,000 MB (1,000,000,000 bytes).
    /// - Uses decimal units: 1 GB = 1,000 MB = 1,000,000,000 bytes.
    public static func formatDataSize(bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }
        
        if bytes < Thresholds.dataUsageGBThresholdBytes {
            let mb = Double(bytes) / Double(Thresholds.bytesPerMB)
            if mb >= 100 || mb.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f MB", round(mb))
            } else if mb >= 10 {
                return String(format: "%.0f MB", round(mb))
            } else {
                return String(format: "%.1f MB", mb)
            }
        } else {
            let gb = Double(bytes) / Double(Thresholds.bytesPerGB)
            return String(format: "%.2f GB", gb)
        }
    }
    
    /// Convenience helper for megabytes input.
    public static func formatDataSize(megabytes: Double) -> String {
        guard megabytes.isFinite && megabytes > 0 else { return "0 MB" }
        let bytes = Int64(megabytes * Double(Thresholds.bytesPerMB))
        return formatDataSize(bytes: bytes)
    }
    
    // MARK: - 2. Network Speed
    
    /// Formats live network throughput dynamically according to magnitude.
    ///
    /// - Displays in KB/s initially.
    /// - Switches to MB/s when throughput reaches 1,000 KB/s (1,000,000 B/s).
    /// - Uses decimal units: 1 KB/s = 1,000 B/s, 1 MB/s = 1,000,000 B/s.
    public static func formatNetworkSpeed(bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite && bytesPerSecond > 0 else { return "0 KB/s" }
        
        if bytesPerSecond < Thresholds.networkSpeedMBThresholdBps {
            let kbps = bytesPerSecond / Double(Thresholds.bytesPerKB)
            if kbps >= 100 || kbps.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f KB/s", round(kbps))
            } else if kbps >= 10 {
                return String(format: "%.0f KB/s", round(kbps))
            } else {
                return String(format: "%.1f KB/s", kbps)
            }
        } else {
            let mbps = bytesPerSecond / Thresholds.networkSpeedMBThresholdBps
            return String(format: "%.2f MB/s", mbps)
        }
    }
    
    // MARK: - 3. Instantaneous Power
    
    /// Formats instantaneous power draw in watts (W).
    ///
    /// Power draw remains in W; it is never converted to kW.
    public static func formatPower(watts: Double) -> String {
        guard watts.isFinite && watts >= 0 else { return "– W" }
        if watts == 0 { return "0 W" }
        
        if watts.truncatingRemainder(dividingBy: 1) == 0 || abs(watts - round(watts)) < 0.05 {
            return String(format: "%.0f W", round(watts))
        } else {
            return String(format: "%.1f W", watts)
        }
    }
    
    // MARK: - 4. Accumulated Energy
    
    /// Formats accumulated energy dynamically according to magnitude.
    ///
    /// - Displays in Wh initially.
    /// - Switches to kWh when energy reaches 1,000 Wh.
    public static func formatEnergy(wattHours: Double) -> String {
        guard wattHours.isFinite && wattHours > 0 else { return "0 Wh" }
        
        if wattHours < Thresholds.energyKWhThresholdWh {
            if wattHours >= 100 || wattHours.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f Wh", round(wattHours))
            } else if wattHours >= 10 {
                return String(format: "%.1f Wh", wattHours)
            } else {
                return String(format: "%.2f Wh", wattHours)
            }
        } else {
            let kwh = wattHours / Thresholds.energyKWhThresholdWh
            return String(format: "%.2f kWh", kwh)
        }
    }
    
    // MARK: - 5. Duration & Screen Time
    
    /// Formats duration dynamically according to magnitude.
    ///
    /// Rules:
    /// - < 1 minute: seconds ("35 sec", "45 sec")
    /// - < 1 hour: minutes ("1 min", "35 min", "59 min"). 59m 59s truncates to "59 min" and never rounds to 1 hr.
    /// - < 24 hours: hours and minutes ("1 hr", "2 hr 30 min", "23 hr")
    /// - >= 24 hours: days and hours ("1 day", "2 days 5 hr")
    public static func formatDuration(seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds > 0 else { return "0 sec" }
        
        let totalSeconds = Int(seconds)
        
        if totalSeconds < Thresholds.secondsPerMinute {
            return "\(totalSeconds) sec"
        } else if totalSeconds < Thresholds.secondsPerHour {
            let mins = totalSeconds / Thresholds.secondsPerMinute
            return "\(mins) min"
        } else if totalSeconds < Thresholds.secondsPerDay {
            let hours = totalSeconds / Thresholds.secondsPerHour
            let remainder = totalSeconds % Thresholds.secondsPerHour
            let mins = remainder / Thresholds.secondsPerMinute
            if mins == 0 {
                return "\(hours) hr"
            } else {
                return "\(hours) hr \(mins) min"
            }
        } else {
            let days = totalSeconds / Thresholds.secondsPerDay
            let remainder = totalSeconds % Thresholds.secondsPerDay
            let hours = remainder / Thresholds.secondsPerHour
            let dayUnit = days == 1 ? "1 day" : "\(days) days"
            if hours == 0 {
                return dayUnit
            } else {
                return "\(dayUnit) \(hours) hr"
            }
        }
    }
}
