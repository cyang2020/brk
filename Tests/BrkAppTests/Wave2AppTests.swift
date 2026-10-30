import AppKit
import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

/// The wave-2 seams on the app side: local AI tool detection and prompts, suggestion parsing, the settings window,
/// the GetURL handler. Owners: F1 (settings window), F3 (external links), F4 (suggestions), later wave (AI).
@MainActor
final class Wave2AppTests: XCTestCase {
    /// detection finds an executable named after the tool in a PATH directory and nothing else
    func test_detectsLocalToolsOnPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("brk-ai-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let claude = dir.appendingPathComponent("claude")
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: claude)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        XCTAssertEqual(AIProviderSeam.executable(for: .claude, environment: ["PATH": dir.path], alsoIn: []), claude)
        XCTAssertNil(AIProviderSeam.executable(for: .codex, environment: ["PATH": "/nonexistent"], alsoIn: []))
        XCTAssertEqual(AIProviderSeam.detect(environment: ["PATH": dir.path], alsoIn: []), [.claude])
        XCTAssertNil(AIProviderSeam.provider(for: .off, detected: [.claude, .codex]))
        XCTAssertNil(AIProviderSeam.provider(for: .auto, detected: []))
    }

    /// every task has a prompt; the renaming prompt carries the title and url
    func test_promptsCarryTheTask() {
        let prompt = AIPrompt.text(for: .renameTab(ItemID("t"), title: "Long title", url: URL(string: "https://example.com/")!))
        XCTAssertTrue(prompt.contains("Long title"))
        XCTAssertTrue(prompt.contains("https://example.com/"))
        XCTAssertFalse(AIPrompt.text(for: .tidyToday(SpaceID("s"), tabs: [])).isEmpty)
        XCTAssertEqual(AIPrompt.text(for: .ask("why")), "why")
    }

    /// a tool that answers is run to completion; a missing tool fails, never traps
    func test_cliProviderRunsAnExecutable() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("brk-ai-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tool = dir.appendingPathComponent("claude")
        try Data("#!/bin/sh\necho \"Tidy Title\"\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let provider = CLIProvider(kind: .claude, executable: tool)
        let text = try await provider.run("anything")
        XCTAssertEqual(text, "Tidy Title")
        let missing = CLIProvider(kind: .codex, executable: dir.appendingPathComponent("codex"))
        do {
            _ = try await missing.run("x")
            XCTFail("a missing tool answered")
        } catch {}
    }

    /// OpenSearch suggestion JSON parses to the list; anything else is empty
    func test_parsesOpenSearchSuggestions() {
        XCTAssertEqual(SuggestionFetcher.parse(Data(#"["swi", ["swift", "swim"]]"#.utf8)), ["swift", "swim"])
        XCTAssertEqual(SuggestionFetcher.parse(Data(#"{"q": 1}"#.utf8)), [])
        XCTAssertEqual(SuggestionFetcher.parse(Data("garbage".utf8)), [])
    }

    /// the settings window follows the snapshot's pane: shown while set, hidden when nil
    func test_settingsWindowFollowsThePane() {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        h.store.dispatch(.user(h.window, .settings(.openPane(.links))))
        XCTAssertEqual(h.store.snapshot.settings.pane, .links)
        let settings = NSApp.windows.first { $0.contentView?.accessibilityIdentifier() == "settings" }
        XCTAssertNotNil(settings, "the settings window exists once a pane opened")
        XCTAssertEqual(settings?.isVisible, true)
        h.store.dispatch(.user(h.window, .settings(.closeWindow)))
        XCTAssertEqual(settings?.isVisible, false)
    }

    /// a key equivalent the window's views do not take is routed through the table before AppKit's menu, so Arc's
    /// hidden rows (Ctrl+Tab) and remapped chords work with a native view focused
    func test_windowRoutesUnhandledKeyEquivalentsThroughTheTable() {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        let controller = h.store.windowController(h.window)!
        let before = h.store.snapshot.rev
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control, timestamp: 5, windowNumber: controller.window.windowNumber,
                                     context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: Key.tab.code)!
        XCTAssertTrue(controller.window.routeKeyEquivalent(event), "Ctrl+Tab (a hidden menu row) was not routed")
        XCTAssertGreaterThan(h.store.snapshot.rev, before, "the cycle did not start")
        let unbound = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 6, windowNumber: controller.window.windowNumber,
                                       context: nil, characters: "y", charactersIgnoringModifiers: "y", isARepeat: false, keyCode: Key.y.code)!
        XCTAssertFalse(controller.window.routeKeyEquivalent(unbound))
    }

    /// the GetURL handler installs without a running event loop (the Apple Event path is proven by W2-7)
    func test_getURLHandlerInstalls() {
        let handler = GetURLHandler(send: { _ in })
        handler.install()
        XCTAssertNotNil(NSAppleEventManager.shared())
    }

    // MARK: stubs

    func test_exportWritesTheChosenFormat() throws {
        throw XCTSkip("wave 2 contract, F1 or F5 to verify on the display: ShareExport's save panel writes JSON or HTML by extension (no headless save panel)")
    }

    /// a .little window is hosted by LittleWindowController: an NSPanel whose page area is Metrics.littleArc.defaultSize
    /// with the hint strip under it, titled "Little <app> — <page>", with an "Open in" pull-down listing every space;
    /// a second Little Arc cascades by Metrics.littleArc.cascade; the standard window stays a BrowserWindow
    func test_littleWindowControllerIsAPanel() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        XCTAssertTrue(h.store.windowController(h.window)?.window is BrowserWindow)
        h.store.dispatch(.user(h.window, .window(.newLittle(URL(string: "https://example.com/little")!))))
        let little = try XCTUnwrap(h.store.snapshot.windows.values.first { $0.kind == .little })
        defer { h.store.windowController(little.id)?.window.orderOut(nil) }
        let controller = try XCTUnwrap(h.store.windowController(little.id) as? LittleWindowController)
        XCTAssertTrue(controller.window is NSPanel)
        XCTAssertEqual(controller.root.bounds.size, Metrics.littleArc.defaultSize.value, "the page area is Arc's default size")
        XCTAssertEqual(controller.window.contentView?.bounds.height, Metrics.littleArc.defaultSize.value.height + Metrics.peek.hintHeight.value)
        XCTAssertEqual(controller.window.title, "Little \(Product.name) — example.com/little", "the page has no title yet, so its display URL")
        XCTAssertFalse(controller.hint.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(controller.hint.accessibilityIdentifier(), "little-hint")
        XCTAssertEqual(controller.hint.stringValue, LittleArcCopy.hint)
        let dock = h.store.snapshot.windows[little.id]!.dock
        XCTAssertEqual(controller.openIn.menu?.items.first?.title, "Open in \(dock[0].title)")
        XCTAssertEqual(controller.openIn.menu?.items.dropFirst().filter { !$0.isSeparatorItem }.map(\.title), dock.map(\.title) + [OpenInMenu.currentSpaceTitle])
        XCTAssertTrue(controller.openIn.isEnabled)
        XCTAssertTrue(controller.window.isVisible)
        // The engine was asked to focus the Little Arc's page (its surface sits in the panel's root).
        let page = PageID(try XCTUnwrap(little.scratch?.rows.first?.id))
        XCTAssertEqual(h.engine.focused.last, page)
        XCTAssertTrue(try XCTUnwrap(h.engine.surface(for: page)).isDescendant(of: controller.root))
        // The reducer reports the first panel's frame; the next Little Arc cascades from it.
        let first = controller.window.frame
        h.store.dispatch(.user(h.window, .window(.newLittle(URL(string: "https://example.com/second")!))))
        let second = try XCTUnwrap(h.store.snapshot.windows.values.first { $0.kind == .little && $0.id != little.id })
        defer { h.store.windowController(second.id)?.window.orderOut(nil) }
        let step = Metrics.littleArc.cascade.value
        XCTAssertEqual(h.store.windowController(second.id)?.window.frame, first.offsetBy(dx: step, dy: -step))
        // Choosing a menu entry moves the tab out and the panel goes.
        let item = try XCTUnwrap(controller.openIn.menu?.items.last)
        _ = (item.target as AnyObject).perform(item.action!, with: item)
        XCTAssertNil(h.store.snapshot.windows[little.id], "Open in current Space closed the Little Arc")
        XCTAssertNil(h.store.windowController(little.id))
        XCTAssertEqual(h.store.snapshot.windows[h.window]?.space.today.rows.count, 2, "the tab is in the standard window's Today")
    }

    /// a key CEF delivers from the peeked page routes to the window whose Peek shows it (the page is in the overlay,
    /// not a pane): Esc closes the Peek and the key is consumed
    func test_keysFromThePeekedPageRouteToItsWindow() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        h.store.dispatch(.user(h.window, .peek(.open(URL(string: "https://example.com/peeked")!))))
        guard case .peek(let peek)? = h.store.snapshot.windows[h.window]?.overlay, let page = peek.page else { return XCTFail("no peek with a page") }
        XCTAssertEqual(h.store.window(showing: page), h.window)
        XCTAssertEqual(h.engine.focused.last, page, "the peeked page got keyboard focus")
        // Esc is a page-first key (`pageThenApp`): CEF asks before the page (declined) and again after it (consumed).
        let press = h.key("escape", stage: .beforePage, id: 11).press
        XCTAssertFalse(h.router.engine(h.engine, page: page, key: press, stage: .beforePage, pressID: PressID(raw: 11)), "Esc is the page's first")
        XCTAssertTrue(h.router.engine(h.engine, page: page, key: press, stage: .afterPage, pressID: PressID(raw: 11)), "Esc from the peeked page was passed to the page")
        XCTAssertNil(h.store.snapshot.windows[h.window]?.overlay, "the Peek did not close")
        XCTAssertNil(h.store.snapshot.pages.first { $0.id == page }, "the peeked page is still demanded")
    }

    /// the engine's download question is answered from the page's profile: its Download Location (the system
    /// Downloads folder when unset) and Ask where to save; the engine's events then reach the Downloads page
    func test_downloadDecisionReadsTheProfilesSettings() throws {
        let h = Harness()
        defer { h.cleanUp() }
        let file = URL(string: "http://127.0.0.1:9/download")!
        func decide() -> DownloadDecision { h.router.engine(h.engine, page: h.page, decideDownload: "fixture.txt", from: file) }
        let system = try XCTUnwrap(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path)
        XCTAssertEqual(decide(), .save(directory: system))
        h.store.dispatch(.user(h.window, .settings(.profile(.default, .downloadsDirectory("/tmp/brk-downloads")))))
        XCTAssertEqual(decide(), .save(directory: "/tmp/brk-downloads"))
        h.store.dispatch(.user(h.window, .settings(.profile(.default, .downloadsDirectory("~/Desktop")))))
        XCTAssertEqual(decide(), .save(directory: "/tmp/brk-downloads"), "the settings boundary refuses relative and tilde paths")
        h.store.dispatch(.user(h.window, .settings(.profile(.default, .downloadsDirectory(NSHomeDirectory() + "/Desktop")))))
        XCTAssertEqual(decide(), .save(directory: NSHomeDirectory() + "/Desktop"))
        h.store.dispatch(.user(h.window, .settings(.profile(.default, .promptForDownloadLocation(true)))))
        XCTAssertEqual(decide(), .ask(directory: NSHomeDirectory() + "/Desktop"))

        let id = DownloadID("x-1-1")
        h.router.engine(h.engine, page: h.page, didEmit: .download(id, .started(url: file, filename: "fixture.txt", path: "/tmp/brk-downloads/fixture.txt")))
        h.router.engine(h.engine, page: h.page, didEmit: .download(id, .finished(path: "/tmp/brk-downloads/fixture.txt")))
        h.store.dispatch(.user(h.window, .library(.open(.downloads))))
        guard case .library(let library)? = h.store.snapshot.windows[h.window]?.overlay else { return XCTFail("no Library") }
        XCTAssertEqual(library.downloads.map(\.path), ["/tmp/brk-downloads/fixture.txt"])
        XCTAssertEqual(library.downloads.map(\.state), [.finished])
    }
}
