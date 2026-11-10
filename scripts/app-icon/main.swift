// Export the same artwork used by the running app.
//   brk-app-icon <out.iconset> [variant] [resource-directory]
//   brk-app-icon --all <output-directory> [resource-directory]
import AppKit

private let iconPoints = [16, 32, 128, 256, 512]
private let pngSizes = [16, 24, 32, 48, 64, 128, 256, 512, 1024]

@MainActor
private func png(_ variant: AppIconArt.Variant, pixels: Int, resources: URL) throws -> Data {
    guard let data = AppIconArt.png(variant, pixels: pixels, resources: resources) else {
        throw NSError(domain: "brk-app-icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not render \(variant.rawValue) at \(pixels) pixels"])
    }
    return data
}

private func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
}

@MainActor
private func iconset(_ variant: AppIconArt.Variant, at directory: URL, resources: URL) throws -> [[String: String]] {
    var members: [[String: String]] = []
    for points in iconPoints {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            try write(png(variant, pixels: points * scale, resources: resources), to: directory.appendingPathComponent(name))
            members.append(["filename": name, "idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x"])
        }
    }
    return members
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}

@MainActor
private func ico(resources: URL) throws -> Data {
    let sizes = [16, 32, 48, 64, 128, 256]
    let frames = try sizes.map { try png(.original, pixels: $0, resources: resources) }
    var result = Data()
    result.appendLittleEndian(UInt16(0))
    result.appendLittleEndian(UInt16(1))
    result.appendLittleEndian(UInt16(frames.count))
    var offset = 6 + frames.count * 16
    for (size, frame) in zip(sizes, frames) {
        result.append(UInt8(size == 256 ? 0 : size))
        result.append(UInt8(size == 256 ? 0 : size))
        result.append(contentsOf: [0, 0])
        result.appendLittleEndian(UInt16(1))
        result.appendLittleEndian(UInt16(32))
        result.appendLittleEndian(UInt32(frame.count))
        result.appendLittleEndian(UInt32(offset))
        offset += frame.count
    }
    for frame in frames { result.append(frame) }
    return result
}

@MainActor
private func pack(at directory: URL, resources: URL) throws {
    for variant in AppIconArt.Variant.allCases {
        let set = directory.appendingPathComponent("iconsets/\(variant.rawValue).iconset")
        let members = try iconset(variant, at: set, resources: resources)
        let catalog = directory.appendingPathComponent("macos/\(variant.rawValue).appiconset")
        for member in members {
            guard let name = member["filename"] else { continue }
            try write(Data(contentsOf: set.appendingPathComponent(name)), to: catalog.appendingPathComponent(name))
        }
        let contents: [String: Any] = ["images": members, "info": ["author": "brk", "version": 1]]
        try write(JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]),
                  to: catalog.appendingPathComponent("Contents.json"))
        for size in pngSizes {
            try write(png(variant, pixels: size, resources: resources),
                      to: directory.appendingPathComponent("png/\(variant.rawValue)/\(size).png"))
        }
    }
    try write(ico(resources: resources), to: directory.appendingPathComponent("web/favicon.ico"))
    for size in [16, 32, 48] {
        try write(png(.original, pixels: size, resources: resources),
                  to: directory.appendingPathComponent("web/favicon-\(size).png"))
    }
    for (name, size) in [("apple-touch-icon", 180), ("icon-192", 192), ("icon-512", 512)] {
        try write(png(.original, pixels: size, resources: resources),
                  to: directory.appendingPathComponent("web/\(name).png"))
    }
    let manifest: [String: Any] = [
        "variants": AppIconArt.Variant.allCases.map(\.rawValue),
        "pngSizes": pngSizes,
        "formats": ["png", "icns", "ico", "iconset", "appiconset"],
    ]
    try write(JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]),
              to: directory.appendingPathComponent("manifest.json"))
}

let arguments = CommandLine.arguments
let all = arguments.count > 1 && arguments[1] == "--all"
let outputIndex = all ? 2 : 1
guard arguments.count > outputIndex else {
    FileHandle.standardError.write(Data("usage: brk-app-icon <out.iconset> [variant] [resource-directory]\n       brk-app-icon --all <output-directory> [resource-directory]\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: arguments[outputIndex], isDirectory: true)
let resourceArgument = arguments.count > 3 ? arguments[3] : "Sources/BrkSettings/Resources/AppIcons"
let resources = URL(fileURLWithPath: resourceArgument, isDirectory: true)
let variant = all ? .original : AppIconArt.Variant(rawValue: arguments.count > 2 ? arguments[2] : "original")
guard let variant else {
    FileHandle.standardError.write(Data("Unknown icon variant: \(arguments[2])\n".utf8))
    exit(2)
}
do {
    try MainActor.assumeIsolated {
        if all { try pack(at: out, resources: resources) }
        else { _ = try iconset(variant, at: out, resources: resources) }
    }
} catch {
    FileHandle.standardError.write(Data("brk-app-icon: \(error.localizedDescription)\n".utf8))
    exit(1)
}
