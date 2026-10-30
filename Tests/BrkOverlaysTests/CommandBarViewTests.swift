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
        type("hub", into: view)   // t2, t1, "Search hub", history status.example.com/hub
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        press(#selector(NSResponder.moveUp(_:)), in: view)       // from the first row up to the last
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        press(#selector(NSResponder.moveDown(_:)), in: view)     // from the last row down to the first
        press(#selector(NSResponder.moveDown(_:)), in: view)
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(sent, [
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
        XCTAssertEqual(sent, [.tab(.focus(ItemID("t2")))])
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
        XCTAssertEqual(rows(view.results), ["switch:t1", "open:Search hub", "history:https://status.example.com/hub"])
        // Cmd+L opens a new bar: its query is the tab's URL and the first row is highlighted again.
        view.show(commandBar(fixtureBar.tabs, fixtureBar.history, openID: 2, initialQuery: "https://github.com/arc"), in: box, scheme: .light)
        XCTAssertEqual(view.input.stringValue, "https://github.com/arc")
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(sent, [.tab(.focus(ItemID("t1")))])
    }

    func testRowsCarryTheirIdentifiersAndOnlyTheCardTakesClicks() {
        let root = FlippedView(frame: CGRect(x: 0, y: 0, width: 1280, height: 776))
        let view = makeBar()
        root.addSubview(view)
        type("hub", into: view)
        let shown = view.descendants.filter { !$0.isHiddenOrHasHiddenAncestor }.map { $0.accessibilityIdentifier() }
        XCTAssertEqual(shown.filter { $0.hasPrefix("command-bar-result-") },
                       ["command-bar-result-0", "command-bar-result-1", "command-bar-result-2", "command-bar-result-3"])
        // Card: the 50 pt input row, then 4 rows of 50 and the list's 10 pt padding (layout-constants.md).
        // Points are in the bar's superview, as AppKit passes them to `hitTest`.
        let rowCentre = CGPoint(x: box.midX, y: box.minY + 50 + 5 + 25)
        XCTAssertEqual(view.hitTest(rowCentre)?.enclosing(ResultRowView.self)?.accessibilityIdentifier(), "command-bar-result-0")
        XCTAssertNotNil(view.hitTest(CGPoint(x: box.midX, y: box.minY + 259)))
        XCTAssertNil(view.hitTest(CGPoint(x: box.midX, y: box.minY + 261)), "below the card the box lets clicks through")
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
