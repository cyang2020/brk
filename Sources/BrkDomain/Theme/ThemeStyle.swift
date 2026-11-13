import BrkBase
import Foundation

public struct ThemePoint: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public static let anchors = [ThemePoint(x: 0.1, y: 0.15), ThemePoint(x: 0.95, y: 0.25), ThemePoint(x: 0.5, y: 1)]
}

public struct ThemeColor: Hashable, Sendable, Codable {
    public var color: RGBA
    public var position: ThemePoint
    public init(color: RGBA, position: ThemePoint) { self.color = color; self.position = position }
}

/// A complete editable appearance. A pair owns two independent values, including textures.
public struct ThemeStyle: Hashable, Sendable, Codable {
    public var colors: [ThemeColor]
    public var wheel: ColorWheel
    public var texture: Texture
    public var noise: Double
    public var intensity: Double
    public var saturation: Double
    public var lightness: Double
    public var darkBias: Double

    public init(legacy: SpaceTheme) {
        colors = legacy.colors.prefix(3).enumerated().map { ThemeColor(color: $0.element, position: ThemePoint.anchors[$0.offset]) }
        wheel = legacy.wheel; texture = legacy.texture; noise = legacy.noise; intensity = legacy.intensity
        saturation = 1; lightness = 0; darkBias = 0
    }

    public var normalized: ThemeStyle {
        var value = self
        value.colors = (colors.isEmpty ? ThemeStyle(legacy: .default).colors : Array(colors.prefix(3))).enumerated().map { i, stop in
            ThemeColor(color: RGBA(unit(stop.color.red), unit(stop.color.green), unit(stop.color.blue)),
                       position: ThemePoint(x: finite(stop.position.x, fallback: ThemePoint.anchors[i].x, range: 0...1),
                                            y: finite(stop.position.y, fallback: ThemePoint.anchors[i].y, range: 0...1)))
        }
        value.noise = finite(noise, fallback: 0.5, range: 0...1)
        value.intensity = finite(intensity, fallback: 0.25, range: 0...1)
        value.saturation = finite(saturation, fallback: 1, range: 0...2)
        value.lightness = finite(lightness, fallback: 0, range: -1...1)
        value.darkBias = finite(darkBias, fallback: 0, range: 0...1)
        return value
    }
}

public struct ThemeVariants: Hashable, Sendable, Codable {
    public var light: ThemeStyle
    public var dark: ThemeStyle
    /// Within the new representation, auto means the native system appearance.
    public var selection: AppearanceChoice
    public init(legacy: SpaceTheme) {
        light = ThemeStyle(legacy: legacy); dark = light
        selection = resolveTheme(legacy).scheme == .dark ? .dark : .light
    }
}

/// The sites adapter receives paint values only, never stored metadata or editor drafts.
public struct WebsiteThemeValues: Hashable, Sendable, Codable {
    public let scheme: Scheme
    public let accent: RGBA
    public let background: RGBA
    public let foreground: RGBA
}

extension ResolvedTheme {
    public var websiteValues: WebsiteThemeValues {
        WebsiteThemeValues(scheme: scheme, accent: gradient.first ?? windowColor, background: windowColor,
                           foreground: scheme == .dark ? RGBA(1, 1, 1) : RGBA(0, 0, 0))
    }
}

func finite(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
    value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
}
private func unit(_ value: Double) -> Double { finite(value, fallback: 0, range: 0...1) }

/// Where Arc's diagonal ramp (from the first base color to the second) stands at the window's four corners, for a window
/// `aspect` = width / height (WindowThemeUI renderVertex and gradientVertex): the ramp runs at 45 degrees through the
/// middle across the shorter side, and the shader interpolates the clamped corner values over the two triangles of the
/// quad (top-left, top-right, bottom-left, bottom-right).
public func themeRampCorners(aspect: Double) -> [Double] {
    let a = max(aspect, 1e-6)
    let (start, end): ((Double, Double), (Double, Double)) = a >= 1
        ? ((0.5 - 0.5 / a, 0), (0.5 + 0.5 / a, 1))
        : ((0, 0.5 - 0.5 * a), (1, 0.5 + 0.5 * a))
    let dx = end.0 - start.0, dy = end.1 - start.1, length2 = dx * dx + dy * dy
    return [(0.0, 0.0), (1, 0), (0, 1), (1, 1)].map { p in min(max(((p.0 - start.0) * dx + (p.1 - start.1) * dy) / length2, 0), 1) }
}

/// The ramp at `point` from the corner values (`themeRampCorners`), as the two triangles of the quad interpolate it.
public func themeRamp(_ corners: [Double], at point: ThemePoint) -> Double {
    let (u, v) = (point.x, point.y)
    return u + v <= 1 ? corners[0] + u * (corners[1] - corners[0]) + v * (corners[2] - corners[0])
        : corners[3] + (1 - u) * (corners[2] - corners[3]) + (1 - v) * (corners[1] - corners[3])
}

/// Arc's theme color at `point` before the underlay (WindowThemeUI gradientFragment): the base colors mixed in OKLab along
/// the diagonal ramp, full at three quarters of it; a third color mixed in from clear at the top, full at three quarters
/// of the height, laid over the base in linear light. Both layers use the theme's alpha.
public func themeGradientColor(_ theme: ResolvedTheme, at point: ThemePoint, aspect: Double = 1280.0 / 776) -> RGBA {
    let colors = theme.gradient.isEmpty ? [RGBA(1, 1, 1)] : theme.gradient
    let s1 = min(max(themeRamp(themeRampCorners(aspect: aspect), at: point) * 4 / 3, 0), 1)
    let base = OKLabColor.mix(OKLabColor(colors[0]), OKLabColor(colors.count > 1 ? colors[1] : colors[0]), s1).linear
    let alpha = unit(theme.layerAlpha)
    guard colors.count > 2 else {
        var color = OKLabColor.encode(base)
        color.alpha = alpha
        return color
    }
    let a = min(max(point.y * 4 / 3, 0), 1) * alpha
    let coverage = a + alpha * (1 - a)
    let over = OKLabColor(colors[2]).linear
    var color = OKLabColor.encode((0..<3).map { (base[$0] * alpha * (1 - a) + over[$0] * a) / max(coverage, 1e-6) })
    color.alpha = coverage
    return color
}

/// The same composition as the Metal renderer: gradient over underlay, multiply texture over both, then material.
public func themeSample(_ theme: ResolvedTheme, at point: ThemePoint, textureLuminance: Double = 1,
                        aspect: Double = 1280.0 / 776) -> RGBA {
    let color = themeGradientColor(theme, at: point, aspect: aspect)
    let under = theme.underlay
    let coverage = color.alpha + under.alpha * (1 - color.alpha)
    let overlayAlpha = theme.textureOpacity * textureTone(theme.texture).alpha
    let overlay = textureLuminance * overlayAlpha
    let alpha = overlayAlpha + coverage * (1 - overlayAlpha)
    func channel(_ value: Double, _ underValue: Double) -> Double {
        let layer = value * color.alpha + underValue * under.alpha * (1 - color.alpha)
        return overlay * layer + overlay * (1 - coverage) + layer * (1 - overlayAlpha)
            + theme.materialBackdrop * (1 - alpha)
    }
    return RGBA(channel(color.red, under.red), channel(color.green, under.green), channel(color.blue, under.blue))
}

/// The grey mean and spread of Arc's tile for `texture`, and its alpha (Metrics.theme.*Tone).
public func textureTone(_ texture: Texture) -> (mean: Double, spread: Double, alpha: Double) {
    let t = switch texture {
    case .grain: Metrics.theme.grainTone.value
    case .sand: Metrics.theme.sandTone.value
    case .denim: Metrics.theme.denimTone.value
    case .tweed: Metrics.theme.tweedTone.value
    }
    return (t[0], t[1], t[2])
}

/// A small deterministic preview of the procedural overlay. The full background uses TexturePixels' GPU tiles.
/// This preview keeps noise, intensity and texture visible while a draft is edited without persisting it.
public func themePreviewSample(_ theme: ResolvedTheme, at point: ThemePoint) -> RGBA {
    let x = floor(point.x * 160), y = floor(point.y * 120)
    func random(_ x: Double, _ y: Double) -> Double {
        let value = sin(x * 12.9898 + y * 78.233) * 43758.5453
        return value - floor(value)
    }
    let value: Double = switch theme.texture {
    case .grain: random(x, y)
    case .sand: random(floor(x / 3), floor(y / 3))
    case .denim: 0.5 + 0.3 * sin((x + y) * 1.8) + 0.15 * (random(x, y) - 0.5)
    case .tweed: 0.5 + 0.3 * sin(x * 1.8) * sin(y * 1.6) + 0.15 * (random(x, y) - 0.5)
    }
    let tone = textureTone(theme.texture)
    let luminance = tone.mean + (min(max(value, 0), 1) - 0.5) * 2 * tone.spread
    return themeSample(theme, at: point, textureLuminance: luminance)
}

/// OKLab (Björn Ottosson's), as Arc's theme shader mixes its colors.
public struct OKLabColor {
    public var l: Double, a: Double, b: Double

    public init(_ c: RGBA) {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = lin(c.red), g = lin(c.green), bl = lin(c.blue)
        let l_ = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m_ = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s_ = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    }

    public init(l: Double, a: Double, b: Double) { self.l = l; self.a = a; self.b = b }

    static func mix(_ x: OKLabColor, _ y: OKLabColor, _ t: Double) -> OKLabColor {
        OKLabColor(l: x.l + (y.l - x.l) * t, a: x.a + (y.a - x.a) * t, b: x.b + (y.b - x.b) * t)
    }

    /// Linear-light sRGB.
    var linear: [Double] {
        let l_ = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m_ = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s_ = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        return [4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
                -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
                -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_]
    }

    static func encode(_ linear: [Double]) -> RGBA {
        func gam(_ v: Double) -> Double { v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }
        let c = linear.map { min(max(gam($0), 0), 1) }
        return RGBA(c[0], c[1], c[2])
    }
}
