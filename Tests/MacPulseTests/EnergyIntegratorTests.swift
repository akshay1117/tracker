import Testing
import Foundation
@testable import MacPulse

@Suite("Energy Integrator Tests")
struct EnergyIntegratorTests {
    
    @Test("Trapezoidal rule integration with constant power")
    func testConstantPowerIntegration() {
        var integrator = EnergyIntegrator()
        
        let start = Date(timeIntervalSince1970: 1000)
        let s1 = PowerSnapshot(
            timestamp: start,
            monotonicTime: 1000.0,
            systemPowerWatts: 10.0,
            batteryPowerWatts: nil,
            isPluggedIn: true,
            isCharging: false,
            isDischarging: false,
            telemetrySource: .appleSiliconPMU,
            confidence: .directHardware,
            quality: .high
        )
        integrator.update(with: s1)
        #expect(integrator.systemEnergyWh == 0.0)
        
        // 10W for 10 seconds = 10 * 10 / 3600 = 0.027777... Wh
        let s2 = PowerSnapshot(
            timestamp: start.addingTimeInterval(10),
            monotonicTime: 1010.0,
            systemPowerWatts: 10.0,
            batteryPowerWatts: nil,
            isPluggedIn: true,
            isCharging: false,
            isDischarging: false,
            telemetrySource: .appleSiliconPMU,
            confidence: .directHardware,
            quality: .high
        )
        let deltaWh = integrator.update(with: s2)
        let expected = (10.0 * 10.0) / 3600.0
        #expect(abs(deltaWh - expected) < 1e-6)
        #expect(abs(integrator.systemEnergyWh - expected) < 1e-6)
    }
    
    @Test("Linear power ramp integration (trapezoidal average)")
    func testLinearPowerRampIntegration() {
        var integrator = EnergyIntegrator()
        
        let start = Date(timeIntervalSince1970: 1000)
        let s1 = PowerSnapshot(
            timestamp: start,
            monotonicTime: 1000.0,
            systemPowerWatts: 10.0,
            batteryPowerWatts: nil,
            isPluggedIn: true,
            isCharging: false,
            isDischarging: false,
            telemetrySource: .appleSiliconPMU,
            confidence: .directHardware,
            quality: .high
        )
        integrator.update(with: s1)
        
        // Power ramps from 10W to 20W over 10 seconds. Average power = 15W.
        // Energy = 15 * 10 / 3600 = 0.041666... Wh
        let s2 = PowerSnapshot(
            timestamp: start.addingTimeInterval(10),
            monotonicTime: 1010.0,
            systemPowerWatts: 20.0,
            batteryPowerWatts: nil,
            isPluggedIn: true,
            isCharging: false,
            isDischarging: false,
            telemetrySource: .appleSiliconPMU,
            confidence: .directHardware,
            quality: .high
        )
        let deltaWh = integrator.update(with: s2)
        let expected = (15.0 * 10.0) / 3600.0
        #expect(abs(deltaWh - expected) < 1e-6)
    }
    
    @Test("Rejection of sleep gaps (> 30s)")
    func testSleepGapRejection() {
        var integrator = EnergyIntegrator()
        
        let s1 = PowerSnapshot(
            timestamp: Date(timeIntervalSince1970: 1000),
            monotonicTime: 1000.0,
            systemPowerWatts: 10.0,
            isPluggedIn: true,
            isCharging: false,
            isDischarging: false,
            telemetrySource: .appleSiliconPMU,
            confidence: .directHardware,
            quality: .high
        )
        integrator.update(with: s1)
        
        // Gap of 300 seconds (sleep or unobserved interval)
        let s2 = PowerSnapshot(
            timestamp: Date(timeIntervalSince1970: 1300),
            monotonicTime: 1300.0,
            systemPowerWatts: 10.0,
            isPluggedIn: true,
            isCharging: false,
            isDischarging: false,
            telemetrySource: .appleSiliconPMU,
            confidence: .directHardware,
            quality: .high
        )
        let delta = integrator.update(with: s2)
        #expect(delta == 0.0)
        #expect(integrator.systemEnergyWh == 0.0)
        #expect(integrator.rejectedIntervalCount == 1)
    }
    
    @Test("Rejection of negative or zero elapsed time")
    func testNegativeIntervalRejection() {
        var integrator = EnergyIntegrator()
        
        let s1 = PowerSnapshot(
            timestamp: Date(timeIntervalSince1970: 1000),
            monotonicTime: 1000.0,
            systemPowerWatts: 10.0,
            isPluggedIn: true,
            isCharging: false,
            isDischarging: false,
            telemetrySource: .appleSiliconPMU,
            confidence: .directHardware,
            quality: .high
        )
        integrator.update(with: s1)
        
        // Negative monotonic delta
        let s2 = PowerSnapshot(
            timestamp: Date(timeIntervalSince1970: 990),
            monotonicTime: 990.0,
            systemPowerWatts: 10.0,
            isPluggedIn: true,
            isCharging: false,
            isDischarging: false,
            telemetrySource: .appleSiliconPMU,
            confidence: .directHardware,
            quality: .high
        )
        let delta = integrator.update(with: s2)
        #expect(delta == 0.0)
        #expect(integrator.rejectedIntervalCount == 1)
    }
    
    @Test("Rejection of implausible wattage (> 150W or negative)")
    func testImplausibleWattageRejection() {
        var integrator = EnergyIntegrator()
        
        let s1 = PowerSnapshot(
            timestamp: Date(timeIntervalSince1970: 1000),
            monotonicTime: 1000.0,
            systemPowerWatts: 10.0,
            isPluggedIn: true,
            isCharging: false,
            isDischarging: false,
            telemetrySource: .appleSiliconPMU,
            confidence: .directHardware,
            quality: .high
        )
        integrator.update(with: s1)
        
        let s2 = PowerSnapshot(
            timestamp: Date(timeIntervalSince1970: 1005),
            monotonicTime: 1005.0,
            systemPowerWatts: 999.0, // Implausible glitch
            isPluggedIn: true,
            isCharging: false,
            isDischarging: false,
            telemetrySource: .appleSiliconPMU,
            confidence: .directHardware,
            quality: .high
        )
        let delta = integrator.update(with: s2)
        #expect(delta == 0.0)
        #expect(integrator.systemEnergyWh == 0.0)
    }
}
