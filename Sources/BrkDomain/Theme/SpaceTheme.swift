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
    public var variants: ThemeVariants? = nil

    public init(colors: [RGBA], wheel: ColorWheel = .analogous, texture: Texture, noise: Double = 0.5,
                intensity: Double, appearance: AppearanceChoice) {
        self.colors = colors
        self.wheel = wheel
        self.texture = texture
        self.noise = noise
        self.intensity = intensity
        self.appearance = appearance
    }

    /// A fresh profile's first space in Arc 1.170 is the light pink-beige of the Brand page's first swatch (#F2EAE4,
    /// verify/visual-pairs/run-20261103 P07-b); grain, noise 0.5 and intensity 0.25 are still guesses.
    public static let `default` = SpaceTheme(colors: [ThemePresets.brand[0]], texture: .grain, intensity: 0.25, appearance: .auto)
}

/// Arc's four 9-color picker sets (visual-and-copy.md, "Space theme preset palette"). Brand5 uses the rendered value
/// #FF8558. `pages` is Arc 1.170's page order in the theme panel (captured 2026-11-03, P28 c): Brand, Pastel, Drab,
/// Greyscale.
public enum ThemePresets {
    public static let pages: [(name: String, colors: [RGBA])] = [("Brand", brand), ("Pastel", pastel), ("Drab", drab), ("Greyscale", greyscale)]
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
    /// TabListOverlapBorder: the hairline where the list's top-level rows overlap the header.
    public var tabListOverlapBorder: RGBA
    /// TabCellBackgroundMutiselected (sic): rows in a Cmd+click multiselection.
    public var tabMultiselected: RGBA
    /// TabCellSlash: the stroke between the panes of a split row.
    public var tabSlash: RGBA

    public static let light = SidebarTokens(
        foreground: RGBA(0, 0, 0, 0.3), foregroundStrong: RGBA(0, 0, 0, 0.45),
        itemBackground: RGBA(hex: "#0E0F10", alpha: 0.05), itemHover: RGBA(hex: "#0E0F10", alpha: 0.1),
        separator: RGBA(0, 0, 0, 0.15), border: RGBA(1, 1, 1, 0.3),
        tabCurrent: RGBA(1, 1, 1, 0.85), tabVisible: RGBA(1, 1, 1, 0.7),
        tabPrevious: RGBA(1, 1, 1, 0.32), tabPreviousHover: RGBA(1, 1, 1, 0.5),
        tabPressed: RGBA(hex: "#0E0F10", alpha: 0.065), tabChild: RGBA(0, 0, 0, 0.07),
        tabShadow: RGBA(0, 0, 0, 0.2), tabShadowBackground: RGBA(1, 1, 1, 0.9),
        dragHint: RGBA(0, 0, 0, 0.2), dragHintStrong: RGBA(0, 0, 0, 0.5),
        tabListOverlapBorder: RGBA(0, 0, 0, 0.05), tabMultiselected: RGBA(0, 0, 0, 0.1), tabSlash: RGBA(0, 0, 0, 0.3)
    )

    public static let dark = SidebarTokens(
        foreground: RGBA(1, 1, 1, 0.45), foregroundStrong: RGBA(1, 1, 1, 0.45),
        itemBackground: RGBA(hex: "#FAFBFF", alpha: 0.1), itemHover: RGBA(hex: "#FAFBFF", alpha: 0.15),
        separator: RGBA(1, 1, 1, 0.15), border: RGBA(1, 1, 1, 0.3),
        tabCurrent: RGBA(hex: "#FAFBFF", alpha: 0.2), tabVisible: RGBA(hex: "#FAFBFF", alpha: 0.15),
        tabPrevious: RGBA(hex: "#FAFBFF", alpha: 0.08), tabPreviousHover: RGBA(hex: "#FAFBFF", alpha: 0.12),
        tabPressed: RGBA(hex: "#FAFBFF", alpha: 0.065), tabChild: RGBA(1, 1, 1, 0.07),
        tabShadow: RGBA(0, 0, 0, 0), tabShadowBackground: RGBA(0, 0, 0, 0),
        dragHint: RGBA(1, 1, 1, 0.2), dragHintStrong: RGBA(1, 1, 1, 0.5),
        tabListOverlapBorder: RGBA(1, 1, 1, 0.05), tabMultiselected: RGBA(hex: "#FAFBFF", alpha: 0.1), tabSlash: RGBA(1, 1, 1, 0.3)
    )
}

/// What surfaces paint with. Derived by `resolveTheme`, never stored.
public struct ResolvedTheme: Hashable, Sendable, Codable {
    public var scheme: Scheme
    public var positions: [ThemePoint] = ThemePoint.anchors
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

/// Pure: stored theme -> paint values.
///
/// - Scheme: forced by `appearance`, else light when the primary's relative luminance is at least
///   `lightSchemeMinLuminance` (the luminance at which black and white text have equal WCAG contrast).
/// - Gradient: always three stops, primary first. The stored base colors come first (at most 3); the rest are the
///   primary's companions by the wheel rule: analogous = hue + offset and lighter, hue - offset and darker;
///   complementary = the opposite hue and lighter, then the primary's hue darker. Saturation is kept; lightness
///   moves by Metrics.theme.companionLightnessStep. Three base colors leave the wheel nothing to add (Arc's editor places them).
/// - Texture opacity: intensity x the texture's multiplier; texture contrast: the stored noise.
/// - Wash: white (light) or black at 35% (dark) with opacity min(0.2 + 0.55 x intensity, 0.5).
/// - Window color: the primary under the wash, so the window's own background matches the first Metal frame.
public func resolveTheme(_ theme: SpaceTheme, systemScheme: Scheme = .light) -> ResolvedTheme {
    if let variants = theme.variants {
        let scheme: Scheme = variants.selection == .auto ? systemScheme : (variants.selection == .dark ? .dark : .light)
        let style = (scheme == .dark ? variants.dark : variants.light).normalized
        var legacy = SpaceTheme(colors: style.colors.map(\.color), wheel: style.wheel, texture: style.texture,
                                noise: style.noise, intensity: style.intensity, appearance: scheme == .dark ? .dark : .light)
        legacy.colors = Array((legacy.colors + companions(of: legacy.colors[0], style.wheel)).prefix(3)).map { color in
            let (h, s, l) = hsl(color)
            return rgb(hue: h, saturation: clamp01(s * style.saturation),
                       lightness: clamp01((l + style.lightness) * (scheme == .dark ? 1 - style.darkBias * 0.8 : 1)))
        }
        var result = resolveTheme(legacy)
        result.positions = (0..<3).map { style.colors.indices.contains($0) ? style.colors[$0].position : ThemePoint.anchors[$0] }
        return result
    }
    let base = (theme.colors.isEmpty ? SpaceTheme.default.colors : Array(theme.colors.prefix(3))).map(opaque)
    let primary = base[0]
    let scheme: Scheme = switch theme.appearance {
    case .light: .light
    case .dark: .dark
    case .auto: relativeLuminance(primary) >= lightSchemeMinLuminance ? .light : .dark
    }
    let gradient = Array((base + companions(of: primary, theme.wheel)).prefix(3))
    let multiplier: Double = switch theme.texture {
    case .grain: Metrics.theme.grainOpacity.value
    case .sand: Metrics.theme.sandOpacity.value
    case .denim: Metrics.theme.denimOpacity.value
    case .tweed: Metrics.theme.tweedOpacity.value
    }
    let intensity = clamp01(theme.intensity)
    let washAlpha = min(Metrics.theme.washBase.value + Metrics.theme.washSlope.value * intensity, Metrics.theme.washCap.value)
    let wash = scheme == .light ? RGBA(1, 1, 1, washAlpha) : RGBA(0, 0, 0, Metrics.theme.darkWashAlpha.value * washAlpha)
    return ResolvedTheme(scheme: scheme, gradient: gradient, texture: theme.texture, textureOpacity: intensity * multiplier,
                         textureContrast: clamp01(theme.noise), wash: wash,
                         tokens: scheme == .light ? .light : .dark, windowColor: mix(primary, wash, wash.alpha))
}

/// sqrt(1.05 x 0.05) - 0.05 = 0.1791: above it black text has the higher WCAG contrast, so the scheme is light
/// (electron-v1 theme.ts `LIGHT_SCHEME_MIN_LUMINANCE`). The default Brand 8 blue (0.43) is light; #757575 is dark.
let lightSchemeMinLuminance = (1.05 * 0.05).squareRoot() - 0.05

/// The two companions of `primary` under `wheel`, opaque sRGB.
private func companions(of primary: RGBA, _ wheel: ColorWheel) -> [RGBA] {
    let (h, s, l) = hsl(primary)
    let step = Metrics.theme.companionLightnessStep.value
    let offsets: [(hue: Double, lightness: Double)] = switch wheel {
    case .analogous:
        [(Metrics.theme.analogousHueOffset.value, step), (-Metrics.theme.analogousHueOffset.value, -step)]
    case .complementary:
        [(Metrics.theme.complementaryHueOffset.value, step), (0, -step)]
    }
    return offsets.map { rgb(hue: h + $0.hue, saturation: s, lightness: clamp01(l + $0.lightness)) }
}

private func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

/// The color clamped into sRGB 0...1 (Arc stores extended sRGB) with alpha 1: the background is opaque.
private func opaque(_ c: RGBA) -> RGBA { RGBA(clamp01(c.red), clamp01(c.green), clamp01(c.blue), 1) }

/// Hue in degrees 0..<360, saturation and lightness 0...1.
private func hsl(_ c: RGBA) -> (Double, Double, Double) {
    let maxC = max(c.red, c.green, c.blue), minC = min(c.red, c.green, c.blue)
    let l = (maxC + minC) / 2, d = maxC - minC
    guard d > 0 else { return (0, 0, l) }
    let s = d / (1 - abs(2 * l - 1))
    let h: Double = if maxC == c.red { ((c.green - c.blue) / d).truncatingRemainder(dividingBy: 6) }
        else if maxC == c.green { (c.blue - c.red) / d + 2 }
        else { (c.red - c.green) / d + 4 }
    return ((h * 60 + 360).truncatingRemainder(dividingBy: 360), s, l)
}

private func rgb(hue: Double, saturation s: Double, lightness l: Double) -> RGBA {
    let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    let c = (1 - abs(2 * l - 1)) * s
    let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
    let m = l - c / 2
    let (r, g, b): (Double, Double, Double) = switch h {
    case ..<60: (c, x, 0)
    case ..<120: (x, c, 0)
    case ..<180: (0, c, x)
    case ..<240: (0, x, c)
    case ..<300: (x, 0, c)
    default: (c, 0, x)
    }
    return RGBA(clamp01(r + m), clamp01(g + m), clamp01(b + m), 1)
}

/// The light sidebar's title ink: the space's primary hue and saturation, as dark as #1A1A1A (relative luminance
/// 0.0103). Measured on Arc 1.170 (verify/visual-pairs/run-20261103): the #F2EAE4 theme writes its rows in #221910
/// (this gives #221811), a neutral theme in #1A1A1A, a teal one in #001E1D and a blank window's lavender in #090D4F;
/// all four sit within 0.001 of that luminance.
public func sidebarInk(_ primary: RGBA) -> RGBA {
    themeShade(primary, luminance: relativeLuminance(RGBA(26 / 255, 26 / 255, 26 / 255)))
}

/// `primary`'s hue and HSL saturation at the HSL lightness (at most 0.5) whose relative luminance is `target`.
public func themeShade(_ primary: RGBA, luminance target: Double) -> RGBA {
    let (h, s, _) = hsl(opaque(primary))
    var lo = 0.0, hi = 0.5
    for _ in 0..<32 {
        let mid = (lo + hi) / 2
        if relativeLuminance(rgb(hue: h, saturation: s, lightness: mid)) < target { lo = mid } else { hi = mid }
    }
    return rgb(hue: h, saturation: s, lightness: (lo + hi) / 2)
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
