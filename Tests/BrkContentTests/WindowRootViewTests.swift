import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
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

    /// Arc's window background lightens while the app is not frontmost (P01-d: white at 40%) and darkens while
    /// websites are set to Dark (P19-b: black at 8.6%); the veil never takes a click
    func testTheBackgroundVeilFollowsTheAppAndTheWebsiteAppearance() throws {
        var v = snapshot(sidebarVisible: true)
        let (container, root, frames) = render(v)
        let veil = try XCTUnwrap(root.subviews.first { $0 is InactiveVeilView })
        XCTAssertEqual(root.subviews.firstIndex(of: veil), 1, "right over the background, under the sidebar")
        func color() -> NSColor? { veil.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.deviceGray) }
        if NSApplication.shared.isActive { XCTAssertTrue(veil.isHidden) }
        else { XCTAssertFalse(veil.isHidden); XCTAssertEqual(color()?.whiteComponent ?? 0, 1, accuracy: 0.01); XCTAssertEqual(color()?.alphaComponent ?? 0, 0.4, accuracy: 0.01) }
        v.websiteAppearance = .dark
        root.render(v, frames: frames, surface: { _ in nil })
        XCTAssertFalse(veil.isHidden)
        XCTAssertEqual(color()?.whiteComponent ?? 1, 0, accuracy: 0.01)
        XCTAssertEqual(color()?.alphaComponent ?? 0, 0.086, accuracy: 0.005)
        let card = try XCTUnwrap(frames.cards.first?.rect)
        XCTAssertFalse(hit(container, CGPoint(x: card.minX - 4, y: card.midY)) === veil)
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
}

final class IDs: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> String { lock.withLock { n += 1; return "c\(n)" } }
}
