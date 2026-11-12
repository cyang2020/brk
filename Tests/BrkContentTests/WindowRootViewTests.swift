import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
@testable import BrkSidebar
import BrkUIKit
import XCTest

/// The root view's composition rules that the e2e scenarios found broken (W2's window root with W3's sidebar):
/// the window-wide content area must not take the clicks meant for the sidebar under it, and a hidden sidebar must
/// still render, because its reveal strip is what peeks it back. Headless: views without a window.
@MainActor
final class WindowRootViewTests: XCTestCase {
    static let size = CGSize(width: 1280, height: 776)
    let now = Instant(milliseconds: 1_790_000_000_000)
    private let ids = IDs()

    /// A fresh profile's window, built only through the domain's public surface, as the app builds it.
    func snapshot(sidebarVisible: Bool) -> WindowSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let restored = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: Self.size),
                                          ctx: Context(now: now, newID: ids.next))
        var state = restored.state
        let window = project(state, ProjectionContext(now: now, calendar: calendar)).windows.keys.sorted()[0]
        if !sidebarVisible { state = reduce(state, .user(window, .sidebar(.toggle)), Context(now: now, newID: ids.next)).state }
        return project(state, ProjectionContext(now: now, calendar: calendar)).windows[window]!
    }

    /// The root inside a plain container (so `hitTest` has a superview coordinate system to take points in).
    func render(_ v: WindowSnapshot) -> (container: NSView, root: WindowRootView, frames: WindowFrames) {
        let container = NSView(frame: CGRect(origin: .zero, size: Self.size))
        let root = WindowRootView(dispatch: { _ in })
        root.frame = container.bounds
        container.addSubview(root)
        let frames = WindowLayout.compute(v, contentSize: Self.size)
        root.render(v, frames: frames, surface: { _ in nil })
        return (container, root, frames)
    }

    /// The view under a window point (top-left origin, as `WindowFrames` are).
    func hit(_ container: NSView, _ point: CGPoint) -> NSView? {
        container.hitTest(CGPoint(x: point.x, y: container.bounds.height - point.y))
    }

    /// The user's report (2026-11-12): in full screen the title row has no traffic lights, and Arc starts it with the
    /// sidebar toggle where the close light would be. Brk kept the toggle at its windowed spot, after room for three
    /// lights that were not there.
    func testFullScreenSidebarToggleStartsTheTitleRow() throws {
        var view = snapshot(sidebarVisible: true)
        let point = CGPoint(x: Metrics.window.trafficLightLeft.value + Metrics.window.trafficLightSize.value / 2,
                            y: Metrics.window.trafficLightCenterY.value)
        let windowed = render(view)
        XCTAssertNotNil(windowed.frames.sidebar?.trafficLightsOrigin)
        XCTAssertNotEqual(hit(windowed.container, point)?.toolTip, SidebarCopy.showHideSidebar, "the toggle is over the lights in a window")
        view.fullScreen = true
        let full = render(view)
        XCTAssertNil(full.frames.sidebar?.trafficLightsOrigin)
        XCTAssertEqual(hit(full.container, point)?.toolTip, SidebarCopy.showHideSidebar, "full screen: the toggle is not where the lights were")
    }

    /// e2e 4 and 7: a click on the dock's Library button or a space cell reaches the sidebar, and one on the card
    /// reaches the card; the content area, which spans the window, takes nothing in between
    func testContentAreaTakesClicksOnlyOnItsCards() throws {
        let (container, root, frames) = render(snapshot(sidebarVisible: true))
        let sidebar = try XCTUnwrap(frames.sidebar)
        let library = hit(container, CGPoint(x: sidebar.libraryButton.midX, y: sidebar.libraryButton.midY))
        XCTAssertEqual(library?.isDescendant(of: root.sidebar), true, "the Library button click went to \(String(describing: library))")
        let card = try XCTUnwrap(frames.cards.first?.rect)
        let page = hit(container, CGPoint(x: card.midX, y: card.midY))
        XCTAssertEqual(page?.isDescendant(of: root.content), true, "the card click went to \(String(describing: page))")
        XCTAssertFalse(page === root.content, "the content area itself, not a card, took the click")
        let gap = hit(container, CGPoint(x: card.minX - Metrics.content.inset.value / 2, y: card.midY))
        XCTAssertFalse(gap === root.content, "the content area took a click in the inset between sidebar and card")
    }

    /// e2e R2: with the sidebar hidden the sidebar view still renders, so its reveal strip is on screen at the
    /// computed frame for the hover that peeks it back
    func testHiddenSidebarStillRendersItsRevealStrip() throws {
        let v = snapshot(sidebarVisible: false)
        XCTAssertFalse(v.sidebar.visible)
        let (_, root, frames) = render(v)
        let strip = try XCTUnwrap(frames.revealStrip, "layout gives a hidden sidebar a reveal strip")
        XCTAssertTrue(root.sidebar.isHidden)
        var found: NSView?
        func walk(_ view: NSView) {
            if view.accessibilityIdentifier() == ViewID.revealStrip.identifier { found = view }
            view.subviews.forEach(walk)
        }
        walk(root)
        let view = try XCTUnwrap(found, "no reveal-strip view in the root")
        XCTAssertFalse(view.isHiddenOrHasHiddenAncestor, "the reveal strip is hidden")
        XCTAssertEqual(view.frame, strip)
    }

    func testIncognitoScratchRowsRenderUpdateAndCloseInTheirOwnSection() throws {
        let ctx = Context(now: now, newID: ids.next)
        let projection = ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "https://example.com/regular"), contentSize: Self.size), ctx: ctx).state
        let standard = try XCTUnwrap(project(state, projection).windows.keys.first)
        let originalTheme = project(state, projection).windows[standard]!.theme
        state = reduce(state, .user(standard, .window(.newIncognito)), ctx).state
        let incognito = try XCTUnwrap(project(state, projection).windows.values.first { $0.kind == .incognito }?.id)
        state = reduce(state, .user(incognito, .commandBar(.submit("https://example.com/private"))), ctx).state
        let first = project(state, projection).windows[incognito]!
        XCTAssertEqual(first.theme.scheme, .dark)
        XCTAssertEqual(first.theme.tokens, .dark)
        XCTAssertLessThan(relativeLuminance(first.theme.windowColor), 0.18)
        XCTAssertEqual(project(state, projection).windows[standard]?.theme, originalTheme)
        let (container, root, _) = render(first)
        _ = container
        func find(_ id: ViewID) -> NSView? {
            func walk(_ view: NSView) -> NSView? {
                if view.accessibilityIdentifier() == id.identifier { return view }
                return view.subviews.lazy.compactMap(walk).first
            }
            return walk(root)
        }
        let tab = try XCTUnwrap(first.scratch?.rows.first?.id)
        let section = try XCTUnwrap(find(.section(.scratch)))
        let row = try XCTUnwrap(find(.row(tab)))
        XCTAssertFalse(row.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(row.isDescendant(of: section))
        let frames = WindowLayout.compute(first, contentSize: Self.size)
        XCTAssertTrue(frames.sidebar?.rows.contains { $0.kind == .item(tab) } == true)
        state = reduce(state, .user(incognito, .commandBar(.submit("https://example.com/private-two"))), ctx).state
        let second = project(state, projection).windows[incognito]!
        let newTab = try XCTUnwrap(second.scratch?.rows.first?.id)
        root.render(second, frames: WindowLayout.compute(second, contentSize: Self.size), surface: { _ in nil })
        XCTAssertNotNil(find(.row(newTab)), "scratch changes must invalidate the sidebar render")
        state = reduce(state, .user(incognito, .tab(.close(.item(newTab)))), ctx).state
        let closed = project(state, projection).windows[incognito]!
        root.render(closed, frames: WindowLayout.compute(closed, contentSize: Self.size), surface: { _ in nil })
        XCTAssertNil(find(.row(newTab)))
        XCTAssertNotNil(find(.row(tab)))
    }

    /// The page draws inside the window's view tree, so a popup shows over it only when layered above the content
    /// cards: `PopupLayer.present` puts it there, and `coveredByPages` (read by the runner on every native read) finds
    /// one made inside the sidebar, which the card hides where it crosses it.
    func testPopupLayerFindsAPopupLayeredUnderThePage() throws {
        let v = snapshot(sidebarVisible: true)
        let frames = WindowLayout.compute(v, contentSize: Self.size)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.borderless], backing: .buffered, defer: true)
        let root = WindowRootView(dispatch: { _ in })
        window.contentView = root
        let page = NSView()
        root.render(v, frames: frames, surface: { _ in page })
        XCTAssertTrue(page.isDescendant(of: root.content), "the page did not go into its card")
        XCTAssertEqual(PopupLayer.coveredByPages(in: root, pages: [page]), [], "the window's own backdrops and sidebar count as under the page")
        // The Library's slide moves the card past the window's right edge; the background still spans what shows of it.
        page.frame.size.width += 600
        XCTAssertEqual(PopupLayer.coveredByPages(in: root, pages: [page]), [], "a page running past the window's edge")
        page.frame.size.width -= 600

        let card = try XCTUnwrap(frames.cards.first?.rect)
        let beside = CGRect(x: root.sidebar.frame.maxX + 4, y: card.minY + 40, width: 240, height: 200)
        let good = NSView(frame: beside)
        XCTAssertTrue(PopupLayer.present(good, over: root.sidebar))
        XCTAssertEqual(PopupLayer.coveredByPages(in: root, pages: [page]), [])

        let wrong = NSView(frame: root.sidebar.convert(beside, from: root))
        wrong.identifier = NSUserInterfaceItemIdentifier("misplaced-card")
        root.sidebar.addSubview(wrong)
        let found = PopupLayer.coveredByPages(in: root, pages: [page])
        XCTAssertEqual(found.count, 1, "\(found)")
        XCTAssertTrue(found.first?.contains("misplaced-card") == true, "\(found)")
    }
}

final class IDs: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> String { lock.withLock { n += 1; return "c\(n)" } }
}
