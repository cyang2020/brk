import BrkBase
import Foundation

/// A colour the command bar reads: `#ff5500`, `#f50`, `rgb(255,85,0)`, `hsl(20,100%,50%)` as they are, CSS names only
/// after the `color` prefix. Its row shows a swatch and its hex, rgb and hsl forms; Return copies the row's form.
public struct QuickColor: Equatable, Sendable {
    public let red: Int, green: Int, blue: Int

    public init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    public var rgb: String { "rgb(\(red), \(green), \(blue))" }

    public var hsl: String {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let high = max(r, g, b), low = min(r, g, b), delta = high - low, lightness = (high + low) / 2
        guard delta > 0 else { return "hsl(0, 0%, \(Int((lightness * 100).rounded()))%)" }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        if high == r { hue = (g - b) / delta } else if high == g { hue = (b - r) / delta + 2 } else { hue = (r - g) / delta + 4 }
        hue *= 60
        if hue < 0 { hue += 360 }
        return "hsl(\(Int(hue.rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
    }

    public var rgba: RGBA { RGBA(Double(red) / 255, Double(green) / 255, Double(blue) / 255) }
}

public enum QuickColors {
    /// A colour written out in full leads its rows. `#abc` (three digits) sits under the typed row: it can as well be a
    /// tag someone is searching for, so Return still searches.
    public static func leads(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces)
        return parse(text) != nil && !(text.hasPrefix("#") && text.count == 4)
    }

    /// `names`: the CSS names too, which only the `color` prefix reads: on their own they are ordinary words.
    public static func parse(_ text: String, names: Bool = false) -> QuickColor? {
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") { return hex(String(text.dropFirst())) }
        if let parts = arguments(text, of: "rgb"), parts.count == 3 {
            let values = parts.compactMap(Int.init)
            guard values.count == 3, values.allSatisfy({ (0...255).contains($0) }) else { return nil }
            return QuickColor(red: values[0], green: values[1], blue: values[2])
        }
        if let parts = arguments(text, of: "hsl"), parts.count == 3 {
            guard let hue = Double(parts[0].replacingOccurrences(of: "deg", with: "")), parts[1].hasSuffix("%"), parts[2].hasSuffix("%"),
                  let saturation = Double(parts[1].dropLast()), let lightness = Double(parts[2].dropLast()),
                  (0...360).contains(hue), (0...100).contains(saturation), (0...100).contains(lightness) else { return nil }
            return fromHSL(hue, saturation / 100, lightness / 100)
        }
        guard names else { return nil }
        if let value = named[text.replacingOccurrences(of: " ", with: "")] { return QuickColor(red: value >> 16 & 255, green: value >> 8 & 255, blue: value & 255) }
        return hex(text)
    }

    private static func hex(_ digits: String) -> QuickColor? {
        guard digits.count == 3 || digits.count == 6, digits.allSatisfy(\.isHexDigit), digits.allSatisfy(\.isASCII) else { return nil }
        let full = digits.count == 3 ? digits.map { "\($0)\($0)" }.joined() : digits
        guard let value = Int(full, radix: 16) else { return nil }
        return QuickColor(red: value >> 16 & 255, green: value >> 8 & 255, blue: value & 255)
    }

    /// "rgb(255, 85, 0)" or "rgb(255 85 0)": what is inside the brackets.
    private static func arguments(_ text: String, of name: String) -> [String]? {
        guard text.hasPrefix(name + "("), text.hasSuffix(")") else { return nil }
        return text.dropFirst(name.count + 1).dropLast().split { $0 == "," || $0.isWhitespace }.map(String.init)
    }

    private static func fromHSL(_ hue: Double, _ saturation: Double, _ lightness: Double) -> QuickColor {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let part = hue.truncatingRemainder(dividingBy: 360) / 60
        let second = chroma * (1 - abs(part.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch Int(part) {
        case 0: (chroma, second, 0)
        case 1: (second, chroma, 0)
        case 2: (0, chroma, second)
        case 3: (0, second, chroma)
        case 4: (second, 0, chroma)
        default: (chroma, 0, second)
        }
        let match = lightness - chroma / 2
        func byte(_ value: Double) -> Int { Int(((value + match) * 255).rounded()) }
        return QuickColor(red: byte(r), green: byte(g), blue: byte(b))
    }

    /// CSS Color Module Level 4's named colours.
    static let named: [String: Int] = [
        "aliceblue": 0xF0F8FF, "antiquewhite": 0xFAEBD7, "aqua": 0x00FFFF, "aquamarine": 0x7FFFD4, "azure": 0xF0FFFF, "beige": 0xF5F5DC, "bisque": 0xFFE4C4, "black": 0x000000,
        "blanchedalmond": 0xFFEBCD, "blue": 0x0000FF, "blueviolet": 0x8A2BE2, "brown": 0xA52A2A, "burlywood": 0xDEB887, "cadetblue": 0x5F9EA0, "chartreuse": 0x7FFF00,
        "chocolate": 0xD2691E, "coral": 0xFF7F50, "cornflowerblue": 0x6495ED, "cornsilk": 0xFFF8DC, "crimson": 0xDC143C, "cyan": 0x00FFFF, "darkblue": 0x00008B, "darkcyan": 0x008B8B,
        "darkgoldenrod": 0xB8860B, "darkgray": 0xA9A9A9, "darkgreen": 0x006400, "darkgrey": 0xA9A9A9, "darkkhaki": 0xBDB76B, "darkmagenta": 0x8B008B, "darkolivegreen": 0x556B2F,
        "darkorange": 0xFF8C00, "darkorchid": 0x9932CC, "darkred": 0x8B0000, "darksalmon": 0xE9967A, "darkseagreen": 0x8FBC8F, "darkslateblue": 0x483D8B, "darkslategray": 0x2F4F4F,
        "darkslategrey": 0x2F4F4F, "darkturquoise": 0x00CED1, "darkviolet": 0x9400D3, "deeppink": 0xFF1493, "deepskyblue": 0x00BFFF, "dimgray": 0x696969, "dimgrey": 0x696969,
        "dodgerblue": 0x1E90FF, "firebrick": 0xB22222, "floralwhite": 0xFFFAF0, "forestgreen": 0x228B22, "fuchsia": 0xFF00FF, "gainsboro": 0xDCDCDC, "ghostwhite": 0xF8F8FF,
        "gold": 0xFFD700, "goldenrod": 0xDAA520, "gray": 0x808080, "green": 0x008000, "greenyellow": 0xADFF2F, "grey": 0x808080, "honeydew": 0xF0FFF0, "hotpink": 0xFF69B4,
        "indianred": 0xCD5C5C, "indigo": 0x4B0082, "ivory": 0xFFFFF0, "khaki": 0xF0E68C, "lavender": 0xE6E6FA, "lavenderblush": 0xFFF0F5, "lawngreen": 0x7CFC00, "lemonchiffon": 0xFFFACD,
        "lightblue": 0xADD8E6, "lightcoral": 0xF08080, "lightcyan": 0xE0FFFF, "lightgoldenrodyellow": 0xFAFAD2, "lightgray": 0xD3D3D3, "lightgreen": 0x90EE90, "lightgrey": 0xD3D3D3,
        "lightpink": 0xFFB6C1, "lightsalmon": 0xFFA07A, "lightseagreen": 0x20B2AA, "lightskyblue": 0x87CEFA, "lightslategray": 0x778899, "lightslategrey": 0x778899,
        "lightsteelblue": 0xB0C4DE, "lightyellow": 0xFFFFE0, "lime": 0x00FF00, "limegreen": 0x32CD32, "linen": 0xFAF0E6, "magenta": 0xFF00FF, "maroon": 0x800000,
        "mediumaquamarine": 0x66CDAA, "mediumblue": 0x0000CD, "mediumorchid": 0xBA55D3, "mediumpurple": 0x9370DB, "mediumseagreen": 0x3CB371, "mediumslateblue": 0x7B68EE,
        "mediumspringgreen": 0x00FA9A, "mediumturquoise": 0x48D1CC, "mediumvioletred": 0xC71585, "midnightblue": 0x191970, "mintcream": 0xF5FFFA, "mistyrose": 0xFFE4E1,
        "moccasin": 0xFFE4B5, "navajowhite": 0xFFDEAD, "navy": 0x000080, "oldlace": 0xFDF5E6, "olive": 0x808000, "olivedrab": 0x6B8E23, "orange": 0xFFA500, "orangered": 0xFF4500,
        "orchid": 0xDA70D6, "palegoldenrod": 0xEEE8AA, "palegreen": 0x98FB98, "paleturquoise": 0xAFEEEE, "palevioletred": 0xDB7093, "papayawhip": 0xFFEFD5, "peachpuff": 0xFFDAB9,
        "peru": 0xCD853F, "pink": 0xFFC0CB, "plum": 0xDDA0DD, "powderblue": 0xB0E0E6, "purple": 0x800080, "rebeccapurple": 0x663399, "red": 0xFF0000, "rosybrown": 0xBC8F8F,
        "royalblue": 0x4169E1, "saddlebrown": 0x8B4513, "salmon": 0xFA8072, "sandybrown": 0xF4A460, "seagreen": 0x2E8B57, "seashell": 0xFFF5EE, "sienna": 0xA0522D, "silver": 0xC0C0C0,
        "skyblue": 0x87CEEB, "slateblue": 0x6A5ACD, "slategray": 0x708090, "slategrey": 0x708090, "snow": 0xFFFAFA, "springgreen": 0x00FF7F, "steelblue": 0x4682B4, "tan": 0xD2B48C,
        "teal": 0x008080, "thistle": 0xD8BFD8, "tomato": 0xFF6347, "turquoise": 0x40E0D0, "violet": 0xEE82EE, "wheat": 0xF5DEB3, "white": 0xFFFFFF, "whitesmoke": 0xF5F5F5,
        "yellow": 0xFFFF00, "yellowgreen": 0x9ACD32,
    ]
}
