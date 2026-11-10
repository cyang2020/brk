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
        sent.filter { switch $0 { case .commandBar(.queryChanged), .commandBar(.queryChangedForSite), .commandBar(.ran): false; default: true } }
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
        type("hub", into: view)
        let results = view.results
        XCTAssertGreaterThan(results.count, 2)
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        press(#selector(NSResponder.moveUp(_:)), in: view)       // from the first row up to the last
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        press(#selector(NSResponder.moveDown(_:)), in: view)     // from the last row down to the first
        press(#selector(NSResponder.moveDown(_:)), in: view)
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(chosen, [results[0].command, results[results.count - 1].command, results[1].command])
        XCTAssertEqual(sent.filter { if case .commandBar(.ran) = $0 { true } else { false } }.count,
                       [results[0], results[results.count - 1], results[1]].filter { $0.usageKey != nil }.count, "each row with a key is learned first")
    }

    /// Arc's inline completion (P02-c, Q01-b): typing on shows the rest of a site's domain after what was typed and
    /// the site leads; the next letter replaces the rest; a deletion never completes; the query sent is what was
    /// typed; → keeps the whole domain
    func testTypingOnCompletesASiteAndDeletingDoesNot() {
        let view = makeBar(commandBar([], [], siteSearch: [bing]))
        type("you", into: view)
        XCTAssertEqual(view.typed, "you")
        XCTAssertEqual(view.completion, "youtube.com")
        XCTAssertEqual(view.input.stringValue, "youtube.com")
        XCTAssertEqual(rows(view.results).first, "domain:youtube.com")
        XCTAssertEqual(view.results.first?.title, "YouTube")
        type("yout", into: view)
        XCTAssertEqual(view.input.stringValue, "youtube.com")
        type("yout", into: view)   // the completion deleted: the field shows what was typed, and it stays so
        XCTAssertNil(view.completion)
        XCTAssertEqual(view.input.stringValue, "yout")
        type("you", into: view)
        XCTAssertNil(view.completion, "shorter is a deletion")
        XCTAssertEqual(sent.filter { if case .commandBar(.queryChanged) = $0 { true } else { false } },
                       ["you", "yout", "yout", "you"].map { Command.commandBar(.queryChanged($0)) })
        type("bin", into: view)
        XCTAssertEqual(view.completion, "bing.com")
        XCTAssertEqual(view.offer, bing, "the completed site's engine is offered beside the input")
        press(#selector(NSResponder.moveRight(_:)), in: view)
        XCTAssertNil(view.completion)
        XCTAssertEqual(view.typed, "bing.com")
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(chosen.last, .commandBar(.submit("bing.com")))
    }

    /// P20-a, Q01-b: titles are whole and the address after them is whole when the row has room; in a narrow row
    /// the title stays whole and the address gives way from its middle
    func testTitlesStayWholeAndOnlyTheAddressGivesWay() throws {
        let view = CommandBarView(dispatch: { _ in })
        view.show(commandBar([], []), in: box, scheme: .light, spaceless: true)
        let rows = view.descendants.compactMap { $0 as? ResultRowView }.filter { !$0.isHidden }
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            row.layoutSubtreeIfNeeded()
            let labels = row.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden && !$0.attributedStringValue.string.isEmpty }
            for label in labels.prefix(2) {
                let text = label.attributedStringValue
                XCTAssertGreaterThanOrEqual(label.frame.width, ceil(text.size().width), "\(text.string) is cut in a 746 pt row")
            }
        }
        let browser = try XCTUnwrap(rows.first { $0.accessibilityLabel() == "The Browser Company" })
        browser.frame.size.width = 240
        browser.layoutSubtreeIfNeeded()
        let fields = browser.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden && !$0.attributedStringValue.string.isEmpty }
        XCTAssertGreaterThanOrEqual(fields[0].frame.width, ceil(fields[0].attributedStringValue.size().width), "the title stays whole")
        XCTAssertLessThan(fields[1].frame.width, ceil(fields[1].attributedStringValue.size().width), "the address gives way")
    }

    /// P20-a, P21-a, Q03-a: a window without a space highlights in Arc's blue-violet (#8F95FF light, #424ADD dark)
    func testWindowsWithoutASpaceHighlightInBlueViolet() throws {
        func highlight(_ scheme: Scheme) throws -> [CGFloat] {
            let view = CommandBarView(dispatch: { _ in })
            view.show(commandBar([], []), in: box, scheme: scheme, spaceless: true)
            return try rowColor(view)
        }
        XCTAssertEqual(try highlight(.light), [0x8F, 0x95, 0xFF])
        XCTAssertEqual(try highlight(.dark), [0x42, 0x4A, 0xDD])
    }

    /// The highlight follows the space's theme in both bars (P49): grey under a white theme (Q01-a #ABABAB), beige
    /// under #F2EAE4 (P02-b #B8A89B), a teal under a pale teal (P49's #68B1B1 has this green and blue).
    func testTheHighlightIsAShadeOfTheTheme() throws {
        func highlight(_ primary: RGBA, overPill: Bool) throws -> [CGFloat] {
            let view = CommandBarView(dispatch: { _ in })
            var bar = commandBar([], [])
            if overPill { bar.placement = .overURLPill }
            view.show(bar, in: box, scheme: .light, primary: primary)
            return try rowColor(view)
        }
        func near(_ color: [CGFloat], _ expected: [CGFloat], tolerance: CGFloat = 2) -> Bool { zip(color, expected).allSatisfy { abs($0 - $1) <= tolerance } }
        for overPill in [false, true] {
            XCTAssertTrue(near(try highlight(RGBA(1, 1, 1), overPill: overPill), [0xAB, 0xAB, 0xAB]))
            XCTAssertTrue(near(try highlight(RGBA(0xF2 / 255, 0xEA / 255, 0xE4 / 255), overPill: overPill), [0xB8, 0xA8, 0x9B]))
            let teal = try highlight(RGBA(0.96, 1, 1), overPill: overPill)
            XCTAssertTrue(near(Array(teal.suffix(2)), [0xB1, 0xB1], tolerance: 3), "\(teal)")
            XCTAssertLessThan(teal[0], teal[1] - 40, "the hue is the theme's")
        }
    }

    private func rowColor(_ view: CommandBarView) throws -> [CGFloat] {
        let row = try XCTUnwrap(view.descendants.first { $0.accessibilityIdentifier() == "command-bar-result-0" })
        let color = try XCTUnwrap(row.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB))
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01)
        return [color.redComponent, color.greenComponent, color.blueComponent].map { ($0 * 255).rounded() }
    }

    /// P02-b: the bar over the URL pill is 350 wide (wider only for its input row), the centered one fills its box
    func testTheCardOverThePillIs350WideAndTheCenteredOneFillsTheBox() {
        let view = CommandBarView(dispatch: { _ in })
        view.resolve = fakeResolve
        let url = "http://127.0.0.1:8764/visual.html"
        var bar = commandBar([candidate("v", "Visual fixture", url, focused: true)], [], initialQuery: url)
        bar.placement = .overURLPill
        let attached = CGRect(x: 8, y: 44, width: 720, height: 338)
        view.show(bar, in: attached, scheme: .light, primary: RGBA(hex: "#F2EAE4"))
        XCTAssertEqual(view.style, .attached)
        let card = view.subviews[0].frame
        XCTAssertEqual(card.width, 350)
        XCTAssertEqual(card.height, 50 + 5 * 50 + 10, "input 50, five rows of 50, 10 under them (P02-b: 310)")
        XCTAssertEqual(rows(view.results).first, "current:\(url)")
        bar.placement = .centered
        bar.initialQuery = ""
        bar.openID = 2
        view.show(bar, in: box, scheme: .light)
        XCTAssertEqual(view.subviews[0].frame.width, box.width)
    }

    func testTypingMovesTheHighlightBackToTheFirstRow() {
        let view = makeBar()
        type("hub", into: view)
        press(#selector(NSResponder.moveDown(_:)), in: view)
        type("hub ", into: view)
        let first = view.results.first?.command
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(chosen, first.map { [$0] })
    }

    func testReturnNavigatesToTheTypedURLInsteadOfAPrefixMatch() {
        let url = "http://127.0.0.1:4000/cookie.html"
        let view = makeBar(commandBar([candidate("setter", "Cookie", url + "#set", space: "Work")], []))
        type(url, into: view)
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(chosen, [.commandBar(.submit(url))])
        press(#selector(NSResponder.moveDown(_:)), in: view)
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(chosen.last, .tab(.focus(ItemID("setter"))), "the fuzzy tab remains an explicit choice")
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
        let view = makeBar(commandBar([], []))   // no site, tab or command matches "zqv"
        type("zqv", into: view)
        XCTAssertEqual(rows(view.results), ["open:zqv"])
        view.show(commandBar([], [], suggestions: ["zqvx", "zqvy"], suggestedFor: "zqv"), in: box, scheme: .light)
        XCTAssertEqual(rows(view.results), ["open:zqv", "suggestion:google:zqvx", "suggestion:google:zqvy"])
        press(#selector(NSResponder.moveDown(_:)), in: view)
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(chosen, [.commandBar(.submitSearch(engine: google.id, query: "zqvx"))])
    }

    /// Tab with a site-search offer beside the input (or Space after an engine's whole name) enters site search: the
    /// engine's pill, an empty input, Return searches there; Backspace in the empty input or Esc gives the typed name
    /// back, and only a second Esc closes the bar
    func testSiteSearchModeWithTabSpaceBackspaceAndEscape() {
        let view = makeBar(commandBar([], [], siteSearch: [bing, kagi]))
        type("bi", into: view)
        XCTAssertEqual(view.offer, bing)
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

        // Tab with no site-search offer stays in the bar and does nothing; "bing" followed by a space and more words
        // is an ordinary search.
        type("weather", into: view)
        XCTAssertTrue(press(#selector(NSResponder.insertTab(_:)), in: view))
        XCTAssertNil(view.siteSearch)
        type("bing chilling ", into: view)
        XCTAssertNil(view.siteSearch)
    }

    func testEscapeDismissesAndReturnWithNothingToChooseDispatchesNothing() {
        // An empty bar always lists Arc's Contact the Team (Q01-a); Ask Max with nothing typed lists nothing.
        var ask = commandBar([], [])
        ask.aiMode = .question
        let view = makeBar(ask)
        XCTAssertTrue(view.results.isEmpty)
        XCTAssertTrue(press(#selector(NSResponder.insertNewline(_:)), in: view))
        XCTAssertTrue(press(#selector(NSResponder.cancelOperation(_:)), in: view))
        XCTAssertEqual(sent, [.commandBar(.dismiss)])
        // Other editing commands stay with the text field.
        XCTAssertFalse(press(#selector(NSResponder.deleteBackward(_:)), in: view))
    }

    func testSiteSearchTakesEscapeBeforeTheWindowsExitShortcut() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: box, styleMask: [.titled], backing: .buffered, defer: false)
        let view = makeBar(commandBar([], [], siteSearch: [bing]))
        window.contentView = view
        window.orderFront(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        XCTAssertTrue(view.focusInput())
        type("bing", into: view)
        press(#selector(NSResponder.insertTab(_:)), in: view)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                                     windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                     charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: Key.escape.code)!
        XCTAssertTrue(view.performKeyEquivalent(with: escape), "the window must not run its Exit binding for this press")
        XCTAssertNil(view.siteSearch)
        XCTAssertEqual(view.input.stringValue, "bing")
        XCTAssertTrue(chosen.isEmpty, "leaving site search must not dismiss the bar")
        XCTAssertFalse(view.performKeyEquivalent(with: escape), "the next Escape is available to the window")
    }

    func testTheSameOpeningKeepsWhatWasTypedAndANewOpeningStartsFromItsInitialQuery() {
        let view = makeBar()
        type("hub", into: view)
        press(#selector(NSResponder.moveDown(_:)), in: view)
        // A page event re-projects the same opening with one tab fewer: the query and its completion stay, the rows
        // follow.
        let reduced = commandBar(fixtureBar.tabs.filter { $0.tab != ItemID("t2") }, fixtureBar.history)
        view.show(reduced, in: box, scheme: .light)
        XCTAssertEqual(view.typed, "hub")
        XCTAssertEqual(view.input.stringValue, "hub")
        XCTAssertEqual(view.results, Suggest.rank(query: "hub", bar: reduced, appName: Product.name, resolve: fakeResolve))
        XCTAssertFalse(rows(view.results).contains("switch:t2"))
        // Cmd+L opens a new bar: its query is the tab's URL and the first row is highlighted again.
        view.show(commandBar(fixtureBar.tabs, fixtureBar.history, openID: 2, initialQuery: "https://github.com/arc"), in: box, scheme: .light)
        XCTAssertEqual(view.input.stringValue, "https://github.com/arc")
        let first = view.results.first?.command
        press(#selector(NSResponder.insertNewline(_:)), in: view)
        XCTAssertEqual(chosen, first.map { [$0] })
    }

    func testRowsCarryTheirIdentifiersAndOnlyTheCardTakesClicks() {
        let root = FlippedView(frame: CGRect(x: 0, y: 0, width: 1280, height: 776))
        let view = makeBar()
        root.addSubview(view)
        type("hub", into: view)
        let shown = view.descendants.filter { !$0.isHiddenOrHasHiddenAncestor }.map { $0.accessibilityIdentifier() }
        XCTAssertEqual(shown.filter { $0.hasPrefix("command-bar-result-") },
                       ["command-bar-result-0", "command-bar-result-1", "command-bar-result-2", "command-bar-result-3", "command-bar-result-4"])
        // Centered card (Q01-a): the 64 pt input row, 5 under its hairline, 5 rows of 50, 9 under them: 328.
        // Points are in the bar's superview, as AppKit passes them to `hitTest`.
        let rowCentre = CGPoint(x: box.midX, y: box.minY + 64 + 5 + 25)
        XCTAssertEqual(view.hitTest(rowCentre)?.enclosing(ResultRowView.self)?.accessibilityIdentifier(), "command-bar-result-0")
        XCTAssertNotNil(view.hitTest(CGPoint(x: box.midX, y: box.minY + 327)))
        XCTAssertNil(view.hitTest(CGPoint(x: box.midX, y: box.minY + 329)), "below the card the box lets clicks through")
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
        click(CGPoint(x: box.midX, y: box.minY + 64 + 5 + 25), in: window) // the first row: t1
        XCTAssertEqual(sent, [.tab(.focus(ItemID("t1")))])
        sent = []
        click(CGPoint(x: 100, y: 700), in: window)                          // outside the card
        XCTAssertEqual(sent, [.commandBar(.dismiss)])
    }
}
