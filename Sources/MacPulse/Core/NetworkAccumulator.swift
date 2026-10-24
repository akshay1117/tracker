import Foundation

/// Accumulates Wi-Fi traffic deltas and computes instantaneous transfer speeds.
/// Protects against negative deltas, counter rollovers, interface changes, and sleep discontinuities.
public struct NetworkAccumulator: Sendable {
    public static let maxValidIntervalSeconds: TimeInterval = 30.0
    public static let minValidIntervalSeconds: TimeInterval = 0.05
    /// Maximum plausible throughput per second for Wi-Fi (e.g. 5 GB/s) to catch corrupt samples.
    public static let maxPlausibleRateBps: Double = 5_000_000_000.0

    /// Total session or tracking-interval bytes received.
    public private(set) var bytesDownloaded: Int64 = 0
    /// Total session or tracking-interval bytes transmitted.
    public private(set) var bytesUploaded: Int64 = 0
    /// Combined total bytes.
    public var totalCombinedBytes: Int64 {
        bytesDownloaded + bytesUploaded
    }
    
    /// Current download speed in bytes/sec.
    public private(set) var currentDownloadSpeedBps: Double = 0.0
    /// Current upload speed in bytes/sec.
    public private(set) var currentUploadSpeedBps: Double = 0.0
    
    /// Previous hardware counter baseline.
    private var lastInterface: String?
    private var lastBytesIn: UInt64?
    private var lastBytesOut: UInt64?
    private var lastMonotonicTime: TimeInterval?

    public init(initialDownloaded: Int64 = 0, initialUploaded: Int64 = 0) {
        self.bytesDownloaded = initialDownloaded
        self.bytesUploaded = initialUploaded
    }
    
    /// Updates accumulator with a new raw hardware counter reading.
    /// Returns a tuple of incremental (downloadDelta, uploadDelta) bytes.
    @discardableResult
    public mutating func update(
        interface: String,
        bytesIn: UInt64,
        bytesOut: UInt64,
        monotonicTime: TimeInterval,
        isConnected: Bool
    ) -> (deltaIn: Int64, deltaOut: Int64) {
        guard isConnected else {
            currentDownloadSpeedBps = 0.0
            currentUploadSpeedBps = 0.0
            resetBaseline()
            return (0, 0)
        }
        
        // Check if interface changed
        if let prevInterface = lastInterface, prevInterface != interface {
            resetBaseline()
        }
        
        guard let prevIn = lastBytesIn,
              let prevOut = lastBytesOut,
              let prevTime = lastMonotonicTime else {
            // First reading establishes the baseline
            lastInterface = interface
            lastBytesIn = bytesIn
            lastBytesOut = bytesOut
            lastMonotonicTime = monotonicTime
            currentDownloadSpeedBps = 0.0
            currentUploadSpeedBps = 0.0
            return (0, 0)
        }
        
        let dt = monotonicTime - prevTime
        lastInterface = interface
        lastBytesIn = bytesIn
        lastBytesOut = bytesOut
        lastMonotonicTime = monotonicTime
        
        // Interval sanity checks (reject sleep or micro intervals)
        guard dt >= Self.minValidIntervalSeconds && dt <= Self.maxValidIntervalSeconds else {
            currentDownloadSpeedBps = 0.0
            currentUploadSpeedBps = 0.0
            return (0, 0)
        }
        
        // Counter reset check (reboot, interface bounce, driver reload)
        guard bytesIn >= prevIn && bytesOut >= prevOut else {
            currentDownloadSpeedBps = 0.0
            currentUploadSpeedBps = 0.0
            return (0, 0)
        }
        
        let deltaInRaw = bytesIn - prevIn
        let deltaOutRaw = bytesOut - prevOut
        
        let rateIn = Double(deltaInRaw) / dt
        let rateOut = Double(deltaOutRaw) / dt
        
        // Plausibility check
        guard rateIn <= Self.maxPlausibleRateBps && rateOut <= Self.maxPlausibleRateBps else {
            currentDownloadSpeedBps = 0.0
            currentUploadSpeedBps = 0.0
            return (0, 0)
        }
        
        let deltaIn = Int64(min(deltaInRaw, UInt64(Int64.max)))
        let deltaOut = Int64(min(deltaOutRaw, UInt64(Int64.max)))
        
        bytesDownloaded += deltaIn
        bytesUploaded += deltaOut
        currentDownloadSpeedBps = rateIn
        currentUploadSpeedBps = rateOut
        
        return (deltaIn, deltaOut)
    }
    
    /// Resets the counter baseline without clearing accumulated bytes.
    public mutating func resetBaseline() {
        lastInterface = nil
        lastBytesIn = nil
        lastBytesOut = nil
        lastMonotonicTime = nil
        currentDownloadSpeedBps = 0.0
        currentUploadSpeedBps = 0.0
    }
    
    /// Resets all counters and baselines to zero.
    public mutating func resetAll() {
        bytesDownloaded = 0
        bytesUploaded = 0
        resetBaseline()
    }
    
    /// Restores accumulated values (e.g. from a checkpoint).
    public mutating func restore(downloaded: Int64, uploaded: Int64) {
        self.bytesDownloaded = downloaded
        self.bytesUploaded = uploaded
        resetBaseline()
    }
}
