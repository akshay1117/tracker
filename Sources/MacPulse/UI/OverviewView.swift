import SwiftUI

/// Overview tab displaying real-time live power draw, network throughput, session totals, and lifetime stats.
/// Precision alignment, balanced grids, and tabular numbers.
public struct OverviewView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // MARK: - Live Meters (Power & Network)
                HStack(spacing: 12) {
                    // Power Card
                    MetricCard(
                        title: "Live Power Draw",
                        subtitle: appState.lastPower?.telemetrySource.rawValue ?? "PMU",
                        icon: "bolt.fill",
                        accentColor: .amberAccent
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(appState.lastPower?.formattedPowerWatts ?? "– W")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .monospacedDigit()
                            
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(confidenceColor(appState.lastPower?.confidence))
                                    .frame(width: 6, height: 6)
                                Text(appState.lastPower?.confidence.displayLabel ?? "Active Sensor")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            
                            Divider().background(Color.white.opacity(0.08))
                            
                            HStack {
                                if let p = appState.lastPower {
                                    if let pct = p.batteryPercent {
                                        Text("\(pct)%")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.85))
                                    }
                                    Text(p.isPluggedIn ? "AC Connected" : "Battery Power")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.55))
                                    
                                    Spacer()
                                    
                                    if let v = p.batteryVoltageVolts {
                                        Text(String(format: "%.1fV", v))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.45))
                                    }
                                } else {
                                    Text("Sampling...")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.4))
                                    Spacer()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Network Card
                    MetricCard(
                        title: "Live Wi-Fi Speed",
                        subtitle: appState.lastNetwork?.interfaceName ?? "en0",
                        icon: "wifi",
                        accentColor: .cyanAccent
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(appState.lastNetwork?.formattedDownloadSpeed ?? "↓ 0 B/s")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .monospacedDigit()
                            }
                            
                            HStack(spacing: 5) {
                                Text(appState.lastNetwork?.formattedUploadSpeed ?? "↑ 0 B/s")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.6))
                                    .monospacedDigit()
                            }
                            
                            Divider().background(Color.white.opacity(0.08))
                            
                            HStack {
                                Circle()
                                    .fill((appState.lastNetwork?.isConnected ?? false) ? Color.emeraldAccent : Color.gray)
                                    .frame(width: 6, height: 6)
                                Text((appState.lastNetwork?.isConnected ?? false) ? "Wi-Fi Connected" : "Disconnected")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.55))
                                
                                Spacer()
                                
                                Text("802.11ax")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // MARK: - Current Session (Equal 3 Columns)
                MetricCard(
                    title: "Current Session",
                    subtitle: "Lid Open Interval",
                    icon: "timer",
                    accentColor: .blueAccent
                ) {
                    HStack(spacing: 0) {
                        // 1. Session Energy
                        VStack(alignment: .leading, spacing: 3) {
                            Text("TOTAL ENERGY")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.45))
                                .tracking(0.6)
                            
                            Text(UnitFormatter.formatEnergy(wattHours: appState.currentSession?.energyWh ?? 0.0))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.amberAccent)
                                .monospacedDigit()
                            
                            Text("Apple Silicon PMU")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Divider().background(Color.white.opacity(0.08)).frame(height: 48)
                        
                        // 2. Wi-Fi Usage
                        VStack(alignment: .leading, spacing: 3) {
                            Text("WI-FI USAGE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.45))
                                .tracking(0.6)
                            
                            Text(UnitFormatter.formatDataSize(bytes: appState.currentSession?.totalCombinedBytes ?? 0))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.cyanAccent)
                                .monospacedDigit()
                            
                            Text("\(UnitFormatter.formatDataSize(bytes: appState.currentSession?.bytesDownloaded ?? 0)) In")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                        
                        Divider().background(Color.white.opacity(0.08)).frame(height: 48)
                        
                        // 3. Screen Time
                        VStack(alignment: .leading, spacing: 3) {
                            Text("SCREEN TIME")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.45))
                                .tracking(0.6)
                            
                            Text(UnitFormatter.formatDuration(seconds: appState.currentSession?.durationSeconds ?? 0))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.emeraldAccent)
                                .monospacedDigit()
                            
                            Text("Awake Duration")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                    }
                    .padding(.vertical, 4)
                }
                
                // MARK: - Active Applications (Structured Columnar Table - Top 5)
                if !appState.currentAppUsage.isEmpty {
                    let activeApps = appState.currentAppUsage.sorted {
                        if $0.isFrontmost != $1.isFrontmost { return $0.isFrontmost }
                        if $0.isRunning != $1.isRunning { return $0.isRunning }
                        if $0.totalCombinedBytes != $1.totalCombinedBytes {
                            return $0.totalCombinedBytes > $1.totalCombinedBytes
                        }
                        if $0.screenOnTimeSeconds != $1.screenOnTimeSeconds {
                            return $0.screenOnTimeSeconds > $1.screenOnTimeSeconds
                        }
                        return $0.appName < $1.appName
                    }
                    let top5Apps = Array(activeApps.prefix(5))
                    
                    MetricCard(
                        title: "Top Applications",
                        subtitle: "Top \(top5Apps.count) of \(activeApps.filter(\.isRunning).count) Running",
                        icon: "app.badge.checkmark",
                        accentColor: .blueAccent
                    ) {
                        VStack(spacing: 8) {
                            // Column Headers
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
                            .padding(.horizontal, 8)
                            .padding(.bottom, 2)
                            
                            Divider().background(Color.white.opacity(0.06))
                            
                            ForEach(top5Apps) { app in
                                HStack(spacing: 10) {
                                    AppIconImageView(bundleIdentifier: app.bundleIdentifier, appName: app.appName)
                                        .frame(width: 24, height: 24)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 5) {
                                            Text(app.appName)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            
                                            if app.isFrontmost {
                                                Text("ACTIVE")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundColor(.emeraldAccent)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.emeraldAccent.opacity(0.12))
                                                    .cornerRadius(3)
                                            } else if app.isRunning {
                                                Text("RUNNING")
                                                    .font(.system(size: 8, weight: .semibold))
                                                    .foregroundColor(.blueAccent)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.blueAccent.opacity(0.12))
                                                    .cornerRadius(3)
                                            }
                                        }
                                        
                                        Text(app.bundleIdentifier)
                                            .font(.system(size: 9))
                                            .foregroundColor(.white.opacity(0.40))
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    // Screen Time (Hours & Minutes)
                                    Text(app.formattedScreenTimeHoursAndMinutes)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.85))
                                        .monospacedDigit()
                                        .frame(width: 95, alignment: .trailing)
                                    
                                    // Energy (Wh)
                                    Text(app.formattedEnergyWh)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.amberAccent)
                                        .monospacedDigit()
                                        .frame(width: 85, alignment: .trailing)
                                    
                                    // Wi-Fi (GB)
                                    Text(app.formattedDataUsageGB)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.cyanAccent)
                                        .monospacedDigit()
                                        .frame(width: 85, alignment: .trailing)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(app.isFrontmost ? Color.white.opacity(0.04) : Color.clear)
                                )
                            }
                            
                            if activeApps.count > 5 {
                                Divider().background(Color.white.opacity(0.06))
                                Text("Showing top 5 of \(activeApps.count) applications • View all in Apps tab")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.40))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 4)
                            }
                        }
                    }
                }
                
                // MARK: - Lifetime Statistics (Balanced 3 Columns)
                MetricCard(
                    title: "Lifetime Statistics",
                    subtitle: "\(appState.aggregateStats.totalSessionsCount) Total Sessions",
                    icon: "chart.bar.xaxis",
                    accentColor: .emeraldAccent
                ) {
                    HStack(spacing: 0) {
                        // 1. Lifetime Energy
                        VStack(alignment: .leading, spacing: 3) {
                            Text("LIFETIME ENERGY")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.45))
                                .tracking(0.6)
                            Text(appState.aggregateStats.formattedLifetimeEnergy)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.amberAccent)
                                .monospacedDigit()
                            Text("\(UnitFormatter.formatEnergy(wattHours: appState.aggregateStats.lifetimeEnergyWh)) Total")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Divider().background(Color.white.opacity(0.08)).frame(height: 44)
                        
                        // 2. Lifetime Wi-Fi
                        VStack(alignment: .leading, spacing: 3) {
                            Text("LIFETIME WI-FI")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.45))
                                .tracking(0.6)
                            Text(UnitFormatter.formatDataSize(bytes: appState.aggregateStats.lifetimeTotalBytes))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.cyanAccent)
                                .monospacedDigit()
                            Text("↓ \(UnitFormatter.formatDataSize(bytes: appState.aggregateStats.lifetimeBytesDownloaded)) In")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                        
                        Divider().background(Color.white.opacity(0.08)).frame(height: 44)
                        
                        // 3. Total Uptime
                        VStack(alignment: .leading, spacing: 3) {
                            Text("TOTAL UPTIME")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.45))
                                .tracking(0.6)
                            Text(appState.formattedLifetimeAwake)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.emeraldAccent)
                                .monospacedDigit()
                            Text("System: \(appState.formattedSystemUptime)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
    }
    
    private func confidenceColor(_ confidence: PowerConfidence?) -> Color {
        switch confidence {
        case .directHardware: return .emeraldAccent
        case .batteryDerived: return .blueAccent
        case .estimated: return .amberAccent
        case .unavailable, .none: return .gray
        }
    }
}
