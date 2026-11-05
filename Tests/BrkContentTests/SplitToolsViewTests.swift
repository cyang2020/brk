import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import XCTest
@testable import BrkContent

@MainActor
final class SplitToolsViewTests: XCTestCase {
    func testFourPaneSegmentCentersSelectInsteadOfClosing() throws {
        let ctx = Context(now: Instant(milliseconds: 1_790_000_000_000), newID: { UUID().uuidString })
        let size = CGSize(width: 1280, height: 776)
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "https://fixture.example/"), contentSize: size), ctx: ctx).state
        let projection = ProjectionContext(now: ctx.now, calendar: Calendar(identifier: .gregorian))
        let window = project(state, projection).windows.keys.first!
        for _ in 0..<3 {
            state = reduce(state, .user(window, .split(.addPane)), ctx).state
            state = reduce(state, .user(window, .commandBar(.dismiss)), ctx).state
        }
        let snapshot = project(state, projection).windows[window]!
        let root = WindowRootView(dispatch: { _ in })
        root.frame = CGRect(origin: .zero, size: size)
        root.render(snapshot, frames: WindowLayout.compute(snapshot, contentSize: size), surface: { _ in nil })
        root.layoutSubtreeIfNeeded()
        func find(_ identifier: String, in view: NSView) -> NSView? {
            if view.accessibilityIdentifier() == identifier { return view }
            for child in view.subviews { if let match = find(identifier, in: child) { return match } }
            return nil
        }
        for pane in snapshot.content.panes {
            let segment = try XCTUnwrap(find(ViewID.splitSegment(pane.tab).identifier, in: root))
            XCTAssertGreaterThan(segment.bounds.width, 0)
            let center = segment.convert(CGPoint(x: segment.bounds.midX, y: segment.bounds.midY), to: segment.superview)
            XCTAssertNotEqual(segment.hitTest(center)?.accessibilityIdentifier(), ViewID.rowClose(pane.tab).identifier)
        }
    }

    func testMovingASurfaceBetweenCardsDoesNotLetItsOldCardDetachOrResizeIt() {
        let old = CardView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let current = CardView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let page = NSView(frame: .zero), replacement = NSView(frame: .zero)
        old.host(page, placeholder: nil)
        current.host(page, placeholder: nil)
        old.host(replacement, placeholder: nil)
        old.layout()
        XCTAssertTrue(page.superview === current)
        XCTAssertEqual(page.frame, current.bounds)
        XCTAssertTrue(replacement.superview === old)
    }
}

@MainActor
final class SplitDropPreviewTests: XCTestCase {
    private func model() -> (state: AppState, window: WindowID, ctx: Context, target: ItemID, source: ItemID) {
        let ctx = Context(now: Instant(milliseconds: 1_790_000_000_000), newID: { UUID().uuidString })
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "https://test.example/target"), contentSize: CGSize(width: 1280, height: 776)), ctx: ctx).state
        let projection = ProjectionContext(now: ctx.now, calendar: .current)
        let window = project(state, projection).windows.keys.first!
        let target = project(state, projection).windows[window]!.content.panes[0].tab
        state = reduce(state, .user(window, .commandBar(.open(.newTab))), ctx).state
        state = reduce(state, .user(window, .commandBar(.submit("https://test.example/source"))), ctx).state
        let source = project(state, projection).windows[window]!.content.panes[0].tab
        state = reduce(state, .user(window, .tab(.focus(target))), ctx).state
        return (state, window, ctx, target, source)
    }

    /// Arc's P23-d: at the right edge the page's card gives up the right half (its page keeps its size, clipped) and
    /// the slot is drawn there; leaving the edge gives the card its frame back.
    func testEdgePreviewNarrowsTheCardWithoutResizingItsPage() throws {
        let m = model()
        let snapshot = project(m.state, ProjectionContext(now: m.ctx.now, calendar: .current)).windows[m.window]!
        let frames = WindowLayout.compute(snapshot, contentSize: CGSize(width: 1280, height: 776))
        let page = NSView(frame: .zero)
        let content = ContentAreaView(dispatch: { _ in })
        content.render(snapshot.content, frames: frames, theme: snapshot.theme, palette: Palette(snapshot.theme), surface: { _ in page })
        let card = try XCTUnwrap(content.subviews.compactMap { $0 as? CardView }.first)
        let rest = card.frame, pageFrame = page.frame
        var clock = 100.0
        content.dropClock = { clock }
        content.beginDrop(m.source)
        let area = frames.contentArea
        XCTAssertNotNil(content.dropCommand(m.source, at: CGPoint(x: area.maxX - 12, y: area.midY)))
        let half = (area.width - Metrics.content.splitGap.value) / 2
        XCTAssertEqual(card.frame, CGRect(x: area.minX, y: area.minY, width: half, height: area.height))
        XCTAssertEqual(page.frame, pageFrame, "the page was resized for the preview")
        let slot = try XCTUnwrap(content.subviews.first { $0.accessibilityIdentifier() == ViewID.splitDropPreview.identifier })
        XCTAssertEqual(slot.frame, CGRect(x: area.maxX - half, y: area.minY, width: half, height: area.height))
        // Over the narrowed page it falls back to the whole page; the middle of that page rings the whole of it (Q13-e),
        // and a release there makes the dragged tab the shown one (Q17-drop-tab-framed-middle).
        clock += 1
        XCTAssertEqual(content.dropCommand(m.source, at: CGPoint(x: area.midX, y: area.midY)), .tab(.focus(m.source)))
        XCTAssertEqual(card.frame, rest)
        XCTAssertEqual(page.frame, pageFrame)
        XCTAssertFalse(slot.isHidden)
        XCTAssertEqual(slot.frame, area)
        XCTAssertEqual(slot.layer?.borderWidth, 3)
        clock += 1
        XCTAssertNil(content.dropCommand(m.source, at: CGPoint(x: area.minX - 40, y: area.midY)))
        XCTAssertTrue(slot.isHidden, "out of the page nothing is ringed")
    }

    /// Q02 b: with nothing shown the card is Arc's opaque #FCFCFC with its shadow, not the theme.
    func testEmptyCardIsOpaqueNearWhite() throws {
        var m = model()
        for tab in [m.target, m.source] { m.state = reduce(m.state, .user(m.window, .tab(.close(.item(tab)))), m.ctx).state }
        let snapshot = project(m.state, ProjectionContext(now: m.ctx.now, calendar: .current)).windows[m.window]!
        XCTAssertTrue(snapshot.content.panes.isEmpty)
        let content = ContentAreaView(dispatch: { _ in })
        content.render(snapshot.content, frames: WindowLayout.compute(snapshot, contentSize: CGSize(width: 1280, height: 776)),
                       theme: snapshot.theme, palette: Palette(snapshot.theme), surface: { _ in nil })
        let card = try XCTUnwrap(content.subviews.compactMap { $0 as? CardView }.first)
        XCTAssertEqual(card.layer?.backgroundColor, ContentAreaView.blankLight.cgColor)
        XCTAssertEqual(ContentAreaView.blankLight.alphaComponent, 1)
        XCTAssertFalse(try XCTUnwrap(content.subviews.compactMap { $0 as? ShadowView }.first).isHidden)
    }

    /// Arc's ring is the folder outline: #725137 under the #F2EAE4 theme (P23-a), #006362 under the cyan one (P23-c).
    func testFocusRingMatchesArcUnderBothCaptureThemes() throws {
        func hex(_ c: NSColor) -> [Int] {
            let s = c.usingColorSpace(.sRGB)!
            return [s.redComponent, s.greenComponent, s.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        for (theme, arc) in [(RGBA(0xF2 / 255.0, 0xEA / 255.0, 0xE4 / 255.0, 1), [0x72, 0x51, 0x37]),
                             (RGBA(0xD8 / 255.0, 1, 0xFF / 255.0, 1), [0x00, 0x63, 0x62])] {
            let ring = hex(ThemeAccent.luminanceMatched(theme, luminance: ThemeAccentDraw.ringLuminance.value))
            for (a, b) in zip(ring, arc) { XCTAssertEqual(Double(a), Double(b), accuracy: 3, "ring \(ring) vs Arc \(arc)") }
        }
    }

    /// P23-splitmenu-arc.png: Arc's seven rows in four groups; the last pane cannot move right, a full split adds none.
    func testSplitMenuRowsFollowArc() {
        let split = ItemID("split")
        let rows = SplitMenuModel.rows(orientation: .horizontal, position: .init(split: split, index: 1, count: 2))
        XCTAssertEqual(rows.map { $0.map(\.title) }, [["Move Left", "Move Right"], ["Add Right Split", "Add Left Split"],
                                                     ["Separate Tab from Split", "Convert to Vertical Split View"], ["Share Split View…"]])
        XCTAssertEqual(rows[0].map(\.enabled), [true, false])
        XCTAssertEqual(rows[3][0].command, .app(.export(.items([split]))))
        let stacked = SplitMenuModel.rows(orientation: .vertical, position: .init(split: split, index: 0, count: 4))
        XCTAssertEqual(stacked[0].map(\.title), ["Move Up", "Move Down"])
        XCTAssertEqual(stacked[0].map(\.enabled), [false, true])
        XCTAssertEqual(stacked[1].map(\.enabled), [false, false])
        XCTAssertEqual(stacked[2][1].command, .split(.orientCurrent(.horizontal)))
    }
}
