import Foundation
import IOKit
import AppKit

/// Protocol for monitoring MacBook lid open/close transitions and system power state.
public protocol ClamshellMonitoring: Sendable {
    /// Returns true if the lid is physically closed.
    func isLidClosed() -> Bool
    /// Returns true if the hardware supports lid state reporting (false on desktops/Mac mini/Mac Studio).
    func isLidStateAvailable() -> Bool
}

/// Native implementation querying `IOPMrootDomain` for `"AppleClamshellState"`.
public final class SystemClamshellMonitor: ClamshellMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var cachedLidState: Bool = false
    private var hasClamshellSensor: Bool = true
    
    public init() {
        refreshState()
    }
    
    /// Reads the current `"AppleClamshellState"` property directly from `IOPMrootDomain`.
    public func isLidClosed() -> Bool {
        refreshState()
        lock.lock()
        defer { lock.unlock() }
        return cachedLidState
    }
    
    public func isLidStateAvailable() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasClamshellSensor
    }
    
    @discardableResult
    public func refreshState() -> Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else {
            lock.lock()
            hasClamshellSensor = false
            lock.unlock()
            return false
        }
        defer { IOObjectRelease(rootDomain) }
        
        if let val = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
            let isClosed: Bool
            if let b = val as? Bool {
                isClosed = b
            } else if CFGetTypeID(val) == CFBooleanGetTypeID() {
                isClosed = CFEqual(val, kCFBooleanTrue)
            } else {
                isClosed = false
            }
            lock.lock()
            cachedLidState = isClosed
            hasClamshellSensor = true
            lock.unlock()
            return isClosed
        } else {
            lock.lock()
            hasClamshellSensor = false
            lock.unlock()
            return false
        }
    }
}

/// Simulated clamshell monitor for deterministic automated testing.
public final class TestClamshellMonitor: ClamshellMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _isLidClosed: Bool
    private var _isAvailable: Bool
    
    public init(isLidClosed: Bool = false, isAvailable: Bool = true) {
        self._isLidClosed = isLidClosed
        self._isAvailable = isAvailable
    }
    
    public func isLidClosed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isLidClosed
    }
    
    public func isLidStateAvailable() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isAvailable
    }
    
    public func setLidClosed(_ closed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _isLidClosed = closed
    }
}
