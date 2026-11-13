import AppKit
import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

/// Window routing, menu keys, Little Arc and prompts for windows that are not on screen (audit 2026-11-12).
@MainActor
final class WindowRoutingRegressionTests: XCTestCase {
    /// With About or Settings in front no browser window is key: their buttons and the menu go to the browser window the
    /// user used last, not to the window created last or to whichever the window table lists first.
    func test_commandsWithoutAKeyBrowserWindowGoToTheWindowUsedLast() throws {
        let h = Harness()
        defer { h.store.dispatch(.user(h.window, .settings(.closeWindow))); h.cleanUp() }
        h.store.start()
        h.store.dispatch(.user(h.window, .window(.newIncognito)))
        let incognito = try XCTUnwrap(h.store.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        defer { h.store.windowController(incognito)?.window.orderOut(nil) }
        // The user goes back to the first window, then opens About.
        h.store.dispatch(.system(.window(h.window, .becameKey)))
        h.store.dispatch(.user(h.window, .app(.showAbout)))
        defer { NSApp.windows.filter { $0 is AboutPanel }.forEach { $0.orderOut(nil) } }
        XCTAssertFalse(h.store.windowController(incognito)?.window.isKeyWindow ?? true)
        XCTAssertEqual(h.store.windowController(nil)?.id, h.window, "About's links and the menu go to the window used last")
        h.store.dispatch(.user(h.window, .settings(.openPane(.profiles))))
        XCTAssertEqual(h.store.windowController(nil)?.id, h.window, "Settings' buttons and the menu go to the window used last")
    }

    /// A download or page output that asks where to save, for a window that is minimized (or behind a hidden app), waits
    /// for the window instead of being cancelled; a closed window still answers that its owner is gone.
    func test_aMinimizedOwnerKeepsItsSavePrompt() throws {
        final class MinimizedWindow: NSWindow {
            override var isMiniaturized: Bool { true }
            override var isVisible: Bool { false }
        }
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let minimized = MinimizedWindow(contentRect: frame, styleMask: [.titled, .miniaturizable], backing: .buffered, defer: true)
        let closed = NSWindow(contentRect: frame, styleMask: [.titled, .miniaturizable], backing: .buffered, defer: true)
        let owner = WindowID("owner"), other = WindowID("other")
        let sheets = DownloadSheets()
        var answers: [WindowID: [String]] = [:]
        for (id, window) in [(owner, minimized as NSWindow), (other, closed)] {
            let prompt = DownloadDestinationPrompt(ticket: DestinationTicket(download: DownloadID(id.rawValue), generation: 0), window: id,
                                                   directory: FileManager.default.temporaryDirectory, suggestedName: "export.csv")
            sheets.present(prompt, in: window) { answers[id, default: []].append("\($0)") }
        }
        XCTAssertNil(answers[owner], "a minimized owner keeps the download's prompt waiting")
        XCTAssertEqual(answers[other], ["ownerGone"], "a closed owner cancels it")
        sheets.ownerGone(owner)
        XCTAssertEqual(answers[owner], ["ownerGone"])

        let outputs = OutputSheets()
        let document = DocumentToken(browser: BrowserToken(page: PageID(window: owner, item: ItemID("tab")), generation: 1), sequence: 1)
        let request = OutputRequest(id: OutputID("pdf"), document: document, intent: .pdf, suggestedName: "Page")
        var outputAnswers: [String] = []
        outputs.destination(OutputDestinationPrompt(request: request), in: minimized) { outputAnswers.append("\($0)") }
        XCTAssertEqual(outputAnswers, [], "Export PDF for a minimized window waits for it")
        outputs.dismiss(request.id)
    }

    /// An item chosen in the menu with the keyboard (Return on a Help search result, or after ⌃F2) runs its command. The
    /// current event is then the Return key-down, which is not the item's own key equivalent.
    func test_aMenuItemChosenWithReturnRunsItsCommand() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        let returnKey = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 200, windowNumber: 0, context: nil,
                                                       characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: Key.returnKey.code))
        h.router.menuAction(.toggleStayOnTop, in: h.window, event: returnKey)
        XCTAssertEqual(h.store.snapshot.windows[h.window]?.stayOnTop, true)
    }

    /// "Open in <space> ⌘O" names the space ⌘O moves the tab to (the space of the standard window used last), and a
    /// click on it goes there too, after the main window has moved to another space.
    func test_littleArcOpenInNamesTheSpaceCmdOMovesTo() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        let home = try XCTUnwrap(h.store.snapshot.windows[h.window]?.space.id)
        h.store.dispatch(.user(h.window, .space(.create(title: "Work", icon: .none, theme: SpaceTheme(colors: [ThemePresets.drab[8]], texture: .grain, intensity: 0.25, appearance: .auto)))))
        let work = try XCTUnwrap(h.store.snapshot.windows[h.window]?.space.id)
        XCTAssertNotEqual(work, home)
        h.store.dispatch(.user(h.window, .space(.focus(home))))
        h.store.dispatch(.user(h.window, .window(.newLittle(URL(string: "https://example.com/little")!))))
        let little = try XCTUnwrap(h.store.snapshot.windows.values.first { $0.kind == .little })
        defer { h.store.windowController(little.id)?.window.orderOut(nil) }
        let controller = try XCTUnwrap(h.store.windowController(little.id) as? LittleWindowController)
        h.store.dispatch(.user(h.window, .space(.focus(work))))
        XCTAssertEqual(controller.header.openIn.accessibilityLabel(), OpenInMenu.buttonTitle(space: "Work"))
        controller.header.openIn.onOpen?()
        XCTAssertNil(h.store.snapshot.windows[little.id])
        XCTAssertEqual(h.store.snapshot.windows[h.window]?.space.id, work, "the button moves the tab where its label says")
        XCTAssertEqual(h.store.snapshot.windows[h.window]?.space.today.rows.count, 1)
    }

    /// Escape in the Little Arc's "Search Spaces…" picker closes the picker; the key table's Exit does not take it first.
    func test_escapeClosesTheLittleArcSpacePicker() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        h.store.dispatch(.user(h.window, .window(.newLittle(URL(string: "https://example.com/little")!))))
        let little = try XCTUnwrap(h.store.snapshot.windows.values.first { $0.kind == .little })
        defer { h.store.windowController(little.id)?.window.orderOut(nil) }
        let controller = try XCTUnwrap(h.store.windowController(little.id) as? LittleWindowController)
        controller.header.openIn.onChoose?()
        XCTAssertFalse(controller.picker.isHidden)
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 300, windowNumber: controller.window.windowNumber,
                                                    context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: Key.escape.code))
        controller.window.sendEvent(escape)
        XCTAssertTrue(controller.picker.isHidden, "Escape closes the picker")
    }

    /// AppKit takes the icon popover down by itself when its row goes (⌘W closed the tab): the picker is then not open,
    /// so the next Escape is not swallowed by a picker no one can see. About 2.5 s: AppKit shows and takes down a real
    /// popover window, and only the real one shows the bug (AppKit closes it, Brk's own close never runs).
    func test_theIconPickerIsNotOpenOnceItsPopoverHasGone() throws {
        let h = Harness()
        defer { TabIconPicker.close(); h.cleanUp() }
        let appearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        defer { NSApp.appearance = appearance }
        h.store.start()
        let controller = try XCTUnwrap(h.store.windowController(h.window))
        TabIconPicker.present(for: h.page.item, in: controller.window, scheme: .dark) { _ in }
        let grid = try XCTUnwrap(NSApp.windows.first { ViewTree.find("tab-icon-picker", in: $0) != nil })
        XCTAssertTrue(grid.isVisible)
        XCTAssertEqual(grid.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), .darkAqua, "the picker follows the sidebar's theme")
        XCTAssertTrue(TabIconPicker.isOpen)
        XCTAssertTrue(h.store.dispatchKey(h.window, h.key("cmd+w", stage: .menu, id: 1)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertFalse(grid.isVisible)
        XCTAssertFalse(TabIconPicker.isOpen)
    }
}
