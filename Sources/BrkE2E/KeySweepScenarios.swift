import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation

/// Real keys (`WindowServerKeys`: posted at the HID tap with Brk made the active app) in each place the keyboard can be,
/// for the shortcuts the full audit of 2026-11-12 found pressed only through the control socket or not at all: a text
/// field in a page, the command bar's field, the Library, the sidebar, a split's panes, a Little Arc, a blank window and
/// the window itself. The control socket only sets up and reads state. Every shortcut in every focus state is routed in
/// BrkDomainTests.CommandSweepTests; this proves the keys get there.
enum KeySweepScenarios {
    static let all: [Scenario] = [
        Scenario("Keys-RealFocus", "real keys in a page's text field, the command bar, the Library, the sidebar, split panes, a Little Arc, a blank window and the window do what the shortcut table says",
                 realFocus),
    ]

    @Sendable static func realFocus(_ app: AppUnderTest) throws {
        let main = app.window!
        func press(_ text: String, in window: WindowID? = nil) throws {
            guard let chord = KeyChord(parsing: text) else { throw Check(description: "no chord \(text)") }
            try WindowServerKeys.press(app, chord, window: window ?? main)
        }
        func overlay(_ window: WindowID? = nil) throws -> OverlaySnapshot? { try app.view(window ?? main).overlay }
        func windows() throws -> [WindowID] {
            guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
            return hello.windows
        }

        // A text field in a page: the page keeps its own editing keys; an app shortcut never reaches it.
        let keysURL = app.site.url("keys.html")
        let keys = try openTab(app, keysURL)
        let page = PageID(window: main, item: keys.id)
        try app.waitForPageInput(page, at: keysURL)
        try press("cmd+a")
        try waitForTitle(app, keys.id, NativeScenarios.keyTitle("cmd+a"))
        try press("cmd+t")
        try app.waitUntil("⌘T in the page's text field opens the command bar") { isCommandBar(try overlay()) }
        try expect(tab(keys.id, in: try app.view())?.title == NativeScenarios.keyTitle("cmd+a"), "the page saw ⌘T")
        app.passed("a page's text field: ⌘A stayed the page's, ⌘T opened the command bar")

        // The command bar's field: ⌘A edits the field and the bar stays; Esc closes it and the page has the keyboard again.
        try press("cmd+a")
        app.sleep(0.4)
        try expect(isCommandBar(try overlay()), "⌘A in the command bar's field closed the bar")
        try press("escape")
        try app.waitUntil("Esc closes the command bar and gives the page the keyboard") {
            try overlay() == nil && app.native().focusedPage == page
        }
        app.sleep(0.3)
        let seen = tab(keys.id, in: try app.view())?.title
        try expect(seen == NativeScenarios.keyTitle("cmd+a"), "the page saw a key pressed while the bar was open: \(seen ?? "no title")")
        app.passed("the command bar: ⌘A kept it open, Esc closed it and gave the page the keyboard; the page saw none of ⌘T, ⌘A and Esc")

        // The Library (a native view has the keyboard): ⌘T opens the command bar over it; Esc closes what is open.
        try press("shift+cmd+l")
        try app.waitUntil("⇧⌘L opens the Library") { if case .library? = try overlay() { true } else { false } }
        try press("cmd+t")
        try app.waitUntil("⌘T in the Library opens the command bar") { isCommandBar(try overlay()) }
        for _ in 0..<2 {
            guard try overlay() != nil else { break }
            try press("escape")
            app.sleep(0.3)
        }
        try app.waitUntil("Esc closes the command bar and the Library") { try overlay() == nil }
        app.passed("the Library: ⌘T opened the command bar, Esc closed it")

        // The sidebar has the keyboard (Reveal Current Tab; its ⌃Space is macOS's input-source key on many Macs): ↓ shows
        // the next row, Esc gives the keyboard back to the page.
        try app.dispatch(.tabTools(.reveal))
        try app.waitUntil("the sidebar has the keyboard") { try app.view().focus == .sidebar }
        try press("down")
        try app.waitUntil("↓ in the sidebar shows the next row") { try currentTab(app.view())?.id != keys.id }
        try press("escape")
        try app.waitUntil("Esc gives the keyboard back to the page") {
            let focus = try app.view().focus
            if case .page = focus { return try app.native().focusedPage != nil }
            return false
        }
        try app.dispatch(.tab(.focus(keys.id)))
        try app.waitUntil("keys.html shown again") { try app.native().focusedPage == page }
        app.passed("the sidebar: ↓ moved to the next row, Esc gave the page the keyboard")

        // A split's panes with a page focused: ⌃⌥1 the first pane, ⌃⌥→ the next, ⌃⌥← back.
        try app.dispatch(.split(.addPane))
        try app.waitUntil("the command bar for the new pane") { isCommandBar(try overlay()) }
        _ = try app.dispatch(.commandBar(.submit(app.site.url("page2.html").absoluteString)))
        try app.waitUntil("two panes, a page focused") { try app.view().content.panes.count == 2 && app.native().focusedPage != nil }
        func focusedPane() throws -> Int? { try app.view().content.panes.firstIndex { $0.focused } }
        try press("ctrl+alt+1")
        try app.waitUntil("⌃⌥1 focuses the first pane") { try focusedPane() == 0 }
        try press("ctrl+alt+right")
        try app.waitUntil("⌃⌥→ focuses the second pane") { try focusedPane() == 1 }
        try press("ctrl+alt+left")
        try app.waitUntil("⌃⌥← focuses the first pane again") { try focusedPane() == 0 }
        app.passed("split panes: ⌃⌥1, ⌃⌥→ and ⌃⌥← moved the focus")

        // ⌘2 jumps to the second item of the list (Favorites, Pinned, then Today).
        let listed = try app.view()
        let second = try XCTUnwrapValue((listed.favorites.tiles.map(\.id) + (listed.space.pinned.rows + listed.space.today.rows).map(\.id)).dropFirst().first)
        try expect(!listed.content.panes.contains { $0.tab == second }, "the second row is shown before ⌘2")
        try press("cmd+2")
        try app.waitUntil("⌘2 shows the second row") { try app.view().content.panes.contains { $0.tab == second } }
        app.passed("⌘2 showed the second row")

        // A Little Arc: ⇧⌘E (Peek Email) does nothing there, ⌘N opens a standard window with its sidebar, ⌘O moves the
        // page into the space.
        let littleURL = app.site.url("red.html")
        try app.dispatch(.window(.newLittle(littleURL)))
        var little: WindowID?
        try app.waitUntil("the Little Arc opens") { little = try windows().first { $0 != main }; return little != nil }
        let littlePage = try XCTUnwrapValue(try app.view(little).content.panes.first?.tab)
        try app.waitUntil("the Little Arc's page has the keyboard") { try app.native(little).focusedPage == PageID(window: little!, item: littlePage) }
        try press("shift+cmd+e", in: little)
        app.sleep(0.8)
        try expect(try overlay(little) == nil && windows().count == 2, "⇧⌘E in a Little Arc opened something")
        let littleFrame = try app.native(little).windowFrame
        try press("cmd+n", in: little)
        var opened: WindowID?
        try app.waitUntil("⌘N in a Little Arc opens a window") { opened = try windows().first { $0 != main && $0 != little }; return opened != nil }
        let fresh = try app.view(opened)
        try expect(fresh.kind == .standard && fresh.sidebar.visible, "the window ⌘N opened from a Little Arc: \(fresh.kind), sidebar \(fresh.sidebar.visible)")
        // A window asked from a Little Arc opens at a standard window's size, not the Little Arc's moved down and right.
        let openedFrame = try app.native(opened).windowFrame
        try expect(openedFrame.width > littleFrame.width && openedFrame.width >= 800,
                   "the window ⌘N opened from a Little Arc has the Little Arc's size: \(openedFrame.size)")
        try press("escape", in: opened)
        try press("shift+cmd+w", in: opened)
        try app.waitUntil("⇧⌘W closes that window") { try !windows().contains(opened!) }
        try press("cmd+o", in: little)
        try app.waitUntil("⌘O moves the Little Arc's page into the space") {
            try !windows().contains(little!) && currentTab(app.view())?.url == littleURL
        }
        app.passed("a Little Arc: ⇧⌘E did nothing, ⌘N opened a standard window with its sidebar at \(Int(openedFrame.width))×\(Int(openedFrame.height)) (the Little Arc \(Int(littleFrame.width))×\(Int(littleFrame.height))), ⌘O moved the page into the space")

        // A blank window (⌃⌘N with a page focused) closed with ⇧⌘W archives its tab.
        try app.waitUntil("the page has the keyboard") { try app.native().focusedPage != nil }
        try press("ctrl+cmd+n")
        var blank: WindowID?
        try app.waitUntil("⌃⌘N opens a blank window") { blank = try windows().first { $0 != main }; return blank != nil }
        let blankKind = try app.view(blank).kind
        try expect(blankKind == .blank, "⌃⌘N opened a \(blankKind) window")
        app.window = blank
        let blankURL = app.site.url("page-browsing.html")
        _ = try app.dispatch(.commandBar(.submit(blankURL.absoluteString)))
        app.window = main
        try app.waitUntil("the blank window shows its tab") { try currentTab(app.view(blank))?.url == blankURL }
        try press("shift+cmd+w", in: blank)
        try app.waitUntil("⇧⌘W closes the blank window") { try !windows().contains(blank!) }
        try expect(try PageSiteFixScenarios.archived(app).contains(blankURL), "the blank window's tab is not in the archive")
        app.passed("a blank window: ⌃⌘N opened it, ⇧⌘W closed it and archived its tab")

        // ⌘M minimizes the window; the control socket brings it back.
        try press("cmd+m")
        try app.waitUntil("⌘M minimizes the window") { try app.native().miniaturized }
        try app.perform(.activateApp(window: main))
        try app.waitUntil("the window is back") { try !app.native().miniaturized }
        app.passed("⌘M minimized the window")
    }
}
