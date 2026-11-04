import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Round 4, R4-14: Arc's toasts (`Q11-b`, `P15`, and the rest of `ToastController`'s list; r4-14/POPUPS.md has the
/// table) and its + popover (`Q11-a`). Each toast: it appears at the content area's top right after the real action,
/// the strip says the words, and it leaves by itself.
enum ToastPopupScenarios {
    static let all = [
        Scenario("R414-CopyToast", "Cmd+Shift+C, Copy URL as Markdown and as Quote say Copied Current URL with a Share button that opens the export; a highlight says Copied Link / With Quote", cefOnly: "native toast and pasteboard", copyToast),
        Scenario("R414-Toasts", "pin, unpin, a move to another Space (click goes there), Clear, restore from the Library, Archive Cleared, a full split, Copied Info, a new Space from a folder, a background tab under a hidden sidebar and auto-archive each show their toast and let it go", cefOnly: "native toast", toasts),
        Scenario("R414-FullScreenToast", "a page going full screen shows To exit full screen, press [esc]", cefOnly: "native full screen", fullScreenToast),
        Scenario("R414-PlusMenu", "the + button opens Arc's popover: rows, shortcuts, × on grey, hover highlight, Escape, × and a click elsewhere close it, each row runs its command", cefOnly: "native popover", plusMenu),
    ]

    private typealias S = SidebarReviewScenarios
    private typealias E = SidebarEvidenceScenarios
    private static let toastID = ViewID.tabTool("toast").identifier

    /// The toast shows `text` at the content area's top right and the strip's labels say `words` (default: `text`).
    @discardableResult
    private static func shows(_ app: AppUnderTest, _ text: String, words: [String]? = nil) throws -> CGRect {
        try app.waitUntil("the toast \(text)") { try S.toast(app) == text && S.frame(app, toastID) != nil }
        guard let frame = try S.frame(app, toastID) else { throw Check(description: "no toast strip for \(text)") }
        let area = try app.native().computed.contentArea
        try expect(frame.maxX <= area.maxX + 0.5 && frame.maxX >= area.maxX - 40 && frame.minY < area.minY + 40, "the toast \(text) is not at the content area's top right: \(frame) in \(area)")
        let said = try S.texts(app, in: frame)
        for word in words ?? [text] { try expect(said.contains(word), "the toast's labels read \(said), not \(word)") }
        return frame
    }
    /// It leaves by itself within `seconds` of real time.
    private static func leaves(_ app: AppUnderTest, within seconds: Double = 7) throws {
        try app.waitUntil("the toast to leave by itself", timeout: seconds) { try S.toast(app) == nil && S.frame(app, toastID) == nil }
    }
    private static func showsAndLeaves(_ app: AppUnderTest, _ text: String, words: [String]? = nil) throws {
        try shows(app, text, words: words)
        _ = try app.screenshot("toast-" + text.prefix(14).replacingOccurrences(of: " ", with: "-"))
        try leaves(app)
        app.passed("toast: \(text)")
    }

    @Sendable static func copyToast(_ app: AppUnderTest) throws {
        let url = app.site.url("page2.html?toast=copy")
        let tab = try app.load(url)
        let page = S.page(app, tab)
        try app.waitForPageInput(page, at: url)
        // Advanced > Shared Quotes is on by default; nothing is highlighted yet.
        try app.press("cmd+shift+c")
        let frame = try shows(app, ToastCopy.copiedCurrentURL)
        try app.waitUntil("the address on the pasteboard") { try app.send(.readPasteboard) == .text(url.absoluteString) }
        guard let share = try S.frame(app, ViewID.tabTool("toast-action").identifier) else { throw Check(description: "no Share button on the toast") }
        try expect(share.maxX < frame.maxX && share.minY >= frame.minY && share.maxY <= frame.maxY, "Share at \(share) is not inside the strip at \(frame)")
        _ = try app.screenshot("copied-current-url")
        // The Share button is the file export that replaced Share-by-link.
        try app.click(.tabTool("toast-action"))
        try app.waitUntil("the export sheet") { try app.native().sheetClass != nil }
        try app.perform(.sheetButton(title: "Cancel"))
        try app.waitUntil("the sheet gone, the toast with it") { try app.native().sheetClass == nil && S.toast(app) == nil }
        // A click on the strip dismisses it.
        try app.press("cmd+shift+c")
        try shows(app, ToastCopy.copiedCurrentURL)
        try app.click(at: CGPoint(x: frame.minX + 30, y: frame.midY))
        try app.waitUntil("the click dismissed it") { try S.toast(app) == nil }
        for (title, format) in [("Copy URL as Markdown", CopyURLFormat.markdown), ("Copy URL as Quote", .quote)] {
            try app.perform(.menuAction(title))
            try shows(app, ToastCopy.copiedCurrentURL)
            let expected = SharedQuote.plain(url: url, title: try currentTab(app.view())?.title ?? "", format: format)
            try app.waitUntil("\(title) on the pasteboard") { try app.send(.readPasteboard) == .text(expected) }
            try leaves(app)
        }
        app.passed("Copied Current URL with Share; Markdown and Quote say the same")
        // With words highlighted the copy links to them.
        try app.evaluate(page, "const q=document.createElement('p');q.textContent='quoted words here';document.body.prepend(q);getSelection().selectAllChildren(q);document.title='selected'")
        app.sleep(0.3)
        try app.press("cmd+shift+c")
        try app.waitUntil("Copied Link") { try S.toast(app) == ToastCopy.copiedLink }
        let quote = try shows(app, ToastCopy.copiedLink, words: [ToastCopy.copiedLink, ToastCopy.withQuote])
        try expect(try S.frame(app, ViewID.tabTool("toast-action").identifier) == nil, "the quote toast has no button")
        _ = try app.screenshot("copied-link-with-quote")
        try expect(quote.height == 46.5, "the two-line toast is \(quote.height) tall")
        try leaves(app)
        app.passed("Copied Link / With Quote after a highlight")
    }

    @Sendable static func toasts(_ app: AppUnderTest) throws {
        let first = try E.loadReady(app, "page2.html?toast=first")
        let second = try E.loadReady(app, "page2.html?toast=second")
        let home = try app.view().space.id
        let homeTitle = "Space 1"

        // Cmd+D both ways, naming the Space.
        try app.press("cmd+d")
        try showsAndLeaves(app, ToastCopy.pinned(to: homeTitle))
        try app.press("cmd+d")
        try showsAndLeaves(app, ToastCopy.unpinned(from: homeTitle))

        // A move to another Space: the click goes there.
        let away = try createSpace(app, title: "Away")
        try app.dispatch(.space(.focus(home)))
        try app.waitUntil("back home") { try app.view().space.id == home }
        try app.dispatch(.item(.move(first, to: .space(away))))
        try shows(app, ToastCopy.tabMoved)
        _ = try app.screenshot("tab-moved")
        try app.click(.tabTool("toast"))
        try app.waitUntil("the click went to the moved tab") { try app.view().space.id == away && E.shown(app.view()) == first }
        try expect(try S.toast(app) == nil, "the toast stayed after its click")
        try app.dispatch(.item(.move(first, to: .space(home))))
        try showsAndLeaves(app, ToastCopy.tabMoved)
        try app.dispatch(.space(.focus(home)))
        try app.waitUntil("back home") { try app.view().space.id == home }

        // Clear, ⌘Z, and the words around the key cap.
        try app.dispatch(.tab(.focus(second)))
        try app.dispatch(.tab(.clearToday))
        try shows(app, "Cleared Tabs! Use", words: ["Cleared Tabs! Use", "⌘Z", "to undo"])
        try app.press("cmd+z")
        try app.waitUntil("⌘Z brought the tabs back") { try S.toast(app) == nil && app.view().space.today.rows.count >= 2 }
        app.passed("Cleared Tabs and its undo")

        // Restoring from the Library: the click closes it onto the tab; the plain words without a Library.
        try app.dispatch(.tab(.archive(.item(first))))
        try app.dispatch(.library(.open(.archive)))
        guard case .library(let library)? = try app.view().overlay, let entry = library.archive?.groups.flatMap(\.entries).first else { throw Check(description: "no archive entry") }
        try app.dispatch(.archive(.restore(entry.id)))
        try shows(app, ToastCopy.restoredClickToView(folder: false, to: homeTitle))
        try app.click(.tabTool("toast"))
        try app.waitUntil("the click closed the Library") { if case .library? = try app.view().overlay { false } else { true } }
        try app.dispatch(.tab(.archive(.item(first))))
        try app.dispatch(.archive(.clear))
        try showsAndLeaves(app, ToastCopy.archiveCleared)

        // Past the pane cap.
        for _ in 1..<Metrics.content.maxPanes.value {
            try app.press("ctrl+shift+=")
            try app.waitUntil("the new pane's command bar") { if case .commandBar? = try app.view().overlay { true } else { false } }
            try app.dispatch(.commandBar(.dismiss))
        }
        try expect(try app.view().content.panes.count == Metrics.content.maxPanes.value, "the split is not full")
        try app.press("ctrl+shift+=")
        try showsAndLeaves(app, ToastCopy.cannotAddPane)
        try app.dispatch(.split(.separateAll))

        try app.dispatch(.app(.help(.copyInfo)))
        try app.waitUntil("the info toast") { try S.toast(app)?.hasPrefix("Copied ") == true }
        try showsAndLeaves(app, try S.toast(app) ?? "")

        // A folder becomes a Space in the background.
        let folder = try E.newFolder(app, "Becomes Space")
        try app.dispatch(.tabTools(.folderToSpace(folder)))
        try showsAndLeaves(app, ToastCopy.newSpaceCreated)
        try app.dispatch(.space(.focus(home)))
        try app.waitUntil("back home") { try app.view().space.id == home }

        // A background tab while the sidebar is hidden has no row to appear in.
        let links = try app.load(app.site.url("index.html"))
        try app.waitForPageInput(S.page(app, links), at: app.site.url("index.html"))
        try app.press("cmd+s")
        try app.waitUntil("the sidebar hidden") { try !app.view().sidebar.visible }
        try app.click(at: try LittlePeekEvidenceScenarios.indexLink(app), modifiers: "cmd")
        try showsAndLeaves(app, ToastCopy.newTabCreated)
        try app.press("cmd+s")
        try app.waitUntil("the sidebar back") { try app.view().sidebar.visible }

        // The twelve-hour sweep. Everything but the shown tab is idle by then.
        let idle = try app.view().space.today.rows.filter { $0.id != E.shown(try app.view()) }.count
        try expect(idle > 0, "nothing to sweep")
        try app.advanceClock(seconds: 13 * 3600)
        try app.waitUntil("the sweep's toast") { try S.toast(app)?.hasPrefix("Auto archived ") == true }
        try showsAndLeaves(app, try S.toast(app) ?? "")
    }

    @Sendable static func fullScreenToast(_ app: AppUnderTest) throws {
        let url = app.site.url("browser-basic.html?toastfull")
        let tab = try app.load(url)
        let page = S.page(app, tab)
        try app.waitForPageInput(page, at: url)
        try app.evaluate(page, "(()=>{let b=document.createElement('button');b.textContent='Full';b.style='position:fixed;left:0;top:0;width:120px;height:60px;z-index:99999';b.onclick=()=>document.documentElement.requestFullscreen();document.body.append(b);document.title='ready'})()")
        try app.waitUntil("the button") { try currentTab(app.view())?.title == "ready" }
        guard let surface = try app.native().pages[page]?.surfaceFrame else { throw Check(description: "no page frame") }
        _ = try app.send(.activate(window: page.window))
        try app.click(at: CGPoint(x: surface.minX + 40, y: surface.minY + 25))
        try app.waitUntil("full screen", timeout: 15) { try app.native().fullscreen && app.native().fullscreenTransitioning != true }
        let shown = try S.toast(app)
        try expect(shown == ToastCopy.exitFullScreen, "no full-screen toast: \(String(describing: shown))")
        _ = try app.screenshot("full-screen-toast")
        try app.press("escape")
        try app.waitUntil("out of full screen", timeout: 15) { try !app.native().fullscreen }
        try expect(try S.toast(app) != ToastCopy.exitFullScreen, "the toast outlived the full screen")
    }

    private static let menuID = ViewID.tabTool("plus-menu").identifier
    private static func rowID(_ glyph: PlusMenuRow.Glyph) -> String { "plus-menu-" + glyph.rawValue }
    private static func openMenu(_ app: AppUnderTest) throws -> CGRect {
        try app.click(.dockPlus)
        try app.waitUntil("the + popover") { try S.frame(app, menuID) != nil }
        guard let frame = try S.frame(app, menuID) else { throw Check(description: "no popover") }
        return frame
    }
    private static func closed(_ app: AppUnderTest) throws -> Bool { try S.frame(app, menuID) == nil }

    @Sendable static func plusMenu(_ app: AppUnderTest) throws {
        _ = try E.loadReady(app, "page2.html?plus=1")
        let plus = try visible(app.native(), .dockPlus).frame
        let edge = CGPoint(x: plus.minX + 3, y: plus.midY)
        let idleFill = try app.pixel(edge)

        // What it offers, in Arc's groups.
        let rows = try app.view().plusMenu
        try expect(rows.map { $0.map(\.title) } == [["New Space", "New Folder"], ["New Easel", "New Boost"], ["New Split", "New Tab"]], "rows: \(rows)")
        try expect(rows.flatMap { $0 }.map(\.keys) == [[], [], ["⌃", "⇧", "E"], [], ["⌃", "⇧", "="], ["⌘", "T"]], "shortcuts: \(rows)")

        // The card: 210 wide, its right edge on the button's, above it with the triangle between.
        let menu = try openMenu(app)
        try expect(menu.width == 210 && menu.maxX == plus.maxX && menu.maxY <= plus.minY && menu.maxY >= plus.minY - 16, "popover at \(menu), + at \(plus)")
        try expect(abs(menu.height - 295.5) < 0.6, "popover height \(menu.height)")
        var lastY = menu.minY
        for row in rows.flatMap({ $0 }) {
            guard let frame = try S.frame(app, rowID(row.glyph)) else { throw Check(description: "no row \(row.title)") }
            try expect(frame.height == 40 && frame.minY >= lastY && frame.maxY <= menu.maxY, "\(row.title) at \(frame)")
            lastY = frame.maxY
            let said = try S.texts(app, in: frame)
            for word in [row.title] + row.keys { try expect(said.contains(word), "\(row.title) reads \(said)") }
        }
        let everything = try S.texts(app, in: menu)
        for gone in ["New GitHub Live Folder…", "Connect Calendar File…"] { try expect(!everything.contains(gone), "the popover still offers \(gone)") }
        _ = try app.screenshot("plus-open")

        // × on the hover fill, New Tab highlighted; hovering moves the highlight.
        try expect(try app.pixel(edge) != idleFill, "the + button has no grey fill while the popover is open")
        guard let tabRow = try S.frame(app, rowID(.newTab)), let spaceRow = try S.frame(app, rowID(.newSpace)) else { throw Check(description: "rows") }
        let tabBlank = CGPoint(x: tabRow.maxX - 80, y: tabRow.midY), spaceBlank = CGPoint(x: spaceRow.maxX - 20, y: spaceRow.midY)
        let highlight = try app.pixel(tabBlank), card = try app.pixel(spaceBlank)
        try expect(highlight != card, "New Tab is not highlighted when it opens: \(highlight)")
        try expect(highlight[0] == 0xDE && card[0] == 0xFD, "light colors: highlight \(highlight), card \(card)")
        try app.hover(spaceBlank)
        try app.waitUntil("the highlight follows the pointer") { try app.pixel(spaceBlank) == highlight && app.pixel(tabBlank) == card }
        _ = try app.screenshot("plus-hover")
        app.passed("popover rows, keys, × fill and hover")

        // Its closers: ×, Escape from the keyboard, a click on the page.
        try app.click(.dockPlus)
        try app.waitUntil("× closed it") { try closed(app) }
        try app.waitUntil("the + fill back") { try app.pixel(edge) == idleFill }
        _ = try openMenu(app)
        if WindowServerKeys.allowed {
            try WindowServerKeys.press(app, KeyChord([], .escape), window: app.window!)
            try app.waitUntil("Escape closed it") { try closed(app) }
            _ = try openMenu(app)
            let facts = try app.native()
            let area = facts.computed.contentArea
            let top = CGDisplayBounds(CGMainDisplayID()).height - facts.windowFrame.maxY
            try PhysicalPointer.click(app, at: CGPoint(x: facts.windowFrame.minX + area.midX, y: top + area.midY), window: app.window!)
            try app.waitUntil("a click on the page closed it") { try closed(app) }
        } else {
            app.note("no event-posting permission: Escape and the outside click were not posted as real events")
            try app.click(.dockPlus)
            try app.waitUntil("× closed it") { try closed(app) }
        }
        app.passed("×, Escape and a click elsewhere close it")

        // Each row runs its command and closes the popover.
        func choose(_ glyph: PlusMenuRow.Glyph) throws {
            _ = try openMenu(app)
            try app.click(.tabTool("plus-menu-" + glyph.rawValue))
            try app.waitUntil("\(glyph) closed it") { try closed(app) }
        }
        try choose(.newTab)
        try app.waitUntil("New Tab's bar") { if case .commandBar(let bar)? = try app.view().overlay { bar.createsTab } else { false } }
        try app.dispatch(.commandBar(.dismiss))
        let folders = try app.view().space.pinned.rows.count
        try choose(.newFolder)
        try app.waitUntil("New Folder") { try app.view().space.pinned.rows.count == folders + 1 && app.view().renaming != nil }
        try app.press("escape")
        try choose(.newSpace)
        try app.waitUntil("New Space") { try app.view().dialog == .newSpace }
        try app.dispatch(.app(.exit))
        try choose(.newSplit)
        try app.waitUntil("New Split") { if case .commandBar? = try app.view().overlay { try app.view().content.split != nil } else { false } }
        try app.dispatch(.commandBar(.dismiss))
        try app.dispatch(.split(.separateAll))
        let pinned = try app.view().space.pinned.rows.count
        try choose(.newEasel)
        try app.waitUntil("New Easel") { try app.view().space.pinned.rows.count == pinned + 1 }
        try choose(.newBoost)
        try app.waitUntil("New Boost") { try app.view().boostEditor != nil }
        app.passed("every row runs its command")
    }
}
