import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Round 3, R3-1: the sidebar and window details compared with Arc 1.170 (verify/visual-pairs/run-20261103: Q02-b,
/// P23-c, P23-d, P27-b, P23-splitmenu). Owned loopback pages and this scenario's temporary data only.
enum SidebarWindowScenarios {
    static let all = [
        Scenario("SidebarWindow1", "a pinned folder tab held at the content edge narrows the page, rings the slot, lifts its row and carries Arc's card; the release splits", cefOnly: "native sidebar pointer drags and CEF surfaces", pinnedDrop),
        Scenario("SidebarWindow2", "the focused pane header carries translate, website controls, split menu and close at Arc's places; the menu's move and add commands", cefOnly: "native split pages", paneHeader),
        Scenario("SidebarWindow3", "a dock reorder drag carries the space in a capsule that follows the pointer and drops where it is released", cefOnly: "native pointer sequences", dockCapsule),
        Scenario("SidebarWindow4", "with Today emptied the divider and Clear are gone, New Tab sits under Pinned and the empty card shows", cefOnly: "native sidebar rows", emptyToday),
        // R4-12 (user reports; P23-e/f, P05-f, P07-b).
        Scenario("SidebarWindow5", "a Today tab held on the middle of another Today tab's row shows a slot in the half under the pointer; the release makes the split in the target's place on that side, two panes, the dragged one focused", cefOnly: "native sidebar pointer drags and CEF surfaces", rowJoin),
        Scenario("SidebarWindow6", "a pinned folder's tab dropped on the middle of a Today tab's row joins it in a split where the Today tab was", cefOnly: "native sidebar pointer drags and CEF surfaces", pinnedRowJoin),
        Scenario("SidebarWindow7", "a tab dropped on another row's upper or lower edge only reorders, and on a folder's middle goes into the folder; no slot, no split", cefOnly: "native sidebar pointer drags", rowEdges),
        Scenario("SidebarWindow8", "from 228 down to 164 in 16 pt steps the empty Favorites box shrinks with its badge, title, two lines and × inside it; Favorites tiles go two by two", cefOnly: "native sidebar layout", narrowSidebar),
    ]

    private static func pointer(_ app: AppUnderTest, _ phase: PointerPhase, _ point: CGPoint) throws {
        _ = try app.send(.pointer(window: app.window, phase: phase, point: point))
    }
    private static func near(_ a: Double, _ b: Double, _ slack: Double = 1) -> Bool { abs(a - b) <= slack }

    /// Target in Today, source in a pinned folder; returns (target, source).
    private static func pinnedPair(_ app: AppUnderTest) throws -> (ItemID, ItemID) {
        let targetURL = app.site.url("split-tools.html?target"), sourceURL = app.site.url("split-tools.html?pinned")
        let target = try app.load(targetURL)
        try app.waitForPageInput(PageID(window: app.window!, item: target), at: targetURL)
        let source = try app.load(sourceURL)
        try app.waitForPageInput(PageID(window: app.window!, item: source), at: sourceURL)
        try app.dispatch(.item(.newFolder))
        guard let folder = try app.view().space.pinned.rows.first(where: { $0.kind == .folder })?.id else { throw Check(description: "no pinned folder") }
        try app.dispatch(.item(.move(source, to: .into(parent: folder, index: 0))))
        try app.click(.row(target))
        try app.waitUntil("the Today tab to be shown") { try app.view().content.panes.map(\.tab) == [target] }
        return (target, source)
    }

    @Sendable static func pinnedDrop(_ app: AppUnderTest) throws {
        let (target, source) = try pinnedPair(app)
        let page = PageID(window: app.window!, item: target)
        let area = try app.native().computed.contentArea
        let row = try visible(app.native(), .row(source)).frame
        let before = try app.native().pages[page]?.surfaceFrame
        // Arc's P23-d hold: 196 in from the right edge, at mid height.
        let held = CGPoint(x: area.maxX - 196, y: area.midY)
        try pointer(app, .down, CGPoint(x: row.midX, y: row.midY))
        try pointer(app, .dragged, CGPoint(x: row.midX + 8, y: row.midY))
        try pointer(app, .dragged, CGPoint(x: (row.midX + held.x) / 2, y: (row.midY + held.y) / 2))
        try pointer(app, .dragged, held)
        // The rule reads the newest position once per 100 ms, as Arc's does.
        app.sleep(0.25)
        let n = try app.native()
        try expect(isShown(n, .splitDropPreview), "a pinned folder tab got no edge preview")
        let half = (area.width - Metrics.content.splitGap.value) / 2
        let card = try visible(n, .card(0)).frame, slot = try visible(n, .splitDropPreview).frame
        try expect(near(card.minX, area.minX) && near(card.width, half), "the page did not give up the right half: \(card) in \(area)")
        try expect(near(slot.maxX, area.maxX) && near(slot.width, half) && near(slot.height, area.height), "the slot \(slot) is not the right half")
        let during = n.pages[page]?.surfaceFrame
        try expect(during != nil && before != nil && near(during!.width, before!.width) && near(during!.height, before!.height),
                   "the page was resized for the preview: \(String(describing: before)) -> \(String(describing: during))")
        let dragCard = try visible(n, .tabTool("content-drag-card")).frame
        try expect(near(dragCard.midX, held.x) && near(dragCard.midY, held.y), "the drag card \(dragCard) is not centred on the pointer \(held)")
        try expect(near(dragCard.width, 169) && near(dragCard.height, 250), "the drag card is not Arc's 169 x 250: \(dragCard)")
        try expect(isShown(n, .rowClose(source)), "the lifted row shows no ×")
        try app.screenshot("pinned-drop-preview")
        try pointer(app, .up, held)
        // Arc keeps a pinned tab pinned and puts a new Today tab in the split (Q17-drop-pinned-right-half; a tab in a pinned
        // folder is treated the same, which has not been seen on Arc).
        try app.waitUntil("the release to split") { let panes = try app.view().content.panes; return panes.count == 2 && panes[0].tab == target && panes[1].tab != source }
        let view = try app.view()
        try expect(view.space.today.rows.contains { $0.id == view.content.split }, "the split is not where the Today tab was")
        try expect(view.space.pinned.rows.contains { row in
            if case .folder(let f) = row { return f.children.contains { $0.id == source } }
            return row.id == source
        }, "the dropped tab left Pinned")
        let after = try app.native()
        try expect(!isShown(after, .tabTool("content-drag-card")) && !isShown(after, .splitDropPreview), "drag feedback left behind")
        try app.screenshot("pinned-drop-split")
    }

    @Sendable static func paneHeader(_ app: AppUnderTest) throws {
        let first = try app.load(app.site.url("split-tools.html?left"))
        try app.waitForPageInput(PageID(window: app.window!, item: first), at: app.site.url("split-tools.html?left"))
        try app.dispatch(.split(.addPane))
        let rightURL = app.site.url("split-tools.html?right")
        try app.dispatch(.commandBar(.submit(rightURL.absoluteString)))
        let right = try app.view().content.panes.first(where: \.focused)!.tab
        try app.waitForPageInput(PageID(window: app.window!, item: right), at: rightURL)
        let n = try app.native()
        let card = try visible(n, .card(1)).frame
        let edge = Metrics.content.paneHeaderEdge.value, pitch = Metrics.content.paneHeaderButtonPitch.value
        let close = card.maxX - edge, split = close - 32, site = split - pitch, translate = site - pitch
        for (id, x) in [(ViewID.tabTool("pane-split-menu"), split), (.paneSiteInfo, site), (.tabTool("pane-translate"), translate)] {
            let frame = try visible(n, id).frame
            try expect(near(frame.midX, x) && frame.minX > card.midX, "\(id.identifier) at \(frame.midX), Arc's place is \(x)")
        }
        try app.screenshot("pane-header")
        // The split menu's rows (unit-tested in SplitDropPreviewTests) dispatch these commands.
        try app.dispatch(.split(.movePane(.next)))
        try expect(try app.view().content.panes.map(\.tab) == [first, right], "Move Right moved the last pane")
        try app.dispatch(.split(.movePane(.previous)))
        try expect(try app.view().content.panes.map(\.tab) == [right, first], "Move Left did not move the pane")
        try expect(try app.view().content.panes.first(where: \.focused)?.tab == right, "Move Left lost the focus")
        try app.waitForPageInput(PageID(window: app.window!, item: right), at: rightURL)
        try app.dispatch(.split(.addPaneBefore))
        let panes = try app.view().content.panes
        try expect(panes.count == 3 && panes[1].tab == right && panes[2].tab == first && panes[0].focused, "Add Left Split did not add before the pane: \(panes.map(\.tab))")
        try app.dispatch(.commandBar(.dismiss))
        try app.screenshot("pane-moved-and-added")
    }

    @Sendable static func dockCapsule(_ app: AppUnderTest) throws {
        let first = try app.view().space.id
        let second = try createSpace(app, title: "Second")
        try app.dispatch(.settings(.advanced(.hapticsOnReorder(false))))
        let f = try app.native().computed.sidebar!
        let cell = f.dockSpaces[second]!, start = CGPoint(x: cell.midX, y: cell.midY)
        let held = CGPoint(x: f.dockSpaces[first]!.midX - 15, y: start.y)
        try pointer(app, .down, start)
        try pointer(app, .dragged, CGPoint(x: start.x - 10, y: start.y))
        try pointer(app, .dragged, held)
        let n = try app.native()
        let capsule = try visible(n, .tabTool("dock-reorder-capsule")).frame
        try expect(near(capsule.midX, held.x, 1.5) && near(capsule.width, cell.width) && near(capsule.height, cell.height),
                   "the capsule \(capsule) does not ride the pointer at \(held)")
        try app.screenshot("dock-reorder-capsule")
        try pointer(app, .up, held)
        try expect(try app.view().dock.map(\.id) == [second, first], "the capsule's release did not reorder")
        try expect(!isShown(try app.native(), .tabTool("dock-reorder-capsule")), "the capsule stayed after the release")
    }

    @Sendable static func emptyToday(_ app: AppUnderTest) throws {
        // A pinned folder (never shown) and Today tabs; then every Today tab closes, as Arc's Q02-b.
        try app.dispatch(.item(.newFolder))
        guard let folder = try app.view().space.pinned.rows.first(where: { $0.kind == .folder })?.id else { throw Check(description: "no pinned folder") }
        _ = try app.load(app.site.url("split-tools.html?today"))
        try app.waitUntil("Today to hold a tab") { try !app.view().space.today.rows.isEmpty }
        for row in try app.view().space.today.rows { try app.dispatch(.tab(.close(.item(row.id)))) }
        try app.waitUntil("Today to be empty and nothing shown") {
            let v = try app.view()
            return v.space.today.rows.isEmpty && v.content.panes.isEmpty
        }
        let n = try app.native()
        try expect(!isShown(n, .todayClear), "the Pinned/Today divider's Clear still shows")
        let newTab = try visible(n, .todayNewTab).frame, row = try visible(n, .row(folder)).frame
        try expect(near(newTab.minY - row.maxY, Metrics.tablist.rowSpacing.value), "New Tab is not right under Pinned: \(row) then \(newTab)")
        try expect(isShown(n, .card(0)), "no empty card")
        try app.screenshot("today-empty")
    }

    // MARK: R4-12

    private static func joinSlot(_ row: ItemID) -> ViewID { .tabTool("split-join-slot-" + row.rawValue) }

    /// Press on `source`'s row and drag in steps to `held` (window points), staying pressed.
    private static func press(_ app: AppUnderTest, row source: ItemID, to held: CGPoint) throws {
        let row = try visible(app.native(), .row(source)).frame
        try pointer(app, .down, CGPoint(x: row.midX, y: row.midY))
        try pointer(app, .dragged, CGPoint(x: row.midX + 4, y: row.midY + (held.y > row.midY ? 4 : -4)))
        try pointer(app, .dragged, CGPoint(x: (row.midX + held.x) / 2, y: (row.midY + held.y) / 2))
        try pointer(app, .dragged, held)
    }

    /// A point `fraction` of the way down `item`'s row (0 is its top).
    private static func onRow(_ app: AppUnderTest, _ item: ItemID, _ fraction: Double, dx: Double = 0) throws -> CGPoint {
        let row = try visible(app.native(), .row(item)).frame
        return CGPoint(x: row.midX + dx, y: row.minY + row.height * fraction)
    }

    private static func loadTabs(_ app: AppUnderTest, _ names: [String]) throws -> [ItemID] {
        try names.map { name in
            let url = app.site.url("split-tools.html?" + name)
            let tab = try app.load(url)
            try app.waitForPageInput(PageID(window: app.window!, item: tab), at: url)
            return tab
        }
    }

    /// Asserts Arc's slot in `target`'s left half while the drag is held (Q15-a), with the row image at the pointer and
    /// the dragged row lifted in place with its ×.
    private static func expectLeftSlot(_ app: AppUnderTest, over target: ItemID, dragging source: ItemID) throws {
        let n = try app.native()
        let slot = try visible(n, joinSlot(target)).frame, row = try visible(n, .row(target)).frame
        try expect(near(slot.minX, row.minX + 14) && near(slot.maxX, row.minX + 114) && slot.height == 36 && slot.minY > row.minY && slot.maxY < row.maxY,
                   "the slot \(slot) is not the left half of \(row)")
        try expect(isShown(n, .tabTool("drag-image")), "the row image is not at the pointer")
        try expect(isShown(n, .rowClose(source)), "the dragged row is not lifted with its ×")
    }

    @Sendable static func rowJoin(_ app: AppUnderTest) throws {
        let tabs = try loadTabs(app, ["inbox", "long", "secondary"])
        let inbox = tabs[0], secondary = tabs[2]
        let before = try app.view().space.today.rows.map(\.id)
        guard let at = before.firstIndex(of: secondary) else { throw Check(description: "no Secondary row") }
        let held = try onRow(app, secondary, 0.5, dx: -40)
        try press(app, row: inbox, to: held)
        try expectLeftSlot(app, over: secondary, dragging: inbox)
        try app.screenshot("row-join-slot")
        try pointer(app, .up, held)
        try app.waitUntil("the release to join the two tabs") { try app.view().content.panes.map(\.tab) == [inbox, secondary] }
        let view = try app.view()
        guard let split = view.content.split else { throw Check(description: "no split shown") }
        try expect(view.space.today.rows.map(\.id) == before.filter { $0 != inbox }.map { $0 == secondary ? split : $0 },
                   "the split is not where Secondary was (index \(at)): \(view.space.today.rows.map(\.id))")
        try expect(view.content.panes.first(where: \.focused)?.tab == inbox, "the dragged tab is not the focused pane")
        let n = try app.native()
        try expect(!isShown(n, .tabTool("split-join-band")), "the band stayed after the release")
        let left = try visible(n, .card(0)).frame, right = try visible(n, .card(1)).frame
        try expect(left.maxX < right.minX && near(left.width, right.width, 2), "the content is not two side-by-side panes: \(left) \(right)")
        try expect(isShown(n, .splitSegment(inbox)) && isShown(n, .splitSegment(secondary)), "the sidebar row is not one split row of the two tabs")
        let menu = try visible(n, .tabTool("pane-split-menu")).frame
        try expect(menu.minX > left.midX && menu.maxX <= left.maxX, "the focused pane's header buttons are not on the left pane: \(menu) in \(left)")
        for (pane, page) in [(inbox, "inbox"), (secondary, "secondary")] {
            try app.waitUntil("\(page) to be on screen in its pane") { try app.native().pages[PageID(window: app.window!, item: pane)]?.surfaceFrame != nil }
        }
        try app.screenshot("row-join-split")
    }

    @Sendable static func pinnedRowJoin(_ app: AppUnderTest) throws {
        let (target, source) = try pinnedPair(app)
        let held = try onRow(app, target, 0.5, dx: -40)
        try press(app, row: source, to: held)
        try expectLeftSlot(app, over: target, dragging: source)
        try app.screenshot("pinned-row-join-slot")
        try pointer(app, .up, held)
        try app.waitUntil("the release to join the pinned tab") { try app.view().content.panes.map(\.tab) == [source, target] }
        let view = try app.view()
        try expect(view.space.today.rows.contains { $0.id == view.content.split }, "the split is not in Today where the target was")
        try expect(!view.space.pinned.rows.contains { row in
            if case .folder(let f) = row { return f.children.contains { $0.id == source } }
            return row.id == source
        }, "the dropped tab is still in Pinned")
        try app.screenshot("pinned-row-join-split")
    }

    @Sendable static func rowEdges(_ app: AppUnderTest) throws {
        let tabs = try loadTabs(app, ["a", "b", "c"])
        let a = tabs[0], b = tabs[1], c = tabs[2]
        // Today, newest first: c, b, a, then whatever the window opened with.
        func order() throws -> [ItemID] { try app.view().space.today.rows.map(\.id).filter { tabs.contains($0) } }
        let start = try order()
        try expect(start == [c, b, a], "unexpected start order \(start)")
        // a onto c's upper quarter: before c.
        var held = try onRow(app, c, 0.12)
        try press(app, row: a, to: held)
        try expect(!isShown(try app.native(), joinSlot(c)), "a slot on the row's upper edge")
        try app.screenshot("row-edge-reorder")
        try pointer(app, .up, held)
        try app.waitUntil("a to move above c") { try order() == [a, c, b] }
        try expect(try app.view().content.split == nil, "an edge drop made a split")
        // a onto b's lower quarter: after b.
        held = try onRow(app, b, 0.88)
        try press(app, row: a, to: held)
        try expect(!isShown(try app.native(), joinSlot(b)), "a slot on the row's lower edge")
        try pointer(app, .up, held)
        try app.waitUntil("a to move below b") { try order() == [c, b, a] }
        // a onto a pinned folder's middle: into the folder.
        try app.dispatch(.item(.newFolder))
        try app.dispatch(.commandBar(.dismiss))
        guard let folder = try app.view().space.pinned.rows.first(where: { $0.kind == .folder })?.id else { throw Check(description: "no pinned folder") }
        try app.dispatch(.item(.rename(folder, title: "Folder")))
        held = try onRow(app, folder, 0.5)
        try press(app, row: a, to: held)
        try expect(!isShown(try app.native(), joinSlot(folder)), "a slot on a folder")
        try pointer(app, .up, held)
        try app.waitUntil("a to go into the folder") {
            guard case .folder(let f)? = try app.view().space.pinned.rows.first(where: { $0.id == folder }) else { return false }
            return f.children.map(\.id) == [a]
        }
        try expect(try app.view().content.split == nil, "a folder drop made a split")
    }

    @Sendable static func narrowSidebar(_ app: AppUnderTest) throws {
        let parts = ["favorites-empty-badge", "favorites-empty-title", "favorites-empty-subtitle", "favorites-empty-close"].map(ViewID.tabTool)
        try app.waitUntil("the empty Favorites box") { try isShown(app.native(), parts[1]) }
        for width in stride(from: Metrics.sidebar.defaultWidth.value, through: Metrics.sidebar.minWidth.value, by: -16) {
            try app.dispatch(.sidebar(.resize(width: width)))
            try app.waitUntil("the sidebar at \(width)") { (try app.native().computed.sidebar?.frame.width).map(Double.init) == width }
            let n = try app.native()
            guard let f = n.computed.sidebar else { throw Check(description: "no sidebar") }
            let box = FavoritesGrid.emptyBox(width: f.favoritesTray.width).box.offsetBy(dx: f.favoritesTray.minX, dy: f.favoritesTray.minY)
            for part in parts {
                let frame = try visible(n, part).frame
                try expect(box.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(part.identifier) \(frame) leaves the box \(box) at \(width)")
            }
            try expect(box.maxY <= f.spaceHeader.minY, "the box \(box) reaches the space header \(f.spaceHeader) at \(width)")
            try app.screenshot("narrow-\(Int(width))-empty")
        }
        // Four Favorites at the narrowest width: two rows of two.
        let root = try app.view().favorites.root
        for (i, name) in ["w", "m", "g", "a"].enumerated() {
            let url = app.site.url("split-tools.html?fav-" + name)
            let tab = try app.load(url)
            try app.waitForPageInput(PageID(window: app.window!, item: tab), at: url)
            try app.dispatch(.item(.move(tab, to: .into(parent: root, index: i))))
        }
        try app.waitUntil("four Favorites") { try app.view().favorites.tiles.count == 4 }
        let n = try app.native()
        let tiles = try app.view().favorites.tiles.map { try visible(n, .favorite($0.id)).frame }
        try expect(Set(tiles.map(\.minX)).count == 2 && Set(tiles.map(\.minY)).count == 2, "Favorites are not two by two at 164: \(tiles)")
        try app.screenshot("narrow-164-favorites")
        try app.dispatch(.sidebar(.resize(width: Metrics.sidebar.defaultWidth.value)))
    }
}
