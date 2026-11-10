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
