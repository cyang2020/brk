import AppKit
import BrkBase
@testable import BrkContent
@testable import BrkDomain
import BrkLayout
import BrkUIKit
@testable import BrkOverlays
@testable import BrkSidebar
import XCTest

/// Every surface a test can draw takes a person's pointer: each view that follows the pointer gets it coming in, moving,
/// a press, a release and leaving, without calling back into itself without end. Build 24 quit on the folder card's rows:
/// a row's redraw asked for the highlight and the highlight redrew the row; no test had ever put the pointer on them.
/// In the same pass every label must read on what is behind it, in Light and in Dark: three of the user's six bugs of
/// 2026-11-12 were dark-mode text the colour of its background, and this Mac runs in Light.
///
/// Each test draws its surfaces in every look (`SurfaceChecks.looks`), so most take more than 2 s: one window per look is the
/// cost of drawing every surface there, shared by all of that test's states.
@MainActor
final class PointerSweepTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    /// The sidebar with every kind of row (Favorites, Pinned, a collapsed and an open folder, a group, a split, Today, a
    /// playing tab), the dock, the pill, the mini player, the + menu, the Library flyout and an item's preview, and the hover
    /// cards of a folder, a calendar, a site and mail.
    func testTheSidebarAndItsCardsTakeThePointerAndRead() throws {
        var problems: [String] = []
        for look in SurfaceChecks.macLooks {
            try SurfaceChecks.appearing(look.mac) {
                let rig = try SweepRig(look)
                defer { rig.close() }
                let sidebar = try rig.buildSidebar()
                rig.render { rig.decorate(&$0, sidebar) }
                // A calendar Favorite's capsule is in Arc's GCalSubtitle colours (ARC_AppTray), which read below 3:1 on a dark tile.
                problems += rig.check("window", reach: 30, exempt: { SurfaceChecks.inside($0, prefix: "favorite-subtitle-") })

                // The cards open after the pointer rests: all four start together and are waited for once.
                let root = rig.root
                let folderRow = try XCTUnwrap(ViewTreeSearch.find(ViewID.row(sidebar.collapsed).identifier, in: root) as? HoverView)
                let calendar = try XCTUnwrap(ViewTreeSearch.find(ViewID.favorite(sidebar.favorites[1]).identifier, in: root) as? HoverView)
                folderRow.setHovered(true)
                calendar.setHovered(true)
                let shown = try XCTUnwrap(rig.shown)
                let extra = [FolderPreview(dispatch: { _ in }), FolderPreview(dispatch: { _ in })]
                let site = try XCTUnwrap(shown.space.pinned.rows.lazy.compactMap { row -> TabRow? in
                    if case .tab(let t) = row, t.id == sidebar.pinned[1] { t } else { nil }
                }.first)
                let mail = try XCTUnwrap(shown.favorites.tiles.first { $0.id == sidebar.favorites[2] })
                let siteCard = try XCTUnwrap(site.hoverCard), mailCard = try XCTUnwrap(mail.hoverCard)
                let siteRow = try XCTUnwrap(ViewTreeSearch.find(ViewID.row(site.id).identifier, in: root))
                let mailTile = try XCTUnwrap(ViewTreeSearch.find(ViewID.favorite(mail.id).identifier, in: root))
                extra[0].hover(tab: site, card: siteCard, over: siteRow, now: rig.now)
                extra[1].hover(tab: mail, card: mailCard, over: mailTile, now: rig.now)
                SurfaceChecks.wait { root.subviews.filter { $0 is FolderPreviewView }.count >= 4 }
                let cards = root.subviews.compactMap { $0 as? FolderPreviewView }
                XCTAssertEqual(cards.count, 4, "\(look): the folder, calendar, site and mail cards opened")
                for card in cards {
                    let surface = try XCTUnwrap(card.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) })
                    problems += rig.check("hover card", [card], base: surface, reach: 2)
                }
                folderRow.setHovered(false)
                calendar.setHovered(false)
                extra.forEach { $0.close() }
                // NEW-hover-cards: the folder's card goes when the folder opens.
                folderRow.setHovered(true)
                XCTAssertTrue(SurfaceChecks.wait {
                    root.subviews.contains { card in
                        card is FolderPreviewView && card.subviews.contains { ($0 as? NSTextField)?.placeholderString == "Search Reading…" }
                    }
                })
                let folderCard = try XCTUnwrap(root.subviews.first { card in
                    card is FolderPreviewView && card.subviews.contains { ($0 as? NSTextField)?.placeholderString == "Search Reading…" }
                })
                XCTAssertNotNil(folderCard.superview, "the card must still be open before its folder opens")
                rig.run(.item(.toggleFolder(sidebar.collapsed)))
                rig.render { rig.decorate(&$0, sidebar) }
                XCTAssertNil(folderCard.superview, "\(look): the folder's card stayed after the folder opened")
                folderRow.setHovered(false)
                rig.run(.item(.toggleFolder(sidebar.collapsed)))

                // A006: the toolbar. A005: the sidebar hidden and floating over the page while the pointer is at the edge.
                rig.run(.sidebar(.toggleToolbar))
                rig.render { rig.decorate(&$0, sidebar) }
                problems += rig.check("toolbar", [root.toolbar], reach: 0)   // AppKit buttons, which follow no pointer
                rig.run(.sidebar(.toggleToolbar))
                rig.run(.sidebar(.toggle))
                rig.run(.sidebar(.peek(true)))
                rig.render { rig.decorate(&$0, sidebar) }
                // Its backdrop blurs whatever page lies under it, which a test cannot know: the pointer only (the same rows read on
                // the anchored sidebar above).
                XCTAssertGreaterThanOrEqual(SurfaceChecks.sweep(root.sidebar, in: rig.window), 20, "\(look) floating sidebar")
                rig.run(.sidebar(.peek(false)))
                rig.run(.sidebar(.toggle))
                rig.render { rig.decorate(&$0, sidebar) }

                // The + menu, opened by a press on its button.
                let plus = try XCTUnwrap(ViewTreeSearch.find(ViewID.dockPlus.identifier, in: root))
                if !root.subviews.contains(where: { $0 is PlusMenuView }) { SurfaceChecks.click(plus) }
                let menu = try XCTUnwrap(root.subviews.first { $0 is PlusMenuView }, "\(look): the + menu opened")
                problems += rig.check("+ menu", [menu], base: rig.base, reach: 1)
                if menu.superview != nil { SurfaceChecks.click(plus) }

                // The Library button's list, shown as the pointer resting on the button shows it.
                let flyout = try XCTUnwrap(ViewTreeSearch.find(ViewID.tabTool("library-flyout").identifier, in: root))
                flyout.isHidden = false
                flyout.alphaValue = 1
                problems += rig.check("Library flyout", [flyout], reach: 3)
                flyout.isHidden = true
                flyout.alphaValue = 0

                // A flyout row's click: the item's preview over the window.
                rig.render { value in
                    rig.decorate(&value, sidebar)
                    let items = value.libraryFlyout?.items ?? []
                    value.libraryFlyout?.preview = items.first
                    value.libraryFlyout?.previewSequence = items.reversed().map(\.key)
                }
                // The age in grey on the grey toolbar is Arc's (docs/arc-anatomy/library-flyout.md, The preview).
                problems += rig.check("item preview", [rig.overlay(LibraryItemPreviewView.self)].compactMap { $0 },
                                      exempt: { $0.accessibilityIdentifier() == ViewID.tabTool("library-item-preview-age").identifier })
                let preview = try XCTUnwrap(rig.overlay(LibraryItemPreviewView.self))
                rig.sent = []
                SurfaceChecks.click(preview, at: CGPoint(x: 2, y: preview.bounds.midY))
                XCTAssertEqual(rig.sent, [.library(.flyout(.preview(nil)))], "clicking the dimmed window closes its preview")
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// The sidebar's clicks the 2026-11-12 audit found no test for (its coverage lists sidebar-1 and sidebar-2), each sent
    /// through the window as a person's click is, so the view under the point takes it: what each sends.
    func testSidebarClicksTheAuditFoundUntestedSendWhatTheyShould() throws {
        let rig = try SweepRig()
        defer { rig.close() }
        let built = try rig.buildSidebar()
        let root = rig.root
        func view(_ id: ViewID) throws -> NSView { try XCTUnwrap(ViewTreeSearch.find(id.identifier, in: root), "\(id)") }
        func sends(_ click: () throws -> Void) rethrows -> [Command] {
            rig.sent = []
            try click()
            return rig.sent
        }
        func menus(_ commands: [Command]) -> [PopupMenuRequest] {
            commands.compactMap { if case .sidebar(.popupMenu(let request, _)) = $0 { request } else { nil } }
        }
        func hovered(_ id: ViewID, _ body: () throws -> Void) throws {
            let row = try XCTUnwrap(try view(id) as? HoverView)
            row.setHovered(true)
            defer { row.setHovered(false) }
            try body()
        }
        for path in ["m", "n", "o"] { rig.open(path) }
        let today = rig.snapshot().space.today.rows.compactMap { row -> ItemID? in if case .tab(let tab) = row { tab.id } else { nil } }
        XCTAssertGreaterThanOrEqual(today.count, 3)
        var sidebar = built
        sidebar.playing = today[0]   // the top Today row, where its speaker is in sight

        // A002: an empty pill is a search field; its magnifier and its right end open the command bar like the rest of it.
        rig.render { rig.decorate(&$0, sidebar); $0.urlPill.text = nil; $0.urlPill.host = nil }
        let pill = try view(.urlPill)
        XCTAssertEqual(sends { SurfaceChecks.click(pill, at: CGPoint(x: 12, y: pill.bounds.midY)) }, [.commandBar(.open(.editCurrent))], "the magnifier")
        XCTAssertEqual(sends { SurfaceChecks.click(pill, at: CGPoint(x: pill.bounds.maxX - 6, y: pill.bounds.midY)) }, [.commandBar(.open(.editCurrent))], "the right end")
        // With an address and the pointer over the sidebar: copy link and the site controls show; a right-click or
        // Control-click on the pill opens the site controls. NEW-clear-tidy: Clear shows too, and clears Today.
        rig.render { rig.decorate(&$0, sidebar); $0.urlPill.canGoBack = true; $0.urlPill.canGoForward = true }
        root.sidebar.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: rig.window.windowNumber,
                                                               context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!)
        let pillButtons = pill.subviews.filter { $0 is GlyphButton && $0.alphaValue > 0 }.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(pillButtons.count, 2, "copy link and the site controls show while the pointer is over the sidebar")
        XCTAssertEqual(Set(sends { pillButtons.forEach { SurfaceChecks.click($0) } }), [.page(.copyURL(.plain)), .site(.controls)])
        XCTAssertEqual(sends { SurfaceChecks.click(pill, .right) }, [.site(.controls)])
        XCTAssertEqual(sends { SurfaceChecks.click(pill, flags: .control) }, [.site(.controls)])
        let clear = try view(.todayClear)
        XCTAssertTrue(!clear.isHiddenOrHasHiddenAncestor && clear.alphaValue > 0, "Clear shows while the pointer is over the sidebar")
        XCTAssertEqual(sends { SurfaceChecks.click(clear) }, [.tab(.clearToday)])
        // A001, A004: the title row's sidebar toggle, back and forward.
        let titleRow = try view(.titleRow)
        for (tip, command) in [(SidebarCopy.showHideSidebar, Command.sidebar(.toggle)), (SidebarCopy.goBack, .page(.back(.focused))),
                               (SidebarCopy.goForward, .page(.forward(.focused)))] {
            let button = try XCTUnwrap(titleRow.subviews.first { $0.toolTip == tip && !$0.isHidden }, tip)
            XCTAssertEqual(sends { SurfaceChecks.click(button) }, [command], tip)
        }
        // A split puts reload in each pane's header; the standalone title row exposes all reload variants.
        let navigation = TitleRowView(dispatch: { rig.sent.append($0) })
        let navigationWindow = SurfaceChecks.window(CGSize(width: 480, height: 48))
        defer { navigationWindow.close() }
        navigationWindow.contentView = navigation
        var pillState = rig.snapshot().urlPill
        var navigationFrames = try XCTUnwrap(WindowLayout.compute(rig.snapshot(), contentSize: SweepRig.size).sidebar)
        navigationFrames.titleRow.size.width = 480
        for loading in [false, true] {
            pillState.loading = loading
            navigation.render(pillState, frames: navigationFrames, toolbar: false, palette: Palette(rig.snapshot().theme))
            let button = try XCTUnwrap(navigation.subviews.first { $0.toolTip == (loading ? SidebarCopy.stop : SidebarCopy.reload) && !$0.isHidden })
            for flags in [NSEvent.ModifierFlags(), .option] {
                XCTAssertEqual(sends { SurfaceChecks.click(button, flags: flags) },
                               [loading ? .page(.stop(.focused)) : .page(.reload(.focused, ignoringCache: flags.contains(.option)))])
            }
        }
        // A003: a double-click on the sidebar's edge puts its width back.
        let handle = try view(.resizeHandle)
        let middle = try XCTUnwrap(root.superview).convert(CGPoint(x: handle.bounds.midX, y: handle.bounds.midY), from: handle)
        XCTAssertTrue(root.hitTest(middle) === handle, "the edge takes the click, not \(String(describing: root.hitTest(middle)))")
        XCTAssertEqual(sends { SurfaceChecks.click(handle, count: 2) }.first, .sidebar(.resize(width: SidebarResizeDrag.resetWidth)))

        // NEW-tablist-hover: the speaker of a playing row mutes it.
        XCTAssertEqual(try sends { SurfaceChecks.click(try view(.tabTool("audio-\(sidebar.playing)"))) }, [.tabTools(.mute(.item(sidebar.playing)))])
        // NEW-tablist-press: a double-click on a folder row renames it; a Control-click on a row is its right-click (A028).
        let open = try view(.row(sidebar.open))
        let doubled = sends { SurfaceChecks.click(open, count: 2) }
        XCTAssertTrue(doubled.contains(.item(.beginRename(.item(sidebar.open)))), "a double-click on a folder sent \(doubled)")
        XCTAssertEqual(menus(sends { SurfaceChecks.click(open, flags: .control) }), [.item(sidebar.open)])
        // NEW-tablist-row-x, A009: the × a row shows under the pointer closes a Today tab, and a group.
        try hovered(.row(today[0])) {
            XCTAssertEqual(try sends { SurfaceChecks.click(try view(.rowClose(today[0]))) }, [.tabTools(.bulk(.items([today[0]]), .close))])
        }
        try hovered(.row(sidebar.group)) {
            XCTAssertEqual(try sends { SurfaceChecks.click(try view(.rowClose(sidebar.group))) }, [.tabTools(.closeGroup(sidebar.group))])
        }
        // A013: a Cmd-click on a Favorite opens it on the release, not the press.
        let favorite = try view(.favorite(sidebar.favorites[0]))
        for flags in [NSEvent.ModifierFlags.command, .shift] {
            let point = favorite.convert(CGPoint(x: favorite.bounds.midX, y: favorite.bounds.midY), to: nil)
            rig.sent = []
            favorite.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: flags, timestamp: 0,
                                                       windowNumber: rig.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            XCTAssertEqual(rig.sent, [], "a modified press waits for the release")
            favorite.mouseUp(with: NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: flags, timestamp: 0,
                                                     windowNumber: rig.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!)
            XCTAssertEqual(rig.sent, [.tab(.focus(sidebar.favorites[0]))])
        }
        // NEW-mini-player, A029: the card's icon goes back to the playing tab; its speaker unmutes a muted tab.
        XCTAssertEqual(try sends { SurfaceChecks.click(try view(.tabTool("mini-player-icon-\(sidebar.playing)"))) }, [.tab(.focus(sidebar.playing))])
        let player = try view(.tabTool("mini-player-\(sidebar.playing)"))
        XCTAssertEqual(sends { SurfaceChecks.click(player, at: CGPoint(x: player.bounds.midX, y: 5)) }, [.tab(.focus(sidebar.playing))])
        rig.render { rig.decorate(&$0, sidebar); $0.miniPlayers[0].muted = true }
        XCTAssertEqual(try sends { SurfaceChecks.click(try view(.tabTool("mini-player-speaker-\(sidebar.playing)"))) }, [.tabTools(.mute(.item(sidebar.playing)))])
        // A008, A012, A007: + New Tab; the Space name collapses Pinned; its right-click is the Space's menu, as is one on
        // the list's empty end (NEW-tablist-context-menus).
        XCTAssertEqual(try sends { SurfaceChecks.click(try view(.todayNewTab)) }, [.commandBar(.open(.newTab))])
        func headers(_ view: NSView) -> [SpaceHeaderView] {
            ((view as? SpaceHeaderView).map { [$0] } ?? []) + view.subviews.flatMap(headers)
        }
        let header = try XCTUnwrap(headers(root.sidebar).first { !$0.isHiddenOrHasHiddenAncestor && $0.visibleRect.width > 0 }, "the Space name")
        XCTAssertEqual(sends { SurfaceChecks.click(header) }, [.space(.togglePinnedSection(.current))])
        let space = rig.snapshot().space.id
        XCTAssertEqual(menus(sends { SurfaceChecks.click(header, .right) }), [.spaceControls(space)])
        let short = try SweepRig()   // a list short enough to have an empty end
        defer { short.close() }
        short.render()
        let newTab = try XCTUnwrap(ViewTreeSearch.find(ViewID.todayNewTab.identifier, in: short.root))
        SurfaceChecks.click(newTab, at: CGPoint(x: newTab.bounds.midX, y: newTab.bounds.maxY + 200), .right)
        XCTAssertEqual(menus(short.sent), [.spaceControls(short.snapshot().space.id)], "a right-click on the list's empty end")
        // A023, NEW-tablist-context-menus: in a Cmd-click selection a right-click is the selection's menu, and a row's ×
        // closes the whole selection.
        rig.run(.tabTools(.select(today[0], .toggle)))
        rig.run(.tabTools(.select(today[1], .toggle)))
        rig.render { rig.decorate(&$0, sidebar) }
        XCTAssertEqual(try menus(try sends { SurfaceChecks.click(try view(.row(today[1])), .right) }).map { request -> Set<ItemID> in
            if case .selection(let items) = request { Set(items) } else { [] }
        }, [Set([today[0], today[1]])])
        try hovered(.row(today[1])) {
            let closed = try sends { SurfaceChecks.click(try view(.rowClose(today[1]))) }
            XCTAssertEqual(closed.compactMap { if case .tabTools(.bulk(.items(let items), _)) = $0 { Set(items) } else { nil } }, [Set([today[0], today[1]])])
        }
        rig.run(.tabTools(.select(today[0], .replace)))
        // A020: a click away from an open rename field commits it.
        rig.render { rig.decorate(&$0, sidebar); $0.renaming = sidebar.open }
        XCTAssertTrue(root.focus(.renameField(sidebar.open)), "the rename field took the keyboard")
        XCTAssertTrue(try sends { SurfaceChecks.click(try view(.row(today[2])), throughApp: true) }.contains(.item(.rename(sidebar.open, title: "Projects"))))
        rig.render { rig.decorate(&$0, sidebar) }

        // A025: a pointer click still selects the row after keyboard focus moves to the list.
        XCTAssertTrue(root.focus(.sidebar))
        let focusedClick = try sends { SurfaceChecks.click(try view(.row(today[2]))) }
        XCTAssertTrue(focusedClick.contains(.tab(.focus(today[2]))))
        let workSpace = try XCTUnwrap(rig.snapshot().dock.first { $0.title == "Work" }?.id)
        rig.render { value in
            rig.decorate(&value, sidebar)
            value.tabTools.toast = ToastSnapshot(text: "Tab moved! Click to go there.", expiresAt: rig.now.advanced(by: .seconds(4)),
                                                click: .space(.focus(workSpace)))
        }
        XCTAssertEqual(try sends { SurfaceChecks.click(try view(.tabTool("toast"))) },
                       [.space(.focus(workSpace)), .tabTools(.dismissToast)])
        rig.render { rig.decorate(&$0, sidebar) }

        // NEW-hover-cards: a supported Pinned tab's card and a calendar Favorite's open from their rows; a card row's click
        // opens its page in a Peek; Join opens the meeting (A015).
        try hovered(.row(sidebar.pinned[1])) {
            try hovered(.favorite(sidebar.favorites[1])) {
                SurfaceChecks.wait { root.subviews.filter { $0 is FolderPreviewView }.count >= 2 }
                let cards = root.subviews.compactMap { $0 as? FolderPreviewView }
                XCTAssertEqual(cards.count, 2, "the site and calendar cards opened")
                let join = try XCTUnwrap(cards.lazy.compactMap { ViewTreeSearch.find("sidebar-hover-card-join", in: $0) }.first { !$0.isHidden }, "Join")
                XCTAssertEqual(sends { SurfaceChecks.click(join) }, [.commandBar(.open(.newTab)), .commandBar(.submit("https://meet.google.com/abc"))])
                let siteCard = try XCTUnwrap(root.subviews.compactMap { $0 as? FolderPreviewView }.first, "the site card stayed")
                let row = try XCTUnwrap(ViewTreeSearch.find("sidebar-hover-card-row-0", in: siteCard))
                XCTAssertEqual(sends { SurfaceChecks.click(row) }, [.peek(.open(URL(string: "https://linear.app/brk/3600000")!))])
                XCTAssertNil(siteCard.superview, "the card closed after opening the page")
            }
        }
    }

    /// What opens over the window: the command bar with results and quick answers, the find bar, the Space dialogs and the
    /// theme editor, the profile dialogs, the save cards, the capture overlay, the Ctrl+Tab switcher, a toast, a Peek, and
    /// the Boost editor's pages.
    func testOverlaysTakeThePointerAndRead() throws {
        var problems: [String] = []
        for look in SurfaceChecks.looks {
            try SurfaceChecks.appearing(look.mac) {
                let rig = try SweepRig(look)
                defer { rig.close() }
                _ = try rig.buildSidebar()
                let tabs = rig.snapshot().space.today.rows.map(\.id)
                /// Draws the state, then checks the overlay's own views (`views`, read after drawing) and any panel or popover it
                /// opened in a window of its own (the theme editor, the icon picker, the Boost editor).
                @MainActor func show(_ name: String, reach: Int = 1, _ views: () -> [NSView?], _ edit: (inout WindowSnapshot) -> Void = { _ in },
                                     exempt: (NSTextField) -> Bool = { _ in false }) {
                    let before = Set(NSApp.windows.map(ObjectIdentifier.init))
                    rig.render(edit)
                    problems += rig.check(name, views().compactMap { $0 }, reach: reach, exempt: exempt)
                    for window in NSApp.windows where !before.contains(ObjectIdentifier(window)) && window.isVisible {
                        guard let content = window.contentView else { continue }
                        SurfaceChecks.conceal(window)
                        problems += rig.check("\(name) window", [content], base: window.backgroundColor ?? .windowBackgroundColor, reach: 0)
                    }
                }
                let root = rig.root

                // Arc draws the highlighted row's white text on a shade of the theme (P02-b: #B8A89B under the #F2EAE4 theme).
                let onHighlight = { (label: NSTextField) -> Bool in
                    var view: NSView? = label
                    while let v = view, v !== root.commandBar {
                        if v.accessibilityIdentifier() == ViewID.commandBarResult(root.commandBar.highlighted).identifier { return true }
                        view = v.superview
                    }
                    return false
                }
                // Arc's Next before a name is typed is off and pale (P42 a).
                let inOffButton = { (label: NSTextField) -> Bool in
                    var view: NSView? = label
                    while let v = view {
                        if let button = v as? AlertButton, !button.isEnabled { return true }
                        view = v.superview
                    }
                    return false
                }
                rig.run(.commandBar(.open(.newTab)))
                for query in ["127", "2+2", "#ff8800", "10 km to mi"] {
                    rig.run(.commandBar(.queryChanged(query)))
                    show("command bar \(query)", reach: 2, { [root.commandBar] }, exempt: onHighlight)
                }
                rig.run(.commandBar(.dismiss))

                rig.run(.find(.open(replace: true)))
                let page = PageID(window: rig.id, item: try XCTUnwrap(rig.snapshot().content.panes.first?.tab))
                show("find bar", reach: 0, { [root.findBar] }) { value in
                    value.find = FindSnapshot(page: page, query: FindQuery(text: "sidebar"), replacement: true, count: 12, ordinal: 3, searching: false,
                                              canReplace: true, message: "", scope: "", focusRequest: nil)
                }
                show("find bar not found", reach: 0, { [root.findBar] }) { value in
                    value.find = FindSnapshot(page: page, query: FindQuery(text: "zzz"), replacement: false, count: 0, ordinal: nil, searching: false,
                                              canReplace: false, message: "", scope: "", focusRequest: nil)
                }
                rig.run(.find(.close))

                for request in [SpaceDialogRequest.newSpace, .rename(.current), .icon(.current), .theme(.current)] {
                    rig.run(.sidebar(.openDialog(request)))
                    show("space dialog \(request)", reach: 0, { [root.spaceDialog] })
                    rig.run(.sidebar(.openDialog(nil)))
                    rig.render()
                }
                let work = try XCTUnwrap(rig.snapshot().dock.first { $0.title == "Work" }?.id)
                rig.run(.space(.requestDelete(work)))
                show("delete space", { [root.spaceDialog] })
                rig.state.session.windows[rig.id]?.pendingSpaceDeletion = nil

                for request in [ProfileDialogRequest.create, .change(.current)] {
                    rig.run(.profile(.openDialog(request)))
                    show("profile dialog \(request)", { [rig.overlay(ProfileDialogHost.self)] }, exempt: inOffButton)
                    rig.run(.profile(.openDialog(nil)))
                }
                rig.render()

                for kind in [SavePrompt.Kind.password, .address, .card] {
                    root.showSavePrompt(SavePrompt(id: "save-\(kind)", page: page, kind: kind, site: "www.example.com"), scheme: rig.snapshot().theme.scheme) { _ in }
                    problems += rig.check("save card \(kind)", [rig.overlay(SavePromptCard.self)].compactMap { $0 }, reach: 2)
                    root.removeSavePrompt()
                }

                let request = CaptureRequest(id: "capture", document: DocumentToken(browser: BrowserToken(page: page, generation: 1), sequence: 1),
                                             context: .profile(.default), mode: .area, title: "A", url: URL(string: "http://127.0.0.1:9/a")!,
                                             createdAt: rig.now, region: CaptureRegion(x: 0.1, y: 0.1, width: 0.3, height: 0.3))
                show("capture", { [rig.overlay(CaptureOverlayView.self)] }) { $0.capture = CaptureSnapshot(request: request) }
                show("capture menu", reach: 3, { [rig.overlay(CaptureOverlayView.self)] }) {
                    $0.capture = CaptureSnapshot(request: request, image: CaptureImage(png: Data([7]), width: 300, height: 200, scale: 2))
                }
                rig.render()

                let recent = tabs.prefix(5).enumerated().map { RecentTabRow(id: $1, title: "Tab \($0)", url: URL(string: "http://127.0.0.1:9/\($0)")) }
                show("switcher", reach: 0, { [rig.overlay(TabToolsOverlayView.self)] }) { $0.tabTools.recent = RecentTabsSnapshot(items: recent, selected: recent[1].id) }
                show("toast", reach: 0, { [rig.overlay(TabToolsOverlayView.self)] }) { value in
                    var toast = ToastSnapshot(text: "Cleared Tabs! Use", expiresAt: Instant(milliseconds: rig.now.milliseconds + 60_000))
                    toast.keycap = "⌘Z"
                    toast.trailing = "to undo"
                    value.tabTools.toast = toast
                }

                rig.run(.peek(.open(URL(string: "https://example.com/peek")!)))
                show("peek", { [root.peek as NSView?] + root.subviews.filter { $0 is PeekRoundButton || $0 is PeekBackdropView }.map { $0 as NSView? } })
                rig.run(.peek(.close))

                let editor = BoostEditorView(dispatch: { _ in })
                let panel = SurfaceChecks.window(BoostEditorView.size(for: .intro))
                defer { panel.close() }
                panel.appearance = NSAppearance(named: .aqua) // Boost's panel follows Arc's fixed light palette.
                panel.contentView = editor
                for boostPage in [BoostEditorPage.intro, .style, .css, .javascript] {
                    panel.setContentSize(BoostEditorView.size(for: boostPage))
                    editor.render(BoostEditor(id: "boost", profile: .default, target: nil,
                                              draft: Boost(id: "draft", name: "My Boost", scope: .allSites, css: "body { color: red }"), page: boostPage))
                    problems += rig.check("boost editor \(boostPage)", [editor], base: .windowBackgroundColor, reach: 0)
                }
                rig.render()
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// Every Library page with content (archive, downloads, media, easels, spaces, boosts, conversations with one open), and
    /// the History card.
    func testLibraryPagesTakeThePointerAndRead() throws {
        var problems: [String] = []
        for look in SurfaceChecks.macLooks {
            try SurfaceChecks.appearing(look.mac) {
                let rig = try SweepRig(look)
                defer { rig.close() }
                _ = try rig.buildSidebar()
                for item in rig.snapshot().space.today.rows.prefix(2).map(\.id) { rig.run(.tab(.close(.item(item)))) }
                let minute: Int64 = 60_000
                let downloads = rig.libraryItems().compactMap { item -> DownloadRow? in if case .download(let row) = item.content { row } else { nil } }
                    + [DownloadRow(id: DownloadID("d3"), filename: "broken.dmg", url: URL(string: "https://files.example.com/broken.dmg")!, path: nil,
                                   received: 1_000, total: 9_000, state: .failed, startedAt: Instant(milliseconds: rig.now.milliseconds - 90 * minute))]
                let thread = AIThreadRow(id: AIRequestID("t1"), title: "Plan the trip", state: .waiting, detail: "Wants to run a command",
                                         updatedAt: Instant(milliseconds: rig.now.milliseconds - 5 * minute))
                var replied = AIThreadRow(id: AIRequestID("t2"), title: "Compare laptops", state: .unread, detail: "Replied 2 minutes ago",
                                          updatedAt: Instant(milliseconds: rig.now.milliseconds - 2 * minute))
                replied.agent = "Claude"
                replied.pages = 1
                var waiting = thread
                waiting.pill = "Approve"
                for page in LibraryPage.allCases {
                    rig.run(.library(.open(page)))
                    rig.render { value in
                        guard case .library(var library)? = value.overlay else { return }
                        switch page {
                        case .downloads: library.downloads = downloads
                        case .media: library.captures = [rig.capture("m1", ago: 3), rig.capture("m2", ago: 300)]
                        case .easelsAndNotes:
                            library.easels = [EaselCard(id: EaselID("e1"), title: "Moodboard", titleSize: 1, elements: [], modifiedAt: rig.now),
                                              EaselCard(id: EaselID("e2"), title: "Untitled", titleSize: 1, elements: [], modifiedAt: Instant(milliseconds: rig.now.milliseconds - 3 * 1_440 * minute))]
                        case .boosts:
                            library.boosts = [Boost(id: "b1", name: "Quiet news", scope: .allSites, css: "aside { display: none }"),
                                              Boost(id: "b2", name: "Wide docs", scope: .allSites, enabled: false)]
                        case .conversations:
                            let answer = AIAnswerSnapshot(request: replied.id, title: replied.title, text: "The lighter one wins on battery.", busy: false, sources: [])
                            library.conversations = LibraryConversationsSnapshot(query: ConversationLibraryQuery(), rows: [waiting, replied], waiting: 1, withPages: 1,
                                                                                 spaces: [], agents: ["Claude"], language: .en,
                                                                                 selected: LibraryConversationDetail(id: replied.id, title: replied.title, meta: "Personal · Claude",
                                                                                                                     space: nil, state: .unread, answer: answer))
                        case .spaces, .archive: break
                        }
                        value.overlay = .library(library)
                    }
                    problems += rig.check("Library \(page.rawValue)", [rig.root.library as NSView] + [rig.overlay(LibraryConversationPreview.self)].compactMap { $0 as NSView? }, reach: 3)
                }
                rig.run(.library(.close))
                rig.run(.library(.openHistory))
                rig.render { value in
                    value.history = (0..<30).map { HistoryRow(url: URL(string: "https://example.com/\($0)")!, title: "Visited page \($0)",
                                                               visitedAt: Instant(milliseconds: rig.now.milliseconds - Int64($0) * 40 * minute)) }
                }
                problems += rig.check("History", [rig.root.history])
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// The AI panel: a conversation with the user's message, steps, an approval waiting, the reply and a page the agent made,
    /// chips waiting in the composer; then the list with a conversation in each state.
    func testTheAIPanelTakesThePointerAndReads() throws {
        let html = FileManager.default.temporaryDirectory.appendingPathComponent("brk-sweep-\(UUID().uuidString).html")
        try Data("<!doctype html><p>Checklist</p>".utf8).write(to: html)
        defer { try? FileManager.default.removeItem(at: html) }
        var problems: [String] = []
        for look in SurfaceChecks.looks {
            try SurfaceChecks.appearing(look.mac) {
                let rig = try SweepRig(look)
                defer { rig.close() }
                for feature in AIFeature.allCases { rig.run(.settings(.max(.feature(feature, !AIFeature.basicLayer.contains(feature))))) }
                rig.system(.aiProvidersDetected([.claude]))
                rig.run(.assist(.ask("Plan a weekend in Lisbon")))
                let request = try XCTUnwrap(rig.snapshot().ai?.request)
                let page = AIPageID("plan")
                rig.render { value in
                    let steps: [AIConversationItem] = [
                        .user("Plan a weekend in Lisbon"),
                        .step(AIAgentStep(id: "s1", title: "Search the web", state: .done, kind: .searchWeb, subject: "Lisbon weekend")),
                        .step(AIAgentStep(id: "s2", title: "Read tab", state: .failed, kind: .readTab, subject: "Timeout")),
                        .step(AIAgentStep(id: "s3", title: "Run a command", state: .running, kind: .command, subject: "ls")),
                        .approval(AIAgentApproval(id: "a1", title: "Run ls", detail: "ls ~/Desktop",
                                                  options: [.init(id: "y", title: "Allow once", kind: .allowOnce), .init(id: "n", title: "Deny", kind: .deny)],
                                                  kind: .command, subject: "ls ~/Desktop")),
                        .assistant("Here is a plan for two days, with a page to tick off."),
                        .page(AIPageRef(id: page, title: "Weekend checklist", height: 160)),
                        .notice("Claude stopped."),
                    ]
                    var conversation = value.ai?.conversation ?? AIConversationSnapshot(id: request)
                    conversation.items = steps
                    conversation.agent = .claude
                    conversation.agentName = "Claude"
                    conversation.attached = [AIAttachment(kind: .tab, id: "tab-1", title: "Flights to Lisbon", tabs: []),
                                             AIAttachment(kind: .folder, id: "folder-1", title: "Reading", tabs: [])]
                    value.ai?.conversation = conversation
                    value.ai?.pages = [AIPageSnapshot(id: page, title: "Weekend checklist", html: html, height: 160, data: nil, kept: false)]
                }
                problems += rig.check("AI conversation", [rig.overlay(AIPanelView.self)].compactMap { $0 }, reach: 5)

                rig.run(.assist(.panelPage(.list)))
                rig.render { value in
                    guard var panel = value.aiPanel else { return }
                    func row(_ id: String, _ title: String, _ state: AIThreadState, _ detail: String) -> AIThreadRow {
                        var row = AIThreadRow(id: AIRequestID(id), title: title, state: state, detail: detail, updatedAt: rig.now)
                        row.pill = state == .waiting ? "Approve" : nil
                        row.agent = "Claude"
                        return row
                    }
                    panel.strips = [row("o1", "Elsewhere", .waiting, "Wants to edit a file")]
                    panel.groups = [AIThreadGroup(kind: .needsUser, title: "Needs you", rows: [row("w1", "Plan the trip", .waiting, "Wants to run a command"),
                                                                                               row("u1", "Compare laptops", .unread, "Replied 2 minutes ago")]),
                                    AIThreadGroup(kind: .running, title: "Running", rows: [row("r1", "Summarise reading", .running, "Read 5 tabs")]),
                                    AIThreadGroup(kind: .today, title: "Today", rows: [row("i1", "Groceries", .idle, "11:32 · 1 AI page")])]
                    panel.waiting = 3
                    value.aiPanel = panel
                }
                problems += rig.check("AI list", [rig.overlay(AIPanelView.self)].compactMap { $0 }, reach: 5)
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// A window as an Arc import leaves it (the user's had hundreds of tabs: 5 Spaces, Pinned folders of 24, a Today of 60):
    /// only the visible rows and their neighbours have views, including after scrolling and switching Spaces. Counting
    /// those views catches the old cost per row directly, without timing other agents' work on this Mac.
    func testABigImportKeepsRowViewsNearTheVisiblePart() throws {
            let rig = try SweepRig()
            defer { rig.close() }
            var serial = 0
            func tab(_ host: String) -> ImportNode {
                serial += 1
                return .tab(title: "\(host) page \(serial)", url: URL(string: "https://\(host).example.com/\(serial)")!)
            }
            let spaces = (0..<5).map { index in
                ImportedSpace(key: "arc:\(index)", title: "Space \(index)",
                              theme: SpaceTheme(colors: [ThemePresets.drab[index]], texture: .grain, intensity: 0.25, appearance: .auto),
                              pinned: [.folder(title: "Docs", children: (0..<24).map { _ in tab("docs") }),
                                       .folder(title: "Work", children: (0..<24).map { _ in tab("work") })] + (0..<4).map { _ in tab("pin") },
                              today: [.split(orientation: .horizontal, panes: [tab("left"), tab("right")])] + (0..<60).map { _ in tab("today") })
            }
            let result = BrowserImportResult(source: "Arc", spaces: spaces, profiles: [ImportedProfileData(favorites: (0..<8).map { _ in tab("fav") })])
            rig.system(.sidebarData(.browserImported(rig.id, target: try XCTUnwrap(rig.state.sidebarImportTarget(in: rig.id)), result)))
            let dock = rig.snapshot().dock.map(\.id)
            XCTAssertEqual(dock.count, 6, "the import made its 5 Spaces")
            XCTAssertGreaterThanOrEqual(serial, 560)
            func rowViews(_ view: NSView) -> [RowView] {
                (view as? RowView).map { [$0] } ?? view.subviews.flatMap(rowViews)
            }
            for space in dock.suffix(5) {
                rig.run(.space(.focus(space)))
                rig.render()
                let list = rig.root.sidebar.tablist
                let height = list.contentView.bounds.height
                let bottom = max(0, (list.documentView?.bounds.height ?? 0) - height)
                let limit = Int(ceil(3 * height / Metrics.tablist.rowHeight.value)) + 4
                for y in [0, bottom / 2, bottom] {
                    list.contentView.scroll(to: CGPoint(x: 0, y: y))
                    list.reflectScrolledClipView(list.contentView)
                    let rows = rowViews(list)
                    XCTAssertGreaterThan(rows.count, 10, "the imported rows must actually be drawn")
                    XCTAssertLessThanOrEqual(rows.count, limit, "\(serial) tabs: \(rows.count) row views for a \(height)-point viewport")
                }
                XCTAssertGreaterThan(SurfaceChecks.sweep(list, in: rig.window), 10)
            }
    }
}
