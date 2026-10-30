import AppKit
import XCTest

@testable import BrkOverlays
import BrkBase
@testable import BrkDomain

/// The bar as AppKit drives it: text changes and key commands arrive through the input's delegate, and the only
/// thing the bar does is dispatch.
@MainActor
final class CommandBarViewTests: XCTestCase {
    private var sent: [Command] = []
    /// What the user chose: everything dispatched except the `queryChanged` each edit sends.
    private var chosen: [Command] {
        sent.filter { if case .commandBar(.queryChanged) = $0 { false } else { true } }
    }
    private let box = CGRect(x: 300, y: 219, width: 766, height: 338)

    private func makeBar(_ bar: CommandBarSnapshot = fixtureBar) -> CommandBarView {
        let view = CommandBarView(dispatch: { [unowned self] in self.sent.append($0) })
        view.resolve = fakeResolve
        view.show(bar, in: box, scheme: .light)
        return view
    }

    private func type(_ text: String, into view: CommandBarView) {
        view.input.stringValue = text
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view.input))
    }

    @discardableResult
    private func press(_ selector: Selector, in view: CommandBarView) -> Bool {
        view.control(view.input, textView: NSTextView(), doCommandBy: selector)
    }

    func testReturnDispatchesTheHighlightedResultAndArrowsWrapAround() {
        let view = makeBar()
        type("hub", into: view)   // t2, t1, "Search hub", hubspot.com, history status.example.com/hub
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        press(#selector(NSResponder.moveUp(_:)), in: view)       // from the first row up to the last
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        press(#selector(NSResponder.moveDown(_:)), in: view)     // from the last row down to the first
        press(#selector(NSResponder.moveDown(_:)), in: view)
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(chosen, [
            .tab(.focus(ItemID("t2"))),
            .commandBar(.submit("https://status.example.com/hub")),
            .tab(.focus(ItemID("t1"))),
        ])
    }

    func testTypingMovesTheHighlightBackToTheFirstRow() {
        let view = makeBar()
        type("hub", into: view)
        press(#selector(NSResponder.moveDown(_:)), in: view)
        type("hub ", into: view)
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(chosen, [.tab(.focus(ItemID("t2")))])
    }

    /// every edit asks the reducer for suggestions with the text as typed; a reopened bar does not
    func testEveryEditDispatchesTheQuery() {
        let view = makeBar()
        type("s", into: view)
        type("sw", into: view)
        type("", into: view)
        XCTAssertEqual(sent, [.commandBar(.queryChanged("s")), .commandBar(.queryChanged("sw")), .commandBar(.queryChanged(""))])
        view.show(commandBar(fixtureBar.tabs, fixtureBar.history, openID: 2), in: box, scheme: .light)
        XCTAssertEqual(sent.count, 3)
    }

    /// suggestions that arrive while the user looks at the rows slot in under the typed row and keep the highlight
    func testArrivingSuggestionsSlotInUnderTheTypedRow() {
        let view = makeBar(commandBar([], []))
        type("swi", into: view)
        XCTAssertEqual(rows(view.results).first, "open:Search swi")
        view.show(commandBar([], [], suggestions: ["swift", "swim"], suggestedFor: "swi"), in: box, scheme: .light)
        XCTAssertEqual(Array(rows(view.results).prefix(3)), ["open:Search swi", "suggestion:google:swift", "suggestion:google:swim"])
        press(#selector(NSResponder.moveDown(_:)), in: view)
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(chosen, [.commandBar(.submitSearch(engine: google.id, query: "swift"))])
    }

    /// Tab on a site-search row (or Space after an engine's whole name) enters site search: the engine's pill, an
    /// empty input, Return searches there; Backspace in the empty input or Esc gives the typed name back, and only
    /// a second Esc closes the bar
    func testSiteSearchModeWithTabSpaceBackspaceAndEscape() {
        let view = makeBar(commandBar([], [], siteSearch: [bing, kagi]))
        type("bi", into: view)
        XCTAssertTrue(rows(view.results).contains("site:Bing:Space or Tab"))
        XCTAssertTrue(press(#selector(NSResponder.insertTab(_:)), in: view))
        XCTAssertEqual(view.siteSearch, bing)
        XCTAssertEqual(view.input.stringValue, "")
        XCTAssertEqual(view.input.placeholderAttributedString?.string, "Search Bing…")
        type("swift", into: view)
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(chosen, [.commandBar(.submitSearch(engine: bing.id, query: "swift"))])

        type("", into: view)
        XCTAssertTrue(press(#selector(NSResponder.deleteBackward(_:)), in: view))
        XCTAssertNil(view.siteSearch)
        XCTAssertEqual(view.input.stringValue, "bi")

        type("kagi ", into: view)
        XCTAssertEqual(view.siteSearch, kagi, "Space after the whole name")
        XCTAssertTrue(press(#selector(NSResponder.cancelOperation(_:)), in: view))
        XCTAssertNil(view.siteSearch)
        XCTAssertEqual(view.input.stringValue, "kagi")
        XCTAssertEqual(chosen.count, 1, "the first Esc only leaves site search")
        press(#selector(NSResponder.cancelOperation(_:)), in: view)
        XCTAssertEqual(chosen.last, .commandBar(.dismiss))

        // Tab with no site-search row stays in the bar and does nothing; "bing" followed by a space and more words
        // is an ordinary search.
        type("weather", into: view)
        XCTAssertTrue(press(#selector(NSResponder.insertTab(_:)), in: view))
        XCTAssertNil(view.siteSearch)
        type("bing chilling ", into: view)
        XCTAssertNil(view.siteSearch)
    }

    func testEscapeDismissesAndReturnWithNothingToChooseDispatchesNothing() {
        let view = makeBar(commandBar([], []))
        XCTAssertTrue(press(#selector(NSResponder.insertNewline(_:)), in: view))
        XCTAssertTrue(press(#selector(NSResponder.cancelOperation(_:)), in: view))
        XCTAssertEqual(sent, [.commandBar(.dismiss)])
        // Other editing commands stay with the text field.
        XCTAssertFalse(press(#selector(NSResponder.deleteBackward(_:)), in: view))
    }

    func testTheSameOpeningKeepsWhatWasTypedAndANewOpeningStartsFromItsInitialQuery() {
        let view = makeBar()
        type("hub", into: view)
        press(#selector(NSResponder.moveDown(_:)), in: view)
        // A page event re-projects the same opening with one tab fewer: the query stays, the rows follow.
        view.show(commandBar(fixtureBar.tabs.filter { $0.tab != ItemID("t2") }, fixtureBar.history), in: box, scheme: .light)
        XCTAssertEqual(view.input.stringValue, "hub")
        XCTAssertEqual(rows(view.results), ["switch:t1", "open:Search hub", "domain:hubspot.com", "history:https://status.example.com/hub"])
        // Cmd+L opens a new bar: its query is the tab's URL and the first row is highlighted again.
        view.show(commandBar(fixtureBar.tabs, fixtureBar.history, openID: 2, initialQuery: "https://github.com/arc"), in: box, scheme: .light)
        XCTAssertEqual(view.input.stringValue, "https://github.com/arc")
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(chosen, [.tab(.focus(ItemID("t1")))])
    }

    func testRowsCarryTheirIdentifiersAndOnlyTheCardTakesClicks() {
        let root = FlippedView(frame: CGRect(x: 0, y: 0, width: 1280, height: 776))
        let view = makeBar()
        root.addSubview(view)
        type("hub", into: view)
        let shown = view.descendants.filter { !$0.isHiddenOrHasHiddenAncestor }.map { $0.accessibilityIdentifier() }
        XCTAssertEqual(shown.filter { $0.hasPrefix("command-bar-result-") },
                       ["command-bar-result-0", "command-bar-result-1", "command-bar-result-2", "command-bar-result-3", "command-bar-result-4"])
        // Card: the 50 pt input row, then 5 rows of 50 and the list's 10 pt padding (layout-constants.md).
        // Points are in the bar's superview, as AppKit passes them to `hitTest`.
        let rowCentre = CGPoint(x: box.midX, y: box.minY + 50 + 5 + 25)
        XCTAssertEqual(view.hitTest(rowCentre)?.enclosing(ResultRowView.self)?.accessibilityIdentifier(), "command-bar-result-0")
        XCTAssertNotNil(view.hitTest(CGPoint(x: box.midX, y: box.minY + 309)))
        XCTAssertNil(view.hitTest(CGPoint(x: box.midX, y: box.minY + 311)), "below the card the box lets clicks through")
    }
}

extension NSView {
    var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) }

    func enclosing<T: NSView>(_ type: T.Type) -> T? {
        var view: NSView? = self
        while let current = view {
            if let match = current as? T { return match }
            view = current.superview
        }
        return nil
    }
}

/// Mouse behavior through the real event path: `NSApp.sendEvent` with events aimed at a window that holds the bar,
/// the way the control socket's `click` op delivers them.
@MainActor
final class CommandBarPointerTests: XCTestCase {
    private var sent: [Command] = []

    private func click(_ point: CGPoint, in window: NSWindow) {
        // Window coordinates of AppKit events count from the bottom-left.
        let location = CGPoint(x: point.x, y: window.contentLayoutRect.height - point.y)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        // The up goes in the queue first: a text field's mouse-down runs a tracking loop that waits for it.
        NSApp.postEvent(event(.leftMouseUp), atStart: false)
        NSApp.sendEvent(event(.leftMouseDown))
        if let up = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) { NSApp.sendEvent(up) }
    }

    func testAClickOutsideTheCardDismissesAndAClickOnARowChoosesIt() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 776), styleMask: [.borderless], backing: .buffered, defer: false)
        let root = FlippedView(frame: CGRect(x: 0, y: 0, width: 1280, height: 776))
        window.contentView = root
        let box = CGRect(x: 300, y: 219, width: 766, height: 338)
        let bar = CommandBarView(dispatch: { [unowned self] in self.sent.append($0) })
        bar.resolve = fakeResolve
        root.addSubview(bar)
        bar.show(fixtureBar, in: box, scheme: .light)
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        click(CGPoint(x: box.midX, y: box.minY + 25), in: window)          // the input row: stays open
        XCTAssertEqual(sent, [])
        click(CGPoint(x: box.midX, y: box.minY + 50 + 5 + 25), in: window) // the first row: t1
        XCTAssertEqual(sent, [.tab(.focus(ItemID("t1")))])
        sent = []
        click(CGPoint(x: 100, y: 700), in: window)                          // outside the card
        XCTAssertEqual(sent, [.commandBar(.dismiss)])
    }
}
