import AppKit

private struct IconFailure: Error, CustomStringConvertible {
    let description: String
}

@main
private enum VerifyIcons {
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw IconFailure(description: message) }
    }

    private static func bitmap(_ url: URL, pixels: Int? = nil) throws -> NSBitmapImageRep {
        guard let image = NSBitmapImageRep(data: try Data(contentsOf: url)) else {
            throw IconFailure(description: "Cannot decode \(url.path)")
        }
        if let pixels {
            try require(image.pixelsWide == pixels && image.pixelsHigh == pixels, "Wrong dimensions: \(url.path)")
        }
        try require(image.hasAlpha, "Missing alpha channel: \(url.path)")
        for (x, y) in [(0, 0), (image.pixelsWide - 1, 0), (0, image.pixelsHigh - 1), (image.pixelsWide - 1, image.pixelsHigh - 1)] {
            try require((image.colorAt(x: x, y: y)?.alphaComponent ?? 1) < 0.01, "Opaque outer corner: \(url.path)")
        }
        return image
    }

    private static func integer(_ data: Data, _ offset: Int, bytes: Int) -> Int {
        (0..<bytes).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
    }

    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw IconFailure(description: "usage: brk-icon-verify <icon-pack-directory>")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var count = 0
        var fingerprints = Set<Data>()
        for variant in AppIconArt.Variant.allCases {
            for size in [16, 24, 32, 48, 64, 128, 256, 512, 1024] {
                let path = root.appendingPathComponent("png/\(variant.rawValue)/\(size).png")
                let image = try bitmap(path, pixels: size)
                if size == 1024 {
                    try require((image.colorAt(x: 512, y: 512)?.alphaComponent ?? 0) > 0.95, "Transparent app tile: \(path.path)")
                    fingerprints.insert(try Data(contentsOf: path))
                }
                count += 1
            }
            let catalog = root.appendingPathComponent("macos/\(variant.rawValue).appiconset")
            let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog.appendingPathComponent("Contents.json"))) as? [String: Any]
            let members = contents?["images"] as? [[String: String]] ?? []
            try require(members.count == 10, "Incomplete asset catalog: \(catalog.path)")
            for member in members {
                guard let name = member["filename"], let size = member["size"]?.split(separator: "x").first.flatMap({ Int($0) }),
                      let scale = member["scale"]?.first.flatMap({ Int(String($0)) }) else {
                    throw IconFailure(description: "Invalid asset catalog member: \(catalog.path)")
                }
                let set = root.appendingPathComponent("iconsets/\(variant.rawValue).iconset/\(name)")
                _ = try bitmap(set, pixels: size * scale)
                _ = try bitmap(catalog.appendingPathComponent(name), pixels: size * scale)
                try require(try Data(contentsOf: set) == Data(contentsOf: catalog.appendingPathComponent(name)), "Iconset/catalog mismatch: \(name)")
                count += 2
            }
            let icns = root.appendingPathComponent("icns/\(variant.rawValue).icns")
            let data = try Data(contentsOf: icns)
            try require(data.starts(with: Data("icns".utf8)), "Invalid ICNS header: \(icns.path)")
            guard let decoded = NSImage(contentsOf: icns) else { throw IconFailure(description: "Cannot decode \(icns.path)") }
            try require(decoded.isValid && decoded.representations.contains { $0.pixelsWide == 1024 }, "Missing 1024-pixel ICNS representation: \(icns.path)")
        }
        try require(fingerprints.count == AppIconArt.Variant.allCases.count, "Two styles exported identical artwork")

        let ico = try Data(contentsOf: root.appendingPathComponent("web/favicon.ico"))
        try require(ico.count >= 6 && integer(ico, 0, bytes: 2) == 0 && integer(ico, 2, bytes: 2) == 1, "Invalid ICO header")
        let frames = integer(ico, 4, bytes: 2)
        try require(frames == 6 && ico.count >= 6 + frames * 16, "Incomplete ICO")
        for index in 0..<frames {
            let entry = 6 + index * 16
            let size = ico[entry] == 0 ? 256 : Int(ico[entry])
            let length = integer(ico, entry + 8, bytes: 4)
            let start = integer(ico, entry + 12, bytes: 4)
            try require(start >= 6 + frames * 16 && start + length <= ico.count, "Invalid ICO frame offset")
            let decoded = NSBitmapImageRep(data: ico.subdata(in: start..<(start + length)))
            try require(decoded?.pixelsWide == size && decoded?.pixelsHigh == size, "Invalid ICO PNG frame")
        }
        for (name, size) in [("favicon-16", 16), ("favicon-32", 32), ("favicon-48", 48),
                             ("apple-touch-icon", 180), ("icon-192", 192), ("icon-512", 512)] {
            _ = try bitmap(root.appendingPathComponent("web/\(name).png"), pixels: size)
            count += 1
        }
        for name in ["logo-color", "logo-black", "logo-white"] {
            let image = try bitmap(root.appendingPathComponent("logos/\(name).png"))
            var opaque = 0
            var transparent = 0
            for y in stride(from: 0, to: image.pixelsHigh, by: 16) {
                for x in stride(from: 0, to: image.pixelsWide, by: 16) {
                    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if color.alphaComponent < 0.01 { transparent += 1 }
                    if color.alphaComponent > 0.95 {
                        opaque += 1
                        if name == "logo-black" {
                            try require(max(color.redComponent, color.greenComponent, color.blueComponent) < 0.08, "Black logo contains colored opaque pixels")
                        } else if name == "logo-white" {
                            try require(min(color.redComponent, color.greenComponent, color.blueComponent) > 0.92, "White logo contains dark opaque pixels")
                        }
                    }
                }
            }
            try require(opaque > 100 && transparent > 100, "Empty or opaque standalone logo: \(name)")
            count += 1
        }
        let report: [String: Any] = ["status": "passed", "variants": AppIconArt.Variant.allCases.map(\.rawValue),
                                      "pngFilesChecked": count, "icnsFilesChecked": 6, "icoFramesChecked": frames]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("verification.json"))
        print("Icons verified: \(count) PNG files, 6 ICNS files, \(frames) ICO frames; alpha, dimensions and monochrome marks passed")
    }
}
