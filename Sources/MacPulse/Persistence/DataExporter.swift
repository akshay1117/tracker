import Foundation

/// Exporter for MacPulse session history, aggregate metrics, and per-app usage.
public struct DataExporter: Sendable {
    
    /// Generates a CSV formatted string of the given sessions and app usage.
    public static func exportCSV(
        sessions: [UsageSession],
        aggregateStats: AggregateStats,
        appUsage: [AppUsageRecord] = []
    ) -> String {
        var lines: [String] = []
        
        // Metadata / Aggregate Header comments
        lines.append("# MacPulse Data Export")
        lines.append("# ExportedAt: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("# LifetimeEnergyWh: \(String(format: "%.4f", aggregateStats.lifetimeEnergyWh))")
        lines.append("# LifetimeBytesDownloaded: \(aggregateStats.lifetimeBytesDownloaded)")
        lines.append("# LifetimeBytesUploaded: \(aggregateStats.lifetimeBytesUploaded)")
        lines.append("# LifetimeAwakeDurationSeconds: \(String(format: "%.1f", aggregateStats.lifetimeAwakeSeconds))")
        lines.append("# TotalSessions: \(aggregateStats.totalSessionsCount)")
        lines.append("")
        
        // Column Header: Sessions
        lines.append("## SESSIONS")
        lines.append("SessionID,BootUUID,StartTime,EndTime,DurationSeconds,EnergyWh,BatteryEnergyWh,BytesDownloaded,BytesUploaded,TotalBytes,EndReason,PowerQuality,DetectionConfidence")
        
        let isoFormatter = ISO8601DateFormatter()
        for s in sessions {
            let start = isoFormatter.string(from: s.startTime)
            let end = s.endTime.map { isoFormatter.string(from: $0) } ?? "Active"
            let row = [
                s.id.uuidString,
                s.bootSessionUUID,
                start,
                end,
                String(format: "%.1f", s.durationSeconds),
                String(format: "%.4f", s.energyWh),
                String(format: "%.4f", s.batteryEnergyWh),
                "\(s.bytesDownloaded)",
                "\(s.bytesUploaded)",
                "\(s.totalCombinedBytes)",
                s.endReason.rawValue,
                s.powerQuality.rawValue,
                s.detectionConfidence.rawValue
            ].joined(separator: ",")
            lines.append(row)
        }
        
        if !appUsage.isEmpty {
            lines.append("")
            lines.append("## APPLICATION USAGE (Screen Time, Energy, Data)")
            lines.append("BundleIdentifier,AppName,ScreenOnSeconds,CpuTimeSeconds,EnergyWh,EnergyImpact,BytesDownloaded,BytesUploaded,TotalBytes,LastUpdated")
            for a in appUsage {
                let updated = isoFormatter.string(from: a.lastUpdated)
                let row = [
                    a.bundleIdentifier,
                    "\"\(a.appName.replacingOccurrences(of: "\"", with: "\"\""))\"",
                    String(format: "%.1f", a.screenOnTimeSeconds),
                    String(format: "%.2f", a.cpuTimeSeconds),
                    String(format: "%.4f", a.energyWh),
                    String(format: "%.1f", a.energyImpact),
                    "\(a.bytesDownloaded)",
                    "\(a.bytesUploaded)",
                    "\(a.totalCombinedBytes)",
                    updated
                ].joined(separator: ",")
                lines.append(row)
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Generates a JSON formatted string of the given sessions, summary, and app usage.
    public static func exportJSON(
        sessions: [UsageSession],
        aggregateStats: AggregateStats,
        appUsage: [AppUsageRecord] = []
    ) throws -> String {
        struct ExportPayload: Codable {
            let exportedAt: String
            let summary: AggregateStats
            let sessions: [UsageSession]
            let applicationUsage: [AppUsageRecord]
        }
        
        let payload = ExportPayload(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            summary: aggregateStats,
            sessions: sessions,
            applicationUsage: appUsage
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
