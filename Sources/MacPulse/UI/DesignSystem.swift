import SwiftUI
import AppKit

/// Precision macOS Dark Design System.
/// Clean, bespoke, non-generic typography, deliberate spacing, and razor-sharp borders.
public enum DesignSystem {
    public static let cornerRadius: CGFloat = 12.0
    public static let cardPadding: CGFloat = 16.0
    
    // Solid architectural dark foundations
    public static let windowBackground = Color(red: 0.06, green: 0.07, blue: 0.09)
    public static let cardBackground = Color(red: 0.10, green: 0.11, blue: 0.15)
    public static let cardBorder = Color.white.opacity(0.08)
    public static let subtleBorder = Color.white.opacity(0.05)
    public static let elevatedSurface = Color(red: 0.13, green: 0.15, blue: 0.20)
    public static let darkSurface = Color(red: 0.10, green: 0.11, blue: 0.15)
    public static let glassSurface = Color.white.opacity(0.05)
    
    // Deliberate specular edge gradient
    public static let glassBorderGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.18),
            Color.white.opacity(0.06),
            Color.white.opacity(0.02)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Header gradient
    public static let headerGradient = LinearGradient(
        colors: [
            Color(red: 0.09, green: 0.11, blue: 0.15),
            Color(red: 0.07, green: 0.08, blue: 0.11)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    public static let glassCardGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.04),
            Color.white.opacity(0.01)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let glassHeaderGradient = LinearGradient(
        colors: [
            Color(red: 0.09, green: 0.11, blue: 0.15),
            Color(red: 0.07, green: 0.08, blue: 0.11)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Accents
    public static let powerAccent = Color(red: 0.96, green: 0.65, blue: 0.14)   // Amber Gold
    public static let networkAccent = Color(red: 0.22, green: 0.74, blue: 0.97) // Glacier Cyan
    public static let uptimeAccent = Color(red: 0.20, green: 0.83, blue: 0.60)  // Mint Emerald
    public static let sessionAccent = Color(red: 0.38, green: 0.65, blue: 0.98) // Steel Blue
    public static let purpleAccent = Color(red: 0.68, green: 0.45, blue: 0.98)  // Iris Purple
}

extension Color {
    public static let amberAccent = DesignSystem.powerAccent
    public static let cyanAccent = DesignSystem.networkAccent
    public static let emeraldAccent = DesignSystem.uptimeAccent
    public static let blueAccent = DesignSystem.sessionAccent
    public static let darkSurface = DesignSystem.darkSurface
}

/// A clean, precision macOS card container with sharp typography and perfect spacing.
public struct MetricCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String?
    let accentColor: Color?
    @ViewBuilder let content: () -> Content
    
    public init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        accentColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accentColor = accentColor
        self.content = content
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Card Header
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(accentColor ?? .white.opacity(0.85))
                }
                
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.80))
                    .textCase(.uppercase)
                    .tracking(0.6)
                
                Spacer()
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            
            content()
        }
        .padding(DesignSystem.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(DesignSystem.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .strokeBorder(DesignSystem.glassBorderGradient, lineWidth: 1)
        )
    }
}
