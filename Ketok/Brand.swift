import SwiftUI

/// Ketok brand identity — adaptive colors, gradients, style tokens, and view modifiers.
/// All colors are dark-mode aware: light mode uses deep saturated tones, dark mode uses
/// brighter/lighter variants so they pop against dark backgrounds.
enum Brand {

    // MARK: - Adaptive Primary Colors

    /// Primary brand color — deep indigo (light) / bright indigo (dark)
    static let primary = Color("BrandPrimary", bundle: nil)

    /// Lighter variant for hover/selected — indigo-400 (light) / indigo-300 (dark)
    static let primaryLight = Color("BrandPrimaryLight", bundle: nil)

    /// Darker variant for pressed states — indigo-800 (light) / indigo-500 (dark)
    static let primaryDark = Color("BrandPrimaryDark", bundle: nil)

    /// Accent — cyan-500 (light) / cyan-400 (dark)
    static let accent = Color("BrandAccent", bundle: nil)

    /// Violet — violet-600 (light) / violet-400 (dark)
    static let violet = Color("BrandViolet", bundle: nil)

    // MARK: - Semantic Colors (adaptive)

    /// Warning — amber
    static let warning = Color("BrandWarning", bundle: nil)

    /// Success — emerald
    static let success = Color("BrandSuccess", bundle: nil)

    /// Error — red
    static let error = Color("BrandError", bundle: nil)

    // MARK: - Surface & Layout Colors (adaptive)

    /// Surface — card/content background
    static let surface = Color("BrandSurface", bundle: nil)

    /// Surface alt — alternating/grouped background
    static let surfaceAlt = Color("BrandSurfaceAlt", bundle: nil)

    /// Border — card/section borders
    static let border = Color("BrandBorder", bundle: nil)

    /// Muted — secondary text, captions
    static let muted = Color("BrandMuted", bundle: nil)

    /// Background — page/window background
    static let background = Color("BrandBackground", bundle: nil)

    // MARK: - Layout Tokens

    static let cardRadius: CGFloat = 14
    static let badgeRadius: CGFloat = 8

    // MARK: - Developer-Themed Fonts

    /// Monospace font for technical content (paths, versions, timestamps)
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Section header font — monospace, uppercase feel
    static func sectionFont(_ size: CGFloat = 10, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Title font — clean system font (no rounded)
    static func titleFont(_ size: CGFloat = 13, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: - Static Gradients (use bright variants so they work on both modes)

    /// Hero gradient for app header / branding areas
    static let heroGradient = LinearGradient(
        colors: [Color(hex: 0x818CF8), Color(hex: 0xA78BFA)],  // Indigo-400 → Violet-400
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Build progress gradient
    static let progressGradient = LinearGradient(
        colors: [Color(hex: 0x818CF8), Color(hex: 0x22D3EE)],  // Indigo-400 → Cyan-400
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Icon background gradient (About view, splash)
    static let iconGradient = LinearGradient(
        colors: [Color(hex: 0x6366F1), Color(hex: 0x8B5CF6)],  // Indigo-500 → Violet-500
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - App Identity

    static let appName = "Ketok"
    static let bundlePrefix = "com.ketok"
    static let tagline = "Tap, build, ship."
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// Create an adaptive color that switches between light and dark variants
    static func adaptive(light: UInt, dark: UInt) -> Color {
        // We use a tiny wrapper view trick — but for static lets we rely on asset catalogs.
        // For inline usage, use AdaptiveColor view modifier instead.
        Color(hex: light) // Fallback; real adaptation happens via colorset assets
    }
}

// MARK: - Branded View Modifiers

/// Branded header style — adapts tint for dark mode
struct BrandedHeaderStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Brand.primary.opacity(0.08), Brand.violet.opacity(0.04), Color.clear]
                            : [Brand.primary.opacity(0.04), Brand.violet.opacity(0.02), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    // Subtle top edge highlight like a code editor tab bar
                    VStack {
                        Brand.progressGradient
                            .frame(height: 1)
                            .opacity(colorScheme == .dark ? 0.15 : 0.1)
                        Spacer()
                    }
                }
            )
    }
}

/// Branded capsule tag — higher opacity in dark mode for visibility
struct BrandedCapsule: ViewModifier {
    var color: Color = Brand.primary
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(colorScheme == .dark ? 0.25 : 0.15))
            )
    }
}

/// Branded section card — uses Brand surface and border tokens
struct BrandedCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Brand.cardRadius)
                    .fill(Brand.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Brand.cardRadius)
                    .strokeBorder(
                        Brand.border.opacity(0.6),
                        lineWidth: 1.0
                    )
            )
    }
}

/// Branded glass card — glassmorphism for top-level header areas
struct BrandedGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Brand.cardRadius)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: Brand.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.cardRadius)
                    .strokeBorder(
                        Brand.border.opacity(0.4),
                        lineWidth: 0.5
                    )
            )
    }
}

/// Branded progress bar overlay
struct BrandedProgress: ViewModifier {
    var progress: Double

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            GeometryReader { geo in
                Brand.progressGradient
                    .frame(width: geo.size.width * progress, height: 2)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
            .frame(height: 2)
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let icon: String
    let title: String
    var iconColor: Color = Brand.primary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(iconColor.opacity(0.7))
            Text(title)
                .font(Brand.sectionFont())
                .foregroundColor(Brand.primary.opacity(0.7))
                .tracking(1.5)
        }
        .padding(.leading, 2)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply branded header styling
    func brandedHeader() -> some View {
        modifier(BrandedHeaderStyle())
    }

    /// Apply branded capsule tag
    func brandedCapsule(color: Color = Brand.primary) -> some View {
        modifier(BrandedCapsule(color: color))
    }

    /// Apply branded card background
    func brandedCard() -> some View {
        modifier(BrandedCard())
    }

    /// Apply branded glass card (header areas only)
    func brandedGlassCard() -> some View {
        modifier(BrandedGlassCard())
    }

    /// Apply branded progress bar
    func brandedProgress(_ progress: Double) -> some View {
        modifier(BrandedProgress(progress: progress))
    }
}
