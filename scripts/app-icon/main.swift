// Writes Brk's app icon as an .iconset (scripts/build.sh turns it into the bundle's .icns with iconutil). Compiled
// together with Sources/BrkSettings/AppIconArt.swift, so the bundle's icon and the in-app drawing are one drawing.
//
//   swiftc -O -o .build/brk-app-icon scripts/app-icon/main.swift Sources/BrkSettings/AppIconArt.swift
//   .build/brk-app-icon <out.iconset> [variant]
import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { FileHandle.standardError.write(Data("usage: brk-app-icon <out.iconset> [variant]\n".utf8)); exit(2) }
let out = URL(fileURLWithPath: arguments[1], isDirectory: true)
let variant = arguments.count > 2 ? AppIconArt.Variant(rawValue: arguments[2]) : .original
guard let variant else { FileHandle.standardError.write(Data("unknown variant \(arguments[2])\n".utf8)); exit(2) }
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
MainActor.assumeIsolated {
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            guard let data = AppIconArt.png(variant, pixels: points * scale) else { FileHandle.standardError.write(Data("could not draw \(name)\n".utf8)); exit(1) }
            do { try data.write(to: out.appendingPathComponent(name)) } catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
        }
    }
}
