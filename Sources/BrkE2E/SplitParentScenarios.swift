import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation

enum SplitParentScenarios {
    static let all = [
        Scenario("SplitFind", "Find follows pane four through expand, orientation and separation", cefOnly: "native Find/split integration", findAndTools),
        Scenario("SplitBackground", "background pane close preserves lazy demand and stationary drag feedback survives title changes", cefOnly: "native split callbacks", backgroundAndFeedback),
    ]

    private static func pointer(_ app: AppUnderTest, _ phase: PointerPhase, _ point: CGPoint) throws {
        _ = try app.send(.pointer(window: app.window, phase: phase, point: point))
    }

    private static func toolbarAvoidsFind(_ app: AppUnderTest) throws {
        let native = try app.native()
        let bar = try visible(native, .findBar).frame
        for action in [ActionID.splitHorizontal, .splitVertical, .maximizeSplitPane, .separateTabFromSplitView, .separateAllSplit] {
            let button = try visible(native, .splitTool(action)).frame
            try expect(!bar.intersects(button), "Split control \(action) is covered by Find")
        }
    }

    private static func findAndTools(_ app: AppUnderTest) throws {
        let first = try FindScenarios.setup(app)
        let source = try app.load(app.site.url("find.html?drag-source"))
        try app.waitForPageInput(PageID(window: first.window, item: source), at: app.site.url("find.html?drag-source"))
        try app.dispatch(.tab(.focus(first.item)))
        try app.waitForPageInput(first, at: app.site.url("find.html"))
        try app.press("cmd+f"); try FindScenarios.typeQuery(app, "needle"); try FindScenarios.matches(app, 3)
        let area = try app.native().computed.contentArea
        let row = try visible(app.native(), .row(source)).frame
        let edge = CGPoint(x: area.maxX - 12, y: area.midY)
        try pointer(app, .down, CGPoint(x: row.midX, y: row.midY)); try pointer(app, .dragged, edge)
        try expect(!isShown(try app.native(), .splitDropPreview), "Find admitted a content drop behind its controls")
        try pointer(app, .up, edge)
        try expect(try app.view().content.panes.count == 1 && app.view().find?.page == first, "Rejected drop changed Find's target")
        try app.click(.findClose)
        for number in 2...4 {
            try app.dispatch(.split(.addPane))
            let url = app.site.url("find.html?pane=\(number)")
            try app.dispatch(.commandBar(.submit(url.absoluteString)))
            let pane = try app.view().content.panes.first(where: \.focused)!.tab
            try app.waitForPageInput(PageID(window: first.window, item: pane), at: url)
        }
        let panes = try app.view().content.panes.map(\.tab)
        let fourth = PageID(window: first.window, item: panes[3])
        let before = try app.pageLog().filter { $0.kind == .created && panes.contains($0.page.item) }
        try app.press("cmd+f"); try FindScenarios.typeQuery(app, "needle"); try FindScenarios.matches(app, 3)
        try expect(try app.view().find?.page == fourth, "Find is not owned by pane four")
        try toolbarAvoidsFind(app)
        try app.click(.splitTool(.maximizeSplitPane))
        try expect(try app.view().content.expanded && app.native().computed.cards.first?.pane == 3, "Expansion lost the original pane index")
        try expect(try app.view().find?.page == fourth, "Expansion retargeted Find")
        try toolbarAvoidsFind(app)
        try app.screenshot("expanded-find-and-tools")
        try app.click(.splitTool(.maximizeSplitPane))
        try app.click(.splitTool(.splitVertical))
        try expect(try app.view().content.orientation == .vertical && app.view().find?.page == fourth, "Orientation changed Find's owner")
        try toolbarAvoidsFind(app)
        try app.click(.splitTool(.separateTabFromSplitView))
        try expect(try app.view().content.split == nil && app.view().find?.page == fourth, "Separate lost the original Find owner")
        try FindScenarios.matches(app, 3)
        try expect(try app.pageLog().filter { $0.kind == .created && panes.contains($0.page.item) } == before, "Split tools recreated a browser")
        try app.screenshot("separated-find")
        try app.click(.findClose)
        try FindScenarios.focus(app, fourth)
    }

    private static func backgroundAndFeedback(_ app: AppUnderTest) throws {
        let first = try app.load(app.site.url("split-tools.html?background=1"))
        try app.waitForPageInput(PageID(window: app.window!, item: first), at: app.site.url("split-tools.html?background=1"))
        for number in 2...3 {
            try app.dispatch(.split(.addPane))
            let url = app.site.url("split-tools.html?background=\(number)")
            try app.dispatch(.commandBar(.submit(url.absoluteString)))
            let pane = try app.view().content.panes.first(where: \.focused)!.tab
            try app.waitForPageInput(PageID(window: app.window!, item: pane), at: url)
        }
        let panes = try app.view().content.panes.map(\.tab)
        let foregroundURL = app.site.url("split-tools.html?foreground")
        let foreground = try app.load(foregroundURL)
        let page = PageID(window: app.window!, item: foreground)
        try app.waitForPageInput(page, at: foregroundURL)
        try app.flush(); try app.restart(); try app.waitForPageInput(page, at: foregroundURL)
        try expect(try !app.pageLog().contains { $0.kind == .created && panes.contains($0.page.item) }, "Background split loaded during lazy restore")
        let close = try visible(app.native(), .rowClose(panes[1])).frame
        try app.hover(CGPoint(x: close.midX, y: close.midY)); try app.click(.rowClose(panes[1]))
        try expect(try app.view().content.panes.map(\.tab) == [foreground], "Background pane close switched the active page")
        try expect(try !app.pageLog().contains { $0.kind == .created && panes.contains($0.page.item) }, "Background close loaded hidden siblings")
        try app.screenshot("background-close-keeps-foreground")
        let sourceURL = app.site.url("split-tools.html?drag-source")
        let source = try app.load(sourceURL)
        try app.waitForPageInput(PageID(window: app.window!, item: source), at: sourceURL)
        try app.click(.row(foreground)); try app.waitForPageInput(page, at: foregroundURL)
        let row = try visible(app.native(), .row(source)).frame
        let area = try app.native().computed.contentArea
        let edge = CGPoint(x: area.maxX - 12, y: area.midY)
        try pointer(app, .down, CGPoint(x: row.midX, y: row.midY)); try pointer(app, .dragged, edge)
        try expect(isShown(try app.native(), .splitDropPreview), "Drag has no edge feedback")
        try app.evaluate(page, "document.title='drag-render-tick'")
        try FindScenarios.title(app, page, "drag-render-tick")
        try expect(isShown(try app.native(), .splitDropPreview), "A title render erased the stationary preview")
        try app.screenshot("drag-preview-after-title")
        try pointer(app, .up, edge)
        try expect(try app.view().content.panes.map(\.tab) == [foreground, source], "The previewed edge release did not create its split")
    }
}
