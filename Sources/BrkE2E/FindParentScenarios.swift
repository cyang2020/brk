import BrkBase
import BrkDomain
import BrkLayout
import CoreGraphics

extension FindScenarios {
    @Sendable static func repeatedFindFocus(_ app: AppUnderTest) throws {
        let page = try setup(app)
        try app.press("cmd+f")
        try typeQuery(app, "needle")
        try matches(app, 3)
        let card = try app.native().computed.cards[0].rect
        try app.click(at: CGPoint(x: card.midX, y: card.minY + 300))
        try focus(app, page)
        try app.press("cmd+f")
        try app.waitUntil("repeated Find focuses its existing query") {
            try app.native().firstResponder.hasSuffix(":" + ViewID.findQuery.identifier)
        }
        try app.press("cmd+a")
        try app.type("apple")
        try matches(app, 6)
        try app.screenshot("repeated-find-focus")
    }

    @Sendable static func narrowPaneControls(_ app: AppUnderTest) throws {
        let page = try setup(app)
        try app.setWindowFrame(CGRect(x: 10, y: 10, width: 1000, height: 720))
        try app.dispatch(.split(.addPane))
        try app.dispatch(.commandBar(.submit(app.site.url("find.html").absoluteString)))
        let view = try app.view()
        guard let split = view.content.split, let right = view.content.panes.last?.tab else {
            throw Check(description: "Missing split fixture")
        }
        try app.waitForPageInput(PageID(window: page.window, item: right), at: app.site.url("find.html"))
        try app.dispatch(.split(.resize(split, fractions: [page.item: 0.15, right: 0.85])))
        try app.dispatch(.tab(.focus(page.item)))
        try app.waitForPageInput(page, at: app.site.url("find.html"))
        try app.press("cmd+f")
        try typeQuery(app, "needle")
        try matches(app, 3)
        try app.screenshot("narrow-find")
        var native = try app.native()
        var bar = try visible(native, .findBar)
        try expect(bar.frame.width < 160, "Fixture did not create a narrow page card")
        for id in [ViewID.findQuery, .findPrevious, .findNext, .findClose, .findStatus] {
            try expect(contains(bar, try visible(native, id)), "Find control \(id) escapes its narrow bar")
        }
        try app.click(.findClose)
        try expect(try app.view().find == nil, "Narrow-bar Close click did not dismiss Find")
        try focus(app, page)
        try select(app, page, "text")
        try replaceMode(app)
        try matches(app, 2)
        native = try app.native()
        bar = try visible(native, .findBar)
        for id in [ViewID.findReplacement, .findReplace, .findReplaceAll, .findCapture] {
            let control = try visible(native, id)
            try expect(contains(bar, control), "Replacement control \(id) escapes its narrow bar")
            try expect(control.frame.width >= 80, "Replacement control \(id) label is squeezed")
        }
        try app.click(.findReplacement)
        try app.type("pear")
        try app.click(.findReplaceAll)
        try edited(app, 2)
        try check(app, page, "text.value", "\"pear pear\"")
        try app.screenshot("narrow-replace")
        try app.click(.findClose)
        try expect(try app.view().find == nil, "Narrow replacement Close click did not dismiss Find")
    }
}
