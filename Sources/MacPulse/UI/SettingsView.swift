import SwiftUI
import AppKit

/// Settings tab for configuring display modes, session policies, export, and reset.
/// Clean architectural alignment, custom buttons, and transparent system telemetry notes.
public struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var showingResetAlert: Bool = false
    @State private var exportNotification: String? = nil
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // MARK: - Menu Bar Appearance
                MetricCard(title: "Menu Bar Display", subtitle: "Status Item Configuration", icon: "menubar.rectangle", accentColor: .amberAccent) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Show in macOS Menu Bar", isOn: $appState.showInMenuBar)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                        
                        if appState.showInMenuBar {
                            Divider().background(Color.white.opacity(0.08))
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DISPLAY MODE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.40))
                                    .tracking(0.6)
                                
                                Picker("", selection: $appState.menuBarMode) {
                                    ForEach(AppState.MenuBarMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .pickerStyle(.radioGroup)
                                .font(.system(size: 11))
                            }
                            
                            // Notch Tip Callout
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                    .foregroundColor(.amberAccent)
                                
                                Text("MacBook Notch Notice: If you have many menu bar items, macOS automatically conceals icons that overlap the camera notch. Select 'Icon Only' (24pt) to preserve space, or ⌘-drag menu bar icons left/right to reposition.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.60))
                                    .lineSpacing(2)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.amberAccent.opacity(0.07))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.amberAccent.opacity(0.20), lineWidth: 0.5)
                                    )
                            )
                            
                            // Re-attach button
                            Button {
                                appState.resetMenuBarPosition()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.counterclockwise.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Re-attach / Reset Menu Bar Icon Position")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(.amberAccent)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.amberAccent.opacity(0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(Color.amberAccent.opacity(0.35), lineWidth: 0.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    }
                }
                
                // MARK: - Session Policy
                MetricCard(title: "Session Boundary Policy", subtitle: "Awake / Sleep Detection", icon: "macbook", accentColor: .blueAccent) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $appState.sessionPolicy) {
                            ForEach(SessionPolicy.allCases, id: \.self) { policy in
                                Text(policy.displayTitle).tag(policy)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .font(.system(size: 11))
                        
                        Text(appState.sessionPolicy.description)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.50))
                            .lineSpacing(1.5)
                            .padding(.top, 2)
                    }
                }
                
                // MARK: - System Options
                MetricCard(title: "Startup & Application Dock", subtitle: "System Integration", icon: "gearshape", accentColor: .cyanAccent) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show icon in macOS Dock", isOn: $appState.showInDock)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                        
                        Toggle("Launch at Login (Background Agent)", isOn: Binding(
                            get: { appState.isLaunchAtLoginEnabled },
                            set: { appState.setLaunchAtLogin(enabled: $0) }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                    }
                }
                
                // MARK: - Data Management & Export
                MetricCard(title: "Data Management & Export", subtitle: "Local SQLite Database", icon: "externaldrive", accentColor: .emeraldAccent) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            // Export CSV Button
                            Button {
                                if let url = appState.exportData(asJSON: false) {
                                    promptSave(for: url, filename: "MacPulse-History.csv")
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Export CSV")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.white.opacity(0.90))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            
                            // Export JSON Button
                            Button {
                                if let url = appState.exportData(asJSON: true) {
                                    promptSave(for: url, filename: "MacPulse-History.json")
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "curlybraces")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Export JSON")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.white.opacity(0.90))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            // Reset History Button
                            Button {
                                showingResetAlert = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Reset History")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(.red.opacity(0.9))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.red.opacity(0.10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(Color.red.opacity(0.30), lineWidth: 0.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if let notice = exportNotification {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.emeraldAccent)
                                Text(notice)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.emeraldAccent)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                
                // MARK: - Measurement Transparency & Architecture
                MetricCard(title: "Architecture & Telemetry Integrity", subtitle: "Zero Cloud Dependencies", icon: "shield.checkerboard", accentColor: .blueAccent) {
                    VStack(spacing: 8) {
                        ArchitectureRow(
                            icon: "bolt.fill",
                            color: .amberAccent,
                            title: "Hardware PMU Power",
                            detail: "Reads direct Apple Silicon PMU system load via AppleSmartBattery. Battery power is sampled with true microampere precision without running invasive root daemon tools."
                        )
                        
                        Divider().background(Color.white.opacity(0.06))
                        
                        ArchitectureRow(
                            icon: "wifi",
                            color: .cyanAccent,
                            title: "Kernel Network Sysctl",
                            detail: "Queries active IEEE80211 interface byte counters directly from kernel routing tables (NET_RT_IFLIST2). Excludes virtual VPN interfaces and loopback."
                        )
                        
                        Divider().background(Color.white.opacity(0.06))
                        
                        ArchitectureRow(
                            icon: "lock.shield.fill",
                            color: .emeraldAccent,
                            title: "Offline-First Privacy",
                            detail: "100% offline local utility. Zero analytics, zero network beacons, zero third-party SDKs. All session data resides exclusively in your local SQLite store."
                        )
                    }
                }
                
                // MARK: - App Footer
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MacPulse v1.0.0 (Native Apple Silicon • arm64)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.50))
                        Text("Targeted for MacBook Air M4 with minimal CPU & memory budget.")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    
                    Spacer()
                    
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "power")
                                .font(.system(size: 10))
                            Text("Quit MacPulse")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.60))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .alert("Reset All History?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) {
                appState.resetAllHistory()
            }
        } message: {
            Text("This will permanently delete all recorded sessions and reset lifetime energy and network statistics to zero. This action cannot be undone.")
        }
    }
    
    private func promptSave(for tempURL: URL, filename: String) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = filename
        savePanel.begin { response in
            if response == .OK, let targetURL = savePanel.url {
                do {
                    if FileManager.default.fileExists(atPath: targetURL.path) {
                        try FileManager.default.removeItem(at: targetURL)
                    }
                    try FileManager.default.copyItem(at: tempURL, to: targetURL)
                    exportNotification = "Exported to \(targetURL.lastPathComponent)"
                } catch {
                    exportNotification = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Architecture Info Row
private struct ArchitectureRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.55))
                    .lineSpacing(1.5)
            }
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
