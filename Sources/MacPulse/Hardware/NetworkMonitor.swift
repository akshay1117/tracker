import Foundation
import SystemConfiguration
import CoreWLAN

/// Protocol for network monitoring.
public protocol NetworkMonitoring: Sendable {
    func sampleNetwork() -> NetworkSnapshot
    func activeWiFiInterfaceName() -> String?
}

/// Native macOS network monitor using kernel `sysctl` `NET_RT_IFLIST2` for 64-bit hardware byte counters.
public final class SystemNetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    private let clock: MonotonicClockProvider
    private var accumulator: NetworkAccumulator
    private let lock = NSLock()
    
    private var cachedWiFiInterface: String?
    private var lastInterfaceLookupTime: TimeInterval = 0
    
    public init(clock: MonotonicClockProvider = SystemMonotonicClock()) {
        self.clock = clock
        self.accumulator = NetworkAccumulator()
        self.cachedWiFiInterface = Self.detectWiFiInterface()
    }
    
    /// Dynamically identifies the primary physical Wi-Fi interface name (e.g. "en0") without hardcoding.
    public static func detectWiFiInterface() -> String? {
        // Method 1: SystemConfiguration API
        if let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for iface in interfaces {
                if let type = SCNetworkInterfaceGetInterfaceType(iface),
                   type == kSCNetworkInterfaceTypeIEEE80211 {
                    if let bsdName = SCNetworkInterfaceGetBSDName(iface) {
                        return bsdName as String
                    }
                }
            }
        }
        
        // Method 2: CoreWLAN fallback
        if let client = CWWiFiClient.shared().interface(),
           let name = client.interfaceName {
            return name
        }
        
        return nil
    }
    
    public func activeWiFiInterfaceName() -> String? {
        let now = clock.now()
        lock.lock()
        defer { lock.unlock() }
        
        // Refresh interface lookup periodically (every 10 seconds) to detect USB Wi-Fi or adapter reconfigurations
        if cachedWiFiInterface == nil || (now - lastInterfaceLookupTime) > 10.0 {
            cachedWiFiInterface = Self.detectWiFiInterface()
            lastInterfaceLookupTime = now
        }
        return cachedWiFiInterface
    }
    
    /// Reads 64-bit kernel counters for the active Wi-Fi interface via sysctl NET_RT_IFLIST2.
    public func sampleNetwork() -> NetworkSnapshot {
        let now = clock.wallClockDate()
        let mono = clock.now()
        
        guard let ifaceName = activeWiFiInterfaceName() else {
            lock.lock()
            defer { lock.unlock() }
            accumulator.resetBaseline()
            return NetworkSnapshot(
                timestamp: now,
                monotonicTime: mono,
                interfaceName: "None",
                isConnected: false,
                rawBytesIn: 0,
                rawBytesOut: 0,
                downloadSpeedBps: 0.0,
                uploadSpeedBps: 0.0
            )
        }
        
        // Read 64-bit hardware counters via NET_RT_IFLIST2
        guard let counters = Self.readInterfaceCounters(targetInterface: ifaceName) else {
            lock.lock()
            defer { lock.unlock() }
            accumulator.resetBaseline()
            return NetworkSnapshot(
                timestamp: now,
                monotonicTime: mono,
                interfaceName: ifaceName,
                isConnected: false,
                rawBytesIn: 0,
                rawBytesOut: 0,
                downloadSpeedBps: 0.0,
                uploadSpeedBps: 0.0
            )
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        _ = accumulator.update(
            interface: ifaceName,
            bytesIn: counters.ibytes,
            bytesOut: counters.obytes,
            monotonicTime: mono,
            isConnected: true
        )
        
        return NetworkSnapshot(
            timestamp: now,
            monotonicTime: mono,
            interfaceName: ifaceName,
            isConnected: true,
            rawBytesIn: counters.ibytes,
            rawBytesOut: counters.obytes,
            downloadSpeedBps: accumulator.currentDownloadSpeedBps,
            uploadSpeedBps: accumulator.currentUploadSpeedBps
        )
    }
    
    /// Reads true 64-bit hardware counters (ifi_ibytes, ifi_obytes) using BSD sysctl NET_RT_IFLIST2.
    public static func readInterfaceCounters(targetInterface: String) -> (ibytes: UInt64, obytes: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: Int = 0
        
        guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0 && len > 0 else {
            return nil
        }
        
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: len)
        defer { buffer.deallocate() }
        
        guard sysctl(&mib, UInt32(mib.count), buffer, &len, nil, 0) == 0 else {
            return nil
        }
        
        var cursor = 0
        while cursor < len {
            let msg = buffer.advanced(by: cursor).withMemoryRebound(to: if_msghdr.self, capacity: 1) { $0.pointee }
            let msgLen = Int(msg.ifm_msglen)
            guard msgLen > 0 else { break }
            
            if msg.ifm_type == RTM_IFINFO2 {
                let msg2 = buffer.advanced(by: cursor).withMemoryRebound(to: if_msghdr2.self, capacity: 1) { $0.pointee }
                let sdl = buffer.advanced(by: cursor + MemoryLayout<if_msghdr2>.size).withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee }
                
                if sdl.sdl_nlen > 0 {
                    let sdlDataOffset = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data) ?? 12
                    let nameOffset = cursor + MemoryLayout<if_msghdr2>.size + Int(sdlDataOffset)
                    let nameBuffer = buffer.advanced(by: nameOffset)
                    let name = String(bytes: UnsafeBufferPointer(start: nameBuffer, count: Int(sdl.sdl_nlen)), encoding: .utf8) ?? ""
                    
                    if name == targetInterface {
                        return (ibytes: msg2.ifm_data.ifi_ibytes, obytes: msg2.ifm_data.ifi_obytes)
                    }
                }
            }
            cursor += msgLen
        }
        
        return nil
    }
}

/// Simulated network monitor for unit tests.
public final class TestNetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var nextSnapshot: NetworkSnapshot
    private var testInterface: String?
    
    public init(initial: NetworkSnapshot? = nil, interface: String? = "en0") {
        self.nextSnapshot = initial ?? NetworkSnapshot(
            timestamp: Date(),
            monotonicTime: 0,
            interfaceName: "en0",
            isConnected: true,
            rawBytesIn: 0,
            rawBytesOut: 0,
            downloadSpeedBps: 0,
            uploadSpeedBps: 0
        )
        self.testInterface = interface
    }
    
    public func setSnapshot(_ snapshot: NetworkSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        nextSnapshot = snapshot
    }
    
    public func sampleNetwork() -> NetworkSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return nextSnapshot
    }
    
    public func activeWiFiInterfaceName() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return testInterface
    }
}
