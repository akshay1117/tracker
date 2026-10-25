import Foundation
import IOKit
import IOKit.ps

/// Protocol for sampling power telemetry.
public protocol PowerMonitoring: Sendable {
    func samplePower() -> PowerSnapshot
}

/// Native macOS implementation of PowerMonitoring reading from AppleSilicon PMU and AppleSmartBattery.
public final class SystemPowerMonitor: PowerMonitoring, @unchecked Sendable {
    private let clock: MonotonicClockProvider
    
    public init(clock: MonotonicClockProvider = SystemMonotonicClock()) {
        self.clock = clock
    }
    
    public func samplePower() -> PowerSnapshot {
        let now = clock.wallClockDate()
        let mono = clock.now()
        
        // 1. Check high-level IOPowerSources for AC connection and charge state
        var isPluggedIn = false
        var isCharging = false
        var isDischarging = false
        var batteryPercent: Int? = nil
        var adapterWatts: Double? = nil
        
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                    if let powerState = desc[kIOPSPowerSourceStateKey as String] as? String {
                        if powerState == (kIOPSACPowerValue as String) {
                            isPluggedIn = true
                        }
                    }
                    if let charging = desc[kIOPSIsChargingKey as String] as? Bool {
                        isCharging = charging
                    }
                    if let cap = desc[kIOPSCurrentCapacityKey as String] as? Int {
                        batteryPercent = cap
                    }
                }
            }
        }
        
        // 2. Query IORegistry for AppleSmartBattery
        let batteryService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard batteryService != 0 else {
            return PowerSnapshot(
                timestamp: now,
                monotonicTime: mono,
                systemPowerWatts: nil,
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                isDischarging: !isPluggedIn,
                telemetrySource: .unavailable,
                confidence: .unavailable,
                quality: .unavailable
            )
        }
        defer { IOObjectRelease(batteryService) }
        
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(batteryService, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return PowerSnapshot(
                timestamp: now,
                monotonicTime: mono,
                systemPowerWatts: nil,
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                isDischarging: !isPluggedIn,
                telemetrySource: .unavailable,
                confidence: .unavailable,
                quality: .unavailable
            )
        }
        
        // Update connection state from IORegistry if available
        if let external = dict["ExternalConnected"] as? Bool {
            isPluggedIn = external
        } else if let external = dict["ExternalConnected"] as? Int {
            isPluggedIn = (external != 0)
        }
        
        if let percent = dict["CurrentCapacity"] as? Int {
            batteryPercent = percent
        }
        
        // Adapter rated watts if present
        if let adapterDetails = dict["AdapterDetails"] as? [String: Any] ?? dict["AppleRawAdapterDetails"] as? [String: Any] {
            if let w = adapterDetails["Watts"] as? Double {
                adapterWatts = w
            } else if let w = adapterDetails["Watts"] as? Int {
                adapterWatts = Double(w)
            }
        }
        
        // Read raw battery electrical specs
        var voltageVolts: Double? = nil
        var currentAmperes: Double? = nil
        var batteryPowerWatts: Double? = nil
        
        if let v_mV = dict["Voltage"] as? Double ?? (dict["Voltage"] as? Int).map(Double.init) {
            voltageVolts = v_mV / 1000.0
        }
        
        // Amperage is signed: positive = charging, negative = discharging
        if let a_mA = dict["InstantAmperage"] as? Double ??
                      (dict["InstantAmperage"] as? Int).map(Double.init) ??
                      dict["Amperage"] as? Double ??
                      (dict["Amperage"] as? Int).map(Double.init) {
            currentAmperes = a_mA / 1000.0
            
            if let v = voltageVolts {
                // If discharging (current is negative or unplugged with non-zero current), compute battery watts
                let pWatts = abs(v * (a_mA / 1000.0))
                if pWatts > 0.01 && pWatts < 200.0 {
                    batteryPowerWatts = pWatts
                }
            }
            if a_mA < -10 {
                isDischarging = true
            } else if a_mA > 10 {
                isCharging = true
            }
        }
        
        // 3. Apple Silicon Hardware PMU Telemetry (PowerTelemetryData)
        if let telemetryData = dict["PowerTelemetryData"] as? [String: Any] {
            // SystemLoad is provided in milliwatts
            if let systemLoad_mW = telemetryData["SystemLoad"] as? Double ??
                                   (telemetryData["SystemLoad"] as? Int).map(Double.init),
               systemLoad_mW > 0 && systemLoad_mW < 250_000 {
                let systemWatts = systemLoad_mW / 1000.0
                
                return PowerSnapshot(
                    timestamp: now,
                    monotonicTime: mono,
                    systemPowerWatts: systemWatts,
                    batteryPowerWatts: batteryPowerWatts,
                    batteryVoltageVolts: voltageVolts,
                    batteryCurrentAmperes: currentAmperes,
                    batteryPercent: batteryPercent,
                    isPluggedIn: isPluggedIn,
                    isCharging: isCharging,
                    isDischarging: isDischarging,
                    adapterWatts: adapterWatts,
                    telemetrySource: .appleSiliconPMU,
                    confidence: .directHardware,
                    quality: .high
                )
            }
        }
        
        // 4. Fallback: Battery Gas Gauge (if running on battery)
        if !isPluggedIn, let bWatts = batteryPowerWatts, bWatts > 0 {
            return PowerSnapshot(
                timestamp: now,
                monotonicTime: mono,
                systemPowerWatts: bWatts, // On battery with negligible other draw, battery discharge is system power
                batteryPowerWatts: bWatts,
                batteryVoltageVolts: voltageVolts,
                batteryCurrentAmperes: currentAmperes,
                batteryPercent: batteryPercent,
                isPluggedIn: false,
                isCharging: false,
                isDischarging: true,
                adapterWatts: nil,
                telemetrySource: .batteryGasGauge,
                confidence: .batteryDerived,
                quality: .moderate
            )
        }
        
        // 5. Fallback: On AC, but PMU telemetry unavailable
        // Never claim charger input power equals system power!
        return PowerSnapshot(
            timestamp: now,
            monotonicTime: mono,
            systemPowerWatts: nil,
            batteryPowerWatts: batteryPowerWatts,
            batteryVoltageVolts: voltageVolts,
            batteryCurrentAmperes: currentAmperes,
            batteryPercent: batteryPercent,
            isPluggedIn: isPluggedIn,
            isCharging: isCharging,
            isDischarging: isDischarging,
            adapterWatts: adapterWatts,
            telemetrySource: .ioPowerSources,
            confidence: .unavailable,
            quality: .unavailable
        )
    }
}

/// Simulated power monitor for unit tests.
public final class TestPowerMonitor: PowerMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var nextSnapshot: PowerSnapshot
    
    public init(initial: PowerSnapshot? = nil) {
        self.nextSnapshot = initial ?? PowerSnapshot(
            timestamp: Date(),
            monotonicTime: 0,
            systemPowerWatts: 0,
            isPluggedIn: true,
            isCharging: false,
            isDischarging: false,
            telemetrySource: .appleSiliconPMU,
            confidence: .directHardware,
            quality: .high
        )
    }
    
    public func setSnapshot(_ snapshot: PowerSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        nextSnapshot = snapshot
    }
    
    public func samplePower() -> PowerSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return nextSnapshot
    }
}
