import Foundation
import AppKit
import Darwin

/// Protocol for monitoring per-application screen time, energy consumption, and data usage.
public protocol AppUsageMonitoring: AnyObject, Sendable {
    func updateSample(elapsedSeconds: TimeInterval, systemPowerWatts: Double?, isSystemAwake: Bool) -> [AppUsageRecord]
    func resetCurrentSession()
    var currentSessionAppRecords: [AppUsageRecord] { get }
    var frontmostBundleId: String? { get }
}

/// Native macOS hardware and process monitor tracking per-app screen-on time, energy use, and network data.
public final class SystemAppUsageMonitor: AppUsageMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    
    // Internal state
    private var sessionRecords: [String: AppUsageRecord] = [:]
    private var previousCpuSeconds: [pid_t: Double] = [:]
    private var previousNetworkCounters: [pid_t: (bytesIn: Int64, bytesOut: Int64)] = [:]
    
    // Cache for PID -> (Bundle ID, App Name)
    private var pidAppCache: [pid_t: (bundleId: String, name: String, timestamp: Date)] = [:]
    private let cacheTtlSeconds: TimeInterval = 60.0
    
    // Asynchronous network poller
    private let nettopQueue = DispatchQueue(label: "com.macpulse.nettop", qos: .utility)
    private var isNettopRunning: Bool = false
    private var lastNettopRunTime: Date = Date.distantPast
    private let nettopMinIntervalSeconds: TimeInterval = 4.0
    
    public init() {
        // Initial scan
        refreshRunningApps()
    }
    
    public var currentSessionAppRecords: [AppUsageRecord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(sessionRecords.values)
    }
    
    public var frontmostBundleId: String? {
        lock.lock()
        defer { lock.unlock() }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
    
    public func resetCurrentSession() {
        lock.lock()
        defer { lock.unlock() }
        sessionRecords.removeAll()
        previousCpuSeconds.removeAll()
        previousNetworkCounters.removeAll()
        pidAppCache.removeAll()
    }
    
    // MARK: - Sampling & Updating
    
    public func updateSample(
        elapsedSeconds: TimeInterval,
        systemPowerWatts: Double?,
        isSystemAwake: Bool
    ) -> [AppUsageRecord] {
        lock.lock()
        defer { lock.unlock() }
        
        guard elapsedSeconds > 0 else {
            return Array(sessionRecords.values)
        }
        
        let now = Date()
        
        // 1. Identify Frontmost Application for Screen-on Time
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let frontmostId = frontmostApp?.bundleIdentifier ?? frontmostApp?.localizedName ?? ""
        
        if isSystemAwake && !frontmostId.isEmpty {
            let appName = frontmostApp?.localizedName ?? frontmostId
            var record = sessionRecords[frontmostId] ?? AppUsageRecord(
                bundleIdentifier: frontmostId,
                appName: appName
            )
            record.screenOnTimeSeconds += elapsedSeconds
            record.isFrontmost = true
            record.lastUpdated = now
            sessionRecords[frontmostId] = record
        }
        
        // Reset isFrontmost flag for non-frontmost apps
        for key in sessionRecords.keys where key != frontmostId {
            sessionRecords[key]?.isFrontmost = false
        }
        
        // 2. Sample CPU & Allocate Energy
        updateCpuAndEnergy(elapsedSeconds: elapsedSeconds, systemPowerWatts: systemPowerWatts, frontmostId: frontmostId, now: now)
        
        // 3. Trigger Asynchronous Network Data Sample via nettop
        triggerAsyncNettop(now: now)
        
        return Array(sessionRecords.values)
    }
    
    // MARK: - CPU & Energy Accounting
    
    private func updateCpuAndEnergy(
        elapsedSeconds: TimeInterval,
        systemPowerWatts: Double?,
        frontmostId: String,
        now: Date
    ) {
        let runningApps = NSWorkspace.shared.runningApplications
        var appCpuDeltas: [String: (deltaCpu: Double, totalCpu: Double, appName: String)] = [:]
        
        var taskInfo = proc_taskinfo()
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        
        for app in runningApps where app.activationPolicy == .regular || app.bundleIdentifier != nil {
            let mainPid = app.processIdentifier
            guard mainPid > 0 else { continue }
            
            let bundleId = app.bundleIdentifier ?? app.localizedName ?? "app_\(mainPid)"
            let appName = app.localizedName ?? bundleId
            
            // Collect main process + all child helper PIDs
            var pidsToMeasure = [mainPid]
            var childPids = [pid_t](repeating: 0, count: 64)
            let childCount = proc_listchildpids(mainPid, &childPids, Int32(MemoryLayout<pid_t>.stride * childPids.count))
            if childCount > 0 {
                for i in 0..<min(Int(childCount), childPids.count) {
                    if childPids[i] > 0 {
                        pidsToMeasure.append(childPids[i])
                    }
                }
            }
            
            var totalAppCpuSeconds: Double = 0.0
            var totalAppDeltaCpu: Double = 0.0
            
            for pid in pidsToMeasure {
                let res = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize)
                if res == taskInfoSize {
                    let cpuSec = Double(taskInfo.pti_total_user + taskInfo.pti_total_system) / 1_000_000_000.0
                    totalAppCpuSeconds += cpuSec
                    
                    if let prev = previousCpuSeconds[pid] {
                        let delta = max(0.0, cpuSec - prev)
                        totalAppDeltaCpu += delta
                    }
                    previousCpuSeconds[pid] = cpuSec
                }
            }
            
            appCpuDeltas[bundleId] = (totalAppDeltaCpu, totalAppCpuSeconds, appName)
        }
        
        // Sum total active CPU delta across apps
        let totalActiveCpuDelta = appCpuDeltas.values.reduce(0.0) { $0 + $1.deltaCpu }
        
        // Compute system interval energy in Watt-hours: E = P * (dt / 3600)
        let watts = (systemPowerWatts != nil && systemPowerWatts!.isFinite && systemPowerWatts! >= 0) ? systemPowerWatts! : 0.0
        let intervalEnergyWh = watts * (elapsedSeconds / 3600.0)
        
        // 70% dynamic energy allocated by CPU share, 30% base/display overhead allocated to frontmost app
        let dynamicEnergyWh = intervalEnergyWh * 0.70
        let baseDisplayEnergyWh = intervalEnergyWh * 0.30
        
        let runningBundleIds = Set(runningApps.compactMap { $0.bundleIdentifier })
        for (bundleId, info) in appCpuDeltas {
            var record = sessionRecords[bundleId] ?? AppUsageRecord(
                bundleIdentifier: bundleId,
                appName: info.appName,
                isFrontmost: (bundleId == frontmostId),
                isRunning: runningBundleIds.contains(bundleId)
            )
            
            record.isRunning = runningBundleIds.contains(bundleId)
            record.isFrontmost = (bundleId == frontmostId)
            record.cpuTimeSeconds += info.deltaCpu
            
            // Energy Impact = instantaneous CPU utilization percentage
            let cpuPercent = (info.deltaCpu / max(0.05, elapsedSeconds)) * 100.0
            record.energyImpact = cpuPercent
            
            // Proportional dynamic energy
            if totalActiveCpuDelta > 0.001 {
                let share = info.deltaCpu / totalActiveCpuDelta
                record.energyWh += (dynamicEnergyWh * share)
            }
            
            // Base screen/display energy attributed to the frontmost application
            if bundleId == frontmostId {
                record.energyWh += baseDisplayEnergyWh
            }
            
            record.lastUpdated = now
            sessionRecords[bundleId] = record
        }
        
        // Ensure all active regular running user applications are included in sessionRecords
        for app in runningApps where app.activationPolicy == .regular {
            guard let bId = app.bundleIdentifier else { continue }
            if sessionRecords[bId] == nil {
                let name = app.localizedName ?? bId
                sessionRecords[bId] = AppUsageRecord(
                    bundleIdentifier: bId,
                    appName: name,
                    isFrontmost: (bId == frontmostId),
                    isRunning: true,
                    lastUpdated: now
                )
            } else {
                sessionRecords[bId]?.isRunning = true
            }
        }
    }
    
    // MARK: - Asynchronous Network Sampling (nettop)
    
    private func triggerAsyncNettop(now: Date) {
        guard !isNettopRunning && now.timeIntervalSince(lastNettopRunTime) >= nettopMinIntervalSeconds else {
            return
        }
        
        isNettopRunning = true
        lastNettopRunTime = now
        
        nettopQueue.async { [weak self] in
            guard let self = self else { return }
            self.executeNettopSample()
        }
    }
    
    private func executeNettopSample() {
        defer {
            lock.lock()
            isNettopRunning = false
            lock.unlock()
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-L", "1", "-P", "-n", "-x", "-J", "bytes_in,bytes_out", "-s", "1"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            
            guard task.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else {
                return
            }
            
            self.processNettopOutput(output)
        } catch {
            // NetTop failed or process couldn't run
        }
    }
    
    private func processNettopOutput(_ output: String) {
        let lines = output.components(separatedBy: "\n")
        var pidTraffic: [pid_t: (name: String, bytesIn: Int64, bytesOut: Int64)] = [:]
        
        for line in lines {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            
            let procField = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard let inBytes = Int64(parts[1]), let outBytes = Int64(parts[2]) else { continue }
            
            // Extract PID from "process_name.PID"
            guard let lastDotIndex = procField.lastIndex(of: ".") else { continue }
            let pidStr = String(procField[procField.index(after: lastDotIndex)...])
            guard let pid = pid_t(pidStr) else { continue }
            let procName = String(procField[..<lastDotIndex])
            
            pidTraffic[pid] = (procName, inBytes, outBytes)
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        
        for (pid, traffic) in pidTraffic {
            let (bundleId, appName) = resolveApp(for: pid, fallbackName: traffic.name)
            
            var deltaIn: Int64 = 0
            var deltaOut: Int64 = 0
            
            if let prev = previousNetworkCounters[pid] {
                if traffic.bytesIn >= prev.bytesIn {
                    deltaIn = traffic.bytesIn - prev.bytesIn
                }
                if traffic.bytesOut >= prev.bytesOut {
                    deltaOut = traffic.bytesOut - prev.bytesOut
                }
            }
            previousNetworkCounters[pid] = (traffic.bytesIn, traffic.bytesOut)
            
            if deltaIn > 0 || deltaOut > 0 {
                var record = sessionRecords[bundleId] ?? AppUsageRecord(
                    bundleIdentifier: bundleId,
                    appName: appName
                )
                record.bytesDownloaded += deltaIn
                record.bytesUploaded += deltaOut
                record.lastUpdated = now
                sessionRecords[bundleId] = record
            }
        }
    }
    
    // MARK: - Process to Application Resolution
    
    private func resolveApp(for pid: pid_t, fallbackName: String) -> (bundleId: String, name: String) {
        let now = Date()
        if let cached = pidAppCache[pid], now.timeIntervalSince(cached.timestamp) < cacheTtlSeconds {
            return (cached.bundleId, cached.name)
        }
        
        // Check if PID is directly an NSRunningApplication
        if let directApp = NSRunningApplication(processIdentifier: pid),
           let bId = directApp.bundleIdentifier {
            let name = directApp.localizedName ?? fallbackName
            pidAppCache[pid] = (bId, name, now)
            return (bId, name)
        }
        
        // Traverse parent PID hierarchy (up to 5 levels) to find owning application
        var currentPid = pid
        var depth = 0
        var bsdInfo = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        
        while currentPid > 1 && depth < 5 {
            let res = proc_pidinfo(currentPid, PROC_PIDTBSDINFO, 0, &bsdInfo, size)
            guard res == size else { break }
            
            let ppid = pid_t(bsdInfo.pbi_ppid)
            guard ppid > 1 && ppid != currentPid else { break }
            
            if let parentApp = NSRunningApplication(processIdentifier: ppid),
               let parentBundleId = parentApp.bundleIdentifier {
                let parentName = parentApp.localizedName ?? parentBundleId
                pidAppCache[pid] = (parentBundleId, parentName, now)
                return (parentBundleId, parentName)
            }
            
            currentPid = ppid
            depth += 1
        }
        
        // Standalone daemon or command line tool
        let daemonId = "daemon.\(fallbackName.lowercased())"
        pidAppCache[pid] = (daemonId, fallbackName, now)
        return (daemonId, fallbackName)
    }
    
    private func refreshRunningApps() {
        let now = Date()
        for app in NSWorkspace.shared.runningApplications {
            if let bundleId = app.bundleIdentifier {
                let name = app.localizedName ?? bundleId
                pidAppCache[app.processIdentifier] = (bundleId, name, now)
            }
        }
    }
}
