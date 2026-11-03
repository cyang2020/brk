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
        // Arc's P23-d hold: 196 in from the right edge, at mid height (inside the right quarter).
        let held = CGPoint(x: area.maxX - 196, y: area.midY)
        try pointer(app, .down, CGPoint(x: row.midX, y: row.midY))
        try pointer(app, .dragged, CGPoint(x: row.midX + 8, y: row.midY))
        try pointer(app, .dragged, CGPoint(x: (row.midX + held.x) / 2, y: (row.midY + held.y) / 2))
        try pointer(app, .dragged, held)
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
        try app.waitUntil("the release to split") { try app.view().content.panes.map(\.tab) == [target, source] }
        let view = try app.view()
        try expect(view.space.today.rows.contains { $0.id == view.content.split }, "the split is not where the Today tab was")
        try expect(!view.space.pinned.rows.contains { row in
            if case .folder(let f) = row { return f.children.contains { $0.id == source } }
            return row.id == source
        }, "the dropped tab is still in Pinned")
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
}
