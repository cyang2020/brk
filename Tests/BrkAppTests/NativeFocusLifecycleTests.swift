import AppKit
import BrkBase
import BrkDomain
import BrkEngine
import XCTest
@testable import BrkApp

@MainActor
final class NativeFocusLifecycleTests: XCTestCase {
    func testPointerDownSelectsTheActualPresentedPaneBeforeItsPageReceivesInput() throws {
        let h = FocusHarness()
        defer { h.close() }
        for n in 2...3 {
            h.store.dispatch(.user(h.window, .split(.addPane)))
            h.store.dispatch(.user(h.window, .commandBar(.submit("https://example.test/\(n)"))))
        }
        let controller = try h.controller()
        let card = try XCTUnwrap(controller.lastFrames?.cards.first)
        let point = controller.root.convert(CGPoint(x: card.rect.midX, y: card.rect.midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 1,
                                                   windowNumber: controller.window.windowNumber, context: nil,
                                                   eventNumber: 1, clickCount: 1, pressure: 1))
        _ = controller.window.hostEvent(event)
        XCTAssertEqual(h.store.snapshot.windows[h.window]?.content.panes.first(where: \.focused)?.tab, h.page.item)
        XCTAssertTrue(controller.window.firstResponder === h.engine.surface(for: h.page))
    }
    func testWindowUpdateRepairsLostPageResponderWithoutAKeyWindow() throws {
        let h = FocusHarness()
        defer { h.close() }
        let controller = try h.controller()
        let page = try XCTUnwrap(h.engine.surface(for: h.page))
        NSApp.keyWindow?.resignKey()
        XCTAssertNil(NSApp.keyWindow)
        XCTAssertTrue(controller.window.makeFirstResponder(page))
        // AppKit clears the Chromium responder during a later sidebar layout or renderer replacement.
        XCTAssertTrue(controller.window.makeFirstResponder(nil))
        h.update(controller)
        XCTAssertTrue(controller.window.firstResponder === page)
        XCTAssertNil(NSApp.keyWindow, "repair must not activate a window")
    }

    func testUpdateKeepsANativeEditorEvenWhenModelStillNamesThePage() throws {
        let h = FocusHarness()
        defer { h.close() }
        let controller = try h.controller()
        let editor = NSTextView(frame: .zero)
        controller.root.addSubview(editor)
        XCTAssertTrue(controller.window.makeFirstResponder(editor))
        h.update(controller)
        XCTAssertTrue(controller.window.firstResponder === editor)
    }
}

@MainActor
private struct FocusHarness {
    let engine: StubEngine
    let store: AppStore
    let window: WindowID
    let page: PageID
    let directory: URL
    private let router: KeyRouter

    init() {
        _ = NSApplication.shared
        engine = StubEngine()
        let clock = OffsetClock()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-focus-unit-\(UUID().uuidString)")
        let restored = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "https://example.test/"),
                                                                contentSize: Metrics.window.defaultSize.value),
                                          ctx: Context(now: clock.now(), newID: { UUID().uuidString }))
        store = AppStore(restored: restored, clock: clock, engine: engine, stateFile: StateFile(directory: directory))
        router = KeyRouter(store: store)
        engine.delegate = router
        window = store.snapshot.windows.keys.first!
        page = store.snapshot.pages[0].id
        store.start()
    }

    func controller() throws -> WindowController { try XCTUnwrap(store.windowController(window)) }

    func update(_ controller: WindowController) {
        controller.window.delegate?.windowDidUpdate?(Notification(name: NSWindow.didUpdateNotification, object: controller.window))
    }

    func close() {
        for id in store.snapshot.windows.keys { store.windowController(id)?.window.orderOut(nil) }
        try? FileManager.default.removeItem(at: directory)
    }
}
