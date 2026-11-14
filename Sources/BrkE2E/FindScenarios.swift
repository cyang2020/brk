import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation
import CoreGraphics

/// Assertions read the production find snapshot and the fixture's real DOM. Titles are test-only readback.
enum FindScenarios {
    static func title(_ app: AppUnderTest, _ page: PageID, _ value: String) throws {
        try app.waitUntil("fixture title \(value)") { try allTabs(app.view(page.window)).first { $0.id == page.item }?.title == value }
    }
    static func focus(_ app: AppUnderTest, _ page: PageID) throws {
        try app.waitUntil("native page focus") { try app.native(page.window).focusedPage == page }
    }
    static func windows(_ app: AppUnderTest) throws -> [WindowID] {
        guard case .hello(let h) = try app.send(.hello) else { throw Check(description:"No hello") }; return h.windows
    }
    static func dispatch(_ app: AppUnderTest, window: WindowID, _ command: Command) throws {
        guard case .dispatched = try app.send(.dispatch(window:window,command:command)) else { throw Check(description:"No dispatch") }
    }
    static func setup(_ app: AppUnderTest) throws -> PageID {
        let tab = try openTab(app, app.site.url("find.html"))
        let page = PageID(window: app.window!, item: tab.id)
        try app.waitForPageInput(page, at: app.site.url("find.html"))
        try waitForTitle(app, tab.id, "Find Fixture")
        return page
    }
    static func check(_ app: AppUnderTest, _ page: PageID, _ expression: String, _ expected: String) throws {
        try app.evaluate(page, "document.title='check:'+JSON.stringify(\(expression))")
        try title(app,page,"check:"+expected)
    }
    static func select(_ app: AppUnderTest, _ page: PageID, _ id: String, start: Int = 0, end: Int = 5) throws {
        try app.evaluate(page,"selectField('\(id)',\(start),\(end))")
        try title(app,page,"selected:"+id)
    }
    static func typeQuery(_ app: AppUnderTest, _ text: String) throws {
        try app.waitUntil("find query field focus") { try app.native().firstResponder.hasSuffix(":"+ViewID.findQuery.identifier) }
        try app.type(text)
    }
    static func matches(_ app: AppUnderTest, _ count: Int, ordinal: Int? = nil) throws {
        try app.waitUntil("find count \(count), ordinal \(ordinal.map(String.init) ?? "any")") {
            let find = try app.view().find
            return find?.count == count && find?.searching == false && (ordinal == nil || find?.ordinal == ordinal)
        }
    }
    static func replaceMode(_ app: AppUnderTest) throws {
        try app.press("cmd+option+f")
        try app.waitUntil("captured editable scope") { try app.view().find?.canReplace == true }
    }
    static func edited(_ app: AppUnderTest, _ n: Int) throws {
        try app.waitUntil("confirmed \(n) native edits") { try app.view().find?.message.hasPrefix("Replaced \(n).") == true }
    }
    static func keysAndCounts(_ app: AppUnderTest) throws {
        let page=try setup(app)
        try check(app, page, "window.swallow=true", "true")
        try app.press("cmd+f"); try title(app,page,"swallowed:f")
        try expect(try app.view().find == nil,"renderer-prevented Cmd+F opened find")
        try check(app, page, "window.swallow=false", "false")
        try app.press("cmd+f")
        try app.waitUntil("native find input") { try app.native().firstResponder.hasSuffix(":"+ViewID.findQuery.identifier) }
        try typeQuery(app,"needle"); try matches(app,3,ordinal:1)
        try app.press("cmd+g");try matches(app,3,ordinal:2)
        try app.press("cmd+shift+g");try matches(app,3,ordinal:1)
        for _ in 0..<5 {try app.press("cmd+g")}; try matches(app,3,ordinal:3)
        try app.screenshot("native-find")
        try app.press("escape"); try focus(app,page)
        try expect(try app.view().find == nil,"Escape did not close find")
        try app.press("cmd+g");try matches(app,3)
        try app.dispatch(.find(.query(FindQuery(text:"missing"))));try matches(app,0)
        try expect(try app.view().find?.ordinal == nil,"zero has an invented ordinal")
        try app.dispatch(.find(.query(FindQuery(text:"\r"))))
        try app.waitUntil("unsupported query has a useful failure") {try app.view().find?.message.contains("carriage returns") == true}
        try app.press("cmd+g")
        try app.waitUntil("Next after failure reports again instead of hanging") {try app.view().find?.searching == false && app.view().find?.message.contains("carriage returns") == true}
        try app.dispatch(.find(.query(FindQuery(text:""))));try expect(try app.view().find?.count == nil,"empty query kept results")
        try app.dispatch(.find(.close))
        try app.dispatch(.settings(.shortcuts(.setChord(.find,KeyChord([.command,.option],.e)))))
        try focus(app,page)
        try app.press("cmd+f");app.sleep(0.2)
        try expect(try app.view().find == nil,"old remapped chord still opened app find")
        try app.recordWindows("old-find-accelerator")
        try app.screenshot("old-find-accelerator")
        try app.press("cmd+option+e")
        try app.waitUntil("remapped native find") {try app.view().find != nil}
        try app.press("escape"); try focus(app,page)
        try check(app, page, "window.swallow=true", "true")
        try app.press("cmd+option+e");try title(app,page,"swallowed:e")
        try expect(try app.view().find == nil,"remap lost page-first priority")
        try app.recordWindows("find-shortcuts")
    }
    static func controlsAndUndo(_ app: AppUnderTest) throws {
        let page=try setup(app)
        for id in ["text","area"] {
            try app.dispatch(.find(.close))
            try app.evaluate(page,"document.getElementById('\(id)').value='🍎 $& [a] é 汉字 $&';events=[]")
            try select(app,page,id,start:3,end:5)
            try replaceMode(app);try matches(app,2,ordinal:1)
            try app.click(.findReplacement);try app.type("🪷$1")
            try app.click(.findReplaceAll);try edited(app,2)
            try check(app,page,"document.getElementById('\(id)').value","\"🍎 🪷$1 [a] é 汉字 🪷$1\"")
            try check(app,page,"[events.filter(x=>x[0]==='beforeinput').length,events.filter(x=>x[0]==='input'&&x[3]).length]","[2,2]")
            try app.screenshot("replace-"+id)
            try app.press("escape");try focus(app,page)
            try undo(app,page,expression:"document.getElementById('\(id)').value",original:"🍎 $& [a] é 汉字 $&")
        }
    }
    static func undo(_ app: AppUnderTest, _ page: PageID, expression: String, original: String) throws {
        try app.evaluate(page,"reportUndo=true;undoCount=0;document.title='undo-armed'")
        try title(app,page,"undo-armed")
        try app.press("cmd+z");try title(app,page,"native-undo:1")
        let expected=String(data:try JSONSerialization.data(withJSONObject:original,options:.fragmentsAllowed),encoding:.utf8)!
        try app.evaluate(page,"document.title='undo-done:'+String(\(expression)===\(expected))")
        try app.waitUntil("first undo readback") { try allTabs(app.view(page.window)).first{$0.id == page.item}?.title.hasPrefix("undo-done:") == true }
        if try allTabs(app.view(page.window)).first(where:{$0.id == page.item})?.title == "undo-done:false" {
            try app.press("cmd+z");try title(app,page,"native-undo:2")
        }
        try check(app,page,expression,expected)
    }
    static func windowsPeekAndPrivate(_ app: AppUnderTest) throws {
        let page=try setup(app), first=app.window!
        try app.dispatch(.find(.open(replace:false)));try app.dispatch(.find(.query(FindQuery(text:"needle"))));try matches(app,3)
        try app.dispatch(.window(.new)); let ids=try windows(app)
        let second=ids.first{$0 != first}!
        try dispatch(app,window:second,.tab(.focus(page.item)))
        app.window=second;try app.perform(.activate(window:second));try focus(app,PageID(window:second,item:page.item))
        try app.press("cmd+f");try typeQuery(app,"apple");try matches(app,6)
        try expect(try app.view(first).find?.query.text == "needle","two windows shared the query")
        try expect(try app.view(first).find?.count == nil && app.view(first).find?.searching == false,
                   "the window without the page retained another window's find results")
        try app.dispatch(.find(.close));try app.dispatch(.peek(.open(app.site.url("find.html"))))
        try app.settle();try app.press("cmd+f");try typeQuery(app,"needle");try matches(app,3)
        try expect(try app.view().overlay != nil,"find dismissed Peek")
        try app.press("escape");try expect(try app.view().overlay != nil,"first Escape dismissed Peek")
        try app.press("escape");try expect(try app.view().overlay == nil,"second Escape did not dismiss Peek")
        try app.dispatch(.window(.newIncognito));let all=try windows(app)
        let priv=all.first{$0 != first && $0 != second}!
        app.window=priv;try app.perform(.activate(window:priv))
        let privateItem=try app.load(app.site.url("find.html"))
        try app.waitForPageInput(PageID(window:priv,item:privateItem),at:app.site.url("find.html"))
        try app.press("cmd+g")
        try app.waitUntil("private find opens") {try app.view().find != nil}
        try expect(try app.view().find?.query.text == "","public query leaked into private window")
        try typeQuery(app,"needle");try matches(app,3);try app.screenshot("private-find")
        try app.dispatch(.window(.close));app.window=first;try app.perform(.activate(window:first))
        try expect(try app.view().find?.query.text == "needle","private expiry changed public query")
        try app.dispatch(.find(.close));try app.dispatch(.split(.addPane));try app.dispatch(.commandBar(.submit(app.site.url("find.html").absoluteString)))
        try app.settle()
        if case .page(let pane)=try app.view().focus {try app.waitForPageInput(pane,at:app.site.url("find.html"))}
        try app.press("cmd+f");try typeQuery(app,"needle");try matches(app,3)
        let left=try app.view().content.panes[0].tab
        try app.dispatch(.tab(.focus(left)));try expect(try app.view().find == nil,"split target change kept old find session")
    }


}
