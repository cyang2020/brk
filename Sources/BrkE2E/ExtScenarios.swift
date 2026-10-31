import BrkBase
import BrkControl
import BrkDomain
import Foundation

/// Production paths only. Native panel gestures and OS authorization are reported separately.
enum ExtScenarios {
    static let all = [
        Scenario("Ext-catalog", "incognito toggle readback, both private script outcomes and profile pins", cefOnly: "CEF extensions", catalog),
        Scenario("Ext-shortcuts", "shortcut editor, conflicts, restart and Brk remap priority", cefOnly: "CEF extension commands", shortcuts),
        Scenario("Ext-loading", "remembered denial and origin readback while the committed document is loading", cefOnly: "CEF permissions", loading),
        Scenario("Ext-blocking", "main-frame, cross-origin frame, redirect and selected EasyList subset", cefOnly: "CEF IO request filtering", blocking),
        Scenario("Ext-media", "audible WebAudio, suspended WebAudio and hidden media scheduling", cefOnly: "Chromium lifecycle", media),
        Scenario("Ext-controls", "origin/profile readback, copy and local link export", cefOnly: "native site controls", controls),
    ]
    static func js(_ text: String) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: [text]), as: UTF8.self).dropFirst().dropLast().description
    }
    static func catalogValue(_ app: AppUnderTest, _ id: String) throws -> BrowserExtension? {
        try SitePolicyScenarios.controls(app).extensions.first { $0.id == id }
    }
    @Sendable static func catalog(_ app: AppUnderTest) throws {
        let (item, fixture) = try ExtensionScenarios.selectedFixture(app)
        defer {
            _ = try? app.screenshotSiteControls("catalog-final")
            if let value = try? app.send(.siteControls), let data = try? ControlWire.encode(value) {
                try? data.write(to: app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/Ext-catalog-controls.json"))
            }
        }
        try app.click(.settingsField("extension-pin-" + fixture.id))
        try expect(try SitePolicyScenarios.controls(app).pinnedExtensions.contains(fixture.id), "public profile pin missing")
        try expect(fixture.canChangeIncognito == true, "fixture incognito permission is not editable")
        for allowed in [false, true, false] {
            if try catalogValue(app, fixture.id)?.incognitoAllowed != allowed {
                try app.click(.settingsField("extension-incognito-" + fixture.id))
            } else { try app.dispatch(.site(.extensionIncognito(fixture.id, allowed))) }
            try app.waitUntil("Chromium incognito readback \(allowed)") {
                if let error = try SitePolicyScenarios.controls(app).extensionError { throw Check(description: error) }
                return try catalogValue(app, fixture.id)?.incognitoAllowed == allowed
            }
            try app.dispatch(.site(.closeControls))
            try app.dispatch(.window(.newIncognito))
            guard case .hello(let hello) = try app.send(.hello),
                  let privateWindow = try hello.windows.first(where: { try app.view($0).kind == .incognito }),
                  case .loaded(let privateItem) = try app.send(.load(window: privateWindow, url: app.site.url("site-policy.html"))) else {
                throw Check(description: "private fixture window missing")
            }
            try app.waitForPageInput(PageID(window: privateWindow, item: privateItem), at: app.site.url("site-policy.html"))
            try app.perform(.evaluate(page: PageID(window: privateWindow, item: privateItem), script: "document.title='private-extension:'+document.documentElement.getAttribute('data-brk-extension')"))
            try app.waitUntil("private content script \(allowed)") {
                let rows = tabRows(try app.view(privateWindow).scratch?.rows ?? [])
                return rows.first { $0.id == privateItem }?.title == "private-extension:" + (allowed ? "installed" : "null")
            }
            _ = try app.send(.dispatch(window: privateWindow, command: .site(.invokeExtension(fixture.id))))
            _ = try app.send(.dispatch(window: privateWindow, command: .window(.close)))
            _ = try app.send(.activate(window: app.window!))
            try app.dispatch(.tab(.focus(item))); try app.dispatch(.site(.nativeExtensions))
            try app.waitUntil("catalog restored") { try catalogValue(app, fixture.id) != nil }
        }
        try app.flush(); try app.restart(); try app.dispatch(.site(.nativeExtensions))
        try app.waitUntil("pin and disabled private permission survive restart") {
            try catalogValue(app, fixture.id)?.incognitoAllowed == false && SitePolicyScenarios.controls(app).pinnedExtensions.contains(fixture.id)
        }
        _ = try app.screenshotSiteControls("incognito-and-pins")
        app.note("Only the selected spanning fixture was installed. Both real private content-script outcomes and permission revocation were checked; private actions were refused by the production reducer.")
    }

    @Sendable static func shortcuts(_ app: AppUnderTest) throws {
        let (item, fixture) = try ExtensionScenarios.selectedFixture(app)
        let command = "fixture-command"
        try app.dispatch(.site(.closeControls)); try app.dispatch(.tab(.focus(item)))
        try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("site-policy.html"))
        try app.dispatch(.site(.nativeExtensions))
        try app.waitUntil("installed shortcut editor") { try catalogValue(app, fixture.id) != nil }
        defer {
            _ = try? app.screenshotSiteControls("shortcut-final")
            if let value = try? app.send(.siteControls), let data = try? ControlWire.encode(value) {
                try? data.write(to: app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/Ext-shortcuts-controls.json"))
            }
        }
        // Drive the native text editor and its Save action, not the manager's mutation API directly.
        try app.click(.settingsField("extension-shortcut-" + fixture.id + "-" + command))
        try app.press("cmd+a"); try app.type("cmd+shift+u")
        try app.click(.settingsField("extension-shortcut-save-" + fixture.id + "-" + command))
        try app.waitUntil("edited Chromium shortcut readback") {
            if let error = try SitePolicyScenarios.controls(app).extensionError { throw Check(description: error) }
            return try catalogValue(app, fixture.id)?.commands?.contains { $0.name == command && ExtensionShortcuts.chord($0.keybinding) == KeyChord([.command, .shift], .u) } == true
        }
        try app.click(.settingsField("extension-shortcut-" + fixture.id + "-" + command))
        try app.press("cmd+shift+u"); app.sleep(0.5)
        try expect(try tab(item, in: app.view())?.title == "Site policy fixture", "native editor leaked the extension command to the page")
        try app.dispatch(.site(.extensionShortcut(fixture.id, "_execute_action", "cmd+shift+u")))
        try expect(try SitePolicyScenarios.controls(app).extensionError?.contains("already assigned") == true, "duplicate shortcut did not report a conflict")
        try app.dispatch(.site(.extensionShortcut(fixture.id, command, "cmd+t")))
        try expect(try SitePolicyScenarios.controls(app).extensionError?.contains("reserved") == true, "reserved shortcut did not report a conflict")
        _ = try app.screenshotSiteControls("shortcut-editor")
        try app.dispatch(.site(.closeControls)); try app.dispatch(.tab(.focus(item)))
        try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("site-policy.html"))
        try app.flush(); try app.restart()
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("site-policy.html"))
        try app.press("cmd+shift+u")
        try waitForTitle(app, item, "extension-command:fixture-command")
        try app.dispatch(.settings(.shortcuts(.setChord(.newTab, KeyChord([.command, .shift], .u)))))
        try app.press("cmd+shift+u")
        try app.waitUntil("Brk app-priority remap opens command bar") { isCommandBar(try app.view().overlay) }
        try app.press("escape")
        try app.dispatch(.settings(.shortcuts(.reset(.newTab))))
        app.note("Native editing, duplicate/reserved errors, persisted command execution, and a later Brk app-priority remap were exercised. Native editor/page-first routing also has reducer tests using the one key table.")
    }

    @Sendable static func loading(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, item, "Site policy fixture")
        try app.dispatch(.site(.controls))
        guard let target = try SitePolicyScenarios.controls(app).target else { throw Check(description: "origin target missing") }
        try app.dispatch(.site(.permission(target, target.origin, [.notifications], .deny)))
        try app.dispatch(.site(.closeControls))
        try app.dispatch(.commandBar(.open(.editCurrent))); try app.dispatch(.commandBar(.submit(app.site.url("held-document").absoluteString)))
        defer { app.site.releaseHeldDocument() }
        try app.waitUntil("committed loading origin", timeout: 5) {
            guard case .pageObservations(let observations) = try app.send(.pageObservations),
                  case .loading = observations[PageID(window: app.window!, item: item)]?.document else { return false }
            return observations[PageID(window: app.window!, item: item)]?.committedURL == app.site.url("held-document")
        }
        try app.dispatch(.site(.controls))
        let value = try SitePolicyScenarios.controls(app)
        try expect(value.target?.origin == target.origin && value.rule.permissions[.notifications] == .deny, "loading document lost remembered readback")
        try SitePolicyScenarios.evaluate(app, item, "Notification.requestPermission().then(x=>document.title='loading-permission:'+x)")
        try waitForTitle(app, item, "loading-permission:denied", timeout: 4)
        _ = try app.screenshotSiteControls("remembered-during-loading")
        app.site.releaseHeldDocument()
        app.note("A real committed loading document read the saved origin denial and Chromium resolved its notification request as denied. No OS prompt or OS permission change was attempted.")
    }

    @Sendable static func blocking(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, item, "Site policy fixture")
        let blockedPath = "/brk-blocked-tracker/tracker.js"
        let baseline = app.site.requestCount(blockedPath)
        let frame = "http://frame.brk.test:\(app.site.port)" + blockedPath
        try SitePolicyScenarios.evaluate(app, item, "let f=document.createElement('iframe');f.src=\(js(frame));document.body.append(f)")
        app.sleep(0.8)
        try expect(app.site.requestCount(blockedPath) == baseline, "cross-origin blocked frame reached server")
        try SitePolicyScenarios.evaluate(app, item, "fetch('/site-policy-redirect').then(r=>document.title='redirect:'+r.ok).catch(()=>document.title='redirect:blocked')")
        try waitForTitle(app, item, "redirect:blocked")
        try expect(app.site.requestCount("/site-policy-redirect") > 0 && app.site.requestCount(blockedPath) == baseline, "redirect destination escaped request filter")
        try app.dispatch(.site(.controls))
        guard let frameTarget = try SitePolicyScenarios.controls(app).target else { throw Check(description: "frame policy target missing") }
        var frameRule = SiteRule(); frameRule.blocking = false
        try app.dispatch(.site(.rule(frameTarget, frameRule)))
        try SitePolicyScenarios.evaluate(app, item, "let allowed=document.createElement('iframe');allowed.src=\(js(frame));document.body.append(allowed)")
        try app.waitUntil("unblocked cross-origin frame positive control") { app.site.requestCount(blockedPath) == baseline + 1 }
        frameRule.blocking = true
        try app.dispatch(.site(.rule(frameTarget, frameRule))); try app.dispatch(.site(.closeControls))
        let permitted = app.site.requestCount(blockedPath)
        _ = try app.load(app.site.url("brk-blocked-tracker/tracker.js"))
        app.sleep(0.8)
        try expect(app.site.requestCount(blockedPath) == permitted, "blocked main-frame request reached server")
        try app.dispatch(.tab(.focus(item))); try app.dispatch(.site(.controls))
        guard let context = try SitePolicyScenarios.controls(app).context else { throw Check(description: "rules context missing") }
        let source = app.dataDirectory.appendingPathComponent("selected-easylist.txt")
        try Data(("! selected subset\n|" + app.site.url("page2.html").absoluteString + "\n##.brk-advertisement\n").utf8).write(to: source)
        try app.dispatch(.site(.selectedBlockingRules(source, context)))
        try app.waitUntil("selected EasyList subset readback") { try SitePolicyScenarios.controls(app).rulesError == nil && SitePolicyScenarios.controls(app).rulesVersion == 1 }
        app.sleep(0.5)
        let before = app.site.requestCount("/page2.html")
        try SitePolicyScenarios.evaluate(app, item, "fetch('/page2.html').then(()=>document.title='import:allowed').catch(()=>document.title='import:blocked')")
        try waitForTitle(app, item, "import:blocked")
        try expect(app.site.requestCount("/page2.html") == before, "imported URL-prefix rule did not block")
        try Data("||ads.example^$third-party\n".utf8).write(to: source)
        try app.dispatch(.site(.selectedBlockingRules(source, context)))
        try app.waitUntil("unsupported rule refresh error") { try SitePolicyScenarios.controls(app).rulesError?.contains("line 1") == true }
        try SitePolicyScenarios.evaluate(app, item, "fetch('/page2.html').then(()=>document.title='retained:allowed').catch(()=>document.title='retained:blocked')")
        try waitForTitle(app, item, "retained:blocked")
        app.note("Blocked main frame, cross-origin iframe and redirected destination produced zero target-server hits. Selected subset import blocked a new URL; an invalid refresh retained that working rule.")
    }

    @Sendable static func media(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("tab-tools-audio.html"))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("tab-tools-audio.html"))
        try app.dispatch(.site(.controls))
        guard let target = try SitePolicyScenarios.controls(app).target else { throw Check(description: "media target missing") }
        var rule = SiteRule(); rule.suspendWhenHidden = true
        try app.dispatch(.site(.rule(target, rule))); try app.dispatch(.site(.closeControls))
        try SitePolicyScenarios.evaluate(app, item, "window.extTick=setInterval(()=>fetch('/ext-media-tick',{cache:'no-store'}),100)")
        let card = try app.native().computed.cards[0].rect
        try app.click(at: CGPoint(x: card.minX + 80, y: card.minY + 50))
        try app.waitUntil("audible WebAudio readback") { try tab(item, in: app.view())?.audible == true }
        _ = try app.load(app.site.url("page2.html"))
        let before = app.site.requestCount("/ext-media-tick")
        try app.waitUntil("hidden audible WebAudio keeps scheduling", timeout: 5) { app.site.requestCount("/ext-media-tick") > before + 1 }
        try app.dispatch(.tab(.focus(item)))
        try SitePolicyScenarios.evaluate(app, item, "suspend()")
        try app.waitUntil("suspended audio becomes inaudible", timeout: 6) { try tab(item, in: app.view())?.audible == false }
        _ = try app.load(app.site.url("page2.html"))
        app.sleep(1)
        let stopped = app.site.requestCount("/ext-media-tick"); app.sleep(1.4)
        try expect(app.site.requestCount("/ext-media-tick") == stopped, "suspended WebAudio prevented suspension")
        try SitePolicyScenarios.evaluate(app, item, "clearInterval(timer)")
        func matrix(_ name: String, setup: String, active: Bool) throws {
            try app.dispatch(.tab(.focus(item)))
            let marker = "matrix:" + name + ":"
            let readback = "JSON.stringify(Array.from(document.querySelectorAll('audio,video')).map(x=>({tag:x.tagName,paused:x.paused,ended:x.ended,muted:x.muted,ready:x.readyState,time:x.currentTime})))"
            try SitePolicyScenarios.evaluate(app, item, "(async()=>{if(window.extElement){extElement.pause();extElement.remove()}" + setup + ";document.title=" + js(marker) + "+" + readback + "})().catch(e=>document.title='matrix-error:'+e.message)")
            var proof = ""
            try app.waitUntil("actual DOM media state before hiding " + name) {
                guard let title = try tab(item, in: app.view())?.title, title.hasPrefix(marker) else { return false }
                proof = String(title.dropFirst(marker.count))
                if active {
                    let values = try JSONSerialization.jsonObject(with: Data(proof.utf8)) as? [[String: Any]] ?? []
                    try expect(values.contains { $0["paused"] as? Bool == false && $0["ended"] as? Bool == false }, "fixture is not playing: " + proof)
                }
                return true
            }
            app.note(name + " before hiding: " + proof)
            _ = try app.load(app.site.url("page2.html"))
            app.sleep(0.9)
            let baseline = app.site.requestCount("/ext-media-tick")
            if active {
                do {
                    try app.waitUntil("hidden " + name + " keeps scheduling", timeout: 5) { app.site.requestCount("/ext-media-tick") > baseline + 1 }
                } catch {
                    var policy: WebsitePolicyStatus?
                    if case .pageObservations(let observations) = try app.send(.pageObservations) { policy = observations[PageID(window: app.window!, item: item)]?.websitePolicyStatus }
                    try app.dispatch(.tab(.focus(item)))
                    try SitePolicyScenarios.evaluate(app, item, "document.title=" + js("after:" + name + ":") + "+" + readback)
                    app.sleep(0.5)
                    let after = try tab(item, in: app.view())?.title ?? "missing"
                    throw Check(description: String(describing: error) + "; DOM before hide=" + proof + "; native policy=" + String(describing: policy) + "; DOM after showing=" + after)
                }
            } else {
                app.sleep(1.4)
                try expect(app.site.requestCount("/ext-media-tick") == baseline, name + " incorrectly kept a hidden page active")
            }
        }
        let wav = """
        const bytes=new Uint8Array(8044), d=new DataView(bytes.buffer);
        const tag=(at,s)=>{for(let i=0;i<s.length;i++)bytes[at+i]=s.charCodeAt(i)};
        tag(0,'RIFF');d.setUint32(4,8036,true);tag(8,'WAVE');tag(12,'fmt ');d.setUint32(16,16,true);d.setUint16(20,1,true);d.setUint16(22,1,true);d.setUint32(24,8000,true);d.setUint32(28,8000,true);d.setUint16(32,1,true);d.setUint16(34,8,true);tag(36,'data');d.setUint32(40,8000,true);bytes.fill(128,44);
        window.extElement=new Audio('data:audio/wav;base64,'+btoa(String.fromCharCode(...bytes)));extElement.muted=true;extElement.loop=true;document.body.append(extElement);await extElement.play()
        """
        try matrix("muted-html-audio", setup: wav, active: true)
        try matrix("paused-html-audio", setup: "document.body.append(extElement);extElement.pause()", active: false)
        try matrix("muted-html-video", setup: "const canvas=document.createElement('canvas');window.extElement=document.createElement('video');extElement.muted=true;extElement.srcObject=canvas.captureStream(10);document.body.append(extElement);await extElement.play()", active: true)
        try matrix("paused-html-video", setup: "document.body.append(extElement);extElement.pause()", active: false)
        try matrix("running-silent-webaudio", setup: "await start(true);clearInterval(timer)", active: false)
        app.note("Audible WebAudio and playback intent for muted HTML audio/video protected hidden scheduling, including Chromium's automatic hidden-media pause. Suspended WebAudio, visibly paused HTML media and a running silent WebAudio source allowed freezing. The typed PiP consumer still awaits captures-media integration.")
    }

    @Sendable static func controls(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, item, "Site policy fixture")
        try app.dispatch(.site(.controls))
        try app.waitUntil("native policy and OS readback") { try SitePolicyScenarios.controls(app).applied?.osAuthorization?.count == 4 }
        try app.click(.settingsField("siteCopyURL"))
        guard case .text(let copied) = try app.send(.readPasteboard) else { throw Check(description: "clipboard readback missing") }
        try expect(copied == app.site.url("site-policy.html").absoluteString, "site control copied a different page")
        try app.click(.settingsField("siteExportLink"))
        try app.waitUntil("real link export save panel") { try app.native().appWindows.contains { $0.className == "NSSavePanel" && $0.isVisible } }
        try app.perform(.sheetButton(title: "Cancel"))
        try app.waitUntil("link export cancellation") { try !app.native().appWindows.contains { $0.className == "NSSavePanel" && $0.isVisible } }
        try app.click(.settingsField("siteExportLink"))
        try app.waitUntil("selected link export save panel") { try app.native().sheetClass == "NSSavePanel" }
        let destination = app.dataDirectory.appendingPathComponent("Ext-link-export.json")
        try app.perform(.answerSavePanel(window: app.window, path: destination.path))
        try app.waitUntil("actual link export bytes") { FileManager.default.fileExists(atPath: destination.path) }
        let data = try Data(contentsOf: destination)
        let exported = try JSONDecoder().decode(ExportDocument.self, from: data)
        try expect(exported.entries == [.link(title: "Site policy fixture", url: app.site.url("site-policy.html"))], "export bytes do not describe the active page")
        try data.write(to: app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/Ext-controls-link-export.json"))
        try app.dispatch(.profile(.create(name: "Ext Profile", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings), let other = settings.profiles.first(where: { $0.profile.name == "Ext Profile" })?.profile.id else { throw Check(description: "profile missing") }
        try app.dispatch(.profile(.assign(.current, to: other)))
        try app.waitUntil("site controls rebind to profile") { try SitePolicyScenarios.controls(app).profileName == "Ext Profile" && SitePolicyScenarios.controls(app).target?.context == .profile(other) }
        _ = try app.screenshotSiteControls("origin-profile-os-readback")
        app.note("Actual OS status readback did not request authorization. Copy, export cancellation and selected-destination JSON bytes describe the active page. Destination selection used the owned fixture bridge and the real save panel; a physical folder-selection gesture is not claimed. Boost/capture actions await their owning slices.")
    }
}
