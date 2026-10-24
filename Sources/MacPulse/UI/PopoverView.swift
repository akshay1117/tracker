import SwiftUI

/// Root view with segmented navigation across Overview, Apps, History, and Settings.
/// Features a dark black OLED aesthetic, specular liquid-glass tabs with spring physics,
/// and smooth asymmetric liquid transitions between screens.
public struct PopoverView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: Tab = .overview
    @Namespace private var tabNamespace
    
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
            // MARK: - Liquid Glass Header Bar
            HStack(spacing: 12) {
                // App Icon Badge with Liquid Glow
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color.amberAccent.opacity(0.24), Color.amberAccent.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.amberAccent.opacity(0.50), Color.amberAccent.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        )
                        .shadow(color: Color.amberAccent.opacity(0.25), radius: 6, x: 0, y: 2)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.amberAccent)
                }
                
                // Title and Status Indicator with Liquid Breathing Glow
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("MacPulse")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    // Live Session State Pill with Ambient Glow
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(stateColor.opacity(0.35))
                                .frame(width: 10, height: 10)
                            Circle()
                                .fill(stateColor)
                                .frame(width: 6, height: 6)
                        }
                        
                        Text(appState.sessionManager.currentState.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(stateColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(stateColor.opacity(0.12))
                            DesignSystem.liquidGlassHighlight
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(stateColor.opacity(0.35), lineWidth: 0.8)
                    )
                }
                
                Spacer()
                
                // Header Uptime & Action Buttons
                HStack(spacing: 8) {
                    // System Uptime Badge
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.emeraldAccent)
                        Text(appState.formattedSystemUptime)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.80))
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.04))
                            DesignSystem.liquidGlassHighlight
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
                    .help("Mac System Uptime")
                    
                    Button {
                        withAnimation(DesignSystem.liquidBouncy) {
                            appState.performTick()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Refresh")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.90))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.06))
                                DesignSystem.liquidGlassHighlight
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(DesignSystem.glassBorderGradient, lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.liquidTactile(scale: 0.92))
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
                            .background(Color.white.opacity(0.08)),
                        alignment: .bottom
                    )
            )
            
            // MARK: - Fluid Liquid Glass Segmented Navigation
            HStack(spacing: 4) {
                ForEach(Tab.allCases) { tab in
                    Button {
                        withAnimation(DesignSystem.liquidSpring) {
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
                                    // Liquid glass floating pill
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.18),
                                                    Color.white.opacity(0.06)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.white.opacity(0.38),
                                                            Color.white.opacity(0.12)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 0.8
                                                )
                                        )
                                        .shadow(color: Color.black.opacity(0.40), radius: 6, x: 0, y: 2)
                                        .matchedGeometryEffect(id: "liquidTabActivePill", in: tabNamespace)
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.clear)
                                }
                            }
                        )
                    }
                    .buttonStyle(.liquidTactile(scale: 0.96))
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
                    )
            )
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            
            // MARK: - Instant Zero-Lag Tab Content
            ZStack {
                OverviewView(appState: appState)
                    .opacity(selectedTab == .overview ? 1 : 0)
                    .allowsHitTesting(selectedTab == .overview)
                
                AppUsageView(appState: appState)
                    .opacity(selectedTab == .apps ? 1 : 0)
                    .allowsHitTesting(selectedTab == .apps)
                
                HistoryView(appState: appState)
                    .opacity(selectedTab == .history ? 1 : 0)
                    .allowsHitTesting(selectedTab == .history)
                
                SettingsView(appState: appState)
                    .opacity(selectedTab == .settings ? 1 : 0)
                    .allowsHitTesting(selectedTab == .settings)
            }
            .animation(.easeInOut(duration: 0.12), value: selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 740)
        .background(
            ZStack {
                // Pitch-black base
                DesignSystem.windowBackground
                
                // Deep ambient chromatic liquid halos for rich OLED backdrop depth
                RadialGradient(
                    colors: [Color.cyanAccent.opacity(0.04), Color.clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 500
                )
                
                RadialGradient(
                    colors: [Color.amberAccent.opacity(0.035), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 500
                )
            }
            .ignoresSafeArea()
        )
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
