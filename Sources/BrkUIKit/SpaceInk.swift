import AppKit
import BrkBase
import BrkDomain

/// A Space's own color made to read on a column of `scheme`: its hue at a mid-dark shade (relative luminance `luminance`)
/// on a light column, bright on a dark one. The dock's ring for a Space where something waits, and the Space dots of the
/// AI conversation lists (docs/design/ai-threads.md), all draw it this way: a pastel theme's raw color is near white.
public enum SpaceInk {
    public static func readable(_ color: RGBA, on scheme: Scheme, luminance: Double) -> NSColor {
        if scheme == .light {
            let shade = themeShade(color, luminance: luminance)
            return NSColor(srgbRed: shade.red, green: shade.green, blue: shade.blue, alpha: 1)
        }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(0.6, saturation * 9), brightness: 0.85, alpha: 1)
    }

    /// The shade the lists' dots use.
    public static let dotLuminance = 0.15
}
