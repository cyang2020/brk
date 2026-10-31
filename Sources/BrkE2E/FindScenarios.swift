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
        try focus(app,page); try waitForTitle(app, tab.id, "Find Fixture")
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
        try app.evaluate(page,"swallow=true")
        try app.press("cmd+f"); try title(app,page,"swallowed:f")
        try expect(try app.view().find == nil,"renderer-prevented Cmd+F opened find")
        try app.evaluate(page,"swallow=false")
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
        try app.evaluate(page,"swallow=true")
        try app.press("cmd+option+e");try title(app,page,"swallowed:e")
        try expect(try app.view().find == nil,"remap lost page-first priority")
        try app.recordWindows("find-shortcuts")
    }
    static func selectionAndJump(_ app: AppUnderTest) throws {
        let page=try setup(app)
        try select(app,page,"text",start:0,end:5)
        try app.dispatch(.find(.useSelection))
        try app.waitUntil("actual selected text") { try app.view().find?.query.text == "apple" }
        try matches(app,6)
        try app.dispatch(.find(.step(.next)));try matches(app,6)
        try expect(try app.view().find?.query.text != "needle","used a native find rectangle as DOM selection")
        try app.dispatch(.find(.close))
        try app.evaluate(page,"const r=document.createRange();r.selectNodeContents(document.getElementById('far'));getSelection().removeAllRanges();getSelection().addRange(r);window.scrollTo(0,0);document.title='far-selected'")
        try title(app,page,"far-selected")
        try app.press("cmd+j")
        try app.waitUntil("selection revealed") { try app.view().find?.message == "Selection revealed." }
        try check(app,page,"[getSelection().toString(),scrollY>500]", "[\"jump-target\",true]")
        try app.screenshot("jump-selection")
        try app.dispatch(.find(.close))
        try app.evaluate(page,"const jumpFrame=document.createElement('iframe');jumpFrame.id='jumpFrame';jumpFrame.style.cssText='display:block;margin-top:1200px;height:160px;width:500px';jumpFrame.srcdoc='<p id=selected>child-jump-target</p>';jumpFrame.onload=()=>{const d=jumpFrame.contentDocument,r=d.createRange();r.selectNodeContents(d.getElementById('selected'));jumpFrame.contentWindow.focus();d.getSelection().removeAllRanges();d.getSelection().addRange(r);window.scrollTo(0,0);document.title='child-jump-selected'};document.body.append(jumpFrame)")
        try title(app,page,"child-jump-selected")
        try app.press("cmd+j")
        try app.waitUntil("frame selection revealed") { try app.view().find?.message == "Selection revealed." }
        try check(app,page,"[jumpFrame.contentDocument.getSelection().toString(),scrollY>1000]","[\"child-jump-target\",true]")
        try app.screenshot("jump-frame-selection")
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
    static func contentEditable(_ app: AppUnderTest) throws {
        let page=try setup(app)
        try select(app,page,"editor")
        try app.dispatch(.find(.open(replace:true)))
        try app.waitUntil("editable capture") { try app.view().find?.canReplace == true }
        try app.dispatch(.find(.query(FindQuery(text:"apple"))));try matches(app,2,ordinal:1)
        try app.dispatch(.find(.replaceAll("pear")));try edited(app,2)
        try check(app,page,"[editor.textContent,document.getElementById('keep').outerHTML]","[\"pear middle pear untouched\",\"<span id=\\\"keep\\\">untouched</span>\"]")
        try app.press("escape");try focus(app,page)
        try undo(app,page,expression:"editor.textContent",original:"apple middle apple untouched")
        try app.screenshot("editable-undo")
    }
    static func refusals(_ app: AppUnderTest) throws {
        let page=try setup(app)
        for id in ["password","readonly","rich"] {
            try app.dispatch(.find(.close));try select(app,page,id)
            try app.dispatch(.find(.open(replace:true)))
            try app.waitUntil("refused \(id)") {try app.view().find?.message.isEmpty == false}
            try expect(try app.view().find?.canReplace == false,"protected field enabled replacement")
            try expect(try app.view().find?.query.text.contains("secret") == false,"protected value was exposed")
        }
        try app.dispatch(.find(.close));try select(app,page,"text")
        try app.evaluate(page,"text.dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true,data:'x'}))")
        try app.dispatch(.find(.useSelection))
        try app.waitUntil("IME refused") {try app.view().find?.message.contains("composing") == true}
        try app.evaluate(page,"text.dispatchEvent(new CompositionEvent('compositionend',{bubbles:true,data:'x'}))")
        try app.dispatch(.find(.close));try select(app,page,"text");try replaceMode(app)
        try app.evaluate(page,"text.setSelectionRange(1,2)")
        try app.waitUntil("changed selection disables editing") {try app.view().find?.canReplace == false}
        try app.dispatch(.find(.replaceAll("bad")))
        try check(app,page,"text.value","\"apple apple\"")
        try app.dispatch(.find(.close))
        let cross=app.site.url("find-frame.html").absoluteString.replacingOccurrences(of:"127.0.0.1",with:"localhost")
        try app.evaluate(page,"const frame=document.createElement('iframe');frame.src='\(cross)';frame.id='foreign';frame.onload=()=>document.title='foreign-loaded';window.frameTrace=[];window.addEventListener('message',e=>{frameTrace.push({fromFrame:e.source===frame.contentWindow,origin:e.origin,data:e.data,active:document.activeElement.id});if(e.source===frame.contentWindow){if(e.data?.kind==='fixture-frame-focus'||(e.data?.kind==='fixture-state'&&e.data.phase==='after-focus'&&e.data.active==='inside'))document.title='foreign-focused';if(e.data?.kind==='fixture-frame-key')document.title='foreign-key'}});document.body.prepend(frame)")
        try title(app,page,"foreign-loaded")
        try app.evaluate(page,"foreign.contentWindow.postMessage('fixture-focus','*')")
        do { try title(app,page,"foreign-focused") }
        catch {
            try app.evaluate(page,"document.title='frame-trace:'+JSON.stringify(frameTrace)")
            try app.waitUntil("frame message census") {try allTabs(app.view()).first{$0.id == page.item}?.title.hasPrefix("frame-trace:") == true}
            try app.recordWindows("frame-message-census")
            throw error
        }
        try app.type("x")
        try title(app,page,"foreign-key")
        try app.dispatch(.find(.useSelection))
        try app.waitUntil("cross-origin frame refusal") {try app.view().find?.message.contains("cross-origin") == true}
    }
    static func dynamicDocuments(_ app: AppUnderTest) throws {
        let page=try setup(app)
        try app.dispatch(.find(.open(replace:false)));try app.dispatch(.find(.query(FindQuery(text:"needle"))));try matches(app,3)
        try app.evaluate(page,"words.textContent+=' needle needle'");try matches(app,5)
        try app.evaluate(page,"const f=document.createElement('iframe');f.id='child';f.srcdoc='<p>needle needle</p><input value=\"frameword frameword\">';f.onload=()=>document.title='child-ready';document.body.prepend(f)")
        try title(app,page,"child-ready");try matches(app,7)
        try app.evaluate(page,"child.remove()");try matches(app,5)
        try app.dispatch(.page(.reload(.focused, ignoringCache:false)));try matches(app,3)
        try expect(try app.view().find?.query.text == "needle","navigation lost visible query")
        try app.dispatch(.find(.close))
        try app.evaluate(page,"const f=document.createElement('iframe');f.id='same';f.srcdoc='<input id=\"inside\" value=\"frameword frameword\">';f.onload=()=>{const e=f.contentDocument.getElementById('inside');e.focus();e.setSelectionRange(0,9);document.title='same-selected'};document.body.prepend(f)")
        try title(app,page,"same-selected")
        try replaceMode(app);try matches(app,2)
        try app.dispatch(.find(.replaceAll("child")));try edited(app,2)
        try check(app,page,"same.contentDocument.getElementById('inside').value","\"child child\"")
    }
    static func partialAndAmbiguous(_ app: AppUnderTest) throws {
        let page=try setup(app)
        try select(app,page,"text");try replaceMode(app)
        try app.evaluate(page,"behavior='rewrite'")
        try app.dispatch(.find(.replaceAll("pear")));try edited(app,1)
        try check(app,page,"text.value","\"apple pear changed\"")
        try app.dispatch(.find(.close));try app.evaluate(page,"behavior='normal';text.value='apple apple'")
        try select(app,page,"text");try replaceMode(app);try app.evaluate(page,"behavior='cancel'")
        try app.dispatch(.find(.replaceAll("pear")));try edited(app,0)
        try check(app,page,"text.value","\"apple apple\"")
        try app.dispatch(.find(.close));try app.evaluate(page,"behavior='delay'");try select(app,page,"text");try replaceMode(app)
        try app.dispatch(.find(.replaceCurrent("pear")))
        try app.waitUntil("timeout is explicitly unconfirmed",timeout:4) { try app.view().find?.message.contains("not confirmed") == true }
        try edited(app,1)
        try check(app,page,"text.value","\"pear apple\"")
        try app.screenshot("confirmed-after-timeout")
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
        try expect(try app.view(first).find?.count == 3,"interleaved browser callbacks contaminated results")
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
    static func staleScopesAndFocus(_ app: AppUnderTest) throws {
        let page=try setup(app), first=app.window!
        try select(app,page,"text");try replaceMode(app)
        try app.evaluate(page,"text.replaceWith(text.cloneNode(true))")
        try app.waitUntil("detached field disables replacement") {try app.view().find?.canReplace == false}
        try app.dispatch(.find(.replaceAll("bad")))
        try check(app,page,"text.value","\"apple apple\"")
        try app.dispatch(.find(.close));try select(app,page,"text");try replaceMode(app)
        try app.evaluate(page,"text.readOnly=true")
        try app.waitUntil("read-only scope invalidated") {try app.view().find?.canReplace == false}
        try app.dispatch(.find(.replaceCurrent("bad")));try check(app,page,"text.value","\"apple apple\"")
        try app.dispatch(.find(.close))
        try app.dispatch(.find(.open(replace:false)));try app.dispatch(.find(.query(FindQuery(text:"not-persisted-search"))))
        try app.flush()
        let saved=try String(contentsOf:app.dataDirectory.appendingPathComponent("state.json"),encoding:.utf8)
        try expect(!saved.contains("not-persisted-search"),"find query persisted")
        try app.dispatch(.window(.new));let second=try windows(app).first{$0 != first}!
        try app.perform(.activate(window:second))
        try app.waitUntil("other window editor") {try app.native(second).firstResponder.hasSuffix(":"+ViewID.commandBarInput.identifier)}
        try dispatch(app,window:first,.find(.close))
        try expect(try app.native(second).firstResponder.hasSuffix(":"+ViewID.commandBarInput.identifier),"closing background find stole another editor")
        try expect(try !app.native(first).isKey,"closing background find activated its window")
        try dispatch(app,window:second,.window(.close));try app.perform(.activate(window:first))
        try app.dispatch(.find(.open(replace:false)))
        _ = try app.send(.openSettings(pane:.profiles))
        try expect(try app.view().find == nil,"Settings left a conflicting find session")
        try app.press("cmd+f")
        try expect(try app.view().find == nil,"Settings invoked find in a remembered browser")
        try app.press("escape");try app.waitUntil("settings closed") {
            guard case .settings(let s)=try app.send(.settings) else{return false};return s.pane == nil
        }
        try app.recordWindows("native-editors-preserved")
    }

    static func frameLifetimeAndIdempotence(_ app: AppUnderTest) throws {
        let page=try setup(app)
        try app.evaluate(page,"const f=document.createElement('iframe');f.id='scopeFrame';f.srcdoc='<input id=\"inside\" value=\"apple apple\">';f.onload=()=>{const e=f.contentDocument.getElementById('inside');e.focus();e.setSelectionRange(0,5);document.title='scope-ready'};document.body.prepend(f)")
        try title(app,page,"scope-ready");try replaceMode(app)
        try app.evaluate(page,"const other=document.createElement('iframe');other.id='otherFrame';other.srcdoc='<input id=\"another\" value=\"other field\">';other.onload=()=>{other.contentDocument.getElementById('another').focus();document.title='other-focused'};document.body.prepend(other)")
        try title(app,page,"other-focused")
        try app.waitUntil("foreign focused frame invalidates captured scope") {try app.view().find?.canReplace == false}
        try app.dispatch(.find(.replaceAll("wrong")))
        try check(app,page,"scopeFrame.contentDocument.getElementById('inside').value","\"apple apple\"")
        try app.dispatch(.find(.close))
        try app.evaluate(page,"const e=scopeFrame.contentDocument.getElementById('inside');e.focus();e.setSelectionRange(0,5);document.title='scope-recaptured'")
        try title(app,page,"scope-recaptured");try replaceMode(app)
        try app.evaluate(page,"scopeFrame.onload=()=>document.title='scope-replaced';scopeFrame.srcdoc='<input id=\"inside\" value=\"new document\">'")
        try title(app,page,"scope-replaced")
        try app.waitUntil("frame document change disables old ticket") {try app.view().find?.canReplace == false}
        try app.dispatch(.find(.replaceAll("wrong")))
        try check(app,page,"scopeFrame.contentDocument.getElementById('inside').value","\"new document\"")
        try app.dispatch(.find(.close))
        // Exercise the exact production editor function twice with the same mutation identity in a real renderer.
        let sourceURL=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Vendor/CefSwift/Sources/CefKit/FindEditorScript.swift")
        let swift=try String(contentsOf:sourceURL,encoding:.utf8)
        let script=swift.components(separatedBy:"static let source = #\"\"\"\n")[1].components(separatedBy:"\n\"\"\"#")[0]
        let body="""
        (()=>{
            const editor=\(script);
            text.focus();text.setSelectionRange(0,5);
            const send=o=>JSON.parse(editor(JSON.stringify(o)));
            const captured=send({op:'capture',ticket:'once'});
            const searched=send({op:'search',ticket:'once',query:'apple',caseSensitive:true});
            const request={op:'replace',request:'mutation-once',ticket:'once',query:'apple',caseSensitive:true,replacement:'pear',all:false};
            const first=send(request), second=send(request);
            document.title='once:'+JSON.stringify([captured.status,searched.count,first.applied,second.applied,text.value]);
        })()
        """
        try app.evaluate(page,body)
        try title(app,page,"once:[\"selection\",2,1,1,\"pear apple\"]")
        try app.screenshot("frame-invalidation-and-once")
    }

}
