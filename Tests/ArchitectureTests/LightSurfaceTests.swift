import Foundation
import XCTest

/// A SwiftUI surface painted with Arc's fixed light sheet colour (0xFBFBFF) must also pin the light colour scheme.
/// Otherwise text that uses the system colour turns white in dark mode and disappears on the light background
/// (the Previews sheet's title and checkbox labels did, 2026-11-12).
final class LightSurfaceTests: XCTestCase {
    static let lightBackground = ".background(ArtColor.rgb(0xFBFBFF))"
    static let pin = ".environment(\\.colorScheme, .light)"

    func testFixedLightSheetsPinTheLightScheme() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        var problems: [String] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for url in files where url.pathExtension == "swift" && !url.path.contains("/BrkE2E/") {
            problems += Self.violations(path: url.lastPathComponent, text: try String(contentsOf: url, encoding: .utf8))
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    func testAMissingPinIsReported() {
        let bad = "VStack {}\n    .background(ArtColor.rgb(0xFBFBFF))\n    .frame(width: 10)\n"
        let good = "VStack {}\n    .background(ArtColor.rgb(0xFBFBFF))\n    // note\n    .environment(\\.colorScheme, .light)\n"
        XCTAssertEqual(Self.violations(path: "Bad.swift", text: bad).count, 1)
        XCTAssertEqual(Self.violations(path: "Good.swift", text: good), [])
    }

    /// The pin has to follow within four lines of the background.
    static func violations(path: String, text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        return lines.indices.compactMap { index in
            guard lines[index].contains(lightBackground) else { return nil }
            let after = lines[(index + 1)..<min(lines.count, index + 5)]
            return after.contains { $0.contains(pin) } ? nil : "\(path):\(index + 1) light sheet without \(pin)"
        }
    }
}
