import AppKit
import BrkBase
@testable import BrkContent
@testable import BrkDomain
import BrkLayout
import XCTest

/// The Ctrl+Tab switcher's page images (about 265 KB each) are kept per window. One of a tab its Space's rows no longer
/// list goes at the next render, whether or not the switcher ever opens; one of a tab that moved to a neighbouring Space
/// goes with it, and images of other Spaces stay for their own switcher. They used to stay for as long as the window
/// lived.
@MainActor
final class PageThumbnailsTests: XCTestCase {
    /// A window the window server shows on screen, without putting it there.
    private final class ShownWindow: NSWindow {
        override var isVisible: Bool { true }
        override var occlusionState: NSWindow.OcclusionState { .visible }
    }

    static let size = CGSize(width: 1280, height: 776)
    let now = Instant(milliseconds: 1_790_000_000_000)

    func testAClosedTabsImageGoesWithoutTheSwitcher() throws {
        let ids = IDs()
        let calendar = Calendar(identifier: .gregorian)
        let state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: Self.size),
                                       ctx: Context(now: now, newID: ids.next)).state
        let id = project(state, ProjectionContext(now: now, calendar: calendar)).windows.keys.sorted()[0]
        let base = project(state, ProjectionContext(now: now, calendar: calendar)).windows[id]!
        let frames = WindowLayout.compute(base, contentSize: Self.size)
        guard case .tab(let template)? = base.space.today.rows.first else { return XCTFail("the restored window has a Today tab") }
        let here = base.space.id, there = SpaceID("there")
        let dockWithThere = base.dock + [DockItem(id: there, title: "There", icon: base.dock[0].icon, active: false, color: base.dock[0].color)]
        func rows(_ items: [String]) -> [Row] {
            items.map { item in
                var row = template
                row.id = ItemID(item)
                return .tab(row)
            }
        }
        /// The window in `space`, its Today listing `items` and showing the first; `next` lists the neighbouring Space's.
        func window(_ space: SpaceID, _ items: [String], next: [String]? = nil, dock: [DockItem]? = nil) -> WindowSnapshot {
            var v = base
            v.space.id = space
            v.space.today.rows = rows(items)
            v.content.panes[0].tab = ItemID(items[0])
            v.dock = dock ?? dockWithThere
            v.neighbors = SpaceNeighbors()
            if let next {
                var page = base.space
                page.id = space == here ? there : here
                page.today.rows = rows(next)
                v.neighbors.next = SpacePage(space: page, favorites: base.favorites, theme: base.theme)
            }
            return v
        }

        // Images are taken only from a window the window server shows; the screen's image here is a flat colour.
        let shown = ShownWindow(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        shown.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(origin: .zero, size: Self.size))
        shown.contentView = view
        defer { shown.close() }

        let context = try XCTUnwrap(CGContext(data: nil, width: 2 * Int(Self.size.width), height: 2 * Int(Self.size.height), bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        let screen = try XCTUnwrap(context.makeImage())
        let thumbnails = PageThumbnails()
        thumbnails.capture = { screen }
        func render(_ v: WindowSnapshot) { thumbnails.afterRender(v, frames: frames, in: view) }
        func take(_ v: WindowSnapshot) {
            render(v)
            thumbnails.beforeRender(opening: true, in: view)   // the switcher's opening takes what is shown at once
        }
        func kept() -> Set<String> { Set(thumbnails.images.keys.map(\.rawValue)) }

        take(window(here, ["a", "b", "c", "d"]))
        take(window(here, ["b", "a", "c", "d"]))
        take(window(here, ["c", "a", "b", "d"]))
        take(window(here, ["d", "a", "b", "c"]))
        take(window(there, ["x"]))
        XCTAssertEqual(kept(), ["a", "b", "c", "d", "x"])

        // Back in the first Space, "c" is closed; no switcher opens.
        render(window(here, ["a", "b", "d"]))
        XCTAssertEqual(kept(), ["a", "b", "d", "x"], "a closed tab's image goes; another Space's image stays for its own switcher")

        // "b" moves to the neighbouring Space: its image goes with it, and goes when it closes there.
        render(window(here, ["a", "d"], next: ["x", "b"]))
        XCTAssertEqual(kept(), ["a", "b", "d", "x"], "a tab that moved keeps its image")
        render(window(there, ["x", "b"]))
        render(window(there, ["x"]))
        XCTAssertEqual(kept(), ["a", "d", "x"], "the moved tab's image now belongs to the Space it moved to")

        // The other Space is deleted: its images go.
        render(window(here, ["a", "d"], dock: base.dock))
        XCTAssertEqual(kept(), ["a", "d"], "a deleted Space's images go")
    }
}
