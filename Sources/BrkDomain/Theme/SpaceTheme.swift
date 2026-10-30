import BrkBase
import Foundation

// Owner: W5 (theme). Space themes as stored, Arc's observed presets and sidebar tokens, and the derived values
// every view paints with. Simplified from Arc's `WindowTheme` (anatomy 1.13, 4.5): a blended gradient of 1 to 3
// base colors, one texture overlay with an intensity, and an appearance choice.

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

/// What a space stores. Arc: `WindowTheme` with a `blendedGradient` background.
public struct SpaceTheme: Hashable, Sendable, Codable {
    /// Primary first; 1 to 3 entries (Arc: `BlendedGradientConfiguration.baseColors`). The reducer clamps the count.
    public var colors: [RGBA]
    public var texture: Texture
    /// 0...1 (Arc: `noiseFactor`/`intensityFactor` collapsed to one control).
    public var intensity: Double
    public var appearance: AppearanceChoice

    public init(colors: [RGBA], texture: Texture, intensity: Double, appearance: AppearanceChoice) {
        self.colors = colors
        self.texture = texture
        self.intensity = intensity
        self.appearance = appearance
    }

    /// Arc's default theme for a new space is not in static data (guess: Brand 8, grain at 0.25).
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
    /// White (light) or black at 35% (dark), with opacity min(0.2 + 0.55 x intensity, 0.5).
    public var wash: RGBA
    public var tokens: SidebarTokens
    /// Solid color for the NSWindow background, visible only before the first Metal frame.
    public var windowColor: RGBA
}

/// Pure: stored theme -> paint values. Light or dark comes from the primary color's luminance unless forced.
public func resolveTheme(_ theme: SpaceTheme) -> ResolvedTheme {
    // TODO(W5): scheme = appearance forced, else luminance(colors[0]) > 0.5 ? .light : .dark (WCAG relative
    // luminance); gradient stops: Arc blends base colors with analogous neighbours (wheel) - v1: base colors plus a
    // lightened/darkened variant of the primary; textureOpacity = intensity * Metrics.theme.<texture>Opacity;
    // wash per Metrics.theme.wash*; tokens = scheme == .light ? .light : .dark.
    fatalError("not implemented")
}
