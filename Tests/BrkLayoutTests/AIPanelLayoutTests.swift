import BrkBase
@testable import BrkDomain
import CoreGraphics
import XCTest
@testable import BrkLayout

/// The AI panel is a column at the window's right edge (docs/design/ai-panel.md): the card ends at its edge as it starts
/// at the sidebar's, the column runs the window's full height, and it gives way before the card gets too narrow. No
/// panel over the Library.
final class AIPanelLayoutTests: XCTestCase {
    private func withPanel(_ d: LayoutDriver) -> WindowSnapshot {
        var snapshot = d.view
        snapshot.ai = AIAnswerSnapshot(request: nil, title: "Ask about your tabs", text: "", busy: false, sources: [], conversation: AIConversationSnapshot(id: AIRequestID("c"), tabs: true))
        return snapshot
    }

    func testTheCardEndsAtThePanelsEdge() {
        let d = LayoutDriver()
        let closed = d.frames()
        XCTAssertNil(closed.aiPanel)
        let frames = d.frames(withPanel(d))
        let width = Metrics.ai.width.value
        XCTAssertEqual(frames.aiPanel, CGRect(x: 1280 - width, y: 0, width: width, height: 776))
        XCTAssertEqual(frames.contentArea, CGRect(x: 228, y: 10, width: 1280 - width - 228, height: 756), "the right inset gives way to the column")
        XCTAssertEqual(frames.cards.first?.rect, frames.contentArea)
        XCTAssertEqual(frames.contentArea.maxX, frames.aiPanel?.minX, "no gap: the column's inset is the gap, as the sidebar's is")
        XCTAssertEqual(frames.sidebar?.frame, closed.sidebar?.frame, "the sidebar does not move")
        XCTAssertEqual(AIPanelLayout.readingWidth(panelWidth: width), width - 2 * Metrics.tablist.selectionInset.value)
    }

    func testNoPanelOverTheLibrary() {
        let d = LayoutDriver()
        d.user(.library(.open(.media)))
        var snapshot = withPanel(d)
        snapshot.overlay = d.view.overlay
        guard case .library? = snapshot.overlay else { return XCTFail("the Library did not open") }
        XCTAssertNil(d.frames(snapshot).aiPanel)
    }

    /// Step 8 (docs/design/ai-right-panel.md): the gap between the card and the panel drags the panel wider, up to half
    /// the window, the card keeping 400 pt and the panel 280; the width a window keeps lays it out; the handle straddles
    /// the card's edge while a list is open.
    func testADraggedWidthStopsAtHalfTheWindowAndTheCardsMinimum() {
        XCTAssertEqual(AIPanelLayout.width(windowWidth: 1600, cardLeft: 250, preferred: 600), 600)
        XCTAssertEqual(AIPanelLayout.width(windowWidth: 1000, cardLeft: 250, preferred: 600), 350, "the card keeps 400")
        XCTAssertEqual(AIPanelLayout.width(windowWidth: 1100, cardLeft: 10, preferred: 900), 550, "half the window")
        XCTAssertEqual(AIPanelLayout.width(windowWidth: 1600, cardLeft: 250, preferred: nil), Metrics.ai.width.value, "the default as before")
        XCTAssertEqual(AIPanelLayout.width(windowWidth: 700, cardLeft: 228, preferred: 600), Metrics.ai.minimumWidth.value, "never under its minimum")
        let d = LayoutDriver()
        var snapshot = withPanel(d)
        snapshot.aiPanelWidth = 520
        XCTAssertEqual(d.frames(snapshot).aiPanel?.width, 520)
        XCTAssertNil(d.frames(snapshot).aiPanelHandle, "no list (no panel snapshot): nothing to drag")
        snapshot.aiPanel = AIPanelSnapshot(page: .list, hasConversation: true, space: d.view.space.id, spaceTitle: "", language: .en, search: "",
                                           strips: [], groups: [], waiting: 0, spaces: [])
        let frames = d.frames(snapshot)
        let panel = frames.aiPanel!
        XCTAssertEqual(frames.aiPanelHandle?.midX, panel.minX, "the handle straddles the card's edge")
        XCTAssertEqual(AIPanelLayout.width(snapshot, contentSize: CGSize(width: 1280, height: 776)), 520, "where the panel would open")
    }
}
