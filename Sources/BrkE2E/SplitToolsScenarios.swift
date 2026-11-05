import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation

enum SplitToolsScenarios {
    static let all = [
        Scenario("SplitTools1", "four native panes edit independently, resize in both orientations, restore and close", cefOnly: "native split pages and pointer dividers", geometry),
        Scenario("SplitTools2", "native content-edge drags preview, cancel, group and respect the four-pane cap", cefOnly: "native sidebar pointer drags", drops),
        Scenario("SplitTools3", "two windows retain local focus, addresses and DOM across expand, separate and separate all", cefOnly: "window-owned CEF pages", tools),
        Scenario("SplitTools4", "private split controls preserve session scope and suppress saved metadata", cefOnly: "private CEF panes", privacy),
        Scenario("SplitTools5", "an accepted POST download keeps its original browser through expand and separation", cefOnly: "actual transfer bytes and original request", transfer),
        Scenario("SplitTools6", "closing pinned panes keeps their rows and addresses through singleton dissolution and restart", cefOnly: "native pinned split closure", pinnedClose),
    ]

    private static func send(_ app: AppUnderTest, _ window: WindowID, _ command: Command) throws {
        _ = try app.send(.dispatch(window: window, command: command))
    }

    private static func pointer(_ app: AppUnderTest, _ phase: PointerPhase, _ point: CGPoint, window: WindowID? = nil) throws {
        _ = try app.send(.pointer(window: window ?? app.window, phase: phase, point: point))
    }

    private static func drag(_ app: AppUnderTest, from: CGPoint, to: CGPoint) throws {
        try pointer(app, .down, from)
        for step in 1...8 {
            let t = Double(step) / 8
            try pointer(app, .dragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            app.sleep(0.03)
        }
        // The drop rule reads the newest position once per 100 ms, as Arc's does: let it read the last one.
        app.sleep(0.15)
        try pointer(app, .up, to)
    }

    private static func title(_ app: AppUnderTest, _ page: PageID, _ title: String) throws {
        try app.waitUntil("\(page) DOM title \(title)") { try tab(page.item, in: app.view(page.window))?.title == title }
    }

    private static func add(_ app: AppUnderTest, number: Int) throws -> ItemID {
        try app.press("ctrl+shift+=")
        try app.waitUntil("new pane command bar") { isCommandBar(try app.view().overlay) }
        let url = app.site.url("split-tools.html?pane=\(number)")
        try app.type(url.absoluteString); try app.press("return")
        let pane = try app.view().content.panes.first(where: \.focused)!.tab
        try app.waitForPageInput(PageID(window: app.window!, item: pane), at: url)
        return pane
    }

    private static func fill(_ app: AppUnderTest, pane index: Int, text: String) throws {
        let view = try app.view(), pane = view.content.panes[index].tab
        let native = try app.native()
        _ = try visible(native, .card(index))
        // The page starts under the pane's own header (Arc's split panes each have one).
        guard let page = native.computed.cards.first(where: { $0.pane == index })?.page else { throw Check(description: "no card \(index)") }
        try app.click(at: CGPoint(x: page.minX + 42, y: page.minY + 99))
        try app.waitUntil("pointer focus in pane \(index)") { try app.native().focusedPage == PageID(window: view.id, item: pane) }
        try app.type(text)
        try title(app, PageID(window: view.id, item: pane), "Split text:" + text)
        try expect(try app.view().content.panes.first(where: \.focused)?.tab == pane, "pointer did not select the pane")
    }

    private static func geometry(_ app: AppUnderTest) throws {
        let first = try app.load(app.site.url("split-tools.html?pane=1"))
        try app.waitForPageInput(PageID(window: app.window!, item: first), at: app.site.url("split-tools.html?pane=1"))
        for n in 2...4 { _ = try add(app, number: n) }
        let panes = try app.view().content.panes.map(\.tab)
        try expect(panes.count == 4, "four panes missing")
        for index in 0...3 { try fill(app, pane: index, text: "pane\(index)") }
        try app.press("ctrl+alt+1")
        try expect(try app.view().content.panes.first(where: \.focused)?.tab == panes[0], "numbered pane shortcut missed")
        try app.press("ctrl+alt+left")
        try expect(try app.view().content.panes.first(where: \.focused)?.tab == panes[0], "previous pane wrapped")
        try app.press("ctrl+alt+right")
        try expect(try app.view().content.panes.first(where: \.focused)?.tab == panes[1], "next pane missed")
        try app.press("ctrl+alt+4")
        try app.press("cmd+l"); try app.type(app.site.url("held-document").absoluteString); try app.press("return")
        try app.waitUntil("a split segment reports the actual pending document") { try tab(panes[3], in: app.view())?.loading == true }
        try app.screenshot("four-segment-loading")
        app.site.releaseHeldDocument()
        try app.settle()
        let before = try app.view().content.panes.map(\.fraction)
        var divider = try visible(app.native(), .divider(0)).frame
        try drag(app, from: CGPoint(x: divider.midX, y: divider.midY), to: CGPoint(x: divider.midX + 65, y: divider.midY))
        let horizontal = try app.view().content.panes.map(\.fraction)
        try expect(horizontal[0] > before[0] + 0.03 && horizontal[1] < before[1], "horizontal divider did not resize adjacent panes")
        try expect(abs(horizontal[2] - before[2]) < 0.001, "horizontal drag resized a nonadjacent pane")
        try app.screenshot("four-horizontal")
        try app.flush(); try app.restart()
        try expect(try app.view().content.orientation == .horizontal && app.view().content.panes.map(\.fraction) == horizontal,
                   "restart lost horizontal divider fractions")
        try SplitParentScenarios.splitTool(app, .splitVertical)
        try expect(try app.view().content.orientation == .vertical, "orientation button did not stack panes")
        try app.waitUntil("the stacked dividers on screen") {
            let frame = try visible(app.native(), .divider(1)).frame
            return frame.width > frame.height
        }
        divider = try visible(app.native(), .divider(1)).frame
        try drag(app, from: CGPoint(x: divider.midX, y: divider.midY), to: CGPoint(x: divider.midX, y: divider.midY + 36))
        var vertical = try app.view().content.panes.map(\.fraction)
        try expect(vertical[1] > horizontal[1] && vertical[2] < horizontal[2], "stacked divider did not resize")
        let native = try app.native(), frame = native.windowFrame
        try app.setWindowFrame(CGRect(x: frame.minX, y: frame.minY, width: frame.width - 120, height: frame.height - 80))
        divider = try visible(app.native(), .divider(1)).frame
        try drag(app, from: CGPoint(x: divider.midX, y: divider.midY), to: CGPoint(x: divider.midX, y: divider.midY - 12))
        vertical = try app.view().content.panes.map(\.fraction)
        try app.screenshot("four-vertical-resized")
        try app.flush(); try app.restart()
        try expect(try app.view().content.orientation == .vertical, "restart lost stacked layout")
        try expect(try app.view().content.panes.map(\.fraction) == vertical, "restart lost divider fractions")
        for pane in panes { try app.click(.splitSegment(pane)); try expect(try app.view().content.panes.first(where: \.focused)?.tab == pane, "sidebar segment missed \(pane)") }
        try app.click(.rowClose(panes[0]))
        try expect(try app.view().content.panes.count == 3, "pointer close did not remove first pane")
        for pane in panes.dropFirst() {
            try expect(try app.native().pages[PageID(window: app.window!, item: pane)]?.surfaceFrame != nil, "closing first pane detached a surviving page")
        }
        try app.press("ctrl+shift+-"); try app.press("ctrl+shift+-")
        try expect(try app.view().content.split == nil && app.view().content.panes.count == 1, "one-pane split did not dissolve")
        try app.recordWindows("after-close")
    }

    private static func drops(_ app: AppUnderTest) throws {
        let target = try app.load(app.site.url("split-tools.html?target"))
        try app.waitForPageInput(PageID(window: app.window!, item: target), at: app.site.url("split-tools.html?target"))
        let source = try app.load(app.site.url("split-tools.html?source"))
        try app.waitForPageInput(PageID(window: app.window!, item: source), at: app.site.url("split-tools.html?source"))
        try app.click(.row(target))
        var area = try app.native().computed.contentArea
        var row = try visible(app.native(), .row(source)).frame
        let origin = CGPoint(x: row.midX, y: row.midY), edge = CGPoint(x: area.maxX - 12, y: area.midY)
        try pointer(app, .down, origin); try pointer(app, .dragged, edge)
        try expect(isShown(try app.native(), .splitDropPreview), "content edge has no visible preview")
        try app.screenshot("drop-preview")
        try app.press("escape"); try pointer(app, .up, edge)
        try expect(try app.view().content.split == nil, "Escape committed a cancelled drag")
        try expect(!isShown(try app.native(), .splitDropPreview), "Escape left preview behind")
        // Past the middle of the page (from the left, a slot that shows holds up to the middle): the frame. No split, the
        // dragged tab is the current one (Arc, Q17-drop-tab-framed-middle).
        try drag(app, from: origin, to: CGPoint(x: area.midX + 40, y: area.midY))
        try expect(try app.view().content.split == nil, "center drop created a split")
        try expect(try app.view().content.panes.map(\.tab) == [source], "center drop did not show the dragged tab")
        try app.click(.row(target))
        let idsBefore = try app.pageLog().filter { $0.kind == .created && ($0.page.item == target || $0.page.item == source) }
        try drag(app, from: origin, to: edge)
        try expect(try app.view().content.panes.map(\.tab) == [target, source], "right-edge pointer drag did not group tabs")
        try expect(try app.pageLog().filter { $0.kind == .created && ($0.page.item == target || $0.page.item == source) } == idsBefore,
                   "drop replaced an original browser or changed its generation")
        try SplitParentScenarios.splitTool(app, .separateAllSplit); try app.click(.row(target))
        row = try visible(app.native(), .row(source)).frame
        area = try app.native().computed.contentArea
        try drag(app, from: CGPoint(x: row.midX, y: row.midY), to: CGPoint(x: area.minX + 12, y: area.midY))
        try expect(try app.view().content.panes.map(\.tab) == [source, target], "left-edge pointer drag did not prepend the source")
        for n in 3...4 {
            let split = try app.view().content.split!
            let tab = try app.load(app.site.url("split-tools.html?drag=\(n)"))
            try app.waitForPageInput(PageID(window: app.window!, item: tab), at: app.site.url("split-tools.html?drag=\(n)"))
            try app.click(.row(split))
            area = try app.native().computed.contentArea
            row = try visible(app.native(), .row(tab)).frame
            // In a side by side split only its own axis has zones (Arc 0x100a46638): at most 80 pt from a pane's sides.
            let end = n == 3 ? CGPoint(x: area.midX + 8, y: area.minY + 12) : CGPoint(x: area.maxX - 12, y: area.midY)
            try drag(app, from: CGPoint(x: row.midX, y: row.midY), to: end)
            try expect(try app.view().content.panes.count == n && app.view().content.orientation == .horizontal, "a side zone failed to extend the split")
            if n == 3 { try expect(try app.view().content.panes[1].tab == tab, "a slot between the panes did not take its index") }
        }
        let split = try app.view().content.split!
        let fifth = try app.load(app.site.url("split-tools.html?fifth"))
        try app.click(.row(split))
        row = try visible(app.native(), .row(fifth)).frame
        area = try app.native().computed.contentArea
        try drag(app, from: CGPoint(x: row.midX, y: row.midY), to: CGPoint(x: area.minX + 12, y: area.midY))
        try expect(try app.view().content.panes.count == 4, "drag exceeded four panes")
        try expect(!isShown(try app.native(), .splitDropPreview), "cap rejection left feedback")
        try app.recordWindows("four-dropped-panes")
    }

    private static func tools(_ app: AppUnderTest) throws {
        let first = try app.load(app.site.url("split-tools.html?first"))
        try app.waitForPageInput(PageID(window: app.window!, item: first), at: app.site.url("split-tools.html?first"))
        let second = try add(app, number: 2), third = try add(app, number: 3)
        let window = app.window!, split = try app.view().content.split!
        try app.press("cmd+d")
        try expect(try app.view().space.pinned.rows.contains { $0.id == split }, "pinning did not retain the complete split")
        try app.dispatch(.window(.new))
        guard case .hello(let hello) = try app.send(.hello), let other = hello.windows.first(where: { $0 != window }) else { throw Check(description: "second window missing") }
        try send(app, other, .tab(.focus(second)))
        try send(app, other, .commandBar(.open(.editCurrent)))
        let otherURL = app.site.url("split-tools.html?other-window")
        try send(app, other, .commandBar(.submit(otherURL.absoluteString)))
        try app.waitForPageInput(PageID(window: other, item: second), at: otherURL)
        _ = try app.send(.activate(window: window))
        try app.click(.splitSegment(third))
        let identities = try app.native(window).pages.mapValues(\.browserID)
        try SplitParentScenarios.splitTool(app, .maximizeSplitPane)
        try expect(try app.view(window).content.expanded, "expand control missed")
        try expect(try app.native(window).computed.cards.count == 1 && app.native(window).computed.dividers.isEmpty, "expanded presentation still tiled")
        try expect(try !app.view(other).content.expanded && app.view(other).content.panes.first(where: \.focused)?.tab == second, "expansion changed the other window")
        try app.press("ctrl+alt+1")
        try expect(try app.native(window).focusedPage == PageID(window: window, item: first), "expanded pane shortcut did not focus")
        try SplitParentScenarios.splitTool(app, .maximizeSplitPane)
        try expect(try app.native(window).pages.mapValues(\.browserID) == identities, "expand/restore replaced pages")
        try app.click(.splitSegment(third)); try fill(app, pane: 2, text: "survives")
        try SplitParentScenarios.splitTool(app, .separateTabFromSplitView)
        try expect(try app.view(window).content.panes.map(\.tab) == [third], "Separate did not select original pane")
        try title(app, PageID(window: window, item: third), "Split text:survives")
        try expect(try app.view(other).content.split == split && app.view(other).content.panes.first(where: \.focused)?.tab == second, "Separate changed other window selection")
        try app.click(.row(split)); try SplitParentScenarios.splitTool(app, .separateAllSplit)
        try expect(try app.view(other).content.panes.map(\.tab) == [second], "Separate All lost other focused page")
        try expect(try tab(second, in: app.view(other))?.url == otherURL, "Separate All lost window-local address")
        try expect(try app.view(window).space.pinned.rows.map(\.id) == [first, second, third], "separation changed pinned pane order")
        app.window = window
        try app.perform(.activate(window: window))
        let local = try app.view(window).content.panes[0].tab
        let localURL = try tab(local, in: app.view(window))!.url!
        try app.waitForPageInput(PageID(window: window, item: local), at: localURL)
        try fill(app, pane: 0, text: "first-separated")
        app.window = other
        try app.perform(.activate(window: other))
        try app.waitForPageInput(PageID(window: other, item: second), at: otherURL)
        try fill(app, pane: 0, text: "second-separated")
        try title(app, PageID(window: window, item: local), "Split text:first-separated")
        try title(app, PageID(window: other, item: second), "Split text:second-separated")
        app.window = window
        try app.recordWindows("separated")
        try app.flush(); try app.restart()
        try expect(try app.view(other).content.panes.map(\.tab) == [second], "restart lost separate window selection")
        try expect(try tab(second, in: app.view(other))?.url == otherURL, "restart lost separate address")
    }

    private static func privacy(_ app: AppUnderTest) throws {
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello), let owner = hello.windows.first(where: { (try? app.view($0).kind) == .incognito }) else { throw Check(description: "private window missing") }
        _ = try app.send(.activate(window: owner))
        try send(app, owner, .commandBar(.submit(app.site.url("split-tools.html?private-one").absoluteString)))
        let first = try app.view(owner).content.panes[0].tab
        try app.waitForPageInput(PageID(window: owner, item: first), at: app.site.url("split-tools.html?private-one"))
        try app.press("ctrl+shift+=")
        try app.type(app.site.url("split-tools.html?private-two").absoluteString); try app.press("return")
        let second = try app.view(owner).content.panes[1].tab
        try app.waitForPageInput(PageID(window: owner, item: second), at: app.site.url("split-tools.html?private-two"))
        // The split's own controls act on the private window (the scenario's main window is the public one).
        try send(app, owner, ActionID.splitVertical.spec.command)
        try expect(try app.view(owner).content.orientation == .vertical, "private orientation control failed")
        try send(app, owner, .split(.toggleExpanded)); try send(app, owner, .split(.restore))
        try app.press("ctrl+alt+1")
        try app.press("ctrl+shift+-")
        try expect(try app.view(owner).content.split == nil, "private singleton did not dissolve")
        try app.flush()
        let saved = try String(contentsOf: app.dataDirectory.appendingPathComponent("state.json"), encoding: .utf8)
        try expect(!saved.contains("private-one") && !saved.contains("private-two"), "private split metadata persisted")
        try app.recordWindows("private-singleton")
        try send(app, owner, .window(.close))
    }

    private static func transfer(_ app: AppUnderTest) throws {
        let directory = app.dataDirectory.appendingPathComponent("split-downloads", isDirectory: true)
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(directory.path))))
        let first = try app.load(app.site.url("split-tools.html?transfer-source"))
        let page = PageID(window: app.window!, item: first)
        try app.waitForPageInput(page, at: app.site.url("split-tools.html?transfer-source"))
        _ = try add(app, number: 2)
        try app.click(.splitSegment(first))
        let browser = try app.native().pages[page]?.browserID
        let address = String(data: try JSONEncoder().encode(app.site.url("transfer-post-split").absoluteString), encoding: .utf8)!
        try app.evaluate(page, "(()=>{let f=document.createElement('form');f.method='POST';f.action=\(address);f.innerHTML='<input name=secret value=original-body>';document.body.append(f);f.submit()})()")
        try app.dispatch(.library(.open(.downloads)))
        try app.waitUntil("accepted POST transfer receives bytes") {
            guard case .library(let library)? = try app.view().overlay else { return false }
            return library.downloads.contains { $0.filename == "transfer-post-split.bin" && $0.state == .inProgress && $0.received > 0 }
        }
        try app.dispatch(.library(.close))
        try SplitParentScenarios.splitTool(app, .maximizeSplitPane); try SplitParentScenarios.splitTool(app, .maximizeSplitPane)
        try SplitParentScenarios.splitTool(app, .separateTabFromSplitView)
        try expect(try app.native().pages[page]?.browserID == browser, "split tools replaced the download's browser")
        try app.dispatch(.library(.open(.downloads)))
        try app.waitUntil("POST transfer completes after separation", timeout: 18) {
            guard case .library(let library)? = try app.view().overlay else { return false }
            return library.downloads.contains { $0.filename == "transfer-post-split.bin" && $0.state == .finished }
        }
        let receipt = try Data(contentsOf: directory.appendingPathComponent("transfer-post-split.bin"))
        try expect(receipt == Data(repeating: 80, count: 4_194_304), "POST receipt bytes differ")
        try expect(app.site.requestCount("/transfer-post-split-valid-post") == 1, "split tools replayed the POST request")
        try expect(app.site.requestCount("/transfer-post-split-complete") == 1, "server did not complete the original transfer")
        try receipt.write(to: app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("split-post-receipt.bin"))
        try app.recordWindows("original-post-complete")
        app.note("One validated POST request; 4,194,304 P bytes; original browser \(String(describing: browser)) survived expand, restore and separation.")
    }

    private static func pinnedClose(_ app: AppUnderTest) throws {
        let first = try app.load(app.site.url("split-tools.html?pinned-first"))
        try app.waitForPageInput(PageID(window: app.window!, item: first), at: app.site.url("split-tools.html?pinned-first"))
        for number in 2...4 { _ = try add(app, number: number) }
        let panes = try app.view().content.panes.map(\.tab)
        let addresses = try panes.map { try tab($0, in: app.view())?.url }
        try app.press("cmd+d")
        for count in stride(from: 3, through: 1, by: -1) {
            try app.press("ctrl+shift+-")
            try expect(try app.view().content.panes.count == count, "pinned close did not remove a content pane")
        }
        try expect(try app.view().content.split == nil, "pinned singleton did not dissolve")
        try expect(try app.view().space.pinned.rows.map(\.id) == panes, "pinned close lost or reordered retained rows")
        try app.waitUntil("closed pinned panes release presentation") {
            let facts = try app.native()
            return panes.dropFirst().allSatisfy { facts.pages[PageID(window: app.window!, item: $0)] == nil }
        }
        try app.flush(); try app.restart()
        try expect(try app.view().space.pinned.rows.map(\.id) == panes, "restart lost pinned rows")
        try expect(try panes.map { try tab($0, in: app.view())?.url } == addresses, "restart lost retained pinned addresses")
        try app.recordWindows("pinned-retained")
    }
}
