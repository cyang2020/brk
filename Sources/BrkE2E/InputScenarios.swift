import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// The input rules of 2026-11-10 (docs/design/input-rules.md), one scenario per cause group, each with real input posted
/// to the window server on a normally launched Brk (keys at the HID tap, real mouse buttons, a phased two-finger
/// gesture, the navigation swipe a mouse driver posts). The control socket only sets up and reads state.
enum InputScenarios {
    static let all: [Scenario] = [
        Scenario("Input-TabKeys", "real keys with a page focused: ⇧⌘] and ⇧⌘[ step to the next and previous tab (Chrome's reserved tab keys, which Arc honours)",
                 tabKeys),
        Scenario("Input-SideButtons", "mouse buttons 4 and 5 and a mouse driver's navigation swipe: over the page back and forward in its history, over the sidebar the previous and next Space",
                 sideButtons),
        Scenario("Input-SwipeIndicator", "a two-finger swipe right on a page with history starts Chromium's back indicator at the page's left edge; over a horizontal scroller it does not",
                 swipeIndicator),
        Scenario("Input-MiddleClick", "a middle-click on a link opens it in a background tab; on a sidebar tab row it closes that tab",
                 middleClick),
    ]

    // MARK: Setup and facts

    /// A fresh tab on the audit page at `?p=2` with `?p=1` behind it, ready for input. The second page is reached by a
    /// real click on its link: a script navigation right after a load is a client redirect to Chromium, which replaces
    /// the history entry instead of adding one.
    private static func pageWithHistory(_ app: AppUnderTest) throws -> PageID {
        let url = app.site.url("input-audit.html?p=1")
        let item = try app.load(url)
        let page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: url)
        try click(app, try element(app, page, "#next"), button: 0)
        try app.waitUntil("the tab on ?p=2") { try url2(app) }
        try app.waitUntil("the page can go back") { try app.view().urlPill.canGoBack }
        return page
    }

    private static func url2(_ app: AppUnderTest) throws -> Bool { try currentTab(app.view())?.url?.query == "p=2" }
    private static func title(_ app: AppUnderTest) throws -> String { try currentTab(app.view())?.title ?? "" }

    /// The centre of a page element in window coordinates, read back through the page's title.
    private static func element(_ app: AppUnderTest, _ page: PageID, _ selector: String) throws -> CGPoint {
        try app.evaluate(page, "var r=document.querySelector('\(selector)').getBoundingClientRect();document.title='rect:'+Math.round(r.left+Math.min(20,r.width/2))+','+Math.round(r.top+r.height/2)")
        var text = ""
        try app.waitUntil("the element's place") { text = try title(app); return text.hasPrefix("rect:") }
        let parts = text.dropFirst(5).split(separator: ",").compactMap { Double($0) }
        let frame = try XCTUnwrapValue(try app.native().pages[page]?.surfaceFrame)
        return CGPoint(x: frame.minX + parts[0], y: frame.minY + parts[1])
    }

    private static func pageCentre(_ app: AppUnderTest, _ page: PageID) throws -> CGPoint {
        let frame = try XCTUnwrapValue(try app.native().pages[page]?.surfaceFrame)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    // MARK: Real input

    /// A window point (top-left content coordinates) on the screen, refused unless this Brk is in front there.
    private static func screen(_ app: AppUnderTest, _ point: CGPoint) throws -> CGPoint {
        let window = app.window!
        try WindowServerKeys.ensureFrontmost(app, window)
        let frame = try app.native(window).windowFrame
        let at = CGPoint(x: frame.minX + point.x, y: CGDisplayBounds(CGMainDisplayID()).height - frame.maxY + point.y)
        guard case .hello(let hello) = try app.send(.hello), PhysicalPointer.frontmost(at: at)?.pid == hello.pid else {
            throw Check(description: "another window is in front of Brk at \(at); real mouse events not posted")
        }
        return at
    }

    /// A real click of `button` (0 left, 2 middle, 3 back, 4 forward) at a window point.
    private static func click(_ app: AppUnderTest, _ point: CGPoint, button: Int) throws {
        let at = try screen(app, point)
        let source = CGEventSource(stateID: .hidSystemState)
        let mouse = CGMouseButton(rawValue: UInt32(button)) ?? .center
        let (down, up): (CGEventType, CGEventType) = button == 0 ? (.leftMouseDown, .leftMouseUp) : (.otherMouseDown, .otherMouseUp)
        for type in [CGEventType.mouseMoved, down, up] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: mouse) else { throw Check(description: "mouse event") }
            if type != .mouseMoved {
                event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
                event.setIntegerValueField(.mouseEventClickState, value: 1)
            }
            event.post(tap: .cghidEventTap)
            usleep(type == .mouseMoved ? 150_000 : 70_000)
        }
    }

    /// The navigation swipe Logi Options+ and Mac Mouse Fix post for Back and Forward: a gesture event of HID type
    /// NavigationSwipe (16), began then ended; AppKit turns it into an `NSEventTypeSwipe` with deltaX +1 (back) or -1.
    private static func navigationSwipe(_ app: AppUnderTest, back: Bool, at point: CGPoint) throws {
        let at = try screen(app, point)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(120_000)
        guard let event = CGEvent(source: nil), let type = CGEventField(rawValue: 55), let hidType = CGEventField(rawValue: 110),
              let phase = CGEventField(rawValue: 132), let motion = CGEventField(rawValue: 115) else { throw Check(description: "gesture event") }
        event.location = at
        event.setIntegerValueField(type, value: 29)
        event.setIntegerValueField(hidType, value: 16)
        event.setIntegerValueField(phase, value: 1)
        event.setIntegerValueField(motion, value: back ? 4 : 8)
        event.post(tap: .cghidEventTap)
        usleep(20_000)
        event.setIntegerValueField(motion, value: 0)
        event.setIntegerValueField(phase, value: 4)
        event.post(tap: .cghidEventTap)
        usleep(100_000)
    }

    // MARK: Scenarios

    @Sendable static func tabKeys(_ app: AppUnderTest) throws {

        let window = app.window!
        // From the new top row ⇧⌘] goes to the row below, ⇧⌘[ comes back.
        let target = app.site.url("input-audit.html?p=second")
        let second = try app.load(target)
        try app.waitForPageInput(PageID(window: window, item: second), at: target)
        try click(app, try pageCentre(app, PageID(window: window, item: second)), button: 0)
        let order = todayIDs(try app.view())
        let below = try XCTUnwrapValue(order.firstIndex(of: second).flatMap { $0 + 1 < order.count ? order[$0 + 1] : nil })
        try WindowServerKeys.press(app, KeyChord([.shift, .command], .rightBracket), window: window)
        try app.waitUntil("⇧⌘] stepped to the next tab") { try currentTab(app.view())?.id == below }
        try WindowServerKeys.press(app, KeyChord([.shift, .command], .leftBracket), window: window)
        try app.waitUntil("⇧⌘[ stepped back to the previous tab") { try currentTab(app.view())?.id == second }
        app.passed("⇧⌘] and ⇧⌘[ stepped tabs")
    }

    @Sendable static func sideButtons(_ app: AppUnderTest) throws {

        let home = try app.view().space.id
        let second = try createSpace(app, title: "Second")
        let page = try pageWithHistory(app)
        // Over the page: Chromium's own (Blink goes back and forward on the side buttons).
        try click(app, try pageCentre(app, page), button: 3)
        try app.waitUntil("button 4 over the page went back") { try !url2(app) }
        try click(app, try pageCentre(app, page), button: 4)
        try app.waitUntil("button 5 over the page went forward") { try url2(app) }
        app.passed("buttons 4 and 5 over the page went back and forward")
        // Over the sidebar: the previous and next Space, as Arc does.
        let list = try XCTUnwrapValue(try app.native().computed.sidebar?.tablistViewport)
        let empty = CGPoint(x: list.midX, y: list.maxY - 30)
        try click(app, empty, button: 3)
        try app.waitUntil("button 4 over the sidebar went to the previous Space") { try app.view().space.id == home }
        try click(app, empty, button: 4)
        try app.waitUntil("button 5 over the sidebar came back to the next Space") { try app.view().space.id == second }
        try expect(try url2(app), "the Space steps changed the page's history")
        app.passed("buttons 4 and 5 over the sidebar stepped Spaces")
        // The navigation swipe (mouse drivers' Back and Forward): the page's history over the page, Spaces over the sidebar.
        try navigationSwipe(app, back: true, at: try pageCentre(app, page))
        try app.waitUntil("the navigation swipe back over the page went back") { try !url2(app) }
        try navigationSwipe(app, back: false, at: try pageCentre(app, page))
        try app.waitUntil("the navigation swipe forward went forward") { try url2(app) }
        try navigationSwipe(app, back: true, at: empty)
        try app.waitUntil("the navigation swipe back over the sidebar went to the previous Space") { try app.view().space.id == home }
        app.passed("the navigation swipe went back and forward over the page and stepped Spaces over the sidebar")
    }

    @Sendable static func swipeIndicator(_ app: AppUnderTest) throws {

        let window = app.window!
        let page = try pageWithHistory(app)
        let frame = try XCTUnwrapValue(try app.native().pages[page]?.surfaceFrame)
        // Chromium's shield: a black disc at alpha 0.25 at least (#BFBFBF or darker over the white page), centred
        // vertically on the page, a few points in from the left edge once the swipe has started.
        let probe = CGPoint(x: frame.minX + 2, y: frame.midY)
        func shield() throws -> Bool { let p = try app.pixel(probe); return p.count >= 3 && p[0] < 225 && abs(p[0] - p[2]) < 8 }
        try expect(try !shield(), "the page's left edge is not white before the swipe")
        var during = false
        try PhysicalPointer.swipe(app, at: try pageCentre(app, page), first: (4, 0), steps: Array(repeating: (22.0, 0.0), count: 10),
                                  held: { during = try shield() }, window: window)
        try expect(during, "no back indicator at the page's left edge while the fingers swiped right")
        try app.waitUntil("the indicator gone after the fingers lifted") { try !shield() }
        app.passed("a swipe right on the page showed Chromium's back indicator at its left edge")
        // Over the horizontal scroller, scrolled into its middle: the scroller takes the gesture, no indicator.
        try app.evaluate(page, "document.getElementById('wide').scrollLeft=600")
        app.sleep(0.4)
        var overScroller = true
        try PhysicalPointer.swipe(app, at: try element(app, page, "#wide"), first: (4, 0), steps: Array(repeating: (22.0, 0.0), count: 10),
                                  held: { overScroller = try shield() }, window: window)
        try expect(!overScroller, "a swipe over a horizontal scroller started the back indicator")
        try expect(try url2(app), "a swipe over a horizontal scroller navigated")
        app.passed("over a horizontal scroller the swipe scrolled it, no indicator")
    }

    @Sendable static func middleClick(_ app: AppUnderTest) throws {

        let window = app.window!
        let url = app.site.url("input-audit.html?p=1")
        let item = try app.load(url)
        let page = PageID(window: window, item: item)
        try app.waitForPageInput(page, at: url)
        let before = Set(allTabs(try app.view()).map(\.id))
        try click(app, try element(app, page, "#third"), button: 2)
        try app.waitUntil("the middle-clicked link in a new tab") { Set(allTabs(try app.view()).map(\.id)).count == before.count + 1 }
        try expect(try currentTab(app.view())?.id == item, "a middle-clicked link took the focus")
        app.passed("a middle-clicked link opened in a background tab")
        let opened = try XCTUnwrapValue(allTabs(try app.view()).map(\.id).first { !before.contains($0) })
        try app.waitUntil("the new tab's row") { try app.native().actual[ViewID.row(opened).identifier] != nil }
        let row = try XCTUnwrapValue(try app.native().actual[ViewID.row(opened).identifier]?.frame)
        try click(app, CGPoint(x: row.midX, y: row.midY), button: 2)
        try app.waitUntil("the middle-clicked row's tab closed") { !allTabs(try app.view()).contains { $0.id == opened } }
        try expect(try currentTab(app.view())?.id == item, "closing a background row by middle-click changed the current tab")
        app.passed("a middle-click on a sidebar tab row closed that tab")
    }
}
