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
    /// 0...1 (Arc: `noiseFactor`, the editor's dial). Scales the texture overlay's opacity.
    public var noise: Double
    /// 0...1: how strong the wash over the color is. Arc's `intensityFactor` (its sine slider's position) runs the
    /// other way, more color to the right, so an imported theme stores 1 - intensityFactor. Controls the theme layer's
    /// alpha (`themeLayer`); the texture has its own noise control.
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
    /// 2a96a9d7f0:verify/visual-pairs/run-20261103 P07-b); grain, noise 0.5 and intensity 0.25 are still guesses.
    public static let `default` = SpaceTheme(colors: [ThemePresets.brand[0]], texture: .grain, intensity: 0.25, appearance: .auto)
}

/// Arc's four 9-color picker sets (visual-and-copy.md, "Space theme preset palette"). Brand5 uses the rendered value
/// #FF8558. `pages` is Arc 1.170's page order in the theme panel (captured 2026-11-03, P28 c): Brand, Pastel, Drab,
/// Greyscale. The hex values are Display P3 (Arc's editor builds colors in that space, bin 0x100d80814; its saved blue
/// Brand preset is #7EB8D6 in P3 to the last digit), so each is converted to sRGB here.
public enum ThemePresets {
    public static let pages: [(name: String, colors: [RGBA])] = [("Brand", brand), ("Pastel", pastel), ("Drab", drab), ("Greyscale", greyscale)]
    public static let brand: [RGBA] = {
        var colors = p3(["#F2EAE4", "#F29BBB", "#A6729D", "#F25E6B", "#FF8558", "#F2D66D", "#73E59C", "#7EB8D6", "#666786"])
        // Arc's default beige is stored directly as extended sRGB, unlike the picker hex colors.
        colors[0] = RGBA(0.95, 0.918, 0.894)
        colors[7] = RGBA(0.4236151278, 0.7285773754, 0.8512415886)
        return colors
    }()
    public static let drab = p3(["#4B3B58", "#623856", "#854444", "#A77048", "#D1B46A", "#CDCCA8", "#84A885", "#34604B", "#2D4468"])
    public static let greyscale = p3(["#FFFFFF", "#E5E5E5", "#CCCCCC", "#B2B2B2", "#808080", "#666666", "#333333", "#1A1A1A", "#000000"])
    public static let pastel = p3(["#FDFBFA", "#FBEAF3", "#ECD2EA", "#F7CDD2", "#FAE1D5", "#FEF9E7", "#E4FCEC", "#E0F2FB", "#C5C6E2"])

    /// The theme colors a swatch gives: Arc's Brand swatches are three-color themes on the analogous wheel (its saved beige
    /// and blue: the swatch, +40 and -40 in Display P3); the other pages give the one color.
    public static func colors(page: Int, index: Int) -> [RGBA] {
        guard pages.indices.contains(page), pages[page].colors.indices.contains(index) else { return [] }
        let color = pages[page].colors[index]
        return page == 0 ? themeWheelColors(color, count: 3, wheel: .analogous) : [color]
    }

    private static func p3(_ hex: [String]) -> [RGBA] { hex.map { sRGB(fromDisplayP3: RGBA(hex: $0)) } }
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
    /// The texture's alpha: the stored noise x the texture's multiplier (Metrics.theme.*Opacity; Arc bin 0x101530cdc), times
    /// the tile's own alpha.
    public var textureOpacity: Double
    /// The theme as one solid color layer, for surfaces that cannot show the window's material (previews, the floating
    /// sidebar, the no-Metal fallback): `underlay` over the material's stand-in color (`ThemeMaterial.standIn`), at
    /// 1 - `layerAlpha` over the gradient. mix(gradient, wash, wash.alpha) is what the window shows over that backdrop.
    public var wash: RGBA
    public var tokens: SidebarTokens
    /// Solid color for the NSWindow background, visible only before the first Metal frame: the primary under `wash`.
    public var windowColor: RGBA
    /// The system material under the theme (Arc: the NSVisualEffectView of `WindowBackgroundTranslucencyViewAppKit`).
    public var material: ThemeMaterial = .light
    /// Material grey used by previews and the no-Metal fallback, where the desktop cannot be sampled.
    public var materialBackdrop: Double = ThemeMaterial.standIn(.light)
    /// How much of the gradient covers the material and the underlay (Arc's GradientLayer alpha). 1: opaque.
    public var layerAlpha: Double = 1
    /// Inside the theme layer, under the gradient (Arc's `underlayColor`): what the material shows through, dimmed.
    public var underlay: RGBA = RGBA(0, 0, 0, 0)
}

/// The NSVisualEffectView material under a window's theme. Arc 1.170 draws its saved themes over `.light` in both macOS
/// modes (docs/checks/2026-11-13-window-translucency.md); `.opaque` is a theme that covers it whole (incognito).
public enum ThemeMaterial: String, Hashable, Sendable, Codable {
    case light, opaque

    /// The material's color over a stand-in backdrop, for `ResolvedTheme.wash`: with nothing behind (what a window
    /// capture shows) in light mode, over black in dark mode (dark-mode users mostly have dark windows behind).
    public static func standIn(_ systemScheme: Scheme) -> Double {
        systemScheme == .dark ? Metrics.theme.materialOverBlack.value : Metrics.theme.materialEmpty.value
    }
}

/// Pure: stored theme -> paint values.
///
/// - Scheme: dark for the dark `appearance` or a primary whose relative luminance is under `lightSchemeMinLuminance`
///   (the luminance at which black and white text have equal WCAG contrast), else light.
/// - Gradient: the stored base colors, 1 to 3 (`gradientStops`); no companions are added at draw time (Arc's editor adds
///   them when colors are added, `themeWheelColors`).
/// - Texture opacity: the stored noise x the texture's multiplier (Arc's `noiseFactor`).
/// - Layer: `themeLayer` (alpha, underlay, material); `wash` is that layer as one solid color.
/// - Window color: the primary under the wash, so the window's own background matches the first Metal frame.
public func resolveTheme(_ theme: SpaceTheme, systemScheme: Scheme = .light) -> ResolvedTheme {
    resolveTheme(theme, systemScheme: systemScheme, followsSystem: theme.appearance == .auto)
}

/// `followsSystem`: the theme takes macOS's light or dark mode (a stored `auto`, or a light/dark pair set to follow it).
private func resolveTheme(_ theme: SpaceTheme, systemScheme: Scheme, followsSystem: Bool) -> ResolvedTheme {
    if let variants = theme.variants {
        let scheme: Scheme = variants.selection == .auto ? systemScheme : (variants.selection == .dark ? .dark : .light)
        let style = (scheme == .dark ? variants.dark : variants.light).normalized
        var legacy = SpaceTheme(colors: style.colors.map(\.color), wheel: style.wheel, texture: style.texture,
                                noise: style.noise, intensity: style.intensity, appearance: scheme == .dark ? .dark : .light)
        legacy.colors = gradientStops(legacy.colors.map(opaque)).map { color in
            if style.saturation == 1, style.lightness == 0, scheme == .light || style.darkBias == 0 { return color }
            let (h, s, l) = hsl(color)
            return rgb(hue: h, saturation: clamp01(s * style.saturation),
                       lightness: clamp01((l + style.lightness) * (scheme == .dark ? 1 - style.darkBias * 0.8 : 1)))
        }
        var result = resolveTheme(legacy, systemScheme: systemScheme, followsSystem: variants.selection == .auto)
        result.positions = (0..<3).map { style.colors.indices.contains($0) ? style.colors[$0].position : ThemePoint.anchors[$0] }
        return result
    }
    let base = (theme.colors.isEmpty ? SpaceTheme.default.colors : Array(theme.colors.prefix(3))).map(opaque)
    let primary = base[0]
    // A dark color keeps its light ink under Arc's automatic and light buttons alike; they draw the same sidebar
    // (f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md, the navy preset under each button).
    let darkPrimary = relativeLuminance(primary) < lightSchemeMinLuminance
    let scheme: Scheme = switch theme.appearance {
    case .light, .auto: darkPrimary ? .dark : .light
    case .dark: .dark
    }
    let gradient = gradientStops(base)
    let multiplier: Double = switch theme.texture {
    case .grain: Metrics.theme.grainOpacity.value
    case .sand: Metrics.theme.sandOpacity.value
    case .denim: Metrics.theme.denimOpacity.value
    case .tweed: Metrics.theme.tweedOpacity.value
    }
    let intensity = clamp01(theme.intensity)
    let layer = themeLayer(followsDarkSystem: followsSystem && systemScheme == .dark, intensity: intensity)
    let wash = solidWash(alpha: layer.alpha, underlay: layer.underlay, systemScheme: systemScheme)
    var resolved = ResolvedTheme(scheme: scheme, gradient: gradient, texture: theme.texture, textureOpacity: clamp01(theme.noise) * multiplier,
                                 wash: wash, tokens: scheme == .light ? .light : .dark, windowColor: mix(gradient[0], wash, wash.alpha))
    resolved.layerAlpha = layer.alpha
    resolved.underlay = layer.underlay
    resolved.materialBackdrop = ThemeMaterial.standIn(systemScheme)
    return resolved
}

extension ResolvedTheme {
    /// An incognito window's chrome: a fixed color under the plain black wash; it has no slider, and
    /// the rules for a space's own dark color do not apply. Opaque: Arc's incognito window shows nothing of what is
    /// behind it (#12151B over a black and a white backdrop alike, docs/checks/2026-11-13-window-translucency.md).
    public static let incognito: ResolvedTheme = {
        let primary = RGBA(hex: "#14171E")
        var theme = resolveTheme(SpaceTheme(colors: [primary], texture: .grain, intensity: SpaceTheme.default.intensity, appearance: .dark))
        let m = Metrics.theme
        let veil = m.darkWashAlpha.value * min(m.washBase.value + m.washSlope.value * SpaceTheme.default.intensity, m.washCap.value)
        theme.gradient = [mix(primary, RGBA(0, 0, 0), veil)]
        theme.material = .opaque
        theme.layerAlpha = 1
        theme.underlay = RGBA(0, 0, 0, 0)
        theme.wash = RGBA(0, 0, 0, 0)
        theme.windowColor = theme.gradient[0]
        return theme
    }()
}

/// Arc's theme layer over the window's material (bin 0x101530d98 builds it, the WindowThemeUI metallib's
/// gradientFragment draws it; docs/checks/2026-11-13-window-translucency.md): the gradient at alpha 0.2 + 0.55 x the
/// slider position (Arc's `intensityFactor` = 1 - Brk's intensity), over an underlay that is white at min(that, 0.5),
/// or black at 35% of it when the window is dark: measured on Arc 1.170, a theme that follows macOS while macOS is in
/// dark mode, or websites set to Dark. The sun and moon buttons do not change the layer: the moon changes the colors
/// the editor saves (SpaceStyleEditor.State.darkModeBiasSetting), not how they are drawn.
private func themeLayer(followsDarkSystem: Bool, intensity: Double) -> (alpha: Double, underlay: RGBA) {
    let m = Metrics.theme
    let alpha = m.washBase.value + m.washSlope.value * (1 - intensity)
    let cover = min(alpha, m.washCap.value)
    let underlay = followsDarkSystem ? RGBA(0, 0, 0, m.darkWashAlpha.value * cover) : RGBA(1, 1, 1, cover)
    return (alpha, underlay)
}

/// The theme layer and the `.light` material's stand-in color as one wash over the gradient (`ResolvedTheme.wash`).
private func solidWash(alpha: Double, underlay: RGBA, systemScheme: Scheme) -> RGBA {
    let grey = ThemeMaterial.standIn(systemScheme)
    let u = underlay.alpha
    return RGBA(u * underlay.red + (1 - u) * grey, u * underlay.green + (1 - u) * grey, u * underlay.blue + (1 - u) * grey, 1 - alpha)
}

/// sqrt(1.05 x 0.05) - 0.05 = 0.1791: above it black text has the higher WCAG contrast, so the scheme is light
/// (electron-v1 theme.ts `LIGHT_SCHEME_MIN_LUMINANCE`). The default Brand 8 blue (0.43) is light; #757575 is dark.
let lightSchemeMinLuminance = (1.05 * 0.05).squareRoot() - 0.05

/// Arc's renderer draws a theme's stored colors and nothing else (bin 0x101530d98; docs/checks/2026-11-13-window-translucency.md,
/// round 2): one color is one flat color, two are the diagonal ramp, a third is the overlay ramp from the top. Extra
/// colors come from the editor's wheel when they are added (`themeWheelColors`), not at draw time.
private func gradientStops(_ base: [RGBA]) -> [RGBA] { Array(base.prefix(3)) }

/// Arc's color wheel (bin 0x100d807dc): the primary and `count - 1` more colors at hue turns in Display P3 that keep its
/// HSL saturation and lightness. Analogous: +40, then -40. Complementary: +180 for two colors, +150 and +210 for three.
/// More than three: evenly spread. Checked against what Arc saved for its beige and blue Brand presets.
public func themeWheelColors(_ primary: RGBA, count: Int, wheel: ColorWheel) -> [RGBA] {
    guard count > 1 else { return [primary] }
    let a = Metrics.theme.analogousTurn.value, c = Metrics.theme.complementaryTurns.value
    let turns: [Double] = switch (count, wheel) {
    case (2, .analogous): [a]
    case (2, .complementary): [c[0]]
    case (3, .analogous): [a, -a]
    case (3, .complementary): [c[1], c[2]]
    default: (1..<count).map { Double($0) * 360 / Double(count) }
    }
    let (h, sat, l) = hsl(displayP3(fromSRGB: opaque(primary)))
    return [primary] + turns.map { sRGB(fromDisplayP3: rgb(hue: h + $0, saturation: sat, lightness: l)) }
}

/// Linear-light conversions between sRGB and Display P3 (same white point and transfer curve).
private func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
private func gam(_ v: Double) -> Double { v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }

func displayP3(fromSRGB c: RGBA) -> RGBA {
    if c.red == c.green && c.green == c.blue { return c }
    let r = lin(c.red), g = lin(c.green), b = lin(c.blue)
    return RGBA(gam(0.8224621 * r + 0.1775380 * g), gam(0.0331941 * r + 0.9668058 * g),
                gam(0.0170827 * r + 0.0723974 * g + 0.9105199 * b), c.alpha)
}

func sRGB(fromDisplayP3 c: RGBA) -> RGBA {
    if c.red == c.green && c.green == c.blue { return c }
    let r = lin(c.red), g = lin(c.green), b = lin(c.blue)
    return RGBA(clamp01(gam(1.2249401 * r - 0.2249404 * g)), clamp01(gam(-0.0420569 * r + 1.0420571 * g)),
                clamp01(gam(-0.0196376 * r - 0.0786361 * g + 1.0982735 * b)), c.alpha)
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
/// 0.0103). Measured on Arc 1.170 (2a96a9d7f0:verify/visual-pairs/run-20261103): the #F2EAE4 theme writes its rows in #221910
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
