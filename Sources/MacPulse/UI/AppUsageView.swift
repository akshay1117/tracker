import SwiftUI
import AppKit
import Charts

/// Dedicated dashboard view tracking per-application Screen-on Time, Energy Consumption, and Data Usage.
/// Features direct one-click filter options (Data Usage as default, Screen Time, Energy Use, Name),
/// synchronized Swift Charts, tabular numbers, and precision column alignments.
public struct AppUsageView: View {
    @ObservedObject var appState: AppState
    
    @State private var timeScope: TimeScope = .activeApps
    @State private var filterOption: AppFilterOption = .dataUsage // Default: Data Usage!
    @State private var searchText: String = ""
    @State private var selectedApp: AppUsageRecord?
    @Namespace private var appFilterNamespace
    
    public enum TimeScope: String, CaseIterable, Identifiable {
        case activeApps = "Active Apps"
        case currentSession = "This Session"
        case lifetime = "All Sessions"
        
        public var id: String { rawValue }
    }
    
    public enum AppFilterOption: String, CaseIterable, Identifiable {
        case dataUsage = "Data Usage"
        case screenTime = "Screen Time"
        case energy = "Energy Use"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .dataUsage: return "wifi"
            case .screenTime: return "display"
            case .energy: return "bolt.fill"
            }
        }
        
        public var accentColor: Color {
            switch self {
            case .dataUsage: return .cyanAccent
            case .screenTime: return .blueAccent
            case .energy: return .amberAccent
            }
        }
    }
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private var rawRecords: [AppUsageRecord] {
        switch timeScope {
        case .activeApps:
            let running = appState.currentAppUsage.filter { $0.isRunning }
            return running.isEmpty ? appState.currentAppUsage : running
        case .currentSession:
            return appState.currentAppUsage
        case .lifetime:
            return appState.lifetimeAppUsage
        }
    }
    
    private var displayedRecords: [AppUsageRecord] {
        let records = rawRecords
        
        let filtered: [AppUsageRecord]
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            filtered = records
        } else {
            let q = searchText.lowercased()
            filtered = records.filter {
                $0.appName.lowercased().contains(q) || $0.bundleIdentifier.lowercased().contains(q)
            }
        }
        
        return filtered.sorted { a, b in
            switch filterOption {
            case .dataUsage:
                return a.totalCombinedBytes > b.totalCombinedBytes
            case .screenTime:
                return a.screenOnTimeSeconds > b.screenOnTimeSeconds
            case .energy:
                return a.energyWh > b.energyWh
            }
        }
    }
    
    private var chartRecords: [AppUsageRecord] {
        let sortedForChart: [AppUsageRecord]
        switch filterOption {
        case .dataUsage:
            sortedForChart = displayedRecords.sorted { $0.totalCombinedBytes > $1.totalCombinedBytes }
        case .screenTime:
            sortedForChart = displayedRecords.sorted { $0.screenOnTimeSeconds > $1.screenOnTimeSeconds }
        case .energy:
            sortedForChart = displayedRecords.sorted { $0.energyWh > $1.energyWh }
        }
        return Array(sortedForChart.prefix(7))
    }
    
    private var totalEnergyWh: Double {
        displayedRecords.reduce(0.0) { $0 + $1.energyWh }
    }
    
    private var totalDataBytes: Int64 {
        displayedRecords.reduce(0) { $0 + $1.totalCombinedBytes }
    }
    
    private var totalDataGB: Double {
        Double(totalDataBytes) / Double(UnitFormatter.Thresholds.bytesPerGB)
    }
    
    private var totalScreenTimeSeconds: TimeInterval {
        displayedRecords.reduce(0.0) { $0 + $1.screenOnTimeSeconds }
    }
    
    private var maxScreenTime: TimeInterval {
        displayedRecords.map(\.screenOnTimeSeconds).max() ?? 1.0
    }
    
    private var maxEnergy: Double {
        displayedRecords.map(\.energyWh).max() ?? 1.0
    }
    
    private var maxDataBytes: Int64 {
        displayedRecords.map(\.totalCombinedBytes).max() ?? 1
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // MARK: - Filter Bar & Controls
                VStack(spacing: 10) {
                    // Top Controls Row: Scope Picker + Search Field
                    HStack(spacing: 12) {
                        Picker("", selection: $timeScope) {
                            ForEach(TimeScope.allCases) { scope in
                                Text(scope.rawValue).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)
                        
                        Spacer()
                        
                        // Search Field
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                            
                            TextField("Search apps...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                            
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .frame(maxWidth: 200)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                        )
                    }
                    
                    // Direct Liquid Glass Filter Options (Data Usage is default)
                    HStack(spacing: 8) {
                        ForEach(AppFilterOption.allCases) { opt in
                            Button {
                                withAnimation(DesignSystem.liquidSpring) {
                                    filterOption = opt
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: opt.icon)
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(opt.rawValue)
                                        .font(.system(size: 11, weight: filterOption == opt ? .bold : .medium))
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .foregroundColor(filterOption == opt ? .white : .white.opacity(0.60))
                                .background(
                                    ZStack {
                                        if filterOption == opt {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [opt.accentColor.opacity(0.28), opt.accentColor.opacity(0.12)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .strokeBorder(
                                                            LinearGradient(
                                                                colors: [opt.accentColor.opacity(0.75), opt.accentColor.opacity(0.25)],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            ),
                                                            lineWidth: 1
                                                        )
                                                )
                                                .overlay(
                                                    DesignSystem.liquidGlassHighlight
                                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                                )
                                                .shadow(color: opt.accentColor.opacity(0.35), radius: 6, x: 0, y: 2)
                                                .matchedGeometryEffect(id: "liquidAppFilterPill", in: appFilterNamespace)
                                        } else {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.white.opacity(0.04))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                                                )
                                        }
                                    }
                                )
                            }
                            .buttonStyle(.liquidTactile(scale: 0.94))
                        }
                        
                        Spacer()
                    }
                }
                
                // MARK: - 4-Column Balanced Summary Badges
                HStack(spacing: 10) {
                    SummaryBadge(
                        title: "ACTIVE APPS",
                        value: "\(displayedRecords.count)",
                        subtitle: "\(displayedRecords.filter(\.isRunning).count) Running",
                        icon: "app.badge.checkmark",
                        color: .blueAccent
                    )
                    
                    SummaryBadge(
                        title: "TOTAL ENERGY",
                        value: UnitFormatter.formatEnergy(wattHours: totalEnergyWh),
                        subtitle: "Session Draw",
                        icon: "bolt.fill",
                        color: .amberAccent
                    )
                    
                    SummaryBadge(
                        title: "WI-FI USAGE",
                        value: UnitFormatter.formatDataSize(bytes: totalDataBytes),
                        subtitle: "Combined Traffic",
                        icon: "wifi",
                        color: .cyanAccent
                    )
                    
                    SummaryBadge(
                        title: "SCREEN TIME",
                        value: UnitFormatter.formatDuration(seconds: totalScreenTimeSeconds),
                        subtitle: "Foreground Awake",
                        icon: "display",
                        color: .emeraldAccent
                    )
                }
                
                // MARK: - Swift Charts Section (Directly synchronized with active filter)
                if !displayedRecords.isEmpty {
                    MetricCard(
                        title: chartTitle,
                        subtitle: "Top Applications",
                        icon: filterOption.icon,
                        accentColor: filterOption.accentColor
                    ) {
                        Chart(chartRecords) { record in
                            BarMark(
                                x: .value("App", record.appName),
                                y: .value("Value", chartValue(for: record))
                            )
                            .foregroundStyle(filterOption.accentColor)
                            .cornerRadius(4)
                            .annotation(position: .top, spacing: 3) {
                                Text(chartAnnotation(for: record))
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.85))
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .frame(height: 120)
                    }
                }
                
                // MARK: - Columnar Applications Table
                MetricCard(
                    title: "Application Usage Table",
                    subtitle: "\(displayedRecords.count) Applications Tracked",
                    icon: "list.bullet.rectangle",
                    accentColor: .blueAccent
                ) {
                    VStack(spacing: 6) {
                        // Table Column Headers
                        HStack(spacing: 8) {
                            Text("APPLICATION")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.40))
                                .tracking(0.6)
                            
                            Spacer()
                            
                            Text("SCREEN TIME")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.40))
                                .tracking(0.6)
                                .frame(width: 95, alignment: .trailing)
                            
                            Text("ENERGY")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.40))
                                .tracking(0.6)
                                .frame(width: 85, alignment: .trailing)
                            
                            Text("WI-FI")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.40))
                                .tracking(0.6)
                                .frame(width: 85, alignment: .trailing)
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 2)
                        
                        Divider().background(Color.white.opacity(0.06))
                        
                        if displayedRecords.isEmpty {
                            VStack(spacing: 8) {
                                Text("No applications recorded yet.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(displayedRecords) { record in
                                    Button {
                                        selectedApp = record
                                    } label: {
                                        AppUsageRow(
                                            record: record,
                                            filterOption: filterOption,
                                            maxScreenTime: maxScreenTime,
                                            maxEnergy: maxEnergy,
                                            maxData: maxDataBytes
                                        )
                                    }
                                    .buttonStyle(.liquidTactile(scale: 0.985))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .sheet(item: $selectedApp) { record in
            AppDetailSheet(record: record)
        }
    }
    
    private var chartTitle: String {
        switch filterOption {
        case .dataUsage:
            return "Wi-Fi Data Usage"
        case .screenTime:
            return "Screen Time"
        case .energy:
            return "Energy Consumption"
        }
    }
    
    private func chartValue(for record: AppUsageRecord) -> Double {
        switch filterOption {
        case .dataUsage:
            return record.dataUsageGB
        case .screenTime:
            return record.screenOnTimeHours
        case .energy:
            return record.energyWh
        }
    }
    
    private func chartAnnotation(for record: AppUsageRecord) -> String {
        switch filterOption {
        case .dataUsage:
            return UnitFormatter.formatDataSize(bytes: record.totalCombinedBytes)
        case .screenTime:
            return UnitFormatter.formatDuration(seconds: record.screenOnTimeSeconds)
        case .energy:
            return UnitFormatter.formatEnergy(wattHours: record.energyWh)
        }
    }
}

// MARK: - Balanced Summary Badge
private struct SummaryBadge: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(0.6)
            }
            
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(1)
            
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.40))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignSystem.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DesignSystem.glassBorderGradient, lineWidth: 1)
        )
    }
}

// MARK: - App Usage Row
private struct AppUsageRow: View {
    let record: AppUsageRecord
    let filterOption: AppUsageView.AppFilterOption
    let maxScreenTime: TimeInterval
    let maxEnergy: Double
    let maxData: Int64
    
    private var progressRatio: Double {
        switch filterOption {
        case .screenTime:
            return maxScreenTime > 0 ? (record.screenOnTimeSeconds / maxScreenTime) : 0
        case .energy:
            return maxEnergy > 0 ? (record.energyWh / maxEnergy) : 0
        case .dataUsage:
            return maxData > 0 ? (Double(record.totalCombinedBytes) / Double(maxData)) : 0
        }
    }
    
    private var progressColor: Color {
        filterOption.accentColor
    }
    
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                // Application Icon
                AppIconImageView(bundleIdentifier: record.bundleIdentifier, appName: record.appName)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                
                // Name & Running/Active Status
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(record.appName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if record.isFrontmost {
                            Text("ACTIVE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.emeraldAccent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.emeraldAccent.opacity(0.12))
                                .cornerRadius(3)
                        } else if record.isRunning {
                            Text("RUNNING")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.blueAccent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blueAccent.opacity(0.12))
                                .cornerRadius(3)
                        }
                    }
                    
                    Text(record.bundleIdentifier)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.40))
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Tabular Metrics (Screen Time in h&m, Energy in Wh, Data in GB)
                Text(record.formattedScreenTimeHoursAndMinutes)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .monospacedDigit()
                    .frame(width: 95, alignment: .trailing)
                
                Text(record.formattedEnergyWh)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.amberAccent)
                    .monospacedDigit()
                    .frame(width: 85, alignment: .trailing)
                
                Text(record.formattedDataUsageGB)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyanAccent)
                    .monospacedDigit()
                    .frame(width: 85, alignment: .trailing)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            
            // Relative Usage Progress Bar
            if progressRatio > 0.005 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 3)
                        Capsule()
                            .fill(progressColor)
                            .frame(width: max(4, geo.size.width * CGFloat(min(1.0, progressRatio))), height: 3)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
            }
        }
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(record.isFrontmost ? Color.white.opacity(0.04) : Color.clear)
        )
    }
}

// MARK: - Native App Icon View
struct AppIconImageView: View {
    let bundleIdentifier: String
    let appName: String
    
    private var iconImage: NSImage {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return app.icon ?? defaultIcon
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return defaultIcon
    }
    
    private var defaultIcon: NSImage {
        if bundleIdentifier.hasPrefix("daemon.") {
            return NSImage(systemSymbolName: "gearshape.2.fill", accessibilityDescription: nil) ?? NSImage()
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
    }
    
    var body: some View {
        Image(nsImage: iconImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}

// MARK: - App Detail Sheet
private struct AppDetailSheet: View {
    let record: AppUsageRecord
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                AppIconImageView(bundleIdentifier: record.bundleIdentifier, appName: record.appName)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.appName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(record.bundleIdentifier)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.liquidTactile(scale: 0.94))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 4)
            
            VStack(spacing: 8) {
                DetailRow(label: "Screen-On Time", value: record.formattedScreenTimeHoursAndMinutes)
                DetailRow(label: "State", value: record.isFrontmost ? "Active (Foreground)" : (record.isRunning ? "Running in Background" : "Saved from Session"))
                Divider().background(Color.white.opacity(0.08))
                DetailRow(label: "Energy Consumed", value: record.formattedEnergyWh)
                DetailRow(label: "Energy Impact (CPU %)", value: String(format: "%.1f %%", record.energyImpact))
                DetailRow(label: "Total CPU Time", value: String(format: "%.2f s", record.cpuTimeSeconds))
                Divider().background(Color.white.opacity(0.08))
                DetailRow(label: "Wi-Fi Usage", value: record.formattedDataUsageGB)
                DetailRow(label: "Data Downloaded", value: NetworkSnapshot.formatBytes(record.bytesDownloaded))
                DetailRow(label: "Data Uploaded", value: NetworkSnapshot.formatBytes(record.bytesUploaded))
                DetailRow(label: "Total Bytes", value: record.formattedTotalBytes)
            }
            .padding(12)
            .background(DesignSystem.cardBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(DesignSystem.glassBorderGradient, lineWidth: 1)
            )
        }
        .padding(18)
        .frame(width: 360)
        .background(DesignSystem.windowBackground)
    }
}
