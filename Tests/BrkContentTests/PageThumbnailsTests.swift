import AppKit
import BrkBase
@testable import BrkContent
@testable import BrkDomain
import BrkLayout
import XCTest

/// The Ctrl+Tab switcher's page images (about 265 KB each) are kept per window. One of a tab that has since closed goes
/// the next time the switcher opens in its Space (the switcher lists every tab of the Space it opens in); images taken in
/// other Spaces stay for their own switcher. They used to stay for as long as the window lived.
@MainActor
final class PageThumbnailsTests: XCTestCase {
    /// A window the window server shows on screen, without putting it there.
    private final class ShownWindow: NSWindow {
        override var isVisible: Bool { true }
        override var occlusionState: NSWindow.OcclusionState { .visible }
    }

    static let size = CGSize(width: 1280, height: 776)
    let now = Instant(milliseconds: 1_790_000_000_000)

    func testAClosedTabsImageGoesWhenTheSwitcherOpensInItsSpace() throws {
        let ids = IDs()
        let calendar = Calendar(identifier: .gregorian)
        let state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: Self.size),
                                       ctx: Context(now: now, newID: ids.next)).state
        let id = project(state, ProjectionContext(now: now, calendar: calendar)).windows.keys.sorted()[0]
        let base = project(state, ProjectionContext(now: now, calendar: calendar)).windows[id]!
        let frames = WindowLayout.compute(base, contentSize: Self.size)
        func showing(_ item: String, space: SpaceID? = nil) -> WindowSnapshot {
            var v = base
            v.content.panes[0].tab = ItemID(item)
            if let space { v.space.id = space }
            return v
        }

        // Images are taken only from a window the window server shows; the screen's image here is a flat colour.
        let window = ShownWindow(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(origin: .zero, size: Self.size))
        window.contentView = view
        defer { window.close() }

        let context = try XCTUnwrap(CGContext(data: nil, width: 2 * Int(Self.size.width), height: 2 * Int(Self.size.height), bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        let screen = try XCTUnwrap(context.makeImage())
        let thumbnails = PageThumbnails()
        thumbnails.capture = { screen }
        func take(_ v: WindowSnapshot) {
            thumbnails.afterRender(v, frames: frames, in: view)
            thumbnails.beforeRender(opening: true, in: view)   // the switcher's opening takes what is shown at once
        }
        take(showing("closed"))
        take(showing("away", space: SpaceID("elsewhere")))
        take(showing("kept"))
        XCTAssertEqual(Set(thumbnails.images.keys), [ItemID("closed"), ItemID("away"), ItemID("kept")])

        // "closed" was closed; the switcher opens in its Space and lists that Space's tabs.
        var switcher = showing("kept")
        switcher.tabTools.recent = RecentTabsSnapshot(items: [RecentTabRow(id: ItemID("kept"), title: "Kept", url: nil)], selected: ItemID("kept"))
        thumbnails.afterRender(switcher, frames: frames, in: view)
        XCTAssertNil(thumbnails.images[ItemID("closed")], "a closed tab's image goes")
        XCTAssertNotNil(thumbnails.images[ItemID("kept")])
        XCTAssertNotNil(thumbnails.images[ItemID("away")], "another Space's image stays for its own switcher")
    }
}
