import Foundation

/// An immutable snapshot of network interface state and counters.
public struct NetworkSnapshot: Codable, Sendable, Equatable {
    /// Timestamp when sample was gathered.
    public let timestamp: Date
    /// Monotonic timestamp in seconds.
    public let monotonicTime: TimeInterval
    
    /// BSD interface name (e.g. "en0").
    public let interfaceName: String
    /// True if interface is currently active and reachable.
    public let isConnected: Bool
    
    /// Total lifetime hardware bytes received on interface.
    public let rawBytesIn: UInt64
    /// Total lifetime hardware bytes transmitted on interface.
    public let rawBytesOut: UInt64
    
    /// Current download rate in bytes per second.
    public let downloadSpeedBps: Double
    /// Current upload rate in bytes per second.
    public let uploadSpeedBps: Double
    
    public init(
        timestamp: Date,
        monotonicTime: TimeInterval,
        interfaceName: String,
        isConnected: Bool,
        rawBytesIn: UInt64,
        rawBytesOut: UInt64,
        downloadSpeedBps: Double,
        uploadSpeedBps: Double
    ) {
        self.timestamp = timestamp
        self.monotonicTime = monotonicTime
        self.interfaceName = interfaceName
        self.isConnected = isConnected
        self.rawBytesIn = rawBytesIn
        self.rawBytesOut = rawBytesOut
        self.downloadSpeedBps = downloadSpeedBps
        self.uploadSpeedBps = uploadSpeedBps
    }
    
    /// Formatted download speed string (e.g. "↓ 1.2 MB/s" or "↓ 0 B/s").
    public var formattedDownloadSpeed: String {
        "↓ " + Self.formatSpeed(bytesPerSec: downloadSpeedBps)
    }
    
    /// Formatted upload speed string (e.g. "↑ 450 KB/s" or "↑ 0 B/s").
    public var formattedUploadSpeed: String {
        "↑ " + Self.formatSpeed(bytesPerSec: uploadSpeedBps)
    }
    
    /// Formats any byte rate into human readable representation.
    public static func formatSpeed(bytesPerSec: Double) -> String {
        UnitFormatter.formatNetworkSpeed(bytesPerSecond: bytesPerSec)
    }
    
    /// Formats raw byte counts into human readable strings using decimal dynamic units.
    public static func formatBytes(_ bytes: Int64) -> String {
        UnitFormatter.formatDataSize(bytes: bytes)
    }
}
