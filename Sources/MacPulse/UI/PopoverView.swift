import SwiftUI

/// Root view with segmented navigation across Overview, Apps, History, and Settings.
/// Features a spacious, architectural dark interface with precise alignment and typography.
public struct PopoverView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: Tab = .overview
    
    public enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case apps = "Apps"
        case history = "History"
        case settings = "Settings"
        
        public var id: String { rawValue }
        public var icon: String {
            switch self {
            case .overview: return "gauge.medium"
            case .apps: return "app.badge.checkmark"
            case .history: return "clock.arrow.circlepath"
            case .settings: return "slider.horizontal.3"
            }
        }
    }
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Precision Header Bar
            HStack(spacing: 12) {
                // App Icon Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.amberAccent.opacity(0.16))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.amberAccent)
                }
                
                // Title and Status Indicator
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("MacPulse")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    // Live Session State Pill
                    HStack(spacing: 5) {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 6, height: 6)
                        
                        Text(appState.sessionManager.currentState.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(stateColor)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(stateColor.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(stateColor.opacity(0.25), lineWidth: 0.5)
                            )
                    )
                }
                
                Spacer()
                
                // Header Action Buttons
                HStack(spacing: 8) {
                    Button {
                        appState.performTick()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Refresh")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Refresh metrics immediately")
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .background(
                Rectangle()
                    .fill(DesignSystem.headerGradient)
                    .overlay(
                        Divider()
                            .background(Color.white.opacity(0.07)),
                        alignment: .bottom
                    )
            )
            
            // MARK: - Navigation Segmented Tabs
            HStack(spacing: 4) {
                ForEach(Tab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: selectedTab == tab ? .bold : .medium))
                        }
                        .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            ZStack {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5)
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.clear)
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            
            // MARK: - Tab Content Area
            Group {
                switch selectedTab {
                case .overview:
                    OverviewView(appState: appState)
                case .apps:
                    AppUsageView(appState: appState)
                case .history:
                    HistoryView(appState: appState)
                case .settings:
                    SettingsView(appState: appState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 740)
        .background(DesignSystem.windowBackground)
    }
    
    private var stateColor: Color {
        switch appState.sessionManager.currentState {
        case .active: return .emeraldAccent
        case .idle: return .gray
        case .sleeping: return .amberAccent
        case .recovering: return .blueAccent
        }
    }
}
