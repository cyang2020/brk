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

    func testANarrowWindowNarrowsThePanelFirst() {
        XCTAssertEqual(AIPanelLayout.width(windowWidth: 1280, cardLeft: 228), Metrics.ai.width.value)
        let narrow = AIPanelLayout.width(windowWidth: 900, cardLeft: 228)
        XCTAssertEqual(narrow, max(Metrics.ai.minimumWidth.value, 900 - 228 - Metrics.ai.minimumCardWidth.value))
        XCTAssertEqual(AIPanelLayout.width(windowWidth: 700, cardLeft: 228), Metrics.ai.minimumWidth.value, "never under its minimum")
    }

    func testNoPanelOverTheLibrary() {
        let d = LayoutDriver()
        d.user(.library(.open(.media)))
        var snapshot = withPanel(d)
        snapshot.overlay = d.view.overlay
        guard case .library? = snapshot.overlay else { return XCTFail("the Library did not open") }
        XCTAssertNil(d.frames(snapshot).aiPanel)
    }

    func testTheToolbarEndsWithTheCard() {
        let d = LayoutDriver()
        var snapshot = withPanel(d)
        snapshot.sidebar.toolbarVisible = true
        let frames = d.frames(snapshot)
        XCTAssertEqual(frames.toolbar?.maxX, frames.aiPanel?.minX)
    }
}
