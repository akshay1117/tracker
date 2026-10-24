import SwiftUI
import AppKit

/// Precision macOS Ultra-Dark Black & Liquid Glass Design System.
/// Pitch-black architectural foundations, frosted specular refraction edges,
/// dynamic chromatic ambient halos, and fluid liquid-spring physics.
public enum DesignSystem {
    public static let cornerRadius: CGFloat = 12.0
    public static let cardPadding: CGFloat = 16.0
    
    // Pitch-black architectural obsidian foundations
    public static let windowBackground = Color(red: 0.015, green: 0.018, blue: 0.024)
    public static let cardBackground = Color(red: 0.045, green: 0.050, blue: 0.065).opacity(0.85)
    public static let elevatedSurface = Color(red: 0.075, green: 0.080, blue: 0.105)
    public static let darkSurface = Color(red: 0.035, green: 0.038, blue: 0.050)
    public static let glassSurface = Color.white.opacity(0.045)
    public static let cardBorder = Color.white.opacity(0.08)
    public static let subtleBorder = Color.white.opacity(0.05)
    
    // Razor-sharp specular liquid-glass border gradients
    public static let glassBorderGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.24),
            Color.white.opacity(0.08),
            Color.white.opacity(0.02),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let specularRimGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.32),
            Color.white.opacity(0.10),
            Color.white.opacity(0.03)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Specular diagonal liquid sheen
    public static let liquidGlassHighlight = LinearGradient(
        colors: [
            Color.white.opacity(0.08),
            Color.white.opacity(0.02),
            Color.clear
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Header obsidian-to-black gradient
    public static let headerGradient = LinearGradient(
        colors: [
            Color(red: 0.040, green: 0.045, blue: 0.058),
            Color(red: 0.015, green: 0.018, blue: 0.024)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    public static let glassCardGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.05),
            Color.white.opacity(0.01)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Chromatic Neon Accents (Vibrant against pitch black)
    public static let powerAccent = Color(red: 0.98, green: 0.68, blue: 0.16)   // Molten Amber Gold
    public static let networkAccent = Color(red: 0.16, green: 0.78, blue: 0.98) // Electric Cyan
    public static let uptimeAccent = Color(red: 0.16, green: 0.86, blue: 0.62)  // Neon Emerald
    public static let sessionAccent = Color(red: 0.35, green: 0.68, blue: 1.00) // Deep Sky Blue
    public static let purpleAccent = Color(red: 0.72, green: 0.46, blue: 1.00)  // Liquid Violet
    
    // Fluid, Snappy Liquid-Spring Animation Curves (Instant, zero-lag feel)
    public static let liquidSpring = Animation.spring(response: 0.22, dampingFraction: 0.74, blendDuration: 0.10)
    public static let liquidBouncy = Animation.interactiveSpring(response: 0.18, dampingFraction: 0.65, blendDuration: 0.08)
    public static let liquidSnappy = Animation.spring(response: 0.15, dampingFraction: 0.78)
}

extension Color {
    public static let amberAccent = DesignSystem.powerAccent
    public static let cyanAccent = DesignSystem.networkAccent
    public static let emeraldAccent = DesignSystem.uptimeAccent
    public static let blueAccent = DesignSystem.sessionAccent
    public static let darkSurface = DesignSystem.darkSurface
}

/// Liquid Glass container with ambient chromatic glow, specular refraction edge, and dark black backdrop.
public struct MetricCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String?
    let accentColor: Color?
    @ViewBuilder let content: () -> Content
    
    @State private var isHovered: Bool = false
    
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
                    .foregroundColor(.white.opacity(0.85))
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
            ZStack {
                // Pitch-black obsidian glass
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .fill(DesignSystem.cardBackground)
                
                // Ambient chromatic liquid glow (subtle reflection of accent color)
                if let accent = accentColor {
                    RadialGradient(
                        colors: [
                            accent.opacity(isHovered ? 0.12 : 0.05),
                            Color.clear
                        ],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 220
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
                }
                
                // Specular liquid glass highlight sheen
                DesignSystem.liquidGlassHighlight
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .strokeBorder(
                    isHovered ? DesignSystem.specularRimGradient : DesignSystem.glassBorderGradient,
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.black.opacity(isHovered ? 0.55 : 0.35),
            radius: isHovered ? 14 : 8,
            x: 0,
            y: isHovered ? 6 : 3
        )
        .onHover { hovering in
            withAnimation(DesignSystem.liquidSpring) {
                isHovered = hovering
            }
        }
    }
}

/// Instant tactile liquid-glass button style with physical down-scale, specular brightness, and trackpad haptic tap.
public struct LiquidTactileButtonStyle: ButtonStyle {
    public var pressedScale: CGFloat = 0.94
    public var pressedOpacity: CGFloat = 0.82
    public var haptic: Bool = true
    
    public init(pressedScale: CGFloat = 0.94, pressedOpacity: CGFloat = 0.82, haptic: Bool = true) {
        self.pressedScale = pressedScale
        self.pressedOpacity = pressedOpacity
        self.haptic = haptic
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .brightness(configuration.isPressed ? 0.08 : 0.0)
            .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.72), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && haptic {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                }
            }
    }
}

extension ButtonStyle where Self == LiquidTactileButtonStyle {
    public static var liquidTactile: LiquidTactileButtonStyle {
        LiquidTactileButtonStyle()
    }
    
    public static func liquidTactile(scale: CGFloat = 0.94, opacity: CGFloat = 0.82) -> LiquidTactileButtonStyle {
        LiquidTactileButtonStyle(pressedScale: scale, pressedOpacity: opacity)
    }
}

