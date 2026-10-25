import SwiftUI
import Charts

/// History view displaying daily/weekly aggregated charts, filter options, and session history.
/// Spacious layout with 1-click filter pills, balanced grids, and tabular metrics.
public struct HistoryView: View {
    @ObservedObject var appState: AppState
    @State private var selectedSession: UsageSession?
    @State private var chartMetric: ChartMetric = .energy
    @State private var timeRange: HistoryTimeRange = .sevenDays
    @State private var rangeSessions: [UsageSession] = []
    @Namespace private var historyMetricNamespace
    @Namespace private var historyTimeRangeNamespace
    
    public enum HistoryTimeRange: String, CaseIterable, Identifiable {
        case sevenDays = "7 Days"
        case monthly = "30 Days"
        case threeMonths = "3 Months"
        case yearly = "1 Year"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .sevenDays: return "calendar"
            case .monthly: return "calendar.badge.clock"
            case .threeMonths: return "chart.bar.xaxis"
            case .yearly: return "clock.arrow.2.circlepath"
            }
        }
        
        public var numberOfDays: Int {
            switch self {
            case .sevenDays: return 7
            case .monthly: return 30
            case .threeMonths: return 90
            case .yearly: return 365
            }
        }
        
        public var badgePrefix: String {
            switch self {
            case .sevenDays: return "7D"
            case .monthly: return "30D"
            case .threeMonths: return "3M"
            case .yearly: return "1Y"
            }
        }
    }
    
    public enum ChartMetric: String, CaseIterable, Identifiable {
        case energy = "Energy (Wh)"
        case network = "Wi-Fi (GB)"
        case duration = "Screen Time (h & m)"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .energy: return "bolt.fill"
            case .network: return "wifi"
            case .duration: return "display"
            }
        }
        
        public var accentColor: Color {
            switch self {
            case .energy: return .amberAccent
            case .network: return .cyanAccent
            case .duration: return .blueAccent
            }
        }
    }
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private func loadSessions() {
        let calendar = Calendar.current
        let now = Date()
        let days = timeRange.numberOfDays
        let startDate = calendar.date(byAdding: .day, value: -days, to: now) ?? now.addingTimeInterval(-Double(days) * 86400)
        
        var fetched = appState.database.fetchSessionsSince(date: startDate)
        if let current = appState.currentSession, current.startTime >= startDate {
            if !fetched.contains(where: { $0.id == current.id }) {
                fetched.append(current)
            }
        }
        self.rangeSessions = fetched.sorted { $0.startTime > $1.startTime }
    }
    
    private var totalRangeEnergy: Double {
        let list = rangeSessions.isEmpty ? appState.recentSessions : rangeSessions
        return list.reduce(0.0) { $0 + $1.energyWh }
    }
    
    private var totalRangeBytes: Int64 {
        let list = rangeSessions.isEmpty ? appState.recentSessions : rangeSessions
        return list.reduce(0) { $0 + $1.totalCombinedBytes }
    }
    
    private var totalRangeDurationSeconds: TimeInterval {
        let list = rangeSessions.isEmpty ? appState.recentSessions : rangeSessions
        return list.reduce(0.0) { $0 + $1.durationSeconds }
    }
    
    private var displayedSessions: [UsageSession] {
        let list = rangeSessions.isEmpty ? appState.recentSessions : rangeSessions
        return Array(list.prefix(100))
    }
    
    private var chartBuckets: [HistoryBucketSummary] {
        let calendar = Calendar.current
        let now = Date()
        let sessions = rangeSessions.isEmpty ? appState.recentSessions : rangeSessions
        
        switch timeRange {
        case .sevenDays:
            let today = calendar.startOfDay(for: now)
            var buckets: [Date: (energy: Double, bytes: Int64, duration: TimeInterval)] = [:]
            for i in (0..<7).reversed() {
                if let d = calendar.date(byAdding: .day, value: -i, to: today) {
                    buckets[d] = (0, 0, 0)
                }
            }
            for s in sessions {
                let day = calendar.startOfDay(for: s.startTime)
                if let cur = buckets[day] {
                    buckets[day] = (cur.energy + s.energyWh, cur.bytes + s.totalCombinedBytes, cur.duration + s.durationSeconds)
                }
            }
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "E"
            return buckets.keys.sorted().compactMap { date in
                guard let val = buckets[date] else { return nil }
                return HistoryBucketSummary(
                    id: date.description,
                    date: date,
                    label: dayFormatter.string(from: date),
                    energyWh: val.energy,
                    bytes: val.bytes,
                    durationSeconds: val.duration
                )
            }
            
        case .monthly:
            let today = calendar.startOfDay(for: now)
            var buckets: [Date: (energy: Double, bytes: Int64, duration: TimeInterval)] = [:]
            for i in (0..<30).reversed() {
                if let d = calendar.date(byAdding: .day, value: -i, to: today) {
                    buckets[d] = (0, 0, 0)
                }
            }
            for s in sessions {
                let day = calendar.startOfDay(for: s.startTime)
                if let cur = buckets[day] {
                    buckets[day] = (cur.energy + s.energyWh, cur.bytes + s.totalCombinedBytes, cur.duration + s.durationSeconds)
                }
            }
            let monthDayFormatter = DateFormatter()
            monthDayFormatter.dateFormat = "d"
            return buckets.keys.sorted().compactMap { date in
                guard let val = buckets[date] else { return nil }
                return HistoryBucketSummary(
                    id: date.description,
                    date: date,
                    label: monthDayFormatter.string(from: date),
                    energyWh: val.energy,
                    bytes: val.bytes,
                    durationSeconds: val.duration
                )
            }
            
        case .threeMonths:
            var weekBuckets: [(start: Date, end: Date, label: String, energy: Double, bytes: Int64, duration: TimeInterval)] = []
            let weekFormatter = DateFormatter()
            weekFormatter.dateFormat = "MMM d"
            
            var cursorEnd = now
            for _ in 0..<12 {
                let cursorStart = calendar.date(byAdding: .day, value: -7, to: cursorEnd) ?? cursorEnd.addingTimeInterval(-7 * 86400)
                weekBuckets.append((cursorStart, cursorEnd, weekFormatter.string(from: cursorStart), 0, 0, 0))
                cursorEnd = cursorStart
            }
            weekBuckets.reverse()
            
            for s in sessions {
                for i in 0..<weekBuckets.count {
                    if s.startTime >= weekBuckets[i].start && s.startTime < weekBuckets[i].end {
                        weekBuckets[i].energy += s.energyWh
                        weekBuckets[i].bytes += s.totalCombinedBytes
                        weekBuckets[i].duration += s.durationSeconds
                        break
                    }
                }
            }
            
            return weekBuckets.map { b in
                HistoryBucketSummary(
                    id: b.start.description,
                    date: b.start,
                    label: b.label,
                    energyWh: b.energy,
                    bytes: b.bytes,
                    durationSeconds: b.duration
                )
            }
            
        case .yearly:
            var monthBuckets: [(date: Date, label: String, energy: Double, bytes: Int64, duration: TimeInterval)] = []
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMM"
            
            for i in (0..<12).reversed() {
                if let mDate = calendar.date(byAdding: .month, value: -i, to: now) {
                    let comps = calendar.dateComponents([.year, .month], from: mDate)
                    if let startOfMonth = calendar.date(from: comps) {
                        monthBuckets.append((startOfMonth, monthFormatter.string(from: startOfMonth), 0, 0, 0))
                    }
                }
            }
            
            for s in sessions {
                let sComps = calendar.dateComponents([.year, .month], from: s.startTime)
                guard let sMonth = calendar.date(from: sComps) else { continue }
                for i in 0..<monthBuckets.count {
                    if calendar.isDate(monthBuckets[i].date, equalTo: sMonth, toGranularity: .month) {
                        monthBuckets[i].energy += s.energyWh
                        monthBuckets[i].bytes += s.totalCombinedBytes
                        monthBuckets[i].duration += s.durationSeconds
                        break
                    }
                }
            }
            
            return monthBuckets.map { b in
                HistoryBucketSummary(
                    id: b.date.description,
                    date: b.date,
                    label: b.label,
                    energyWh: b.energy,
                    bytes: b.bytes,
                    durationSeconds: b.duration
                )
            }
        }
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // MARK: - Time Range Scope Selector (7 Days, 30 Days, 3 Months, 1 Year)
                HStack(spacing: 8) {
                    ForEach(HistoryTimeRange.allCases) { range in
                        Button {
                            withAnimation(DesignSystem.liquidSpring) {
                                timeRange = range
                                loadSessions()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: range.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(range.rawValue)
                                    .font(.system(size: 11, weight: timeRange == range ? .bold : .medium))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .foregroundColor(timeRange == range ? .white : .white.opacity(0.60))
                            .background(
                                ZStack {
                                    if timeRange == range {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.cyanAccent.opacity(0.28), Color.cyanAccent.opacity(0.12)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .strokeBorder(
                                                        LinearGradient(
                                                            colors: [Color.cyanAccent.opacity(0.75), Color.cyanAccent.opacity(0.25)],
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
                                            .shadow(color: Color.cyanAccent.opacity(0.35), radius: 6, x: 0, y: 2)
                                            .matchedGeometryEffect(id: "liquidHistoryRangePill", in: historyTimeRangeNamespace)
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
                
                // MARK: - Selected Time Range Metric Totals (3-Column Grid)
                HStack(spacing: 12) {
                    MetricSummaryBadge(
                        title: "\(timeRange.badgePrefix) TOTAL ENERGY",
                        value: UnitFormatter.formatEnergy(wattHours: totalRangeEnergy),
                        subtitle: "\(timeRange.rawValue) Rolling",
                        icon: "bolt.fill",
                        color: .amberAccent
                    )
                    
                    MetricSummaryBadge(
                        title: "\(timeRange.badgePrefix) WI-FI USAGE",
                        value: UnitFormatter.formatDataSize(bytes: totalRangeBytes),
                        subtitle: "\(timeRange.rawValue) Traffic",
                        icon: "wifi",
                        color: .cyanAccent
                    )
                    
                    MetricSummaryBadge(
                        title: "\(timeRange.badgePrefix) SCREEN TIME",
                        value: UnitFormatter.formatDuration(seconds: totalRangeDurationSeconds),
                        subtitle: "\(timeRange.rawValue) Awake",
                        icon: "display",
                        color: .blueAccent
                    )
                }
                
                // MARK: - Swift Charts Section with Direct Filter Pills
                MetricCard(
                    title: "Activity (\(timeRange.rawValue))",
                    subtitle: chartMetric.rawValue,
                    icon: "chart.xyaxis.line",
                    accentColor: chartMetric.accentColor
                ) {
                    VStack(spacing: 12) {
                        // 1-Click Liquid Glass Chart Metric Selector Pills
                        HStack(spacing: 8) {
                            ForEach(ChartMetric.allCases) { m in
                                Button {
                                    withAnimation(DesignSystem.liquidSpring) {
                                        chartMetric = m
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: m.icon)
                                            .font(.system(size: 10, weight: .semibold))
                                        Text(m.rawValue)
                                            .font(.system(size: 11, weight: chartMetric == m ? .bold : .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 28)
                                    .foregroundColor(chartMetric == m ? .white : .white.opacity(0.60))
                                    .background(
                                        ZStack {
                                            if chartMetric == m {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [m.accentColor.opacity(0.28), m.accentColor.opacity(0.12)],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .strokeBorder(
                                                                LinearGradient(
                                                                    colors: [m.accentColor.opacity(0.75), m.accentColor.opacity(0.25)],
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
                                                    .shadow(color: m.accentColor.opacity(0.35), radius: 6, x: 0, y: 2)
                                                    .matchedGeometryEffect(id: "liquidHistoryMetricPill", in: historyMetricNamespace)
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
                        
                        Divider().background(Color.white.opacity(0.06))
                        
                        // Chart Visualization
                        if #available(macOS 13.0, *) {
                            Chart(chartBuckets) { item in
                                BarMark(
                                    x: .value("Period", item.dayLabel),
                                    y: .value("Value", item.value(for: chartMetric))
                                )
                                .foregroundStyle(item.barColor(for: chartMetric))
                                .cornerRadius(4)
                                .annotation(position: .top, spacing: 3) {
                                    if item.value(for: chartMetric) > 0.001 {
                                        Text(item.formattedValue(for: chartMetric))
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.90))
                                    }
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading)
                            }
                            .frame(height: 130)
                        } else {
                            Text("Charts require macOS 13 or newer.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // MARK: - Session History List (Columnar Table)
                MetricCard(
                    title: "Session History",
                    subtitle: "\(displayedSessions.count) Sessions (\(timeRange.rawValue))",
                    icon: "clock.arrow.circlepath",
                    accentColor: .emeraldAccent
                ) {
                    VStack(spacing: 8) {
                        if displayedSessions.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white.opacity(0.3))
                                Text("No finalized sessions in this period.")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                Text("Sessions automatically record and finalize when the display sleeps or the lid closes.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                        } else {
                            // Column Headers
                            HStack(spacing: 8) {
                                Text("SESSION / REASON")
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
                            .padding(.horizontal, 8)
                            .padding(.bottom, 2)
                            
                            Divider().background(Color.white.opacity(0.06))
                            
                            // Rows
                            LazyVStack(spacing: 6) {
                                ForEach(displayedSessions) { session in
                                    Button {
                                        selectedSession = session
                                    } label: {
                                        SessionRowView(session: session)
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
        .onAppear {
            loadSessions()
        }
        .onChange(of: timeRange) { _, _ in
            loadSessions()
        }
        .onReceive(appState.$recentSessions) { _ in
            loadSessions()
        }
        .sheet(item: $selectedSession) { session in
            SessionDetailSheet(session: session, appState: appState)
        }
    }
}

// MARK: - Metric Summary Badge
private struct MetricSummaryBadge: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(0.6)
            }
            
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(1)
            
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.40))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignSystem.cardBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DesignSystem.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Time Range Summary Bucket Model
struct HistoryBucketSummary: Identifiable {
    let id: String
    let date: Date
    let label: String
    let energyWh: Double
    let bytes: Int64
    let durationSeconds: TimeInterval
    
    var dataGB: Double {
        Double(bytes) / Double(UnitFormatter.Thresholds.bytesPerGB)
    }
    
    var durationHours: Double {
        durationSeconds / Double(UnitFormatter.Thresholds.secondsPerHour)
    }
    
    var formattedScreenTime: String {
        UnitFormatter.formatDuration(seconds: durationSeconds)
    }
    
    var dayLabel: String { label }
    
    func value(for metric: HistoryView.ChartMetric) -> Double {
        switch metric {
        case .energy: return energyWh
        case .network: return dataGB
        case .duration: return durationHours
        }
    }
    
    func formattedValue(for metric: HistoryView.ChartMetric) -> String {
        switch metric {
        case .energy:
            return UnitFormatter.formatEnergy(wattHours: energyWh)
        case .network:
            return UnitFormatter.formatDataSize(bytes: bytes)
        case .duration:
            return UnitFormatter.formatDuration(seconds: durationSeconds)
        }
    }
    
    func barColor(for metric: HistoryView.ChartMetric) -> Color {
        switch metric {
        case .energy: return .amberAccent
        case .network: return .cyanAccent
        case .duration: return .blueAccent
        }
    }
}
typealias DailySummary = HistoryBucketSummary

// MARK: - Session Row View
struct SessionRowView: View {
    let session: UsageSession
    
    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 28, height: 28)
                
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(dateFormatter.string(from: session.startTime))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(session.endReason.displayTitle)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(3)
                }
                
                Text(session.powerQuality.rawValue)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.40))
            }
            
            Spacer()
            
            // Screen Time
            Text(session.formattedDurationHoursAndMinutes)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .monospacedDigit()
                .frame(width: 95, alignment: .trailing)
            
            // Energy
            Text(UnitFormatter.formatEnergy(wattHours: session.energyWh))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.amberAccent)
                .monospacedDigit()
                .frame(width: 85, alignment: .trailing)
            
            // Wi-Fi
            Text(session.formattedDataGB)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.cyanAccent)
                .monospacedDigit()
                .frame(width: 85, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.03))
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Session Detail Inspector Sheet
struct SessionDetailSheet: View {
    let session: UsageSession
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    private var appsForSession: [AppUsageRecord] {
        if session.id == appState.currentSession?.id {
            return appState.currentAppUsage
        }
        return appState.database.fetchAppUsage(sessionId: session.id)
    }
    
    private var fullDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 16) {
                // Header Row
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Session Inspection")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text(session.id.uuidString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
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
                
                // Detailed Metrics Card
                VStack(spacing: 8) {
                    DetailRow(label: "Start Time", value: fullDateFormatter.string(from: session.startTime))
                    DetailRow(label: "End Time", value: session.endTime.map { fullDateFormatter.string(from: $0) } ?? "Active Session")
                    DetailRow(label: "Awake Duration", value: UnitFormatter.formatDuration(seconds: session.durationSeconds))
                    DetailRow(label: "Termination Reason", value: session.endReason.displayTitle)
                    DetailRow(label: "Detection Confidence", value: session.detectionConfidence.displayTitle)
                    
                    Divider().background(Color.white.opacity(0.08))
                    
                    DetailRow(label: "System Energy Consumed", value: UnitFormatter.formatEnergy(wattHours: session.energyWh))
                    DetailRow(label: "Battery Energy Consumed", value: UnitFormatter.formatEnergy(wattHours: session.batteryEnergyWh))
                    DetailRow(label: "Power Quality Assessment", value: session.powerQuality.rawValue)
                    
                    Divider().background(Color.white.opacity(0.08))
                    
                    DetailRow(label: "Wi-Fi Downloaded", value: UnitFormatter.formatDataSize(bytes: session.bytesDownloaded))
                    DetailRow(label: "Wi-Fi Uploaded", value: UnitFormatter.formatDataSize(bytes: session.bytesUploaded))
                    DetailRow(label: "Total Data Usage", value: UnitFormatter.formatDataSize(bytes: session.totalCombinedBytes))
                    DetailRow(label: "Kernel Boot UUID", value: session.bootSessionUUID)
                }
                .padding(14)
                .background(DesignSystem.cardBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DesignSystem.cardBorder, lineWidth: 1)
                )
                
                // Application Breakdown Section
                if !appsForSession.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("APPLICATION BREAKDOWN (\(appsForSession.count))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.40))
                            .tracking(0.6)
                        
                        VStack(spacing: 6) {
                            ForEach(appsForSession.prefix(12)) { app in
                                HStack(spacing: 8) {
                                    AppIconImageView(bundleIdentifier: app.bundleIdentifier, appName: app.appName)
                                        .frame(width: 22, height: 22)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(app.appName)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(app.bundleIdentifier)
                                            .font(.system(size: 8))
                                            .foregroundColor(.white.opacity(0.4))
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 8) {
                                        Text(app.formattedScreenTimeHoursAndMinutes)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.75))
                                            .frame(width: 80, alignment: .trailing)
                                        
                                        Text(app.formattedEnergyWh)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.amberAccent)
                                            .frame(width: 75, alignment: .trailing)
                                        
                                        Text(app.formattedDataUsageGB)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.cyanAccent)
                                            .frame(width: 75, alignment: .trailing)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.03))
                                .cornerRadius(5)
                            }
                        }
                    }
                    .padding(14)
                    .background(DesignSystem.cardBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DesignSystem.cardBorder, lineWidth: 1)
                    )
                }
            }
            .padding(20)
        }
        .frame(width: 500, height: 560)
        .background(DesignSystem.windowBackground)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }
}
