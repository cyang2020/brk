import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum BrowserOpsScenarios {
    static let all = [
        Scenario("BO1", "raw shortcut receipts, Chrome ordering, Downloads priority, remaps and two windows", cefOnly: "CEF keys", keys),
        Scenario("BO2", "real empty popup, document.write, opener, native identity and close", cefOnly: "CEF popup browsing contexts", popups),
        Scenario("BO3", "page source, DevTools panels and auxiliary closure with the owning page", cefOnly: "native developer windows", developer),
        Scenario("BO4", "DOM/video and native fullscreen, overlay-first Escape and focus return", cefOnly: "native fullscreen", fullscreen),
        Scenario("BO5", "real context-owned media-router enumeration and source rejection", cefOnly: "CEF media router", cast),
        Scenario("BO5C", "custom-profile media-router enumeration and source-close drain", cefOnly: "CEF media router context lifetime", castCustomProfile),
        Scenario("BO6", "transformations execute in native fields and web editing contexts", cefOnly: "real responder chain", transformations),
    ]
    private static func load(_ app: AppUnderTest, _ path: String) throws -> PageID {
        let url = app.site.url(path), item = try app.load(url)
        let page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: url)
        return page
    }
    private static func title(_ app: AppUnderTest, _ page: PageID) throws -> String? {
        let view = try app.view(page.window)
        return (allTabs(view) + tabRows(view.scratch?.rows ?? [])).first { $0.id == page.item }?.title
    }
    private static func facts(_ app: AppUnderTest, _ page: PageID) throws -> PageFacts {
        let native = try app.native(page.window)
        guard let facts = native.pages[page] ?? native.ownedPages?[page] else { throw Check(description: "Page facts missing") }
        return facts
    }
    private static func record<T: Encodable>(_ app: AppUnderTest, _ name: String, _ value: T) throws {
        let url = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent(app.scenarioID + "-" + name + ".json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url)
    }
    private static func clickedScript(_ app: AppUnderTest, _ page: PageID, _ script: String) throws {
        let encoded = String(decoding: try JSONEncoder().encode(script), as: UTF8.self)
        try app.evaluate(page, "(()=>{document.getElementById('bo-action')?.remove();let b=document.createElement('button');b.id='bo-action';b.textContent='Run browser operation';b.style='position:fixed;left:12px;top:12px;width:210px;height:55px;z-index:999999';b.onclick=()=>{(0,eval)(\(encoded))};document.body.append(b);document.title='BO action ready'})()")
        try app.waitUntil("operation button") { try title(app, page) == "BO action ready" }
        guard let frame = try facts(app, page).surfaceFrame else { throw Check(description: "No native page frame") }
        _ = try app.send(.activate(window: page.window))
        try app.click(at: CGPoint(x: frame.minX + 40, y: frame.minY + 35))
    }
    @Sendable static func keys(_ app: AppUnderTest) throws {
        let page = try load(app, "keys.html?swallow=1")
        defer { try? record(app, "keys", facts(app, page)) }
        try app.press("cmd+shift+j")
        try app.waitUntil("Downloads app priority") { if case .library(let library)? = try app.view().overlay { library.page == .downloads } else { false } }
        try expect(try title(app, page) == "keys:loads=1", "App-priority Downloads reached the renderer")
        try app.dispatch(.library(.close))
        try app.waitUntil("page focus after Downloads") { try app.native().focusedPage == page }
        try app.dispatch(.settings(.shortcuts(.setPriority(.viewDownloads, .page))))
        try app.press("cmd+shift+j")
        try app.waitUntil("explicit page-priority Downloads override") { try title(app, page) == NativeScenarios.keyTitle("cmd+shift+j", swallowed: true) }
        try expect(try app.view().overlay == nil, "A page-swallowed override opened Downloads")
        try app.dispatch(.settings(.shortcuts(.setPriority(.viewDownloads, .app))))
        try app.dispatch(.settings(.shortcuts(.setChord(.viewDownloads, KeyChord([.command, .option, .control], .j)))))
        try app.press("ctrl+alt+cmd+j")
        try app.waitUntil("remapped Downloads") { if case .library(let library)? = try app.view().overlay { library.page == .downloads } else { false } }
        try app.dispatch(.library(.close))
        try app.press("cmd+l"); try app.type("native-edit"); try app.press("cmd+a")
        try app.perform(.menuAction("Copy"))
        try expect(try app.send(.readPasteboard) == .text("native-edit"), "Native field did not execute Copy")
        try app.press("escape")
        let reload = try load(app, "keys.html?chrome-order")
        try app.press("cmd+r")
        try app.waitUntil("one unconsumed reload") { try title(app, reload) == "keys:loads=2" }
        try record(app, "chrome-order", facts(app, reload))
        try app.dispatch(.window(.new))
        guard case .hello(let hello) = try app.send(.hello), let second = hello.windows.first(where: { $0 != page.window }) else { throw Check(description: "No second window") }
        _ = try app.send(.activate(window: second))
        try app.press("ctrl+alt+cmd+j")
        try app.waitUntil("remap routes to second window") { if case .library(let library)? = try app.view(second).overlay { library.page == .downloads } else { false } }
        try expect(try app.view(page.window).overlay == nil, "Second-window key opened the first window's Library")
        try app.screenshot("downloads-second-window", window: second)
        app.note("Raw pre/post/Chrome receipts retained. Downloads default app priority, explicit page override, remapping, native editor and separate window routing exercised.")
    }
    @Sendable static func popups(_ app: AppUnderTest) throws {
        let page = try load(app, "browser-basic.html?popup")
        defer { try? record(app, "popup-final", facts(app, page)) }
        try clickedScript(app, page, "window.boChild=window.open('','bo-child','width=420,height=260');if(boChild){boChild.document.write('<title>Owned popup</title><body>Written popup</body>');boChild.document.close();document.title='popup:'+boChild.document.body.textContent+':'+(boChild.opener===window)}else{document.title='popup:blocked'}")
        try app.waitUntil("document.write and opener survive") { try title(app, page) == "popup:Written popup:true" }
        try app.waitUntil("owned native popup appears") { !(try facts(app, page).auxiliaryWindows ?? []).isEmpty }
        let popup = try facts(app, page)
        guard let metadata = popup.popupRequests?.last else { throw Check(description: "No raw popup metadata") }
        try expect(metadata.popupID != nil && metadata.sourceFrame != nil && metadata.userGesture && metadata.width == 420,
                   "Popup lost identity, frame, gesture or features")
        try record(app, "popup-open", popup)
        try app.recordWindows("popup-open")
        try app.evaluate(page, "boChild.close();document.title='popup:closed'")
        try app.waitUntil("native child closure drains") { try facts(app, page).auxiliaryBrowsers?.isEmpty == true }
        let nonce = UUID().uuidString
        var auth = URLComponents(url: app.site.url("browser-ops-auth.html"), resolvingAgainstBaseURL: false)!
        let returnOrigin = "http://127.0.0.1:\(auth.port!)"
        auth.host = "localhost"
        auth.queryItems = [URLQueryItem(name: "nonce", value: nonce), URLQueryItem(name: "returnOrigin", value: returnOrigin)]
        let authURL = String(decoding: try JSONEncoder().encode(auth.url!.absoluteString), as: UTF8.self)
        try clickedScript(app, page, "window.addEventListener('message',e=>{if(e.source===window.boChild&&e.origin==='http://localhost:\(auth.port!)'&&e.data.kind==='bo-auth'&&e.data.nonce==='\(nonce)')document.title='auth:opener-preserved'});window.boChild=window.open(\(authURL),'bo-auth-window')")
        try app.waitUntil("cross-origin named popup posts to its real opener") { try title(app, page) == "auth:opener-preserved" }
        try record(app, "cross-origin-opener", facts(app, page))
        try app.evaluate(page, "boChild.close()")
        try app.waitUntil("auth child closes") { try facts(app, page).auxiliaryBrowsers?.isEmpty == true }
        try clickedScript(app, page, "window.boChild=window.open('','bo-child-again','width=420,height=260');if(boChild){boChild.document.write('<body>Close with owner</body>');boChild.document.close();document.title='popup:second'}")
        try app.waitUntil("second popup") { try title(app, page) == "popup:second" }
        let windows = Set(try facts(app, page).auxiliaryWindows ?? [])
        try app.dispatch(.tab(.close(.item(page.item))))
        try app.waitUntil("source close removes native popup windows") {
            let visible = Set(try app.native().appWindows.filter(\.isVisible).map(\.number))
            return windows.isDisjoint(with: visible)
        }
        try privatePopup(app)
        app.note("The real CEF popup retained document.write and opener. Raw popup/frame/gesture/features were observed; child and owner-close paths drained.")
    }
    private static func privatePopup(_ app: AppUnderTest) throws {
        let marker = "bo-private-" + UUID().uuidString
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello),
              let window = hello.windows.first(where: { (try? app.view($0).kind) == .incognito }),
              case .loaded(let item) = try app.send(.load(window: window, url: app.site.url("browser-basic.html?" + marker))) else {
            throw Check(description: "Private popup owner missing")
        }
        let page = PageID(window: window, item: item)
        try app.waitForPageInput(page, at: app.site.url("browser-basic.html?" + marker))
        try clickedScript(app, page, "document.cookie='bo_private=\(marker);path=/';window.boChild=window.open('','bo-private-child','width=420,height=260');boChild.document.write('<body>Private child</body>');boChild.document.close();document.title='private:opened'")
        try app.waitUntil("private native child exists") { !(try facts(app, page).auxiliaryWindows ?? []).isEmpty }
        _ = try app.send(.load(window: window, url: app.site.url("page2.html")))
        try app.waitUntil("private source is hidden") { try !app.view(window).content.panes.contains { $0.tab == item } }
        try app.evaluate(page, "document.title='private:'+boChild.document.cookie.includes('\(marker)')+':'+(boChild.opener===window)")
        try app.waitUntil("hidden source retains private popup context and opener") { try title(app, page) == "private:true:true" }
        let windows = Set(try facts(app, page).auxiliaryWindows ?? [])
        try record(app, "hidden-private-popup", facts(app, page))
        _ = try app.send(.dispatch(window: window, command: .window(.close)))
        try app.waitUntil("last private owner closes its popup") {
            windows.isDisjoint(with: Set(try app.native().appWindows.filter(\.isVisible).map(\.number)))
        }
        let publicPage = try load(app, "browser-basic.html?public-after-private")
        try app.evaluate(publicPage, "document.title='public-private-cookie:'+document.cookie.includes('bo_private=')")
        try app.waitUntil("private popup cookie is absent publicly") { try title(app, publicPage) == "public-private-cookie:false" }
        try app.flush()
        let saved = try String(contentsOf: app.dataDirectory.appendingPathComponent("state.json"), encoding: .utf8)
        try expect(!saved.contains(marker), "Private popup identity entered saved metadata")
    }
    @Sendable static func developer(_ app: AppUnderTest) throws {
        let page = try load(app, "browser-basic.html?developer")
        defer { try? record(app, "developer-final", facts(app, page)) }
        try app.perform(.menuAction("View Source"))
        try app.waitUntil("source text in owned native window") { try facts(app, page).developerResult?.hasPrefix("Source displayed:") == true }
        try record(app, "source", facts(app, page))
        for panel in [DeveloperOperation.console, .network] {
            _ = try app.send(.dispatch(window: page.window, command: .page(.developer(panel))))
            try app.waitUntil("DevTools \(panel.rawValue) selected", timeout: 12) { try facts(app, page).developerResult == panel.rawValue + " selected" }
            try record(app, panel.rawValue, facts(app, page))
        }
        _ = try app.send(.dispatch(window: page.window, command: .page(.developer(.inspect))))
        try app.waitUntil("real DevTools belongs to page") { try facts(app, page).hasDevTools == true }
        let windows = Set(try facts(app, page).auxiliaryWindows ?? [])
        try app.recordWindows("developer-windows")
        try app.dispatch(.tab(.close(.item(page.item))))
        try app.waitUntil("developer windows close with owner") {
            let visible = Set(try app.native().appWindows.filter(\.isVisible).map(\.number))
            return windows.isDisjoint(with: visible)
        }
    }
    @Sendable static func fullscreen(_ app: AppUnderTest) throws {
        let page = try load(app, "browser-basic.html?fullscreen")
        for video in [false, true] {
            try clickedScript(app, page, "{let el=document.documentElement;\(video ? "let canvas=document.createElement('canvas');canvas.width=64;canvas.height=64;canvas.getContext('2d').fillRect(0,0,64,64);el=document.createElement('video');el.controls=true;el.muted=true;el.srcObject=canvas.captureStream(5);document.body.append(el);el.play();window.boVideo=el;" : "")document.onfullscreenchange=()=>document.title='fullscreen:'+!!document.fullscreenElement;el.requestFullscreen().catch(e=>document.title='fullscreen-error:'+e.name)}")
            try app.waitUntil("DOM fullscreen reaches native window", timeout: 15) { try title(app, page) == "fullscreen:true" && app.native().fullscreen }
            if video {
                try app.evaluate(page, "boVideo.play().then(()=>document.title='video-playing:'+(!boVideo.paused&&boVideo.readyState>=2))")
                try app.waitUntil("actual captured video playback") { try title(app, page) == "video-playing:true" }
            }
            try app.dispatch(.library(.open(.history)))
            try app.press("escape")
            try app.waitUntil("overlay closes before fullscreen") { try app.view().overlay == nil }
            try expect(try app.native().fullscreen, "First Escape left fullscreen before closing overlay")
            try app.press("escape")
            try app.waitUntil("page fullscreen exits native window", timeout: 15) { try !app.native().fullscreen }
            try app.waitUntil("focus returns to document") { try app.native().focusedPage == page }
        }
        try app.press("ctrl+cmd+f")
        try app.waitUntil("native fullscreen shortcut", timeout: 15) { try app.native().fullscreen }
        try app.press("escape")
        try app.waitUntil("native fullscreen Escape", timeout: 15) { try !app.native().fullscreen }
        try app.screenshot("fullscreen-focus-returned")
        app.note("Actual NSWindow style and DOM fullscreen were observed for document/video elements and injected native key input. Physical keys and traffic-light gestures remain manual.")
    }
    @Sendable static func cast(_ app: AppUnderTest) throws {
        let page = try load(app, "browser-basic.html?cast")
        defer { try? record(app, "media-router", facts(app, page)) }
        try app.perform(.menuAction("Cast"))
        try app.waitUntil("real media-router enumeration", timeout: 15) {
            let f = try facts(app, page)
            return (f.castSinkNotifications ?? 0) > 0 && (f.castRouteNotifications ?? 0) > 0 && f.castSourceSupported != nil
        }
        let result = try facts(app, page)
        try expect(result.castSourceSupported == false, "The pinned router unexpectedly accepted arbitrary HTTP page mirroring")
        try app.recordWindows("cast-receivers")
        app.note("Real request-context sink/route enumeration returned \(result.castSinks ?? []). GetSource rejected HTTP page mirroring. No native route creation or termination is claimed without a receiver. ABI callback/termination ownership is covered separately by raw unit fixtures.")
    }
    @Sendable static func castCustomProfile(_ app: AppUnderTest) throws {
        try app.dispatch(.profile(.create(name: "Cast owner", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings),
              let profile = settings.profiles.first(where: { $0.profile.name == "Cast owner" })?.profile.id else { throw Check(description: "Cast profile missing") }
        try app.dispatch(.profile(.assign(.current, to: profile)))
        try cast(app)
    }
    @Sendable static func transformations(_ app: AppUnderTest) throws {
        let page = try load(app, "browser-basic.html?transformations")
        for element in ["input", "textarea", "editable", "frame-input"] {
            let target = element == "frame-input" ? "document.querySelector('iframe').contentDocument.getElementById('frame-input')" : "document.getElementById('\(element)')"
            let setup = element == "editable"
                ? "let el=\(target);el.textContent='abCdef';el.focus();let r=document.createRange();r.setStart(el.firstChild,1);r.setEnd(el.firstChild,4);getSelection().removeAllRanges();getSelection().addRange(r)"
                : "let el=\(target);el.value='abCdef';el.focus();el.setSelectionRange(1,4)"
            try app.evaluate(page, "{\(setup);document.title='transform-ready:\(element)'}")
            try app.waitUntil("transform selection ready") { try title(app, page) == "transform-ready:" + element }
            try app.perform(.menuAction("Make Upper Case"))
            try app.waitUntil("uppercase selection in \(element)") { try title(app, page) == "value:aBCDef" }
        }
        try app.press("cmd+l"); try app.type("mixed Text"); try app.press("cmd+a")
        try app.perform(.menuAction("Make Upper Case")); try app.perform(.menuAction("Copy"))
        try expect(try app.send(.readPasteboard) == .text("MIXED TEXT"), "Native field uppercase failed")
        try app.press("escape")
        try app.screenshot("transformations")
    }
}
