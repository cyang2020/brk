import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

enum MediaScenarios {
    static let all = [
        Scenario("R55-Row", "a real click plays: the row shows one speaker between icon and title and nothing at its end; clicking the speaker mutes and unmutes the real tab", cefOnly: "real mouse and Chrome media", rowSpeaker),
        Scenario("R55-Card", "a playing tab left behind shows a card over the dock; the pointer makes it taller with its title; a real click on Pause really pauses without changing the tab; Play plays; shown again the card goes", cefOnly: "real mouse and Chrome media", card),
        ]
    static func row(_ app: AppUnderTest, _ item: ItemID) throws -> TabRow? { tab(item, in: try app.view()) }
    @Sendable static func controls(_ app: AppUnderTest) throws {
        let url = app.site.url("capture-media.html")
        let first = try app.load(url)
        let page = PageID(window: app.window!, item: first)
        try app.waitForPageInput(page, at: url)
        try app.waitUntil("real video is observed playing") { try row(app, first)?.mediaPlayers.first?.paused == false }
        let player = try row(app, first)!.mediaPlayers[0]
        let second = try app.load(app.site.url("page2.html"))
        try app.dispatch(.page(.media(.item(first), player.id, .pause)))
        try app.waitUntil("background player's actual paused state") { try row(app, first)?.mediaPlayers.first?.paused == true }
        try expect(try app.view().content.panes.first?.tab == second, "background Pause stole tab selection")
        try app.dispatch(.page(.media(.item(first), player.id, .play)))
        try app.waitUntil("background player's actual playing state") { try row(app, first)?.mediaPlayers.first?.paused == false }
        try app.dispatch(.tab(.focus(first)))
        try app.evaluate(page, "document.title='DOM paused='+document.querySelector('video').paused")
        try app.waitUntil("DOM independently confirms play") { try row(app, first)?.title == "DOM paused=false" }
        try app.evaluate(page, "const f=document.createElement('iframe');f.src='http://localhost:'+location.port+'/media-frame.html';document.body.appendChild(f)")
        try app.waitUntil("foreign frame has its own player identity") { try row(app, first)?.mediaPlayers.contains(where: { $0.id.frame != 0 }) == true }
        let child = try row(app, first)!.mediaPlayers.first { $0.id.frame != 0 }!
        try app.dispatch(.page(.media(.item(first), child.id, .pause)))
        try app.waitUntil("only foreign player pauses") {
            guard let players = try row(app, first)?.mediaPlayers else { return false }
            return players.contains { $0.id == child.id && $0.paused } && players.contains { $0.id == player.id && !$0.paused }
        }
        try app.recordWindows("media-background-and-frame-controls")
        _ = try app.screenshot("media-player-controls")
        try app.evaluate(page, "location.href='page2.html'")
        try app.waitUntil("navigation removes the old player controls") { try row(app, first)?.mediaPlayers.isEmpty == true }
        try app.dispatch(.page(.media(.item(first), player.id, .play)))
        try expect(try row(app, first)?.mediaPlayers.isEmpty == true, "stale control resurrected a navigated player")
    }

    // MARK: R5-5, Arc's speaker and mini player (6777d0968b:verify/visual-pairs/run-20261103/Q18). Setup loads pages by command; every
    // gesture under test goes through the window server.

    private typealias E = SidebarEvidenceScenarios

    private static func frame(_ app: AppUnderTest, _ id: ViewID) throws -> CGRect { try visible(app.native(), id).frame }
    private static func centre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }
    private static func tool(_ name: String, _ tab: ItemID) -> ViewID { .tabTool(name + tab.rawValue) }

    /// A real click on a view: the pointer goes there first, so its hover state is what a person's click would see.
    private static func press(_ app: AppUnderTest, _ id: ViewID) throws {
        try PhysicalPointer.press(app, at: centre(frame(app, id)), window: app.window!) {}
    }
    /// The pointer on `id`, and the stack answering: the card reads two lines tall.
    private static func onto(_ app: AppUnderTest, _ id: ViewID, card tab: ItemID) throws {
        try PhysicalPointer.move(app, to: centre(frame(app, id)), window: app.window!)
        try app.waitUntil("the card opens under the pointer", timeout: 3) { try frame(app, tool("mini-player-", tab)).height >= Metrics.miniPlayer.expandedHeight.value }
    }
    private static func away(_ app: AppUnderTest) throws {
        let card = try app.native().computed.cards[0].rect
        try PhysicalPointer.move(app, to: CGPoint(x: card.midX, y: card.midY), window: app.window!)
    }
    private static func cardHeight(_ app: AppUnderTest, _ tab: ItemID) throws -> Double { Double(try frame(app, tool("mini-player-", tab)).height) }

    /// `tab` playing the fixture through a real click on its Play button, then `other` shown through a real click on its row.
    private struct Playing { var tab: ItemID; var other: ItemID; var page: PageID }
    private static func playing(_ app: AppUnderTest, query: String = "") throws -> Playing {
        let other = try E.loadReady(app, "page2.html?other")
        let tab = try E.loadReady(app, "mini-player.html" + query)
        guard WindowServerKeys.allowed else { throw Check(description: "no permission to post real mouse events") }
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        try playOnPage(app, tab)
        return Playing(tab: tab, other: other, page: PageID(window: app.window!, item: tab))
    }
    private static func playOnPage(_ app: AppUnderTest, _ tab: ItemID) throws {
        let card = try app.native().computed.cards[0].rect
        try PhysicalPointer.press(app, at: CGPoint(x: card.minX + 100, y: card.minY + 50), window: app.window!) {}
        try app.waitUntil("the page reports it plays") { try row(app, tab)?.title.hasPrefix("paused=false") == true }
        try app.waitUntil("the player is observed playing") { try row(app, tab)?.mediaPlayers.first?.paused == false }
        try app.waitUntil("the tab is audible") { try row(app, tab)?.audible == true }
    }
    private static func leave(_ app: AppUnderTest, for other: ItemID, card tab: ItemID) throws {
        try press(app, .row(other))
        try app.waitUntil("the other tab is shown") { try E.shown(app.view()) == other }
        try app.waitUntil("the card appears") { isShown(try app.native(), tool("mini-player-", tab)) }
        try away(app)
        try app.waitUntil("the card rests", timeout: 3) { try cardHeight(app, tab) == Metrics.miniPlayer.rowHeight.value }
    }
    /// The page's own word: its title is rewritten on every play, pause and volume change, in the background too.
    private static func pageSays(_ app: AppUnderTest, _ tab: ItemID, _ prefix: String) throws {
        try app.waitUntil("the page says \(prefix)") { try row(app, tab)?.title.hasPrefix(prefix) == true }
    }

    @Sendable static func rowSpeaker(_ app: AppUnderTest) throws {
        let p = try playing(app)
        let native = try app.native()
        let rowFrame = try frame(app, .row(p.tab))
        let speaker = try frame(app, tool("audio-", p.tab))
        let selectionX = rowFrame.minX + Metrics.tablist.selectionInset.value
        try expect(speaker.minX == selectionX + Metrics.tablist.speakerLeading.value, "the speaker is not between the icon and the title: \(speaker)")
        try expect(speaker.width == Metrics.tablist.speakerSide.value, "the speaker's button is not 24 wide")
        try expect(!isShown(native, .tabTool("media-" + p.tab.rawValue)), "a play button is left at the row's end")
        try expect(native.computed.sidebar?.miniPlayers.isEmpty == true && !isShown(native, tool("mini-player-", p.tab)), "the tab on screen has a card")
        _ = try app.screenshot("row-speaker")
        // The label is the row's title and it starts after the button (AX reads it where it is drawn).
        let label = NativeSystemInput.staticTexts(pid: app.hello!.pid).first { $0.text.hasPrefix("paused=false") }
        if let label {
            let top = CGDisplayBounds(CGMainDisplayID()).height - native.windowFrame.maxY
            try expect(label.frame.minX - native.windowFrame.minX >= speaker.maxX, "the title starts under the speaker: \(label.frame)")
            try expect(abs(label.frame.midY - top - rowFrame.midY) < 2, "the title is not in the row")
        } else { throw Check(description: "no title label in the row") }
        try press(app, .row(p.other))
        try app.waitUntil("the other tab is shown") { try E.shown(app.view()) == p.other }
        // The window's facts list only pages on screen: the real browser's state is read once the tab is shown.
        try press(app, tool("audio-", p.tab))
        try app.waitUntil("the row reads muted") { try row(app, p.tab)?.speaker == .muted }
        try expect(try E.shown(app.view()) == p.other, "the speaker's click changed the tab")
        _ = try app.screenshot("row-muted")
        try press(app, .row(p.tab))
        try app.waitUntil("the real tab is muted") { try app.native().pages[p.page]?.audioMuted == true }
        try press(app, tool("audio-", p.tab))
        try app.waitUntil("the real tab is unmuted") { try app.native().pages[p.page]?.audioMuted == false }
        try app.waitUntil("the row reads audible") { try row(app, p.tab)?.speaker == .audible }
    }

    @Sendable static func card(_ app: AppUnderTest) throws {
        let p = try playing(app)
        try leave(app, for: p.other, card: p.tab)
        var facts = try app.native()
        let card = try frame(app, tool("mini-player-", p.tab))
        let m = Metrics.miniPlayer
        try expect(card.width == facts.computed.sidebar!.frame.width - 2 * m.sideInset.value && card.height == m.rowHeight.value, "the card at rest is \(card)")
        try expect(card.maxY == facts.computed.sidebar!.dock.minY - m.bottomGap.value, "the card does not stand 8 above the dock: \(card)")
        try expect(facts.computed.sidebar!.tablistViewport.maxY == card.minY - m.listGap.value, "the list does not end above the card")
        _ = try app.screenshot("card-rest")
        // Under the pointer it grows by one line, up, and the list gets shorter.
        try onto(app, tool("mini-player-play-", p.tab), card: p.tab)
        let open = try frame(app, tool("mini-player-", p.tab))
        try expect(open.maxY == card.maxY && open.height == m.expandedHeight.value, "the card did not grow up: \(open)")
        let title = try S.texts(app, in: open)
        try expect(title.contains { $0.hasPrefix("paused=false") }, "no title on the open card: \(title)")
        try app.waitUntil("the tooltip", timeout: 3) { isShown(try app.native(), .tabTool("arc-tooltip")) }
        try expect(try S.texts(app, in: frame(app, .tabTool("arc-tooltip"))).contains("Pause"), "the tooltip does not read Pause")
        _ = try app.screenshot("card-open")
        // A real click on Pause really pauses, and the tab shown stays.
        try press(app, tool("mini-player-play-", p.tab))
        try pageSays(app, p.tab, "paused=true")
        try expect(try E.shown(app.view()) == p.other, "Pause changed the tab")
        try app.waitUntil("the card reads Play") { try app.view().miniPlayers.first?.playing == false }
        _ = try app.screenshot("card-paused")
        try app.waitUntil("the row loses its speaker once silent", timeout: 8) { try row(app, p.tab)?.speaker == nil }
        facts = try app.native()
        try expect(isShown(facts, tool("mini-player-", p.tab)), "the paused card went away")
        try press(app, tool("mini-player-play-", p.tab))
        try pageSays(app, p.tab, "paused=false")
        try app.waitUntil("the card reads Pause") { try app.view().miniPlayers.first?.playing == true }
        // Shown again, the card goes.
        try press(app, .row(p.tab))
        try app.waitUntil("the tab is shown") { try E.shown(app.view()) == p.tab }
        try app.waitUntil("no card for the shown tab") { !isShown(try app.native(), tool("mini-player-", p.tab)) }
        try expect(try row(app, p.tab)?.title.hasPrefix("paused=false") == true, "going back paused the tab")
        // A tab paused before it leaves the screen gets none.
        let surface = try app.native().computed.cards[0].rect
        try PhysicalPointer.press(app, at: CGPoint(x: surface.minX + 300, y: surface.minY + 50), window: app.window!) {}
        try pageSays(app, p.tab, "paused=true")
        try press(app, .row(p.other))
        try app.waitUntil("the other tab is shown") { try E.shown(app.view()) == p.other }
        Thread.sleep(forTimeInterval: 1.5)
        try expect(!isShown(try app.native(), tool("mini-player-", p.tab)), "a tab paused before it left has a card")
    }





    @Sendable static func arrow(_ app: AppUnderTest) throws {
        for n in 0..<16 { _ = try E.loadReady(app, "page2.html?row=\(n)") }
        guard WindowServerKeys.allowed else { throw Check(description: "no permission to post real mouse events") }
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        let view = try app.view()
        let rows = view.space.today.rows.map(\.id)
        guard let shown = E.shown(view), let first = rows.first, let far = [rows.last, first].compactMap({ $0 }).first(where: { $0 != shown }) else { throw Check(description: "no rows") }
        // The far row current, then the list scrolled the other way: the arrow points to it.
        try app.dispatch(.tab(.focus(far)))
        try app.waitUntil("the far row is shown") { try E.shown(app.view()) == far }
        guard let list = try app.native().computed.sidebar?.tablistViewport else { throw Check(description: "no list") }
        let arrow = ViewID.tabTool("current-row-arrow")
        func scrolled(_ lines: Int32) throws {
            try PhysicalPointer.scroll(app, lines: lines, at: CGPoint(x: list.midX, y: list.midY), window: app.window!)
        }
        for lines: Int32 in [12, -12] {
            try scrolled(lines)
            if isShown(try app.native(), arrow) { break }
        }
        try app.waitUntil("the arrow", timeout: 3) { isShown(try app.native(), arrow) }
        let button = try frame(app, arrow)
        try expect(abs(button.midX - list.midX) < 1 && button.width == Metrics.tablist.currentArrowSide.value, "the arrow is not centred: \(button)")
        _ = try app.screenshot("arrow")
        try PhysicalPointer.move(app, to: centre(button), window: app.window!)
        try app.waitUntil("the tooltip", timeout: 3) { isShown(try app.native(), .tabTool("arc-tooltip")) }
        let title = try tab(far, in: app.view())?.title ?? ""
        try expect(try S.texts(app, in: frame(app, .tabTool("arc-tooltip"))).contains(title), "the tooltip is not the current tab's title (\(title))")
        try press(app, arrow)
        try app.waitUntil("the row is back and the arrow gone", timeout: 3) { !isShown(try app.native(), arrow) }
    }
    private typealias S = SidebarReviewScenarios
}
