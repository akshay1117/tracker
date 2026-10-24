import Foundation

/// Provides boot-level uptime and system boot session identity from kernel sysctl.
public protocol UptimeProviding: Sendable {
    func currentBootUptime() -> TimeInterval
    func bootSessionUUID() -> String
    func bootDate() -> Date
}

public struct SystemUptimeProvider: UptimeProviding {
    public init() {}
    
    /// Returns the system boot uptime in seconds (includes sleep).
    public func currentBootUptime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
    
    /// Returns the unique UUID for the current macOS boot instance (`kern.bootsessionuuid`).
    public func bootSessionUUID() -> String {
        var size: Int = 0
        if sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0 && size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 {
                return buffer.withUnsafeBufferPointer { ptr in
                    guard let base = ptr.baseAddress else { return "DEFAULT-BOOT-SESSION" }
                    return String(cString: base).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return "DEFAULT-BOOT-SESSION"
    }
    
    /// Returns the wall-clock timestamp of when the Mac booted (`kern.boottime`).
    public func bootDate() -> Date {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        if sysctl(&mib, UInt32(mib.count), &bootTime, &size, nil, 0) == 0 {
            return Date(timeIntervalSince1970: Double(bootTime.tv_sec) + Double(bootTime.tv_usec) / 1_000_000.0)
        }
        return Date().addingTimeInterval(-ProcessInfo.processInfo.systemUptime)
    }
}

/// Simulated uptime provider for unit testing.
public struct TestUptimeProvider: UptimeProviding {
    public let testUptime: TimeInterval
    public let testBootUUID: String
    public let testBootDate: Date
    
    public init(testUptime: TimeInterval = 3600.0, testBootUUID: String = "TEST-BOOT-UUID", testBootDate: Date = Date(timeIntervalSince1970: 1700000000)) {
        self.testUptime = testUptime
        self.testBootUUID = testBootUUID
        self.testBootDate = testBootDate
    }
    
    public func currentBootUptime() -> TimeInterval { testUptime }
    public func bootSessionUUID() -> String { testBootUUID }
    public func bootDate() -> Date { testBootDate }
}
