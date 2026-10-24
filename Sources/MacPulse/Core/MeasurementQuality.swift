import Foundation

/// The hardware or subsystem source that provided power telemetry.
public enum TelemetrySource: String, Codable, Sendable {
    /// Direct system load telemetry from Apple Silicon PMU via AppleSmartBattery PowerTelemetryData.
    case appleSiliconPMU = "AppleSiliconPMU"
    /// Battery gas gauge voltage and current (V * A).
    case batteryGasGauge = "BatteryGasGauge"
    /// Standard IOPowerSources API (high-level power source description).
    case ioPowerSources = "IOPowerSources"
    /// Simulated telemetry used for automated unit testing.
    case simulated = "Simulated"
    /// Telemetry could not be read.
    case unavailable = "Unavailable"
}

/// The measurement confidence level of a power reading.
public enum PowerConfidence: String, Codable, Sendable {
    /// Directly measured by dedicated hardware power-monitoring circuitry.
    case directHardware = "DirectHardware"
    /// Derived from battery discharge current and voltage. Accurately reflects battery draw, but not AC system load.
    case batteryDerived = "BatteryDerived"
    /// Estimated or interpolated value.
    case estimated = "Estimated"
    /// Telemetry unavailable.
    case unavailable = "Unavailable"
    
    public var displayLabel: String {
        switch self {
        case .directHardware: return "Hardware Measured (PMU)"
        case .batteryDerived: return "Battery Measured (Discharge)"
        case .estimated: return "Estimated"
        case .unavailable: return "Unavailable"
        }
    }
}

/// The overall quality rating of telemetry during a session.
public enum PowerQuality: String, Codable, Sendable {
    case high = "High"
    case moderate = "Moderate"
    case degraded = "Degraded"
    case unavailable = "Unavailable"
}

/// The recorded trigger that caused a session to end.
public enum SessionEndReason: String, Codable, Sendable {
    case lidClosed = "LidClosed"
    case manualSleep = "ManualSleep"
    case idleSleep = "IdleSleep"
    case systemShutdown = "SystemShutdown"
    case appQuit = "AppQuit"
    case crashRecovered = "CrashRecovered"
    case policyChange = "PolicyChange"
    case unknown = "Unknown"
    
    public var displayTitle: String {
        switch self {
        case .lidClosed: return "Lid Closed"
        case .manualSleep: return "Manual Sleep"
        case .idleSleep: return "Idle Sleep"
        case .systemShutdown: return "System Shutdown"
        case .appQuit: return "App Quit"
        case .crashRecovered: return "Crash Recovery"
        case .policyChange: return "Policy Change"
        case .unknown: return "Unknown"
        }
    }
}

/// Confidence rating for the session boundary detection mechanism.
public enum SessionDetectionConfidence: String, Codable, Sendable {
    /// True hardware clamshell / lid transition detected from IOPMrootDomain.
    case hardwareClamshell = "HardwareClamshell"
    /// Verified power/workspace sleep or wake event.
    case workspaceNotification = "WorkspaceNotification"
    /// Reconstructed via startup crash recovery from checkpointed state.
    case recoveredCheckpoint = "RecoveredCheckpoint"
    /// Fallback heuristic.
    case fallbackHeuristic = "FallbackHeuristic"
    
    public var displayTitle: String {
        switch self {
        case .hardwareClamshell: return "Hardware Lid Event"
        case .workspaceNotification: return "Sleep/Wake Event"
        case .recoveredCheckpoint: return "Recovered from Checkpoint"
        case .fallbackHeuristic: return "Fallback Heuristic"
        }
    }
}
