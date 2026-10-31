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

/// CPU preview/fallback uses the same Gaussian weights and anchors as the Metal shader.
public func themeSample(_ theme: ResolvedTheme, at point: ThemePoint, textureLuminance: Double = 1) -> RGBA {
    var r = 0.0, g = 0.0, b = 0.0, total = 0.0
    for (i, color) in theme.gradient.prefix(3).enumerated() {
        let anchor = theme.positions.indices.contains(i) ? theme.positions[i] : ThemePoint.anchors[i]
        let dx = point.x - anchor.x, dy = point.y - anchor.y
        let weight = (i == 0 ? 1.5 : 1) * exp(-(dx * dx + dy * dy) / (2 * 0.42 * 0.42))
        r += color.red * weight; g += color.green * weight; b += color.blue * weight; total += weight
    }
    let factor = 1 - theme.textureOpacity * (1 - textureLuminance)
    let color = RGBA(r / max(total, 1e-6) * factor, g / max(total, 1e-6) * factor, b / max(total, 1e-6) * factor)
    return mix(color, theme.wash, theme.wash.alpha)
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
    let luminance = 0.5 + (min(max(value, 0), 1) - 0.5) * theme.textureContrast
    return themeSample(theme, at: point, textureLuminance: luminance)
}
