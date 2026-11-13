import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
@testable import BrkSidebar
@testable import BrkUIKit
import XCTest

/// Sidebar views under the pointer and the keyboard, from the 2026-11-12 audit: buttons nobody sees take no clicks,
/// Control-click is a right-click, the hover card's wait, its closing and the floating sidebar around it, the Space
/// pager's jump, and the translation popover. Views on a window whose commands are recorded, not run.
@MainActor
final class SidebarPointerFixTests: XCTestCase {
    static let size = CGSize(width: 1280, height: 776)

    private final class Rig {
        var state: AppState
        let ctx: Context
        let projection: ProjectionContext
        let id: WindowID
        var sent: [Command] = []
        var window: NSWindow!
        var root: WindowRootView!
        init(state: AppState, ctx: Context, projection: ProjectionContext, id: WindowID) {
            self.state = state; self.ctx = ctx; self.projection = projection; self.id = id
        }
        var view: WindowSnapshot { project(state, projection).windows[id]! }
        func run(_ command: Command) { state = reduce(state, .user(id, command), ctx).state }
        @MainActor func render(_ snapshot: WindowSnapshot? = nil) {
            let shown = snapshot ?? view
            root.render(shown, frames: WindowLayout.compute(shown, contentSize: SidebarPointerFixTests.size), surface: { _ in nil })
            root.layoutSubtreeIfNeeded()
        }
        var folder: FolderRow? {
            for row in view.space.pinned.rows + view.space.today.rows { if case .folder(let folder) = row { return folder } }
            return nil
        }
    }

    /// Today a, b, c with hover previews on. `folder`: two of them go into a collapsed folder. `onScreen`: the window is
    /// ordered in far off screen, where a hover card can open (it opens only over a visible window).
    private func rig(startURL: String? = "http://127.0.0.1:9/a", folder: Bool = false, onScreen: Bool = false,
                     setup: (Rig) -> Void = { _ in }) throws -> Rig {
        _ = NSApplication.shared
        let ids = IDs()
        let now = Instant(milliseconds: 1_790_000_000_000)
        let ctx = Context(now: now, newID: ids.next)
        let projection = ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))
        let state = StateCodec.restore(nil, seed: RestoreSeed(startURL: startURL.flatMap(URL.init(string:)), contentSize: Self.size), ctx: ctx).state
        let id = try XCTUnwrap(project(state, projection).windows.keys.first)
        let rig = Rig(state: state, ctx: ctx, projection: projection, id: id)
        rig.run(.tabTools(.preferences(includeFavorites: false, previews: true)))
        if startURL != nil {
            for path in ["b", "c"] {
                rig.run(.commandBar(.open(.newTab)))
                rig.run(.commandBar(.submit("http://127.0.0.1:9/" + path)))
            }
        }
        if folder {
            let today = rig.view.space.today.rows.map(\.id)
            rig.run(.tabTools(.bulk(.items([today[0], today[1]]), .newFolder(group: false))))
            let made = try XCTUnwrap(rig.folder)
            rig.run(.item(.rename(made.id, title: "Folder")))
            if !(rig.folder?.collapsed ?? false) { rig.run(.item(.toggleFolder(made.id))) }
            XCTAssertEqual(rig.folder?.collapsed, true)
        }
        setup(rig)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if onScreen {
            window.setFrameOrigin(CGPoint(x: -6000, y: -6000))
            window.orderFront(nil)
        }
        addTeardownBlock { @MainActor in window.orderOut(nil) }
        let root = WindowRootView(dispatch: { [weak rig] in rig?.sent.append($0) })
        window.contentView = root
        rig.window = window
        rig.root = root
        rig.render()
        return rig
    }

    private func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// Waits until `condition` holds or `timeout` passes. GitHub's runners fire the card's timers late: a fixed wait of
    /// the delay plus 0.2 s failed there twice (builds 35 and 36) while the card opened fine.
    private func wait(until condition: () -> Bool, timeout: Double) {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { wait(0.02) }
    }

    private func card(in rig: Rig) -> FolderPreviewView? { ViewTreeSearch.find("sidebar-hover-card", in: rig.root) as? FolderPreviewView }

    private func enterExit(_ type: NSEvent.EventType, in window: NSWindow, at location: CGPoint = .zero) -> NSEvent {
        NSEvent.enterExitEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
    }

    private func mouse(_ type: NSEvent.EventType, at windowPoint: CGPoint, in window: NSWindow, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                           context: nil, eventNumber: 0, clickCount: type == .mouseMoved ? 0 : 1, pressure: type == .mouseMoved ? 0 : 1)!
    }

    /// Opens the collapsed folder's card: the pointer rests on the row, then moves onto the card.
    private func openCard(_ rig: Rig) throws -> (row: RowView, card: FolderPreviewView) {
        let folder = try XCTUnwrap(rig.folder)
        let row = try XCTUnwrap(ViewTreeSearch.find(ViewID.row(folder.id).identifier, in: rig.root) as? RowView)
        row.setHovered(true)
        wait(until: { self.card(in: rig) != nil }, timeout: PreviewDraw.delay.value + 3)
        let card = try XCTUnwrap(card(in: rig), "the folder's card did not open")
        card.mouseEntered(with: enterExit(.mouseEntered, in: rig.window))
        row.setHovered(false)
        return (row, card)
    }

    // MARK: Buttons that are not shown

    /// A row's × shows only while the pointer is on the row. With Brk in the background there is no hover, and the
    /// first click into the window landed on the invisible × and archived the tab; it selects the row, as in Arc.
    func testARowsCloseButtonTakesClicksOnlyWhileItShows() throws {
        let rig = try rig()
        guard case .tab(let tab)? = rig.view.space.today.rows.first else { return XCTFail("no Today tab") }
        let row = try XCTUnwrap(ViewTreeSearch.find(ViewID.row(tab.id).identifier, in: rig.root) as? RowView)
        let close = try XCTUnwrap(ViewTreeSearch.find(ViewID.rowClose(tab.id).identifier, in: row))
        let spot = close.convert(CGPoint(x: close.bounds.midX, y: close.bounds.midY), to: row.superview)
        XCTAssertTrue(row.hitTest(spot) === row, "a click on the hidden × went to \(String(describing: row.hitTest(spot)))")
        row.setHovered(true)
        XCTAssertTrue(row.hitTest(spot) === close, "the shown × does not take its click")
    }

    /// A window with no page reads "Search or Enter URL…" with a magnifier: a click anywhere on the pill opens the
    /// command bar. The magnifier (an off site-controls button) swallowed it, and the invisible copy-link button at
    /// the right end took it and copied nothing.
    func testEveryPartOfAnEmptyPillOpensTheCommandBar() throws {
        let rig = try rig(startURL: nil)
        let pill = rig.root.sidebar.urlPill
        XCTAssertNil(rig.view.urlPill.text)
        let magnifier = try XCTUnwrap(ViewTreeSearch.find(ViewID.siteInfo.identifier, in: pill))
        for point in [CGPoint(x: magnifier.frame.midX, y: magnifier.frame.midY), CGPoint(x: pill.bounds.maxX - 12, y: pill.bounds.midY),
                      CGPoint(x: pill.bounds.midX, y: pill.bounds.midY)] {
            let hit = pill.hitTest(pill.convert(point, to: pill.superview))
            XCTAssertTrue(hit === pill, "a click at \(point) went to \(String(describing: hit)), not the pill")
        }
    }

    // MARK: Control-click

    /// Control-click is a right-click, as on the rows and the Favorites: the Space name opens the Space's menu, the
    /// pill its site controls. The name toggled Pinned and the pill opened the command bar.
    func testControlClickOnTheSpaceNameAndThePillIsARightClick() throws {
        let rig = try rig()
        func controlClick(_ view: NSView) {
            let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            view.mouseDown(with: mouse(.leftMouseDown, at: point, in: rig.window, flags: .control))
            view.mouseUp(with: mouse(.leftMouseUp, at: point, in: rig.window, flags: .control))
        }
        controlClick(rig.root.sidebar.spaceHeader)
        XCTAssertFalse(rig.sent.contains(.space(.togglePinnedSection(.current))), "Control-click toggled Pinned")
        XCTAssertTrue(rig.sent.contains { if case .sidebar(.popupMenu(.spaceControls(_), _)) = $0 { true } else { false } }, "no Space menu: \(rig.sent)")
        rig.sent = []
        controlClick(rig.root.sidebar.urlPill)
        XCTAssertFalse(rig.sent.contains(.commandBar(.open(.editCurrent))), "Control-click opened the command bar")
        XCTAssertEqual(rig.sent, [.site(.controls)])
    }

    // MARK: The hover card

    /// The card opens after the pointer rests on the folder half a second. A page loading redraws the sidebar several
    /// times a second, and each redraw told the card the pointer had left and come back, which started the wait again.
    func testRedrawsWhileAPageLoadsDoNotRestartTheCardsWait() throws {
        let rig = try rig(folder: true, onScreen: true)
        let folder = try XCTUnwrap(rig.folder)
        let row = try XCTUnwrap(ViewTreeSearch.find(ViewID.row(folder.id).identifier, in: rig.root) as? RowView)
        row.setHovered(true)
        let start = Date()
        var progress = 0.0
        // A redraw every tenth of a second until the card opens. A wait restarted by each redraw would never end; the
        // limit only has room for a runner that fires timers late.
        while card(in: rig) == nil, Date().timeIntervalSince(start) < PreviewDraw.delay.value + 3 {
            wait(0.1)
            guard card(in: rig) == nil else { break }
            progress += 0.05
            var shown = rig.view
            shown.urlPill.loading = true
            shown.urlPill.loadProgress = progress
            rig.render(shown)
        }
        XCTAssertNotNil(card(in: rig), "the card did not open while the page loaded")
    }

    /// The card stays while its search field has the keyboard, even with the pointer off it. Once the field loses the
    /// keyboard (a click on the page) with the pointer away, the card closes; it stayed over the page for good.
    func testTheCardClosesWhenItsSearchFieldLosesTheKeyboardWithThePointerAway() throws {
        let rig = try rig(folder: true, onScreen: true)
        let (_, card) = try openCard(rig)
        let search = try XCTUnwrap(card.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        XCTAssertTrue(rig.window.makeFirstResponder(search))
        search.stringValue = "b"
        card.mouseExited(with: enterExit(.mouseExited, in: rig.window))
        wait(PreviewDraw.hideDelay.value + 0.1)
        XCTAssertNotNil(self.card(in: rig), "the card closed while its field had the keyboard")
        let page = NSTextView(frame: CGRect(x: 600, y: 300, width: 100, height: 50))
        rig.root.addSubview(page)
        XCTAssertTrue(rig.window.makeFirstResponder(page))
        wait(until: { self.card(in: rig) == nil }, timeout: PreviewDraw.hideDelay.value + 3)
        XCTAssertNil(self.card(in: rig), "the card stayed over the page after its field lost the keyboard")
    }

    // MARK: The floating sidebar

    /// The floating sidebar stays out while the pointer is on its hover card, which reaches past the 80 pt the column
    /// keeps beyond its edge; off the card that far, the column goes.
    func testTheFloatingSidebarStaysWhileThePointerIsOnItsHoverCard() throws {
        let rig = try rig(folder: true, onScreen: true) { rig in
            rig.run(.sidebar(.toggle))
            rig.run(.sidebar(.peek(true)))
        }
        let frames = try XCTUnwrap(WindowLayout.compute(rig.view, contentSize: Self.size).sidebar)
        XCTAssertTrue(WindowLayout.compute(rig.view, contentSize: Self.size).sidebarFloats)
        let tracking = try XCTUnwrap(rig.root.trackingAreas.compactMap { $0.owner as? FloatingSidebarTracking }.first)
        let (_, card) = try openCard(rig)
        let onCard = CGPoint(x: frames.frame.maxX + Metrics.sidebar.floatingStayOpenSlack.value + 60, y: card.frame.midY)
        XCTAssertTrue(card.frame.contains(onCard), "the point \(onCard) is not on the card \(card.frame)")
        let moved = mouse(.mouseMoved, at: rig.root.convert(onCard, to: nil), in: rig.window)
        rig.sent = []
        tracking.mouseMoved(with: moved)
        XCTAssertFalse(rig.sent.contains(.sidebar(.peek(false))), "the column went while the pointer was on its card")
        card.mouseExited(with: enterExit(.mouseExited, in: rig.window))
        tracking.mouseMoved(with: moved)
        XCTAssertTrue(rig.sent.contains(.sidebar(.peek(false))), "the column stayed with the pointer off it and its card")
    }

    /// Arc keeps the floating sidebar out while the pointer is within 250 pt past the window's left edge. Leaving the
    /// window there closed it at once; past those 250 pt it goes.
    func testTheFloatingSidebarStaysInTheZoneLeftOfTheWindow() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(CGPoint(x: -6000, y: -6000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.contentView = root
        var dismissed = 0
        let tracking = FloatingSidebarTracking(root: root, staysOpen: { false }, boundary: { 300 }, dismiss: { dismissed += 1 })
        defer { tracking.stop() }
        tracking.mouseExited(with: enterExit(.mouseExited, in: window, at: CGPoint(x: -2, y: 300)))
        XCTAssertEqual(dismissed, 0, "leaving the window on the left closed the column")
        tracking.mouseMoved(with: mouse(.mouseMoved, at: CGPoint(x: -200, y: 300), in: window))
        XCTAssertEqual(dismissed, 0, "200 pt left of the window closed the column")
        tracking.mouseMoved(with: mouse(.mouseMoved, at: CGPoint(x: -260, y: 300), in: window))
        XCTAssertEqual(dismissed, 1, "past the zone the column stayed")
        tracking.mouseExited(with: enterExit(.mouseExited, in: window, at: CGPoint(x: 400, y: 602)))
        XCTAssertEqual(dismissed, 2, "leaving over the top edge kept the column")
    }

    /// Another app coming to the front (a click in that zone left of the window, ⌘Tab) ends the moves that decide: the
    /// column goes then unless the pointer is on it. It stayed drawn over the page while Brk was in the back.
    func testTheFloatingSidebarGoesWhenAnotherAppComesToTheFront() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(CGPoint(x: -6000, y: -6000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.contentView = root
        var dismissed = 0
        let tracking = FloatingSidebarTracking(root: root, staysOpen: { false }, boundary: { 300 }, dismiss: { dismissed += 1 })
        defer { tracking.stop() }
        tracking.pointer = { window.convertPoint(toScreen: CGPoint(x: 100, y: 300)) }
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertEqual(dismissed, 0, "the column went with the pointer on it")
        tracking.pointer = { window.convertPoint(toScreen: CGPoint(x: -100, y: 300)) }
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertEqual(dismissed, 1, "the column stayed over the page with Brk in the back and the pointer off it")
    }

    // MARK: The Space pager

    /// A jump to a Space that is not the current one's neighbour starts with the Space left standing one column width
    /// beside the new one. Jumping to the first Space from the third started a Library width away instead (the page
    /// before the first Space is the Library, 417 pt or more): a blank column and the wrong dots lit.
    func testAJumpToTheFirstSpaceStartsOneColumnAway() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(CGPoint(x: -6000, y: -6000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let host = NSView(frame: window.contentLayoutRect)
        window.contentView = host
        let pager = PagePager<Int>()
        pager.host = host
        let library = 417.0, column = 228.0
        pager.update(pages: [0, 1, 2, 3], widths: [library, column, column, column])
        pager.select(3, animated: false)
        var first: Double?
        pager.onMove = { if first == nil { first = pager.position } }
        pager.select(1, animated: true)
        XCTAssertEqual(first ?? 0, library + column, accuracy: 0.001, "the jump from the third Space did not start one column right of the first")
        pager.select(1, animated: false)
        first = nil
        pager.select(3, animated: true)
        XCTAssertEqual(first ?? 0, library + column, accuracy: 0.001, "the jump from the first Space did not start one column left of the third")
        pager.select(3, animated: false)
        pager.onMove = nil
    }

    // MARK: The translation popover

    /// A second click on "Translation Available" replaces the open popover. The first one's did-close notice arrives
    /// after its fade, and it dropped the reference to the second, which then neither Translate nor the pill could close.
    func testALatePopoverCloseNoticeDoesNotLoseTheNewPopover() throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(CGPoint(x: -6000, y: -6000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let anchor = NSView(frame: CGRect(x: 40, y: 40, width: 120, height: 20))
        window.contentView?.addSubview(anchor)
        final class Seen: @unchecked Sendable { var popovers: [NSPopover] = [] }
        let seen = Seen()
        let token = NotificationCenter.default.addObserver(forName: NSPopover.willShowNotification, object: nil, queue: nil) { note in
            if let popover = note.object as? NSPopover { seen.popovers.append(popover) }
        }
        defer {
            NotificationCenter.default.removeObserver(token)
            for popover in seen.popovers { popover.close() }
        }
        let popover = TranslationPopover(dispatch: { _ in })
        popover.show(from: anchor, kind: .offer(to: "English"))
        popover.show(from: anchor, kind: .offer(to: "English"))
        XCTAssertEqual(seen.popovers.count, 2)
        let (first, second) = (try XCTUnwrap(seen.popovers.first), try XCTUnwrap(seen.popovers.last))
        XCTAssertTrue(second.isShown)
        popover.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: first))
        popover.close()
        // It fades out first.
        let start = Date()
        while second.isShown, Date().timeIntervalSince(start) < 1.5 { wait(0.05) }
        XCTAssertFalse(second.isShown, "the second popover stayed open")
    }
}
