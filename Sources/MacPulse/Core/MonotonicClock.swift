import Foundation

/// A monotonic time provider to measure precise durations independent of system wall-clock adjustments.
public protocol MonotonicClockProvider: Sendable {
    /// Returns the current monotonic time in seconds.
    func now() -> TimeInterval
    /// Returns the current wall-clock date.
    func wallClockDate() -> Date
}

/// The system monotonic clock backed by `ProcessInfo.processInfo.systemUptime`.
public struct SystemMonotonicClock: MonotonicClockProvider {
    public init() {}
    
    public func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
    
    public func wallClockDate() -> Date {
        Date()
    }
}

/// A simulated clock for deterministic unit and integration tests.
public final class TestMonotonicClock: MonotonicClockProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var currentTime: TimeInterval
    private var currentDate: Date
    
    public init(initialTime: TimeInterval = 1000.0, initialDate: Date = Date(timeIntervalSince1970: 1700000000)) {
        self.currentTime = initialTime
        self.currentDate = initialDate
    }
    
    public func now() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return currentTime
    }
    
    public func wallClockDate() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return currentDate
    }
    
    public func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        currentTime += seconds
        currentDate = currentDate.addingTimeInterval(seconds)
    }
    
    public func setTime(time: TimeInterval, date: Date) {
        lock.lock()
        defer { lock.unlock() }
        currentTime = time
        currentDate = date
    }
}
