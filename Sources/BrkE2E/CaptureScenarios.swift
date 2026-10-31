import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum CaptureScenarios {
    static let all = [Scenario("CaptureScale", "zoomed full-page and scrolled area pixels match independent DOM metrics", cefOnly:"embedded pixel scale", scale),
        Scenario("CaptureProduct", "area, full-page, portrait, real library export/restart/remove and private memory", cefOnly: "embedded captures", product),
        Scenario("CapturePiPOwnership", "specific players, activation failure, per-site exemption and private PiP retirement", cefOnly:"embedded media ownership", pipOwnership),
        Scenario("CapturePiP", "explicit video/document PiP, automatic video and source lifecycle", cefOnly: "embedded PiP", pictureInPicture),
        Scenario("CaptureProbe", "embedded Chrome capture and separate video/document PiP probes", cefOnly: "embedded DevTools", probe)]
    static func library(_ app: AppUnderTest) throws -> LibrarySnapshot? { if case .library(let value)? = try app.view().overlay { value } else { nil } }
    static func pngSize(_ bytes: Data) -> [Int] { [16,20].map { offset in bytes[offset..<(offset+4)].reduce(0) { $0*256+Int($1) } } }
    static func captureRecord(_ app: AppUnderTest, mode: CaptureMode, previous: Int) throws -> CaptureRecord {
        do { try app.waitUntil("capture reaches Media as a real indexed PNG", timeout:20) {
            if try library(app)?.captures.count == previous + 1 { return true }
            let view = try app.view()
            if view.capture == nil, let toast = view.tabTools.toast { throw Check(description:toast.text) }
            return false
        } } catch {
            try? JSONEncoder().encode(try app.view()).write(to:app.shotsDirectory.appendingPathComponent("capture-failed-view.json"))
            try? JSONEncoder().encode(try app.send(.pageObservations)).write(to:app.shotsDirectory.appendingPathComponent("capture-failed-observations.json"))
            throw error
        }
        guard let record = try library(app)?.captures.first, let file = try library(app)?.captureFiles[record.id] else { throw Check(description:"No capture record/file") }
        let bytes = try Data(contentsOf:file)
        try expect(pngSize(bytes) == [record.width,record.height],"index dimensions disagree with PNG")
        try bytes.write(to:app.shotsDirectory.appendingPathComponent("product-"+mode.rawValue+".png"))
        return record
    }
    @Sendable static func product(_ app: AppUnderTest) throws {
        try app.dispatch(.settings(.advanced(.autoPictureInPicture(false))))
        let url=app.site.url("capture-media.html"), item=try app.load(app.site.url("capture-media.html"))
        let page=PageID(window:app.window!,item:item)
        try app.waitForPageInput(page,at:url)
        try app.perform(.menuAction(ActionID.captureFullPage.rawValue))
        let full=try captureRecord(app,mode:.fullPage,previous:0)
        try expect(full.height == Int(3050 * full.scale),"full page omitted long content")
        _ = try app.screenshot("product-media-full")
        try app.dispatch(.library(.close))
        try app.perform(.menuAction(ActionID.capturePage.rawValue))
        try app.waitUntil("selection overlay appears") { try app.view().capture?.request.mode == .area }
        let card=try app.native().computed.cards[0].rect
        _ = try app.send(.pointerDrag(from:CGPoint(x:card.minX+card.width*0.4,y:card.minY+card.height*0.4),to:CGPoint(x:card.minX+card.width*0.65,y:card.minY+card.height*0.65),cancel:false))
        _ = try app.screenshot("product-area-selection")
        try app.click(.tabTool("capture-confirm"))
        let area=try captureRecord(app,mode:.area,previous:1)
        try expect(abs(Double(area.width)-Double(full.width)*0.25)<=2,"area pixels do not match pointer selection")
        try app.dispatch(.library(.close))
        try app.perform(.menuAction(ActionID.capturePrettyScreenshot.rawValue))
        _ = try app.screenshot("product-portrait-framing")
        try app.click(.tabTool("capture-confirm"))
        let portrait=try captureRecord(app,mode:.portrait,previous:2)
        try expect(abs(Double(portrait.width)/Double(portrait.height)-9.0/16)<0.01,"portrait framing is not 9:16")
        try app.dispatch(.capture(.preview(area.id)))
        try expect(try library(app)?.capturePreview == area.id,"preview selection lost")
        try app.click(.tabTool("capture-open"))
        try app.waitUntil("actual PNG opens in its native image viewer") { if case .menuItems = try? app.send(.sidebarPanel(window:app.window,action:.inspect)) { true } else { false } }
        Thread.sleep(forTimeInterval:0.25)
        _ = try app.send(.sidebarPanel(window:app.window,action:.capture(path:app.shotsDirectory.appendingPathComponent("product-open-viewer.png").path)))
        _ = try app.send(.sidebarPanel(window:app.window,action:.button("Close")))
        try app.click(.tabTool("capture-export"))
        try app.waitUntil("real PNG save sheet opens") { if case .menuItems = try? app.send(.sidebarPanel(window:app.window, action:.inspect)) { true } else { false } }
        Thread.sleep(forTimeInterval:0.25)
        _ = try app.send(.sidebarPanel(window:app.window, action:.capture(path:app.shotsDirectory.appendingPathComponent("product-export-sheet.png").path)))
        let exported=app.dataDirectory.appendingPathComponent("exported-capture.png")
        try app.click(.tabTool("capture-export-path")); try app.press("cmd+a");try app.type(exported.path)
        _ = try app.send(.sidebarPanel(window:app.window,action:.button("Export")))
        try app.waitUntil("native save panel exports actual PNG bytes",timeout:15) { FileManager.default.fileExists(atPath:exported.path) }
        try expect(try Data(contentsOf:exported) == Data(contentsOf:library(app)!.captureFiles[area.id]!),"export changed PNG bytes")
        try app.restart()
        try app.dispatch(.library(.open(.media)))
        try app.waitUntil("capture index survives restart") { try library(app)?.captures.count == 3 }
        try app.dispatch(.capture(.remove(area.id)))
        try app.waitUntil("remove deletes PNG and index row") { try library(app)?.captures.count == 2 }
        try app.dispatch(.library(.close))
        try app.dispatch(.tab(.focus(item)))
        try app.waitForPageInput(page,at:url)
        try app.perform(.menuAction(ActionID.capturePage.rawValue)); try app.press("escape")
        try expect(try app.view().capture == nil,"Esc did not cancel selection")
        try app.perform(.menuAction(ActionID.capturePage.rawValue))
        try app.dispatch(.commandBar(.open(.editCurrent))); try app.dispatch(.commandBar(.submit(app.site.url("page2.html").absoluteString)))
        try app.waitUntil("navigation invalidates pending capture") { try app.view().capture == nil }
        let publicWindow=app.window!
        guard case .hello(let before)=try app.send(.hello) else { throw Check(description:"hello missing") }
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let after)=try app.send(.hello), let privateWindow=after.windows.first(where:{!before.windows.contains($0)}) else { throw Check(description:"private window missing") }
        app.window=privateWindow; _ = try app.send(.activate(window:privateWindow))
        let privateItem=try app.load(url); try app.waitForPageInput(PageID(window:privateWindow,item:privateItem),at:url)
        let diskBefore=try FileManager.default.subpathsOfDirectory(atPath:app.dataDirectory.appendingPathComponent("Captures").path)
        try app.dispatch(.capture(.begin(.fullPage)))
        try app.waitUntil("private capture exists only in memory") { try app.view().capture?.image != nil }
        _ = try app.screenshot("product-private-memory-preview")
        try expect(try FileManager.default.subpathsOfDirectory(atPath:app.dataDirectory.appendingPathComponent("Captures").path)==diskBefore,"private capture wrote a file")
        try app.dispatch(.capture(.cancel)); try app.dispatch(.window(.close))
        app.window=publicWindow; _ = try app.send(.activate(window:publicWindow))
        try app.dispatch(.library(.open(.media)))
        try expect(try library(app)?.captures.count == 2,"private capture entered public index")
        try app.dispatch(.library(.close))
        try app.dispatch(.peek(.open(url)))
        try app.waitUntil("Peek source owns its ready page") { if case .peek(let peek)? = try app.view().overlay { return peek.page != nil };return false }
        guard case .peek(let peek)? = try app.view().overlay, let peekPage = peek.page else { throw Check(description:"Peek page missing") }
        try app.waitForPageInput(peekPage,at:url)
        try app.dispatch(.capture(.begin(.area)))
        try expect(try app.view().capture?.request.document.browser.page == peekPage,"Capture switched from Peek to the underlying tab")
        let peekRect = try app.native().computed.peek!
        _ = try app.send(.pointerDrag(from:CGPoint(x:peekRect.minX+peekRect.width*0.4,y:peekRect.minY+peekRect.height*0.4),to:CGPoint(x:peekRect.minX+peekRect.width*0.65,y:peekRect.minY+peekRect.height*0.65),cancel:false))
        try app.click(.tabTool("capture-confirm"))
        try app.waitUntil("Peek capture reaches its public profile library") { try library(app)?.captures.count == 3 }
        guard let peekCapture = try library(app)?.captures.first, let peekFile = try library(app)?.captureFiles[peekCapture.id] else { throw Check(description:"Peek capture missing") }
        try expect(peekCapture.url == url,"Peek capture has the underlying tab's address")
        try Data(contentsOf:peekFile).write(to:app.shotsDirectory.appendingPathComponent("peek-area.png"))
        let originalSpace = try app.view().space.id
        _ = try createSpace(app,title:"Capture profile")
        try app.dispatch(.profile(.create(name:"Capture isolated",icon:nil)))
        guard case .settings(let settings) = try app.send(.settings), let profile = settings.profiles.first(where:{$0.profile.name == "Capture isolated"})?.profile.id else { throw Check(description:"capture profile missing") }
        try app.dispatch(.profile(.assign(.current,to:profile)))
        try app.dispatch(.library(.open(.media)))
        try app.waitUntil("different profile has an empty real media index") { try library(app)?.captures.isEmpty == true }
        try app.dispatch(.library(.close))
        let isolatedItem = try app.load(url); try app.waitForPageInput(PageID(window:app.window!,item:isolatedItem),at:url)
        try app.dispatch(.capture(.begin(.fullPage)))
        try app.waitUntil("isolated profile capture is indexed") { try library(app)?.captures.count == 1 }
        guard let isolated = try library(app)?.captures.first, let isolatedFile = try library(app)?.captureFiles[isolated.id] else { throw Check(description:"isolated artifact missing") }
        try expect(isolated.profile == profile,"capture stored under the wrong profile")
        try app.dispatch(.profile(.assign(.current,to:.default)))
        try app.dispatch(.profile(.delete(profile)))
        try app.waitUntil("profile deletion removes its capture folder") { !FileManager.default.fileExists(atPath:isolatedFile.path) }
        try app.dispatch(.space(.focus(originalSpace)))
        try app.dispatch(.library(.open(.media)))
        try app.waitUntil("default profile captures survive isolated profile deletion") { try library(app)?.captures.count == 3 }
        let evidence=try JSONEncoder().encode([full,area,portrait]);try evidence.write(to:app.shotsDirectory.appendingPathComponent("product-records.json"))
    }
    @Sendable static func scale(_ app: AppUnderTest) throws {
        try app.dispatch(.settings(.advanced(.autoPictureInPicture(false))))
        let url=app.site.url("capture-media.html"),item=try app.load(app.site.url("capture-media.html"))
        let page=PageID(window:app.window!,item:item)
        try app.waitForPageInput(page,at:url)
        let before=try app.view().urlPill.zoomPercent
        try app.dispatch(.page(.zoom(.zoomIn)))
        try app.waitUntil("native page zoom changes") { try app.view().urlPill.zoomPercent > before }
        try app.evaluate(page,"document.title='scale:'+JSON.stringify({width:document.documentElement.scrollWidth,height:document.documentElement.scrollHeight,dpr:devicePixelRatio,viewport:innerHeight})")
        try app.waitUntil("DOM supplies independent pixel scale") { try tab(item,in:app.view())?.title.hasPrefix("scale:") == true }
        let text=String(try tab(item,in:app.view())!.title.dropFirst(6))
        let metrics=try JSONSerialization.jsonObject(with:Data(text.utf8)) as! [String:Double]
        try Data(text.utf8).write(to:app.shotsDirectory.appendingPathComponent("zoom-metrics.json"))
        try app.dispatch(.capture(.begin(.fullPage)))
        let observation = try app.send(.pageObservations)
        try expect(try app.view().capture != nil,"Capture begin was not admitted after zoom: \(observation)")
        let record=try captureRecord(app,mode:.fullPage,previous:0)
        try expect(abs(Double(record.width)-metrics["width"]!*metrics["dpr"]!)<=2 && abs(Double(record.height)-metrics["height"]!*metrics["dpr"]!)<=2,"zoomed pixels do not match actual DOM devicePixelRatio")
        try Data(text.utf8).write(to:app.shotsDirectory.appendingPathComponent("zoom-metrics.json"))
        if let file=try library(app)?.captureFiles[record.id] { try Data(contentsOf:file).write(to:app.shotsDirectory.appendingPathComponent("zoomed-full.png")) }
        try app.dispatch(.library(.close))
        try app.evaluate(page,"scrollTo(0,1400);document.title='scrolled:'+scrollY")
        try app.waitUntil("page scrolled beyond first band") { try tab(item,in:app.view())?.title.hasPrefix("scrolled:1400") == true }
        try app.dispatch(.capture(.begin(.area)));try app.dispatch(.capture(.select(CaptureRegion(x:0.4,y:0.4,width:0.25,height:0.25))))
        let scrolled=try captureRecord(app,mode:.area,previous:1)
        if let file=try library(app)?.captureFiles[scrolled.id] { try Data(contentsOf:file).write(to:app.shotsDirectory.appendingPathComponent("scrolled-area.png")) }
        try JSONEncoder().encode([record,scrolled]).write(to:app.shotsDirectory.appendingPathComponent("scale-records.json"))
    }
    static func captureNewWindows(_ app: AppUnderTest, since before: Set<Int>, name: String) throws {
        let windows = try app.native().appWindows.filter { $0.isVisible && !before.contains($0.number) }
        try expect(!windows.isEmpty,"PiP exposed no visible native window")
        for (index,window) in windows.enumerated() { _ = try app.send(.mediaWindowScreenshot(number:window.number,path:app.shotsDirectory.appendingPathComponent(name+"-"+String(index)+".png").path)) }
    }
    static func mediaRow(_ app: AppUnderTest, _ id: ItemID) throws -> TabRow? { let view = try app.view(); return tab(id,in:view) ?? tabRows(view.scratch?.rows ?? []).first(where:{$0.id == id}) }
    @Sendable static func pipOwnership(_ app: AppUnderTest) throws {
        try app.dispatch(.settings(.advanced(.autoPictureInPicture(false))))
        let url = app.site.url("capture-media.html"), item = try app.load(app.site.url("capture-media.html")), window = app.window!
        let page = PageID(window:window,item:item)
        try app.waitForPageInput(page,at:url)
        try app.waitUntil("main player is observed") { try mediaRow(app,item)?.mediaPlayers.count == 1 }
        let first = try mediaRow(app,item)!.mediaPlayers[0]
        try app.evaluate(page,"globalThis.second=document.createElement('video');second.muted=true;second.srcObject=document.querySelector('video').srcObject;document.body.prepend(second);second.play()")
        try app.waitUntil("two distinct video elements are observed") { try mediaRow(app,item)?.mediaPlayers.count == 2 }
        let second = try mediaRow(app,item)!.mediaPlayers.first(where:{$0.id != first.id})!
        try app.dispatch(.page(.media(.item(item),second.id,.enterPictureInPicture)))
        try app.waitUntil("chosen second player alone owns PiP") { guard let players=try mediaRow(app,item)?.mediaPlayers else{return false};return players.contains(where:{$0.id == second.id && $0.pictureInPicture}) && !players.contains(where:{$0.id == first.id && $0.pictureInPicture}) }
        try app.evaluate(page,"document.title='second-owner:'+String(document.pictureInPictureElement===second)")
        try app.waitUntil("DOM confirms exact PiP element") { try mediaRow(app,item)?.title == "second-owner:true" }
        try app.dispatch(.page(.media(.item(item),second.id,.exitPictureInPicture)))
        try app.evaluate(page,"second.remove();const f=document.createElement('iframe');f.id='blockedFrame';f.allow=\"picture-in-picture 'none'\";f.src='http://localhost:'+location.port+'/media-frame.html';document.body.append(f)")
        try app.waitUntil("policy-blocked foreign frame player is observed") { try mediaRow(app,item)?.mediaPlayers.contains(where:{$0.id.frame != 0}) == true }
        let blocked = try mediaRow(app,item)!.mediaPlayers.first(where:{$0.id.frame != 0})!
        try app.dispatch(.page(.media(.item(item),blocked.id,.enterPictureInPicture)))
        try app.waitUntil("PiP policy rejection is reported") { try mediaRow(app,item)?.mediaError != nil }
        try expect(try mediaRow(app,item)?.mediaPlayers.contains(where:{$0.id == blocked.id && $0.pictureInPicture}) == false,"policy-denied PiP was claimed active")
        try JSONEncoder().encode(try mediaRow(app,item)).write(to:app.shotsDirectory.appendingPathComponent("pip-policy-failure.json"))
        try app.evaluate(page,"blockedFrame.remove()")
        try app.dispatch(.page(.media(.item(item),first.id,.play)))
        guard case .pageObservations(let observations) = try app.send(.pageObservations), case .ready(let document)? = observations[page]?.document else { throw Check(description:"source document missing") }
        var rule = SiteRule();rule.pictureInPictureExempt = true
        let target = SiteTarget(document:document,context:.profile(.default),origin:SiteOrigin(url)!)
        try app.dispatch(.site(.rule(target,rule)));try app.dispatch(.settings(.advanced(.autoPictureInPicture(true))))
        _ = try app.load(app.site.url("page2.html"))
        for _ in 0..<8 { try expect(try mediaRow(app,item)?.mediaPlayers.contains(where:{$0.pictureInPicture}) == false,"per-site exemption did not suppress auto PiP");Thread.sleep(forTimeInterval:0.1) }
        try app.dispatch(.tab(.focus(item)));try app.dispatch(.settings(.advanced(.autoPictureInPicture(false))))
        rule.pictureInPictureExempt = false;try app.dispatch(.site(.rule(target,rule)))
        guard case .hello(let before) = try app.send(.hello) else { throw Check(description:"hello missing") }
        let publicWindows = Set(try app.native().appWindows.filter(\.isVisible).map(\.number))
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let after) = try app.send(.hello), let privateWindow = after.windows.first(where:{!before.windows.contains($0)}) else { throw Check(description:"private window missing") }
        app.window = privateWindow;_ = try app.send(.activate(window:privateWindow))
        let privateItem = try app.load(url);try app.waitForPageInput(PageID(window:privateWindow,item:privateItem),at:url)
        try app.waitUntil("private media identity is isolated") { try mediaRow(app,privateItem)?.mediaPlayers.count == 1 }
        try app.dispatch(.page(.pictureInPicture(.video)))
        try app.waitUntil("private video PiP enters explicitly") { try mediaRow(app,privateItem)?.mediaPlayers.contains(where:{$0.pictureInPicture}) == true }
        try app.dispatch(.page(.pictureInPicture(.close)))
        try app.waitUntil("private video PiP exits") { try mediaRow(app,privateItem)?.mediaPlayers.contains(where:{$0.pictureInPicture}) == false }
        try app.dispatch(.page(.pictureInPicture(.document)))
        try app.waitUntil("private document PiP enters") { try mediaRow(app,privateItem)?.documentPictureInPicture == true }
        try app.recordWindows("private-document-pip")
        try app.dispatch(.window(.close));app.window = window;_ = try app.send(.activate(window:window))
        try app.waitUntil("closing private owner closes its native PiP window") { Set(try app.native().appWindows.filter(\.isVisible).map(\.number)).isSubset(of:publicWindows) }
        try app.recordWindows("private-pip-drained")
    }
    @Sendable static func pictureInPicture(_ app: AppUnderTest) throws {
        try app.dispatch(.settings(.advanced(.autoPictureInPicture(false))))
        let url=app.site.url("capture-media.html"), item=try app.load(app.site.url("capture-media.html"))
        let page=PageID(window:app.window!,item:item)
        try app.waitForPageInput(page,at:url)
        try app.waitUntil("ready video player") { try tab(item,in:app.view())?.mediaPlayers.isEmpty == false }
        let beforeVideo = Set(try app.native().appWindows.filter(\.isVisible).map(\.number))
        try app.perform(.menuAction(ActionID.videoPictureInPicture.rawValue))
        try app.waitUntil("explicit video PiP entered") { try tab(item,in:app.view())?.mediaPlayers.contains(where:{$0.pictureInPicture}) == true }
        try app.recordWindows("explicit-video-pip")
        try captureNewWindows(app,since:beforeVideo,name:"video-pip-window")
        try app.perform(.menuAction(ActionID.closePictureInPicture.rawValue))
        try app.waitUntil("video PiP exited") { try tab(item,in:app.view())?.mediaPlayers.contains(where:{$0.pictureInPicture}) == false }
        let beforeDocument = Set(try app.native().appWindows.filter(\.isVisible).map(\.number))
        try app.perform(.menuAction(ActionID.documentPictureInPicture.rawValue))
        try app.waitUntil("document PiP entered with an owned child window") { try tab(item,in:app.view())?.documentPictureInPicture == true }
        try app.recordWindows("document-pip")
        try captureNewWindows(app,since:beforeDocument,name:"document-pip-window")
        _ = try app.screenshot("document-pip-source")
        try app.perform(.menuAction(ActionID.closePictureInPicture.rawValue))
        try app.waitUntil("document PiP closes and restores its DOM") { try tab(item,in:app.view())?.documentPictureInPicture == false }
        try app.evaluate(page,"document.title='restored:'+!!document.querySelector('video')")
        try app.waitUntil("DOM reattached after document PiP") { try tab(item,in:app.view())?.title == "restored:true" }
        try app.waitUntil("restored video is observed playing") { try tab(item,in:app.view())?.mediaPlayers.contains(where:{$0.kind == .video && !$0.paused}) == true }
        try app.dispatch(.settings(.advanced(.autoPictureInPicture(true))))
        _ = try app.load(app.site.url("page2.html"))
        try app.waitUntil("automatic video PiP or explicit activation failure") {
            guard let row=try tab(item,in:app.view()) else { return false }
            return row.mediaPlayers.contains(where:{$0.pictureInPicture}) || row.mediaError != nil
        }
        guard let row=try tab(item,in:app.view()) else { throw Check(description:"video row lost") }
        try expect(row.mediaPlayers.contains(where:{$0.pictureInPicture}),"automatic PiP failed: "+(row.mediaError ?? "unknown"))
        try app.dispatch(.tab(.focus(item)))
        try app.waitUntil("automatic PiP reattaches when source becomes visible") { try tab(item,in:app.view())?.mediaPlayers.contains(where:{$0.pictureInPicture}) == false }
        try app.dispatch(.page(.pictureInPicture(.document)))
        try app.waitUntil("document PiP reenters") { try tab(item,in:app.view())?.documentPictureInPicture == true }
        try app.dispatch(.commandBar(.open(.editCurrent)));try app.dispatch(.commandBar(.submit(app.site.url("page2.html").absoluteString)))
        try app.waitUntil("navigation clears document PiP owner") { try tab(item,in:app.view())?.documentPictureInPicture == false }
        try app.recordWindows("pip-after-navigation")
        try app.waitForPageInput(page,at:app.site.url("page2.html"))
        try app.dispatch(.page(.pictureInPicture(.document)))
        try app.waitUntil("owned document PiP can remain active until quit") { try tab(item,in:app.view())?.documentPictureInPicture == true }
        try app.recordWindows("pip-active-before-clean-quit")

    }
    @Sendable static func probe(_ app: AppUnderTest) throws {
        let url = app.site.url("capture-media.html")
        let item = try app.load(url)
        let page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: url)
        let directory = app.dataDirectory.appendingPathComponent("capture-probe")
        guard case .text(let report) = try app.send(.captureProbe(page: page, directory: directory), timeout: 30) else { throw Check(description: "no probe response") }
        app.note(report)
        for name in ["area", "full", "portrait"] {
            let data = try Data(contentsOf: directory.appendingPathComponent(name + ".png"))
            try expect(data.count > 24 && Array(data.prefix(8)) == [137,80,78,71,13,10,26,10], "invalid probe PNG")
            func dimension(_ offset: Int) -> Int { data[offset..<(offset + 4)].reduce(0) { $0 * 256 + Int($1) } }
            try expect(dimension(16) > 100 && dimension(20) > 100, "empty capture")
            try data.write(to: app.shotsDirectory.appendingPathComponent("probe-" + name + ".png"))
        }
        try FileManager.default.copyItem(at: directory.appendingPathComponent("probe.json"), to: app.shotsDirectory.appendingPathComponent("probe.json"))
        try FileManager.default.copyItem(at: directory.appendingPathComponent("metrics.json"), to: app.shotsDirectory.appendingPathComponent("metrics.json"))
        _ = try app.screenshot("probe-embedded-page")
    }
}
