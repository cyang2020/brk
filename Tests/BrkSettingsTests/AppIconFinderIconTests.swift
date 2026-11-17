import AppKit
import XCTest
@testable import BrkSettings

/// Issue #15: a custom icon pasted on Brk.app in Finder's Get Info stays the Dock icon while The Original is chosen;
/// a built-in choice still replaces it.
@MainActor
final class AppIconFinderIconTests: XCTestCase {
    func testTheOriginalFollowsAFinderCustomIconAndBuiltInChoicesDoNot() throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent("issue15-\(UUID().uuidString).app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        let original = AppIconArt.Variant.original, neon = AppIconArt.Variant.neon
        let artwork = AppIconArt.image(original, side: 64)
        XCTAssertFalse(AppIconArt.hasFinderIcon(bundle))
        XCTAssertTrue(AppIconArt.appImage(original, side: 64, bundle: bundle) === artwork, "no custom icon: the artwork")

        let red = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { NSColor.red.setFill(); $0.fill(); return true }
        XCTAssertTrue(NSWorkspace.shared.setIcon(red, forFile: bundle.path, options: []))
        XCTAssertTrue(AppIconArt.hasFinderIcon(bundle))
        XCTAssertFalse(AppIconArt.appImage(original, side: 64, bundle: bundle) === artwork, "the Finder icon replaces The Original")
        XCTAssertTrue(AppIconArt.appImage(neon, side: 64, bundle: bundle) === AppIconArt.image(neon, side: 64), "a built-in choice wins")

        XCTAssertTrue(NSWorkspace.shared.setIcon(nil, forFile: bundle.path, options: []))
        XCTAssertFalse(AppIconArt.hasFinderIcon(bundle), "Get Info's Delete brings The Original back")
    }
}
