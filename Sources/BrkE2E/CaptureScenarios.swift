import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum CaptureScenarios {
    static let all = [Scenario("CaptureProduct", "area, full-page, portrait, real library export/restart/remove and private memory", cefOnly: "embedded captures", product),
        Scenario("CapturePiP", "explicit video/document PiP, automatic video and source lifecycle", cefOnly: "embedded PiP", pictureInPicture),
        Scenario("CaptureProbe", "embedded Chrome capture and separate video/document PiP probes", cefOnly: "embedded DevTools", probe)]
    static func library(_ app: AppUnderTest) throws -> LibrarySnapshot? { if case .library(let value)? = try app.view().overlay { value } else { nil } }
    static func pngSize(_ bytes: Data) -> [Int] { [16,20].map { offset in bytes[offset..<(offset+4)].reduce(0) { $0*256+Int($1) } } }
    static func captureRecord(_ app: AppUnderTest, mode: CaptureMode, previous: Int) throws -> CaptureRecord {
        try app.waitUntil("capture reaches Media as a real indexed PNG", timeout:20) { try library(app)?.captures.count == previous + 1 }
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
        try app.click(.tabTool("capture-export"))
        try app.waitUntil("real PNG save sheet opens") { if case .menuItems = try? app.send(.sidebarPanel(window:app.window, action:.inspect)) { true } else { false } }
        _ = try app.send(.sidebarPanel(window:app.window, action:.capture(path:app.shotsDirectory.appendingPathComponent("product-export-sheet.png").path)))
        _ = try app.send(.sidebarPanel(window:app.window, action:.save(directory:app.dataDirectory.path,filename:"exported-capture.png")),timeout:15)
        let exported=app.dataDirectory.appendingPathComponent("exported-capture.png")
        try app.waitUntil("native save panel exports actual PNG bytes",timeout:15) { FileManager.default.fileExists(atPath:exported.path) }
        try expect(try Data(contentsOf:exported) == Data(contentsOf:library(app)!.captureFiles[area.id]!),"export changed PNG bytes")
        try app.restart()
        try app.dispatch(.library(.open(.media)))
        try app.waitUntil("capture index survives restart") { try library(app)?.captures.count == 3 }
        try app.dispatch(.capture(.remove(area.id)))
        try app.waitUntil("remove deletes PNG and index row") { try library(app)?.captures.count == 2 }
        try app.dispatch(.library(.close))
        try app.dispatch(.tab(.focus(item)))
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
        let evidence=try JSONEncoder().encode([full,area,portrait]);try evidence.write(to:app.shotsDirectory.appendingPathComponent("product-records.json"))
    }
    @Sendable static func pictureInPicture(_ app: AppUnderTest) throws {
        try app.dispatch(.settings(.advanced(.autoPictureInPicture(false))))
        let url=app.site.url("capture-media.html"), item=try app.load(app.site.url("capture-media.html"))
        let page=PageID(window:app.window!,item:item)
        try app.waitForPageInput(page,at:url)
        try app.waitUntil("ready video player") { try tab(item,in:app.view())?.mediaPlayers.isEmpty == false }
        try app.perform(.menuAction(ActionID.videoPictureInPicture.rawValue))
        try app.waitUntil("explicit video PiP entered") { try tab(item,in:app.view())?.mediaPlayers.contains(where:{$0.pictureInPicture}) == true }
        try app.recordWindows("explicit-video-pip")
        try app.perform(.menuAction(ActionID.closePictureInPicture.rawValue))
        try app.waitUntil("video PiP exited") { try tab(item,in:app.view())?.mediaPlayers.contains(where:{$0.pictureInPicture}) == false }
        try app.perform(.menuAction(ActionID.documentPictureInPicture.rawValue))
        try app.waitUntil("document PiP entered with an owned child window") { try tab(item,in:app.view())?.documentPictureInPicture == true }
        try app.recordWindows("document-pip")
        _ = try app.screenshot("document-pip-source")
        try app.perform(.menuAction(ActionID.closePictureInPicture.rawValue))
        try app.waitUntil("document PiP closes and restores its DOM") { try tab(item,in:app.view())?.documentPictureInPicture == false }
        try app.evaluate(page,"document.title='restored:'+!!document.querySelector('video')")
        try app.waitUntil("DOM reattached after document PiP") { try tab(item,in:app.view())?.title == "restored:true" }
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
