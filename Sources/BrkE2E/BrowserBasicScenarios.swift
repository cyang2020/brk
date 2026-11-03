import BrkBase
import BrkControl
import BrkDomain
import Foundation
import PDFKit

enum BrowserBasicScenarios {
    static let all = [
        Scenario("BB1", "offline MHTML, parsed PDF, owner-bound save/print cancellation and export bytes", cefOnly: "CEF document output", outputs),
        Scenario("BB2", "preset zoom changes real DOM scale; clipboard formats and navigation target Peek", cefOnly: "CEF DOM and pasteboard", zoomCopyNavigation),
        Scenario("BB3", "blank/sidebar isolation, floating Little window, stay on top, minimize and restore-off", cefOnly: "native windows", windows),
        Scenario("BB4", "menu copy/plain paste in HTML editors and frames; native command-bar editing", cefOnly: "native responder actions", editing),
        Scenario("BB5", "configured site search, calculator, private suggestion boundary and full repeated History", cefOnly: "actual fixture requests", commandBar),
        Scenario("BB6", "fixture-selected MHTML/PDF bytes, offline resources, and native print cancellation", cefOnly: "real CEF output callbacks", fixtureOutputs),
    ]

    private static func dispatch(_ app: AppUnderTest, _ window: WindowID, _ command: Command) throws {
        guard case .dispatched = try app.send(.dispatch(window: window, command: command)) else { throw Check(description: "Dispatch failed") }
    }
    private static func title(_ app: AppUnderTest, _ page: PageID) throws -> String? {
        let view = try app.view(page.window)
        if case .peek(let peek)? = view.overlay, peek.page == page { return peek.tab.title }
        return (allTabs(view) + tabRows(view.scratch?.rows ?? [])).first { $0.id == page.item }?.title
    }
    private static func waitTitle(_ app: AppUnderTest, _ page: PageID, _ expected: String) throws {
        try app.waitUntil("DOM title \(expected)") { try title(app, page) == expected }
    }
    private static func page(_ app: AppUnderTest, _ url: URL) throws -> PageID {
        let item = try app.load(url), page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: url)
        return page
    }
    private static func terminal(_ app: AppUnderTest, _ window: WindowID) throws -> OutputResult {
        var result: OutputResult?
        try app.waitUntil("output terminal result", timeout: 20) {
            if case .terminal(let value)? = try app.view(window).output?.stage { result = value; return true }; return false
        }
        return result!
    }
    private static func save(_ app: AppUnderTest, _ page: PageID, _ intent: OutputIntent, path: URL) throws -> FileReceipt {
        try app.perform(.configureSavePanel(window: page.window, path: path.path))
        try dispatch(app, page.window, .page(.output(intent)))
        try app.waitUntil("native save panel on initiating window") { try app.native(page.window).sheetClass?.contains("SavePanel") == true }
        try app.screenshotSheet(intent.rawValue + "-destination", window: page.window)
        try app.perform(.answerSavePanel(window: page.window, path: path.path))
        let result: OutputResult
        do { result = try terminal(app, page.window) }
        catch {
            try? app.perform(.cancelCurrentOutput(window: page.window))
            throw error
        }
        guard case .saved(let receipt) = result else { throw Check(description: "Output did not save") }
        try expect(receipt.url.resolvingSymlinksInPath() == path.resolvingSymlinksInPath(), "Output selected the wrong destination: \(receipt.url)")
        try expect(receipt.bytes == Int64(Data(contentsOf: path).count), "Output receipt byte count differs from disk")
        return receipt
    }

    /// The explicit control answer chooses an owned fixture path. It does not claim native save-chooser completion.
    private static func fixtureSave(_ app: AppUnderTest, _ page: PageID, _ intent: OutputIntent, path: URL) throws -> FileReceipt {
        try app.perform(.chooseOutputFixture(window: page.window, path: path.path))
        try dispatch(app, page.window, .page(.output(intent)))
        guard case .saved(let receipt) = try terminal(app, page.window) else { throw Check(description: "Fixture output failed") }
        try expect(receipt.bytes == Int64(Data(contentsOf: path).count), "Fixture file bytes differ from receipt")
        return receipt
    }

    @Sendable static func fixtureOutputs(_ app: AppUnderTest) throws {
        let port = try BrowserBasicInspection.unusedPort()
        app.remoteDebuggingPort = port
        try app.restart()
        let server = FixtureServer(root: app.site.root)
        try server.start(); defer { server.stop() }
        let page = try page(app, server.url("browser-basic.html"))
        let archive = app.dataDirectory.appendingPathComponent("fixture.mhtml"), pdf = app.dataDirectory.appendingPathComponent("fixture.pdf")
        let mhtml = try fixtureSave(app, page, .mhtml, path: archive)
        let exported = try fixtureSave(app, page, .pdf, path: pdf)
        guard let document = PDFDocument(url: pdf), document.pageCount > 0,
              document.string.map { $0.filter { !$0.isWhitespace }.contains("Browserbasicoutputfixture") } == true else { throw Check(description: "PDF did not contain the real fixture") }
        let evidence = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("artifacts/" + app.scenarioID, isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        for file in [archive, pdf] { try Data(contentsOf: file).write(to: evidence.appendingPathComponent(file.lastPathComponent), options: .atomic) }
        try JSONSerialization.data(withJSONObject: ["mhtmlBytes": mhtml.bytes, "pdfBytes": exported.bytes, "pdfPages": document.pageCount,
                                                    "destination": "explicit owned fixture answer; native chooser not claimed"], options: [.prettyPrinted, .sortedKeys])
            .write(to: evidence.appendingPathComponent("output-receipts.json"))
        try app.screenshot("pdf-generated")
        try dispatch(app, page.window, .page(.output(.print)))
        try app.waitUntil("native print sheet", timeout: 20) { try app.native(page.window).sheetClass != nil }
        try app.screenshotSheet("print-cancel", window: page.window)
        try app.perform(.cancelPrintPanel(window: page.window))
        guard case .cancelled = try terminal(app, page.window) else { throw Check(description: "Print cancellation did not complete") }
        let count = server.requestCount("/browser-basic.svg")
        server.stop()
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello), let owner = hello.windows.first(where: { (try? app.view($0).kind) == .incognito }),
              case .loaded(let item) = try app.send(.load(window: owner, url: archive)) else { throw Check(description: "Offline private context missing") }
        let offline = PageID(window: owner, item: item)
        try app.waitForPageInput(offline, at: archive)
        let observed = try BrowserBasicInspection.evaluate(port: port, document: archive,
            expression: "({url:location.href,text:document.body.innerText,imageWidth:document.querySelector('img')?.naturalWidth ?? -1})")
        try observed.write(to: evidence.appendingPathComponent("offline-dom.json"))
        let dom = try JSONSerialization.jsonObject(with: observed) as? [String: Any] ?? [:]
        try expect(dom["url"] as? String == archive.absoluteString, "Inspected the wrong archive target")
        try expect((dom["text"] as? String)?.contains("Browser basic output fixture") == true && dom["imageWidth"] as? Int == 64,
                   "Offline DOM/image differs: \(dom)")
        try expect(server.requestCount("/browser-basic.svg") == count, "Offline archive fetched a network image")
        try app.screenshot("offline-archive", window: owner)
        app.note("Real CEF MHTML/PDF callbacks produced parsed files; MHTML text/image reopened in a fresh private context with no additional image request. The destination was an explicit fixture answer, not native chooser acceptance. Print Cancel was native; no printer submission is claimed.")
    }

    @Sendable static func outputs(_ app: AppUnderTest) throws {
        let port = try BrowserBasicInspection.unusedPort()
        app.remoteDebuggingPort = port
        try app.restart()
        let server = FixtureServer(root: app.site.root)
        try server.start(); defer { server.stop() }
        let source = server.url("browser-basic.html")
        let page = try page(app, source)
        let archive = app.dataDirectory.appendingPathComponent("fixture.mhtml")
        let pdf = app.dataDirectory.appendingPathComponent("fixture.pdf")
        // Native save-panel input is verified by the file-panels slice. Use the explicit destination for byte
        // acceptance so a missing Return gesture cannot be mistaken for a lost renderer completion callback.
        let mhtml = try fixtureSave(app, page, .mhtml, path: archive)
        let exportedPDF = try fixtureSave(app, page, .pdf, path: pdf)
        guard let document = PDFDocument(url: pdf) else { throw Check(description: "Generated PDF failed to parse") }
        try expect(document.pageCount > 0 && document.string.map { $0.filter { !$0.isWhitespace }.contains("Browserbasicoutputfixture") } == true, "PDF missed actual fixture text")
        let evidence = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("artifacts/" + app.scenarioID, isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        for file in [archive, pdf] { try Data(contentsOf: file).write(to: evidence.appendingPathComponent(file.lastPathComponent), options: .atomic) }
        let receipt: [String: Any] = ["mhtmlBytes": mhtml.bytes, "pdfBytes": exportedPDF.bytes, "pdfPages": document.pageCount, "pdfContainsFixtureText": true,
                                      "destination": "explicit owned fixture answer; native save-panel gesture belongs to file-panels"]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]).write(to: evidence.appendingPathComponent("output-receipts.json"))

        try dispatch(app, page.window, .page(.output(.print)))
        try app.waitUntil("native print sheet belongs to source window", timeout: 20) { try app.native(page.window).sheetClass != nil }
        try app.screenshotSheet("print-dialog", window: page.window)
        try app.perform(.cancelPrintPanel(window: page.window))
        guard case .cancelled = try terminal(app, page.window) else { throw Check(description: "Native print cancellation was not reported") }

        try dispatch(app, page.window, .page(.output(.mhtml)))
        try app.waitUntil("source-close save sheet") { try app.native(page.window).sheetClass != nil }
        try dispatch(app, page.window, .tab(.close(.item(page.item))))
        try app.waitUntil("source close dismisses only its native sheet") { try app.native(page.window).sheetClass == nil }
        guard case .cancelled = try terminal(app, page.window) else { throw Check(description: "Closed source retained an output decision") }

        // A fresh private context has no access to the source browser's memory/disk HTTP cache.
        let resourceRequests = server.requestCount("/browser-basic.svg")
        server.stop()
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello), let privateWindow = hello.windows.first(where: { (try? app.view($0).kind) == .incognito }),
              case .loaded(let item) = try app.send(.load(window: privateWindow, url: archive)) else { throw Check(description: "Offline private window missing") }
        let offline = PageID(window: privateWindow, item: item)
        try app.waitForPageInput(offline, at: archive)
        // Chromium refuses the public ExecuteJavaScript API for MHTML. Read this actual archive target through
        // the opt-in inspection port, as BB6 does, rather than waiting for a script that cannot execute.
        let observed = try BrowserBasicInspection.evaluate(port: port, document: archive,
            expression: "({url:location.href,text:document.body.innerText,imageWidth:document.querySelector('img')?.naturalWidth ?? -1})")
        try observed.write(to: evidence.appendingPathComponent("offline-dom.json"))
        let dom = try JSONSerialization.jsonObject(with: observed) as? [String: Any] ?? [:]
        try expect(dom["url"] as? String == archive.absoluteString && (dom["text"] as? String)?.contains("Browser basic output fixture") == true && dom["imageWidth"] as? Int == 64,
                   "Offline archive text/image differs: \(dom)")
        try expect(server.requestCount("/browser-basic.svg") == resourceRequests, "Offline reopen made a network image request")
        try app.screenshot("offline-mhtml", window: privateWindow)
        app.note("MHTML reopened with its fixture server stopped in a fresh private context: fixture text and image width 64. PDFKit parsed \(document.pageCount) page(s). Native print Cancel was observed; printer submission is a separate gate.")
    }

    @Sendable static func zoomCopyNavigation(_ app: AppUnderTest) throws {
        let source = app.site.url("browser-basic.html")
        let page = try page(app, source)
        try app.evaluate(page, "document.title='width:'+innerWidth")
        var initialWidth = 0
        try app.waitUntil("initial rendered width") { initialWidth = Int((try title(app, page) ?? "").replacingOccurrences(of: "width:", with: "")) ?? 0; return initialWidth > 0 }
        for percent in [110, 125] {
            try app.dispatch(.page(.zoom(.zoomIn)))
            try app.waitUntil("effective \(percent)% zoom") { try app.view().urlPill.zoomPercent == percent }
        }
        try app.evaluate(page, "document.title='width:'+innerWidth")
        var zoomedWidth = 0
        try app.waitUntil("rendered width shrinks at 125 percent") { zoomedWidth = Int((try title(app, page) ?? "").replacingOccurrences(of: "width:", with: "")) ?? 0; return zoomedWidth > 0 && zoomedWidth < initialWidth }
        try expect(abs(Double(initialWidth) / Double(zoomedWidth) - 1.25) < 0.03, "DOM zoom ratio does not match 125%")
        try app.dispatch(.page(.zoom(.reset)))
        try app.evaluate(page, "document.title='A [title]'")
        try waitTitle(app, page, "A [title]")
        for (format, expected) in [(CopyURLFormat.plain, source.absoluteString), (.markdown, "[A \\[title\\]](\(source.absoluteString))"), (.quote, "> A [title]\n\(source.absoluteString)")] {
            try app.dispatch(.page(.copyURL(format)))
            try expect(try app.send(.readPasteboard) == .text(expected), "Clipboard \(format) differs")
        }
        try app.dispatch(.peek(.open(app.site.url("page2.html"))))
        guard case .peek(let peek)? = try app.view().overlay, let peekPage = peek.page else { throw Check(description: "Peek missing") }
        try app.waitForPageInput(peekPage, at: app.site.url("page2.html"))
        try app.press("cmd+shift+c")
        try expect(try app.send(.readPasteboard) == .text(app.site.url("page2.html").absoluteString), "Peek clipboard targeted its underlying tab")
        try app.dispatch(.page(.zoom(.zoomIn)))
        try app.evaluate(peekPage, "document.title='peek-width:'+innerWidth")
        try app.waitUntil("Peek received zoom and remains focused") { try app.native().focusedPage == peekPage }
        try app.screenshot("peek-zoom")
        try app.dispatch(.peek(.close))
        try app.press("cmd+l"); try app.type(app.site.url("page2.html?address-edit").absoluteString); try app.press("return")
        try app.waitForPageInput(page, at: app.site.url("page2.html?address-edit"))
        try app.dispatch(.page(.back(.focused)))
        try app.waitForPageInput(page, at: source)
        try app.dispatch(.page(.forward(.focused)))
        try app.waitForPageInput(page, at: app.site.url("page2.html?address-edit"))
        app.note("Real DOM width ratio \(initialWidth)/\(zoomedWidth) matched 125%; all three clipboard formats, Peek Copy URL, and same-tab Cmd+L/back/forward passed.")
    }

    @Sendable static func windows(_ app: AppUnderTest) throws {
        let owner = app.window!
        try app.dispatch(.window(.newBlank))
        guard case .hello(let hello) = try app.send(.hello), let blank = hello.windows.first(where: { (try? app.view($0).kind) == .blank }) else { throw Check(description: "Blank window missing") }
        let empty = try app.view(blank)
        try expect(empty.space.today.rows.isEmpty && empty.favorites.tiles.isEmpty, "Blank inherited sidebar rows")
        try dispatch(app, blank, .commandBar(.submit(app.site.url("browser-basic.html").absoluteString)))
        try dispatch(app, owner, .window(.toggleStayOnTop))
        try expect(try app.native(owner).windowLevel > app.native(blank).windowLevel, "Stay on top did not raise native stacking level")
        try dispatch(app, owner, .window(.toggleStayOnTop))
        try expect(try app.native(owner).windowLevel == 0, "Stay on top was not reversible")
        try dispatch(app, owner, .window(.newLittle(app.site.url("page2.html"))))
        guard case .hello(let withLittle) = try app.send(.hello), let little = withLittle.windows.first(where: { (try? app.view($0).kind) == .little }) else { throw Check(description: "Little window missing") }
        try expect(try app.native(little).windowLevel > 0, "Little window is not floating")
        try app.screenshot("blank-sidebar", window: blank)
        try app.screenshot("little-floating", window: little)
        _ = try app.send(.activate(window: owner))
        try dispatch(app, owner, .app(.minimize))
        try app.waitUntil("native minimize") { try app.native(owner).miniaturized }
        _ = try app.send(.activate(window: owner))
        try app.waitUntil("native restore") { try !app.native(owner).miniaturized }
        try dispatch(app, owner, .settings(.advanced(.restoreWindowsOnLaunch(false))))
        try app.flush(); try app.restart()
        guard case .hello(let restored) = try app.send(.hello) else { throw Check(description: "Restart missing") }
        try expect(restored.windows.count == 1, "Restore-off reopened extra windows")
        try expect(try app.native().pages.isEmpty && isCommandBar(app.view().overlay), "Restore-off loaded a saved page")
    }

    @Sendable static func editing(_ app: AppUnderTest) throws {
        let page = try page(app, app.site.url("browser-basic.html"))
        for element in ["input", "textarea", "editable", "frame-input"] {
            let setup: String
            if element == "editable" {
                setup = "const el=document.getElementById('editable');el.textContent='abcdef';el.focus();const r=document.createRange();r.setStart(el.firstChild,1);r.setEnd(el.firstChild,4);getSelection().removeAllRanges();getSelection().addRange(r);document.title='editing:editable'"
            } else {
                let target = element == "frame-input" ? "document.querySelector('iframe').contentDocument.getElementById('frame-input')" : "document.getElementById('\(element)')"
                setup = "{const el=\(target);el.focus();el.value='abcdef';el.setSelectionRange(1,4);document.title='editing:\(element)'}"
            }
            try app.evaluate(page, "{\(setup)}")
            try waitTitle(app, page, "editing:\(element)")
            try app.perform(.menuAction("Copy"))
            try app.waitUntil("native Copy from \(element)") { try app.send(.readPasteboard) == .text("bcd") }
            try app.perform(.menuAction("Cut")); try waitTitle(app, page, "value:aef")
            try app.perform(.menuAction("Undo")); try waitTitle(app, page, "value:abcdef")
            try app.perform(.menuAction("Redo")); try waitTitle(app, page, "value:aef")
            try app.perform(.pasteboard("Z"))
            try app.perform(.menuAction("Paste and Match Style")); try waitTitle(app, page, "value:aZef")
        }
        try app.press("cmd+l"); try app.press("cmd+a")
        try app.perform(.pasteboard(app.site.url("page2.html?native-paste").absoluteString))
        try app.perform(.menuAction("Paste")); try app.press("return")
        try app.waitForPageInput(page, at: app.site.url("page2.html?native-paste"))
        app.note("Native menu Copy/Cut/Undo/Redo/Paste and Match Style changed actual input, textarea, contenteditable and same-origin frame DOM values; native command-bar Paste navigated the same page.")
    }

    @Sendable static func commandBar(_ app: AppUnderTest) throws {
        let profile = ProfileID.default
        try app.dispatch(.settings(.profile(profile, .searchSuggestions(false))))
        try app.dispatch(.settings(.profile(profile, .addSiteSearch(name: "Fixture Search", keyword: "fixture", template: app.site.baseURL.absoluteString + "browser-basic-search.html?q={q}"))))
        try app.press("cmd+t"); try app.type("fixture"); try app.press("tab"); try app.type("a b&c"); try app.press("return")
        try app.waitUntil("configured site search reached the actual fixture") { currentTab(try app.view())?.title == "query:a b&c" }
        try expect(app.site.requestCount("/browser-basic-search.html") == 1, "Site search did not make exactly one fixture request")
        let before = app.site.requestCount("/suggest")
        try app.press("cmd+t"); try app.type("2+3*4"); try app.press("return")
        try expect(try app.send(.readPasteboard) == .text("14"), "Calculator did not copy its result")
        try expect(app.site.requestCount("/suggest") == before, "Calculator or opted-out search queried suggestions")
        let page = try page(app, app.site.url("browser-basic.html"))
        for _ in 0..<2 { try app.dispatch(.page(.reload(.focused, ignoringCache: true))); try app.waitForPageInput(page, at: app.site.url("browser-basic.html")) }
        try app.press("cmd+y")
        try app.waitUntil("History opened from the real key callback") { try app.view().history != nil }
        let history = try app.view().history ?? []
        try expect(history.filter { $0.url == app.site.url("browser-basic.html") }.count >= 3, "Repeated visits were lost")
        try app.screenshot("full-history")
        try app.flush(); try app.restart()
        let restored = try historyRows(app, returning: false)
        try expect(restored.filter { $0.url == app.site.url("browser-basic.html") }.count >= 3, "Repeated visits did not persist")
    }
}
