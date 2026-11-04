import AppKit
import BrkControl
import XCTest
@testable import BrkApp

/// `TextLayoutAudit` against views cut on purpose, in a real window: each rule reports the case it is for and stays
/// quiet on the same text given the room it needs.
@MainActor final class TextLayoutAuditTests: XCTestCase {
    private func audit(_ build: (NSView) -> Void) -> TextLayoutReport {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = root
        build(root)
        DrawnTextRecorder.install()
        var walk = TextLayoutAudit.Walk()
        walk.visit(window)
        return walk.report
    }

    private func label(_ text: String, font: NSFont = .systemFont(ofSize: 11, weight: .semibold)) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.isSelectable = false
        return label
    }

    private func problems(_ report: TextLayoutReport, _ text: String) -> [TextLayoutFinding.Problem] {
        report.findings.filter { $0.text == text }.map(\.problem)
    }

    /// The bug the check was written for: a frame of `intrinsicContentSize` leaves out the cell's inset.
    func testAFrameOfTheIntrinsicWidthIsCut() {
        let report = audit { root in
            let clear = label("Clear")
            clear.frame = CGRect(origin: CGPoint(x: 20, y: 20), size: clear.intrinsicContentSize)
            root.addSubview(clear)
        }
        XCTAssertEqual(problems(report, "Clear"), [.overflowsFrame])
        XCTAssertEqual(report.measured.count, 1)
        XCTAssertTrue(report.measured[0].hasPrefix("Clear | frame "))
    }

    func testAFrameOfTheCellSizeFits() {
        let report = audit { root in
            let clear = label("Clear")
            clear.frame = CGRect(origin: CGPoint(x: 20, y: 20), size: clear.fittingSize)
            root.addSubview(clear)
        }
        XCTAssertEqual(report.findings, [])
        XCTAssertEqual(report.truncated, [])
    }

    /// A clipping label needs its advance and the leading inset only: its ink is whole there.
    func testAClippingLabelNeedsNoTrailingInset() {
        let report = audit { root in
            let clear = label("Clear")
            clear.frame = CGRect(x: 20, y: 20, width: ceil(clear.attributedStringValue.size().width) + 2, height: clear.fittingSize.height)
            root.addSubview(clear)
        }
        XCTAssertEqual(report.findings, [])
    }

    /// A centred label's cell keeps 4 on each side; its ink is whole at the intrinsic width and cut below it.
    func testACentredLabelAtItsIntrinsicWidthIsWhole() {
        func report(width: (NSTextField) -> Double) -> TextLayoutReport {
            audit { root in
                let hint = label("Switch to Tab", font: .systemFont(ofSize: 13, weight: .medium))
                hint.alignment = .center
                hint.frame = CGRect(x: 20, y: 20, width: width(hint), height: hint.fittingSize.height)
                root.addSubview(hint)
            }
        }
        XCTAssertEqual(report { $0.intrinsicContentSize.width }.findings, [])
        XCTAssertEqual(report { $0.attributedStringValue.size().width }.findings.map(\.problem), [.overflowsFrame])
    }

    func testATruncatingLabelTooNarrowIsListedNotCut() {
        let report = audit { root in
            let long = label("A long title that cannot fit its row")
            long.lineBreakMode = .byTruncatingTail
            long.frame = CGRect(x: 20, y: 20, width: 80, height: 16)
            root.addSubview(long)
        }
        XCTAssertEqual(report.findings, [])
        XCTAssertEqual(report.truncated.map(\.problem), [.ellipsis])
    }

    /// A truncating label sized to its text shows an ellipsis on a text that would have fitted.
    func testATruncatingLabelAtTheIntrinsicWidthIsCut() {
        let report = audit { root in
            let title = label("Cancel")
            title.lineBreakMode = .byTruncatingTail
            title.frame = CGRect(origin: CGPoint(x: 20, y: 20), size: title.intrinsicContentSize)
            root.addSubview(title)
        }
        XCTAssertEqual(problems(report, "Cancel"), [.overflowsFrame])
    }

    func testAShortFrameIsCutUnderTheLine() {
        let report = audit { root in
            let title = label("Clear")
            title.frame = CGRect(x: 20, y: 20, width: 60, height: 8)
            root.addSubview(title)
        }
        XCTAssertEqual(problems(report, "Clear"), [.tooShort])
    }

    func testWrappedLinesTallerThanTheFrameAreCut() {
        let report = audit { root in
            let wrapped = NSTextField(wrappingLabelWithString: "Favorites keep your most used sites and apps close, on every space of this profile")
            wrapped.frame = CGRect(x: 20, y: 20, width: 90, height: 30)
            root.addSubview(wrapped)
        }
        XCTAssertEqual(report.findings.map(\.problem), [.wrapOverflow])
    }

    func testAnAncestorThatClipsCutsATruncatedLabel() {
        let report = audit { root in
            let box = NSView(frame: CGRect(x: 20, y: 20, width: 60, height: 30))
            box.clipsToBounds = true
            root.addSubview(box)
            let title = label("Secondary reference")
            title.lineBreakMode = .byTruncatingTail
            title.frame = CGRect(x: 10, y: 5, width: 100, height: 16)
            box.addSubview(title)
        }
        XCTAssertEqual(problems(report, "Secondary reference"), [.clippedByAncestor])
    }

    func testScrollingAwayIsNotCutButCutAcrossTheAxisIs() {
        let report = audit { root in
            let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
            scroll.hasVerticalScroller = true
            let document = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
            scroll.documentView = document
            root.addSubview(scroll)
            let below = label("Scrolled away")
            below.frame = CGRect(origin: CGPoint(x: 10, y: 400), size: below.fittingSize)
            document.addSubview(below)
            let across = label("Runs past the scroll view's right edge")
            across.frame = CGRect(origin: CGPoint(x: 150, y: 0), size: across.fittingSize)
            document.addSubview(across)
        }
        XCTAssertEqual(problems(report, "Scrolled away"), [])
        XCTAssertEqual(problems(report, "Runs past the scroll view's right edge"), [.clippedByAncestor])
    }

    func testAHiddenSubtreeIsNotMeasured() {
        let report = audit { root in
            let box = NSView(frame: CGRect(x: 20, y: 20, width: 60, height: 30))
            box.isHidden = true
            root.addSubview(box)
            let clear = label("Clear")
            clear.frame = CGRect(origin: .zero, size: clear.intrinsicContentSize)
            box.addSubview(clear)
        }
        XCTAssertEqual(report.measured, [])
    }

    func testTextAViewDrawsItselfIsMeasuredAgainstTheView() {
        let report = audit { root in
            let inside = DrawnLabel(text: "Fits", at: CGPoint(x: 2, y: 2))
            inside.frame = CGRect(x: 10, y: 10, width: 120, height: 30)
            root.addSubview(inside)
            let outside = DrawnLabel(text: "Runs past the view", at: CGPoint(x: 2, y: 2))
            outside.frame = CGRect(x: 10, y: 60, width: 40, height: 30)
            root.addSubview(outside)
        }
        XCTAssertEqual(problems(report, "Fits"), [])
        XCTAssertEqual(problems(report, "Runs past the view"), [.drawnOutsideView])
        XCTAssertEqual(report.measured.count, 2)
    }

    func testABoxWithoutTruncationIsCutAndWithItIsListed() {
        let report = audit { root in
            let plain = DrawnBox(text: "A wrapped string that needs more lines than its box holds", options: [.usesLineFragmentOrigin])
            plain.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
            root.addSubview(plain)
            let ended = DrawnBox(text: "Another string that needs more lines than its box holds", options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            ended.frame = CGRect(x: 10, y: 60, width: 200, height: 40)
            root.addSubview(ended)
        }
        XCTAssertEqual(report.findings.map(\.problem), [.wrapOverflow])
        XCTAssertEqual(report.truncated.map(\.problem), [.ellipsis])
    }

    /// A pop-up is judged by its selected item, not its widest (`cellSize` is the widest's).
    func testAPopUpIsMeasuredByItsSelectedItem() {
        func popUp(width: Double) -> TextLayoutReport {
            audit { root in
                let popUp = NSPopUpButton(frame: CGRect(x: 10, y: 10, width: width, height: 24), pullsDown: false)
                popUp.addItems(withTitles: ["Short", "An item a good deal wider than the selected one"])
                popUp.selectItem(at: 0)
                root.addSubview(popUp)
            }
        }
        XCTAssertEqual(popUp(width: 120).truncated, [])
        XCTAssertEqual(popUp(width: 120).findings, [])
        XCTAssertEqual(popUp(width: 20).findings.count + popUp(width: 20).truncated.count, 1)
    }

    /// A button that wraps (the sidebar's auto-archive notice) needs its lines' height, not one line's width.
    func testAWrappingButtonIsMeasuredAtItsWidth() {
        func button(height: Double) -> TextLayoutReport {
            audit { root in
                let button = NSButton(title: "Idle Today tabs archive after 12 hours. Tabs on screen stay open.", target: nil, action: nil)
                button.bezelStyle = .regularSquare
                button.cell?.wraps = true
                button.cell?.usesSingleLineMode = false
                button.frame = CGRect(x: 10, y: 10, width: 148, height: height)
                root.addSubview(button)
            }
        }
        XCTAssertEqual(button(height: 80).findings, [])
        XCTAssertEqual(button(height: 16).findings.map(\.problem), [.wrapOverflow])
    }

    func testAPlaceholderIsMeasuredOnceAndAFieldScrollsItsOwnText() {
        func field(_ width: Double, y: Double, placeholder: String = "", text: String = "") -> NSTextField {
            let field = NSTextField(frame: CGRect(x: 10, y: y, width: width, height: 24))
            field.cell?.isScrollable = true
            field.placeholderString = placeholder
            field.stringValue = text
            return field
        }
        let report = audit { root in
            root.addSubview(field(200, y: 10, placeholder: "Space name…"))
            root.addSubview(field(40, y: 40, placeholder: "A placeholder far wider than its field"))
            root.addSubview(field(40, y: 70, text: "Typed text far wider than its field scrolls"))
        }
        XCTAssertEqual(problems(report, "Space name…"), [])
        XCTAssertEqual(problems(report, "A placeholder far wider than its field"), [.overflowsFrame])
        XCTAssertEqual(problems(report, "Typed text far wider than its field scrolls"), [])
    }

    func testAPlaceholderThatWrapsPastItsFieldIsCut() {
        let report = audit { root in
            let search = NSTextField(frame: CGRect(x: 10, y: 10, width: 120, height: 16))
            search.placeholderString = "Search Reading list with a rather long name…"
            search.isBordered = false
            search.cell?.wraps = true
            root.addSubview(search)
        }
        XCTAssertEqual(problems(report, "Search Reading list with a rather long name…"), [.wrapOverflow])
    }

    /// `draw(at:)` is judged by its glyphs: a line box overhanging the view (the site panel's rows) cuts nothing.
    func testAnOverhangingLineBoxIsNotCut() {
        let report = audit { root in
            let row = DrawnLabel(text: "DEVELOPER MODE", at: CGPoint(x: 2, y: -2))
            row.frame = CGRect(x: 10, y: 10, width: 140, height: 18)
            root.addSubview(row)
        }
        XCTAssertEqual(report.findings, [])
    }

    func testASwiftUITextNarrowerThanItsStringIsListed() {
        let frame = CGSize(width: 40, height: 16)
        let needed = SwiftUIText.needed(for: "A settings label", frame: frame)
        XCTAssertGreaterThan(needed.width, frame.width + 1)
        let fits = SwiftUIText.needed(for: "OK", frame: frame)
        XCTAssertLessThanOrEqual(fits.width, frame.width + 1)
    }

    func testAMenuIsMeasuredWithItsSubmenus() {
        _ = NSApplication.shared
        let menu = NSMenu()
        menu.addItem(withTitle: "Close and Keep Pinned", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let parent = menu.addItem(withTitle: "Move to", action: nil, keyEquivalent: "")
        parent.submenu = NSMenu(title: "Move to")
        parent.submenu?.addItem(withTitle: "Research and Development Notes", action: nil, keyEquivalent: "")
        let report = TextLayoutAudit.menu(menu)
        XCTAssertEqual(report.measured.count, 3)
        XCTAssertEqual(report.findings, [])
        XCTAssertEqual(report.windows.count, 2)
    }
}

private final class DrawnLabel: NSView {
    let text: String, at: CGPoint
    init(text: String, at: CGPoint) {
        self.text = text
        self.at = at
        super.init(frame: .zero)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override func draw(_ dirtyRect: NSRect) {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)]).draw(at: at)
    }
}

private final class DrawnBox: NSView {
    let text: String, options: NSString.DrawingOptions
    init(text: String, options: NSString.DrawingOptions) {
        self.text = text
        self.options = options
        super.init(frame: .zero)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override func draw(_ dirtyRect: NSRect) {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)])
            .draw(with: CGRect(x: 0, y: 0, width: 80, height: 18), options: options)
    }
}
