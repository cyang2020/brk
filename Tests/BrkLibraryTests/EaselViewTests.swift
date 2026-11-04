import AppKit
import BrkBase
@testable import BrkDomain
import BrkLayout
import BrkUIKit
import XCTest
@testable import BrkLibrary

/// The board (Q09 a) and the Library's Easels page (P32 c) as views: layout against Arc's measurements, what the
/// tools dispatch for real mouse events, the Delete key, the cards and their search, Share's PNG.
@MainActor
final class EaselViewTests: XCTestCase {
    private var sent: [Command] = []
    private let id = EaselID("easel-1")
    private let card = CGRect(x: 228, y: 10, width: 1042, height: 756)

    private func snapshot(_ elements: [EaselElement] = [], editing: Bool = false) -> EaselSnapshot {
        EaselSnapshot(id: id, page: PageID(window: WindowID("w"), item: ItemID("row")), title: "Untitled Easel", titleSize: 25,
                      elements: elements, editingTitle: editing, message: nil)
    }

    /// A board in a borderless window, so events convert and the board can take the keyboard.
    private func board(_ easel: EaselSnapshot) -> (EaselBoardView, NSWindow) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 776), styleMask: [.borderless], backing: .buffered, defer: false)
        let root = FlippedRoot(frame: CGRect(x: 0, y: 0, width: 1280, height: 776))
        window.contentView = root
        let view = EaselBoardView(dispatch: { [unowned self] in self.sent.append($0) })
        root.addSubview(view)
        view.render(easel, in: card, cornerRadius: 10)
        view.layoutSubtreeIfNeeded()
        return (view, window)
    }

    private func event(_ type: NSEvent.EventType, at boardPoint: CGPoint, in view: EaselBoardView, window: NSWindow) -> NSEvent {
        let local = CGPoint(x: view.bounds.midX + boardPoint.x, y: boardPoint.y)
        let inWindow = view.convert(local, to: nil)
        return NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                  context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func id(_ v: NSView, _ name: String) -> NSView? { v.descendants.first { $0.accessibilityIdentifier() == ViewID.easelControl(name).identifier } }

    func testTheBoardLaysOutLikeQ09a() throws {
        let (view, _) = board(snapshot(editing: true))
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.frame, card)
        // The title box: 628 x 78.5, 34.5 below the card's top, centred.
        XCTAssertEqual(view.titleBox, CGRect(x: (1042 - 628) / 2, y: 34.5, width: 628, height: 78.5))
        XCTAssertEqual(view.titleField.stringValue, "Untitled Easel")
        // The + Aa − card: 36 wide, 12.5 left of the box, shown with the title selected.
        let font = try XCTUnwrap(id(view, "font-tool"))
        XCTAssertFalse(font.isHidden)
        XCTAssertEqual(font.frame.width, 36)
        XCTAssertEqual(view.titleBox.minX - font.frame.maxX, 12.5, accuracy: 0.01)
        // The toolbar: 12 from the card's left and bottom, 44 tall, seven tools 38 apart, then duplicate.
        let toolbar = try XCTUnwrap(id(view, "toolbar"))
        XCTAssertEqual(toolbar.frame.minX, 12)
        XCTAssertEqual(toolbar.frame.maxY, 756 - 12)
        XCTAssertEqual(toolbar.frame.height, 44)
        XCTAssertEqual(toolbar.frame.width, 313, accuracy: 0.01)
        let tools = ["select", "image", "text", "ellipse", "rectangle", "arrow", "pen"].map { try? XCTUnwrap(id(view, "tool-" + $0)) }
        XCTAssertEqual(tools.compactMap { $0?.frame.minX }, (0..<7).map { 4 + Double($0) * 38 })
        XCTAssertEqual(id(view, "duplicate")?.frame.minX, 273)
        let person = try XCTUnwrap(id(view, "person"))
        XCTAssertEqual(person.frame, CGRect(x: 1042 - 12 - 44, y: 756 - 12 - 44, width: 44, height: 44))
        XCTAssertEqual(view.tool, .select)
        // Without a selection the + Aa − card goes.
        view.render(snapshot(editing: false), in: card, cornerRadius: 10)
        XCTAssertTrue(view.titleSelected, "the title stays selected until something else is clicked")
        view.render(nil, in: nil, cornerRadius: 0)
        XCTAssertTrue(view.isHidden)
    }

    func testDraggingWithTheRectangleToolAddsARectangleAndSelectsIt() throws {
        let (view, window) = board(snapshot())
        (id(view, "tool-rectangle") as? NSButton)?.performClick(nil)
        XCTAssertEqual(view.tool, .rectangle)
        view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: -100, y: 200), in: view, window: window))
        view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: -40, y: 240), in: view, window: window))
        view.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 20, y: 280), in: view, window: window))
        guard case .easel(.add(let easel, let element))? = sent.last else { return XCTFail("\(sent)") }
        XCTAssertEqual(easel, id)
        XCTAssertEqual(element.shape, .rectangle)
        XCTAssertEqual(element.frame, CGRect(x: -100, y: 200, width: 120, height: 80))
        XCTAssertEqual(view.tool, .select, "a drawn shape returns to the select tool")
        // Once the snapshot has it, it is selected; Delete removes it.
        view.render(snapshot([element]), in: card, cornerRadius: 10)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.selection, [element.id])
        XCTAssertFalse(id(view, "selection")?.isHidden ?? true)
        let delete = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                      characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51)!
        view.keyDown(with: delete)
        XCTAssertEqual(sent.last, .easel(.remove(id, [element.id])))
    }

    func testDraggingASelectedShapeMovesItAndTheFreehandToolKeepsTheStroke() throws {
        let shape = EaselElement(id: "r", shape: .rectangle, frame: CGRect(x: -100, y: 200, width: 120, height: 80))
        let (view, window) = board(snapshot([shape]))
        view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: -40, y: 240), in: view, window: window))
        view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: -20, y: 250), in: view, window: window))
        view.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 0, y: 270), in: view, window: window))
        XCTAssertEqual(sent.last, .easel(.update(id, [shape.moved(by: CGSize(width: 40, height: 30))])))
        (id(view, "tool-pen") as? NSButton)?.performClick(nil)
        view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 0, y: 400), in: view, window: window))
        for i in 1...10 { view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: Double(i) * 6, y: 400 + Double(i % 2) * 8), in: view, window: window)) }
        view.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 60, y: 400), in: view, window: window))
        guard case .easel(.add(_, let ink))? = sent.last else { return XCTFail("\(sent)") }
        XCTAssertEqual(ink.shape, .ink)
        XCTAssertEqual(ink.points.count, 11)
        XCTAssertEqual(view.tool, .pen, "freehand stays on for the next stroke")
    }

    /// A101: the selection's corner handles resize it (the opposite corner stays); Shift keeps the proportions.
    func testDraggingACornerHandleResizesTheSelection() throws {
        let shape = EaselElement(id: "r", shape: .rectangle, frame: CGRect(x: -100, y: 200, width: 120, height: 80))
        let arrow = EaselElement(id: "a", shape: .arrow, frame: CGRect(x: 0, y: 0, width: 10, height: 10), points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        let (view, window) = board(snapshot([shape, arrow]))
        view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: -40, y: 240), in: view, window: window))
        view.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: -40, y: 240), in: view, window: window))
        XCTAssertEqual(view.selection, ["r"])
        sent = []
        // The bottom-right handle sits on the selection box's corner, the element's corner plus the frame's outset.
        let outset = EaselDraw.board.elementOutset.value
        view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 20 + outset, y: 280 + outset), in: view, window: window))
        view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 60, y: 300), in: view, window: window))
        view.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 80, y: 320), in: view, window: window))
        guard case .easel(.update(let easel, let changed))? = sent.last else { return XCTFail("\(sent)") }
        XCTAssertEqual(easel, id)
        XCTAssertEqual(changed.map(\.frame), [CGRect(x: -100, y: 200, width: 180, height: 120)], "the top-left corner stays, the box follows the pointer")
        // Arrows and strokes scale their points with the box.
        let scaled = arrow.resized(from: CGRect(x: 0, y: 0, width: 10, height: 10), to: CGRect(x: 0, y: 0, width: 20, height: 40))
        XCTAssertEqual(scaled.points, [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 40)])
        XCTAssertEqual(scaled.frame, CGRect(x: 0, y: 0, width: 20, height: 40))
    }

    func testTheImageToolAndThePersonButtonAskTheApp() throws {
        let (view, _) = board(snapshot())
        (id(view, "tool-image") as? NSButton)?.performClick(nil)
        guard case .easel(.chooseImage(let easel, _))? = sent.last else { return XCTFail("\(sent)") }
        XCTAssertEqual(easel, id)
        XCTAssertEqual(view.tool, .select)
        (id(view, "person") as? NSButton)?.performClick(nil)
        XCTAssertEqual(sent.last, .easel(.share(id)))
        (id(view, "font-larger") as? NSButton)?.performClick(nil)
        XCTAssertEqual(sent.last, .easel(.stepTitleSize(id, by: 1)))
    }

    func testTheEaselsPageShowsACardPerEaselAndSearchesTitles() throws {
        let page = EaselsPageView(dispatch: { [unowned self] in self.sent.append($0) })
        let cards = [EaselCard(id: EaselID("a"), title: "Trip plan", titleSize: 25, elements: [], modifiedAt: Instant(milliseconds: 2)),
                     EaselCard(id: EaselID("b"), title: "Untitled Easel", titleSize: 25,
                               elements: [EaselElement(id: "r", shape: .rectangle, frame: CGRect(x: 0, y: 200, width: 50, height: 50))], modifiedAt: Instant(milliseconds: 1))]
        var library = LibrarySnapshot(openID: 1, page: .easelsAndNotes, archive: nil, downloads: [])
        library.easels = cards
        page.show(library, in: CGRect(x: 112, y: 0, width: 304, height: 776), scheme: .light)
        page.layoutSubtreeIfNeeded()
        XCTAssertEqual(page.cards.map(\.card.id), [EaselID("a"), EaselID("b")])
        // P32 c: 132 pt cards from x 12 of the column, 16 apart; the first row 60 from the top.
        XCTAssertEqual(page.cards[0].frame.size, CGSize(width: 132, height: 132))
        XCTAssertEqual(page.cards[1].frame.minX - page.cards[0].frame.maxX, 16)
        XCTAssertEqual(page.cards[0].convert(CGPoint.zero, to: page), CGPoint(x: 12, y: 60))
        XCTAssertEqual(page.texts, [])
        XCTAssertEqual(page.cards[0].actions().items.map(\.title), ["Open", "Share…", "", "Delete…"])
        page.cards[1].mouseUp(with: NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                                       eventNumber: 0, clickCount: 1, pressure: 1)!)
        page.searchField.field.stringValue = "trip"
        page.searchField.onChange()
        page.layoutSubtreeIfNeeded()
        XCTAssertEqual(page.cards.map(\.card.id), [EaselID("a")])
        library.easels = []
        page.searchField.field.stringValue = ""
        page.show(library, in: CGRect(x: 112, y: 0, width: 304, height: 776), scheme: .light)
        XCTAssertEqual(page.texts, [LibraryCopy.nothingHereYet, LibraryCopy.easelsEmpty])
    }

    func testShareDrawsTheBoardAsAPNG() throws {
        let card = EaselCard(id: id, title: "Plan", titleSize: 25, elements: [
            EaselElement(id: "r", shape: .rectangle, frame: CGRect(x: -100, y: 200, width: 200, height: 100)),
            EaselElement(id: "t", shape: .text, frame: CGRect(x: -40, y: 330, width: 80, height: 24), text: "Hello"),
        ], modifiedAt: Instant(milliseconds: 0))
        let png = try XCTUnwrap(EaselDrawing.png(card))
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(png.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertGreaterThan(image.pixelsWide, 400)
        XCTAssertGreaterThan(image.pixelsHigh, 500)
    }
}

private final class FlippedRoot: NSView {
    override var isFlipped: Bool { true }
}
