import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
import XCTest

/// The AI panel's two pages sit side by side in a strip that moves (docs/design/ai-threads.md); a click on a control of
/// the page that shows reaches that control, whichever page it is.
@MainActor
final class AIPanelHitTests: XCTestCase {
    static let size = CGSize(width: 1280, height: 776)
    let now = Instant(milliseconds: 1_790_000_000_000)
    private let ids = IDs()

    private func state() -> (AppState, WindowID) {
        let restored = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: Self.size),
                                          ctx: Context(now: now, newID: ids.next))
        var state = restored.state
        let window = project(state, ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))).windows.keys.sorted()[0]
        func run(_ command: Command) { state = reduce(state, .user(window, command), Context(now: now, newID: ids.next)).state }
        for feature in AIFeature.allCases { run(.settings(.max(.feature(feature, !AIFeature.basicLayer.contains(feature))))) }
        state = reduce(state, .system(.aiProvidersDetected([.claude])), Context(now: now, newID: ids.next)).state
        run(.assist(.ask("hello")))
        return (state, window)
    }

    private func find(_ id: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == id { return view }
        for sub in view.subviews { if let found = find(id, in: sub) { return found } }
        return nil
    }

    func testClicksReachTheControlsOfThePageThatShows() throws {
        var (state, window) = state()
        func snapshot() -> WindowSnapshot { project(state, ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))).windows[window]! }
        let container = NSView(frame: CGRect(origin: .zero, size: Self.size))
        let root = WindowRootView(dispatch: { _ in })
        root.frame = container.bounds
        container.addSubview(root)
        func show() {
            let v = snapshot()
            root.render(v, frames: WindowLayout.compute(v, contentSize: Self.size), surface: { _ in nil })
            container.layoutSubtreeIfNeeded()
        }
        func hit(_ id: String) -> NSView? {
            guard let view = find(id, in: root), !view.isHiddenOrHasHiddenAncestor else { return nil }
            let center = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: container)
            // A click is window activity, which renders before AppKit hit-tests the press: no layout pass in between.
            state = reduce(state, .system(.window(window, .activity)), Context(now: Instant(milliseconds: now.milliseconds + 1_000), newID: ids.next)).state
            let v = snapshot()
            root.render(v, frames: WindowLayout.compute(v, contentSize: Self.size), surface: { _ in nil })
            return container.hitTest(center)
        }
        show()
        XCTAssertNotNil(snapshot().aiPanel)
        for id in ["ai-list", "ai-plus", "ai-new", "ai-close", "ai-page-dot-list"] {
            let target = find(id, in: root)
            XCTAssertNotNil(target, id)
            XCTAssertTrue(hit(id) === target, "\(id) took \(String(describing: hit(id)))")
        }
        state = reduce(state, .user(window, .assist(.panelPage(.list))), Context(now: now, newID: ids.next)).state
        show()
        for id in ["ai-list-back", "ai-list-close", "ai-page-dot-conversation"] {
            let target = find(id, in: root)
            XCTAssertTrue(hit(id) === target, "\(id) took \(String(describing: hit(id)))")
        }
    }
}
