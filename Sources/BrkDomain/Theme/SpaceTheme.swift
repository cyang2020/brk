import BrkBase
import Foundation

// Owner: W5 (theme). Space themes as stored, Arc's observed presets and sidebar tokens, and the derived values
// every view paints with. Follows Arc's `WindowTheme` / `BlendedGradientConfiguration` / `BlendedBackgroundModifiers`
// (anatomy 1.13, 4.5): 1 to 3 base colors with a wheel rule for their companions, one texture overlay with a noise
// amount and a strength, and an appearance choice. The editor's controls (anatomy, "Space theme editor") map one
// to one: color pad, wheel, noise dial, intensity sine slider, light/dark/auto toggle, preset pages.

/// A color as Arc stores it (`ARCUI.StorableColor`: extended sRGB components 0...1 plus alpha).
public struct RGBA: Hashable, Sendable, Codable {
    public var red: Double, green: Double, blue: Double, alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// "#RRGGBB" (sRGB), for preset tables copied from the anatomy.
    public init(hex: String, alpha: Double = 1) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(digits, radix: 16) ?? 0
        self.init(Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255, alpha)
    }
}

/// Arc: `BlendedBackgroundModifiers.overlay`.
public enum Texture: String, Hashable, Sendable, Codable, CaseIterable {
    case grain, sand, denim, tweed
}

/// Arc: translucency style light | dark | auto. `auto` derives the scheme from the primary color's luminance.
public enum AppearanceChoice: String, Hashable, Sendable, Codable, CaseIterable {
    case auto, light, dark
}

public enum Scheme: String, Hashable, Sendable, Codable { case light, dark }

/// How companion colors are derived from the base colors (Arc: `BlendedGradientConfiguration.wheel`, spelled
/// `complimentary` there).
public enum ColorWheel: String, Hashable, Sendable, Codable, CaseIterable { case analogous, complementary }

/// What a space stores. Arc: `WindowTheme` with a `blendedGradient` background.
public struct SpaceTheme: Hashable, Sendable, Codable {
    /// Primary first; 1 to 3 entries (Arc: `BlendedGradientConfiguration.baseColors`). The reducer clamps the count.
    public var colors: [RGBA]
    public var wheel: ColorWheel
    public var texture: Texture
    /// 0...1 (Arc: `noiseFactor`, the editor's dial). How much of the texture's own variation shows: the renderer
    /// scales the tile's contrast by it. Its exact role in Arc's shader was not recovered (layout-constants.md,
    /// "Not recovered"); this is our reading of the two separate controls.
    public var noise: Double
    /// 0...1 (Arc: `intensityFactor`, the editor's sine slider). Texture opacity = intensity x the texture's
    /// multiplier (Metrics.theme.*Opacity); wash opacity = min(0.2 + 0.55 x intensity, 0.5).
    public var intensity: Double
    public var appearance: AppearanceChoice

    public init(colors: [RGBA], wheel: ColorWheel = .analogous, texture: Texture, noise: Double = 0.5,
                intensity: Double, appearance: AppearanceChoice) {
        self.colors = colors
        self.wheel = wheel
        self.texture = texture
        self.noise = noise
        self.intensity = intensity
        self.appearance = appearance
    }

    /// Arc's default theme for a new space is not in static data (guess: Brand 8, grain, noise 0.5, intensity 0.25).
    public static let `default` = SpaceTheme(colors: [ThemePresets.brand[7]], texture: .grain, intensity: 0.25, appearance: .auto)
}

/// Arc's four 9-color picker sets (visual-and-copy.md, "Space theme preset palette"). Brand5 uses the rendered value
/// #FF8558. Arc's page order is unknown; this order is ours.
public enum ThemePresets {
    public static let brand = ["#F2EAE4", "#F29BBB", "#A6729D", "#F25E6B", "#FF8558", "#F2D66D", "#73E59C", "#7EB8D6", "#666786"].map { RGBA(hex: $0) }
    public static let drab = ["#4B3B58", "#623856", "#854444", "#A77048", "#D1B46A", "#CDCCA8", "#84A885", "#34604B", "#2D4468"].map { RGBA(hex: $0) }
    public static let greyscale = ["#FFFFFF", "#E5E5E5", "#CCCCCC", "#B2B2B2", "#808080", "#666666", "#333333", "#1A1A1A", "#000000"].map { RGBA(hex: $0) }
    public static let pastel = ["#FDFBFA", "#FBEAF3", "#ECD2EA", "#F7CDD2", "#FAE1D5", "#FEF9E7", "#E4FCEC", "#E0F2FB", "#C5C6E2"].map { RGBA(hex: $0) }
}

/// Arc's sidebar tokens (visual-and-copy.md, "Sidebar and tab colors"): translucent black or white over the theme,
/// so the gradient shows through. One struct per scheme; a token missing from either fails to compile.
public struct SidebarTokens: Hashable, Sendable, Codable {
    public var foreground: RGBA
    public var foregroundStrong: RGBA
    public var itemBackground: RGBA
    public var itemHover: RGBA
    public var separator: RGBA
    public var border: RGBA
    public var tabCurrent: RGBA
    public var tabVisible: RGBA
    public var tabPrevious: RGBA
    public var tabPreviousHover: RGBA
    public var tabPressed: RGBA
    public var tabChild: RGBA
    public var tabShadow: RGBA
    public var tabShadowBackground: RGBA
    public var dragHint: RGBA
    public var dragHintStrong: RGBA

    public static let light = SidebarTokens(
        foreground: RGBA(0, 0, 0, 0.3), foregroundStrong: RGBA(0, 0, 0, 0.45),
        itemBackground: RGBA(hex: "#0E0F10", alpha: 0.05), itemHover: RGBA(hex: "#0E0F10", alpha: 0.1),
        separator: RGBA(0, 0, 0, 0.15), border: RGBA(1, 1, 1, 0.3),
        tabCurrent: RGBA(1, 1, 1, 0.85), tabVisible: RGBA(1, 1, 1, 0.7),
        tabPrevious: RGBA(1, 1, 1, 0.32), tabPreviousHover: RGBA(1, 1, 1, 0.5),
        tabPressed: RGBA(hex: "#0E0F10", alpha: 0.065), tabChild: RGBA(0, 0, 0, 0.07),
        tabShadow: RGBA(0, 0, 0, 0.2), tabShadowBackground: RGBA(1, 1, 1, 0.9),
        dragHint: RGBA(0, 0, 0, 0.2), dragHintStrong: RGBA(0, 0, 0, 0.5)
    )

    public static let dark = SidebarTokens(
        foreground: RGBA(1, 1, 1, 0.45), foregroundStrong: RGBA(1, 1, 1, 0.45),
        itemBackground: RGBA(hex: "#FAFBFF", alpha: 0.1), itemHover: RGBA(hex: "#FAFBFF", alpha: 0.15),
        separator: RGBA(1, 1, 1, 0.15), border: RGBA(1, 1, 1, 0.3),
        tabCurrent: RGBA(hex: "#FAFBFF", alpha: 0.2), tabVisible: RGBA(hex: "#FAFBFF", alpha: 0.15),
        tabPrevious: RGBA(hex: "#FAFBFF", alpha: 0.08), tabPreviousHover: RGBA(hex: "#FAFBFF", alpha: 0.12),
        tabPressed: RGBA(hex: "#FAFBFF", alpha: 0.065), tabChild: RGBA(1, 1, 1, 0.07),
        tabShadow: RGBA(0, 0, 0, 0), tabShadowBackground: RGBA(0, 0, 0, 0),
        dragHint: RGBA(1, 1, 1, 0.2), dragHintStrong: RGBA(1, 1, 1, 0.5)
    )
}

/// What surfaces paint with. Derived by `resolveTheme`, never stored.
public struct ResolvedTheme: Hashable, Sendable, Codable {
    public var scheme: Scheme
    /// Gradient stops for the Metal background, primary first (derived from the base colors; 1 to 3 + blends).
    public var gradient: [RGBA]
    public var texture: Texture
    /// intensity x the texture's multiplier (Metrics.theme.*Opacity).
    public var textureOpacity: Double
    /// The stored `noise`, 0...1: the renderer multiplies the tile's deviation from mid grey by it.
    public var textureContrast: Double
    /// White (light) or black at 35% (dark), with opacity min(0.2 + 0.55 x intensity, 0.5).
    public var wash: RGBA
    public var tokens: SidebarTokens
    /// Solid color for the NSWindow background, visible only before the first Metal frame.
    public var windowColor: RGBA
}

/// Pure: stored theme -> paint values. Light or dark comes from the primary color's luminance unless forced.
/// First pass by the integrator; W5 owns the gradient derivation (companions by `wheel`, lightness nudges) and
/// the ported theme cases pin the scheme choice.
public func resolveTheme(_ theme: SpaceTheme) -> ResolvedTheme {
    let colors = theme.colors.isEmpty ? [ThemePresets.brand[7]] : Array(theme.colors.prefix(3))
    let primary = colors[0]
    let scheme: Scheme
    switch theme.appearance {
    case .light: scheme = .light
    case .dark: scheme = .dark
    case .auto: scheme = relativeLuminance(primary) > 0.5 ? .light : .dark   // TODO(W5): the ported mid-tone case
    }
    // TODO(W5): companions by wheel (Metrics.theme.analogousHueOffset / complementaryHueOffset) with the lightness
    // range; v1 pass: the base colors plus a lightened/darkened variant of the primary.
    var gradient = colors
    gradient.append(scheme == .light ? mix(primary, RGBA(1, 1, 1), 0.25) : mix(primary, RGBA(0, 0, 0), 0.25))
    let multiplier: Double = switch theme.texture {
    case .grain: Metrics.theme.grainOpacity.value
    case .sand: Metrics.theme.sandOpacity.value
    case .denim: Metrics.theme.denimOpacity.value
    case .tweed: Metrics.theme.tweedOpacity.value
    }
    let intensity = min(max(theme.intensity, 0), 1)
    let washAlpha = min(Metrics.theme.washBase.value + Metrics.theme.washSlope.value * intensity, Metrics.theme.washCap.value)
    let wash = scheme == .light ? RGBA(1, 1, 1, washAlpha) : RGBA(0, 0, 0, Metrics.theme.darkWashAlpha.value * washAlpha)
    return ResolvedTheme(scheme: scheme, gradient: gradient, texture: theme.texture, textureOpacity: intensity * multiplier,
                         textureContrast: min(max(theme.noise, 0), 1), wash: wash,
                         tokens: scheme == .light ? .light : .dark, windowColor: mix(primary, wash, wash.alpha))
}

/// WCAG relative luminance of an sRGB color.
public func relativeLuminance(_ c: RGBA) -> Double {
    func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.red) + 0.7152 * lin(c.green) + 0.0722 * lin(c.blue)
}

/// Linear blend of two colors; alpha of the result is `a`'s.
func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
    RGBA(a.red + (b.red - a.red) * t, a.green + (b.green - a.green) * t, a.blue + (b.blue - a.blue) * t, a.alpha)
}
