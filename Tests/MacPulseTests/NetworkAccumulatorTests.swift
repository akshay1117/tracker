import Testing
import Foundation
@testable import MacPulse

@Suite("Network Accumulator Tests")
struct NetworkAccumulatorTests {
    
    @Test("Calculates normal throughput delta and speeds accurately")
    func testNormalNetworkDelta() {
        var acc = NetworkAccumulator()
        
        // Initial baseline reading
        acc.update(interface: "en0", bytesIn: 1_000_000, bytesOut: 500_000, monotonicTime: 100.0, isConnected: true)
        #expect(acc.bytesDownloaded == 0)
        #expect(acc.bytesUploaded == 0)
        #expect(acc.currentDownloadSpeedBps == 0.0)
        
        // 5 seconds later: 5 MB received, 1 MB sent
        // Download speed = 5,000,000 / 5 = 1,000,000 B/s (1 MB/s)
        let (dIn, dOut) = acc.update(
            interface: "en0",
            bytesIn: 6_000_000,
            bytesOut: 1_500_000,
            monotonicTime: 105.0,
            isConnected: true
        )
        
        #expect(dIn == 5_000_000)
        #expect(dOut == 1_000_000)
        #expect(acc.bytesDownloaded == 5_000_000)
        #expect(acc.bytesUploaded == 1_000_000)
        #expect(acc.totalCombinedBytes == 6_000_000)
        #expect(acc.currentDownloadSpeedBps == 1_000_000.0)
        #expect(acc.currentUploadSpeedBps == 200_000.0)
    }
    
    @Test("Counter rollover or reset does not produce negative bytes or false spikes")
    func testCounterResetProtection() {
        var acc = NetworkAccumulator()
        
        acc.update(interface: "en0", bytesIn: 50_000_000, bytesOut: 20_000_000, monotonicTime: 100.0, isConnected: true)
        _ = acc.update(interface: "en0", bytesIn: 55_000_000, bytesOut: 22_000_000, monotonicTime: 105.0, isConnected: true)
        #expect(acc.bytesDownloaded == 5_000_000)
        
        // Network counter resets to 100,000 (e.g. driver restart or Wi-Fi toggle)
        let (dIn, dOut) = acc.update(
            interface: "en0",
            bytesIn: 100_000,
            bytesOut: 50_000,
            monotonicTime: 110.0,
            isConnected: true
        )
        
        #expect(dIn == 0)
        #expect(dOut == 0)
        // Accumulated bytes must be preserved, not reduced or blown up!
        #expect(acc.bytesDownloaded == 5_000_000)
        #expect(acc.bytesUploaded == 2_000_000)
        #expect(acc.currentDownloadSpeedBps == 0.0)
        
        // Next normal increment resumes smoothly
        _ = acc.update(interface: "en0", bytesIn: 200_000, bytesOut: 100_000, monotonicTime: 115.0, isConnected: true)
        #expect(acc.bytesDownloaded == 5_100_000)
    }
    
    @Test("Interface switching resets baseline safely")
    func testInterfaceSwitching() {
        var acc = NetworkAccumulator()
        
        acc.update(interface: "en0", bytesIn: 10_000_000, bytesOut: 2_000_000, monotonicTime: 100.0, isConnected: true)
        _ = acc.update(interface: "en0", bytesIn: 12_000_000, bytesOut: 3_000_000, monotonicTime: 105.0, isConnected: true)
        #expect(acc.bytesDownloaded == 2_000_000)
        
        // Switch to en1 (e.g. secondary interface)
        let (dIn, dOut) = acc.update(
            interface: "en1",
            bytesIn: 500_000,
            bytesOut: 100_000,
            monotonicTime: 110.0,
            isConnected: true
        )
        
        #expect(dIn == 0)
        #expect(dOut == 0)
        #expect(acc.bytesDownloaded == 2_000_000)
    }
    
    @Test("Disconnected state drops throughput to zero")
    func testDisconnectedState() {
        var acc = NetworkAccumulator()
        acc.update(interface: "en0", bytesIn: 10_000_000, bytesOut: 2_000_000, monotonicTime: 100.0, isConnected: true)
        _ = acc.update(interface: "en0", bytesIn: 12_000_000, bytesOut: 3_000_000, monotonicTime: 105.0, isConnected: true)
        
        _ = acc.update(interface: "en0", bytesIn: 12_000_000, bytesOut: 3_000_000, monotonicTime: 110.0, isConnected: false)
        #expect(acc.currentDownloadSpeedBps == 0.0)
        #expect(acc.currentUploadSpeedBps == 0.0)
        #expect(acc.bytesDownloaded == 2_000_000)
    }
}
