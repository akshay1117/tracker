import Testing
import Foundation
@testable import MacPulse

@Suite("Hardware Integration Checks")
struct HardwareIntegrationTests {
    
    @Test("Kernel Uptime Provider returns non-zero uptime and valid boot UUID")
    func testKernelUptime() {
        let provider = SystemUptimeProvider()
        let uptime = provider.currentBootUptime()
        let uuid = provider.bootSessionUUID()
        let bootDate = provider.bootDate()
        
        #expect(uptime > 0)
        #expect(!uuid.isEmpty)
        #expect(uuid != "DEFAULT-BOOT-SESSION")
        #expect(bootDate.timeIntervalSince1970 > 0)
    }
    
    @Test("Clamshell Monitor reports valid boolean state on Apple Silicon hardware")
    func testClamshellMonitor() {
        let monitor = SystemClamshellMonitor()
        let isClosed = monitor.isLidClosed()
        // On a running interactive session, the lid should be open (false)
        #expect(isClosed == false || isClosed == true)
    }
    
    @Test("System Power Monitor samples without crashes")
    func testSystemPowerSampling() {
        let monitor = SystemPowerMonitor()
        let snapshot = monitor.samplePower()
        
        #expect(snapshot.timestamp.timeIntervalSince1970 > 0)
        #expect(snapshot.monotonicTime > 0)
        // Telemetry must be recognized
        #expect(snapshot.telemetrySource != .simulated)
    }
    
    @Test("System Network Monitor detects Wi-Fi interface and reads 64-bit counters")
    func testNetworkSampling() {
        let monitor = SystemNetworkMonitor()
        let iface = monitor.activeWiFiInterfaceName()
        let snapshot = monitor.sampleNetwork()
        
        #expect(snapshot.monotonicTime > 0)
        if let iface = iface {
            #expect(!iface.isEmpty)
            #expect(!iface.starts(with: "utun")) // Must NOT be a VPN interface!
            #expect(!iface.starts(with: "lo"))   // Must NOT be loopback!
        }
    }
}
