import AppKit
import BrkBase
@testable import BrkContent
@testable import BrkDomain
import BrkLayout
import XCTest

/// The menu card beside a finished capture (P33-c) filters its rows by what is typed into its Send To… field. Each
/// capture's card opens with that field empty: the window keeps one card, and the text typed into the last one used to
/// stay, hiding rows (every row, for text no row has).
@MainActor
final class CaptureMenuCardTests: XCTestCase {
    static let size = CGSize(width: 1280, height: 776)
    let now = Instant(milliseconds: 1_790_000_000_000)

    func testTheNextCaptureMenuOpensUnfiltered() throws {
        let ids = IDs()
        let calendar = Calendar(identifier: .gregorian)
        let state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: Self.size),
                                       ctx: Context(now: now, newID: ids.next)).state
        let window = project(state, ProjectionContext(now: now, calendar: calendar)).windows.keys.sorted()[0]
        let v = project(state, ProjectionContext(now: now, calendar: calendar)).windows[window]!
        let frames = WindowLayout.compute(v, contentSize: Self.size)
        let page = try XCTUnwrap(frames.cards.lazy.compactMap { card -> PageID? in if case .page(let page) = card.content { page } else { nil } }.first)
        func capture(_ id: String, image: Bool) -> CaptureSnapshot {
            let request = CaptureRequest(id: id, document: DocumentToken(browser: BrowserToken(page: page, generation: 1), sequence: 1),
                                         context: .profile(.default), mode: .area, title: "A", url: URL(string: "http://127.0.0.1:9/a")!,
                                         createdAt: now, region: CaptureRegion(x: 0.1, y: 0.1, width: 0.3, height: 0.3))
            return CaptureSnapshot(request: request, image: image ? CaptureImage(png: Data([7]), width: 300, height: 200, scale: 2) : nil)
        }
        let overlay = CaptureOverlayView(dispatch: { _ in })
        overlay.frame = CGRect(origin: .zero, size: Self.size)
        func view(_ name: String) -> NSView? { ViewTreeSearch.find(ViewID.tabTool(name).identifier, in: overlay) }

        overlay.render(capture("first", image: false), frames: frames, peek: nil)
        overlay.render(capture("first", image: true), frames: frames, peek: nil)
        let field = try XCTUnwrap(view("capture-menu-search") as? NSTextField)
        field.stringValue = "xyz"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertEqual(view("capture-menu-library")?.isHidden, true, "no row has xyz")

        overlay.render(nil, frames: frames, peek: nil)   // a click outside the card leaves capture mode
        overlay.render(capture("second", image: false), frames: frames, peek: nil)
        overlay.render(capture("second", image: true), frames: frames, peek: nil)
        XCTAssertEqual(field.stringValue, "")
        XCTAssertEqual(view("capture-menu-library")?.isHidden, false, "the next capture's card shows every row")
    }
}
