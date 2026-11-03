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
        Scenario("Ext-blocking", "main-frame, cross-origin frame, redirect and a selected EasyList file", cefOnly: "CEF IO request filtering", blocking),
        Scenario("Ext-media", "audible WebAudio, suspended WebAudio and hidden media scheduling", cefOnly: "Chromium lifecycle", media),
        Scenario("Ext-controls", "origin/profile readback, copy and local link export", cefOnly: "native site controls", controls),
        Scenario("Ext-shortcut-physical", "window-server key events edit the shortcut field and fire the extension command",
                 cefOnly: "CEF extension commands", physicalShortcut),
    ]
    static func js(_ text: String) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: [text]), as: UTF8.self).dropFirst().dropLast().description
    }
    static func catalogValue(_ app: AppUnderTest, _ id: String) throws -> BrowserExtension? {
        try SitePolicyScenarios.controls(app).extensions.first { $0.id == id }
    }
    /// The full site form is the popover's second page: open it from the Settings title first, as a user would.
    static func control(_ app: AppUnderTest, _ field: String, _ action: SiteControlAction) throws {
        guard let owner = app.window else { throw Check(description: "site-controls owner missing") }
        if (try? app.perform(.siteControlInput(window: owner, field: field, action: action))) != nil { return }
        try app.perform(.siteControlInput(window: owner, field: "siteSettingsDetails", action: .press))
        try app.waitUntil("site settings page shows \(field)") {
            (try? app.perform(.siteControlInput(window: owner, field: field, action: action))) != nil
        }
    }
    @Sendable static func catalog(_ app: AppUnderTest) throws {
        let (item, fixture) = try ExtensionScenarios.selectedFixture(app)
        defer {
            _ = try? app.screenshotSiteControls("catalog-final")
            if let value = try? app.send(.siteControls), let data = try? ControlWire.encode(value) {
                try? data.write(to: app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/Ext-catalog-controls.json"))
            }
        }
        try control(app, "extension-pin-" + fixture.id, .press)
        try expect(try SitePolicyScenarios.controls(app).pinnedExtensions.contains(fixture.id), "public profile pin missing")
        try expect(fixture.canChangeIncognito == true, "fixture incognito permission is not editable")
        for allowed in [false, true, false] {
            if try catalogValue(app, fixture.id)?.incognitoAllowed != allowed {
                try control(app, "extension-incognito-" + fixture.id, .press)
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
        try control(app, "extension-shortcut-" + fixture.id + "-" + command, .focus)
        try app.press("cmd+a"); try app.type("cmd+shift+u")
        try control(app, "extension-shortcut-save-" + fixture.id + "-" + command, .press)
        try app.waitUntil("edited Chromium shortcut readback") {
            if let error = try SitePolicyScenarios.controls(app).extensionError { throw Check(description: error) }
            return try catalogValue(app, fixture.id)?.commands?.contains { $0.name == command && ExtensionShortcuts.chord($0.keybinding) == KeyChord([.command, .shift], .u) } == true
        }
        try control(app, "extension-shortcut-" + fixture.id + "-" + command, .focus)
        try app.press("cmd+shift+u"); app.sleep(0.5)
        try expect(try tab(item, in: app.view())?.title == "Site policy fixture", "native editor leaked the extension command to the page")
        try control(app, "extension-shortcut-" + fixture.id + "-_execute_action", .focus)
        try app.type("cmd+shift+u")
        try control(app, "extension-shortcut-save-" + fixture.id + "-_execute_action", .press)
        try expect(try SitePolicyScenarios.controls(app).extensionError?.contains("already assigned") == true, "duplicate shortcut did not report a conflict")
        try control(app, "extension-shortcut-" + fixture.id + "-" + command, .focus)
        try app.type("cmd+t")
        try control(app, "extension-shortcut-save-" + fixture.id + "-" + command, .press)
        try expect(try SitePolicyScenarios.controls(app).extensionError?.contains("reserved") == true, "reserved shortcut did not report a conflict")
        _ = try app.screenshotSiteControls("shortcut-editor")
        try app.dispatch(.site(.closeControls)); try app.dispatch(.tab(.focus(item)))
        try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("site-policy.html"))
        try app.flush(); try app.restart()
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("site-policy.html"))
        try app.waitUntil("extension listener ready after restart") {
            try SitePolicyScenarios.evaluate(app, item, "document.title='shortcut-ready:'+document.documentElement.getAttribute('data-brk-extension')")
            return try tab(item, in: app.view())?.title == "shortcut-ready:installed"
        }
        try app.press("cmd+shift+u")
        try waitForTitle(app, item, "extension-command:fixture-command")
        try app.dispatch(.settings(.shortcuts(.setChord(.newTab, KeyChord([.command, .shift], .u)))))
        try app.press("cmd+shift+u")
        try app.waitUntil("Brk app-priority remap opens command bar") { isCommandBar(try app.view().overlay) }
        try app.press("escape")
        app.sleep(0.5)
        try SitePolicyScenarios.evaluate(app, item, "document.title='extension-count:'+document.documentElement.getAttribute('data-brk-extension-commands')")
        try waitForTitle(app, item, "extension-count:1")
        try app.dispatch(.settings(.shortcuts(.reset(.newTab))))
        app.note("Owned AppKit focus/press actions plus real key input edited the actual fields and exercised duplicate/reserved errors. Chromium binding and command execution survived restart; command count stayed one after a Brk app-priority remap. Synthetic physical utility-panel clicks remain a separate verification limitation.")
    }

    /// The shortcut editor's text and the shortcut itself arrive as keyboard events from the window server
    /// (`PhysicalKeys`), not through the control socket's in-process press.
    @Sendable static func physicalShortcut(_ app: AppUnderTest) throws {
        let (item, fixture) = try ExtensionScenarios.selectedFixture(app)
        guard let pid = app.hello?.pid, let owner = app.window else { throw Check(description: "app identity missing") }
        let command = "fixture-command", field = "extension-shortcut-" + fixture.id + "-" + command
        try app.dispatch(.site(.nativeExtensions))
        try app.waitUntil("installed shortcut editor") { try catalogValue(app, fixture.id) != nil }
        try control(app, field, .focus)
        PhysicalKeys.press(KeyChord([.command], .a), pid: pid)
        PhysicalKeys.type("cmd+shift+u", pid: pid)
        app.sleep(0.3)
        try control(app, "extension-shortcut-save-" + fixture.id + "-" + command, .press)
        try app.waitUntil("Chromium reads back the typed shortcut") {
            if let error = try SitePolicyScenarios.controls(app).extensionError { throw Check(description: error) }
            return try catalogValue(app, fixture.id)?.commands?.contains { $0.name == command && ExtensionShortcuts.chord($0.keybinding) == KeyChord([.command, .shift], .u) } == true
        }
        _ = try app.screenshotSiteControls("physical-shortcut")
        try app.dispatch(.site(.closeControls)); try app.dispatch(.tab(.focus(item)))
        try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitForPageInput(PageID(window: owner, item: item), at: app.site.url("site-policy.html"))
        try app.waitUntil("extension listener ready") {
            try SitePolicyScenarios.evaluate(app, item, "document.title='shortcut-ready:'+document.documentElement.getAttribute('data-brk-extension')")
            return try tab(item, in: app.view())?.title == "shortcut-ready:installed"
        }
        _ = try app.send(.activate(window: owner))
        app.sleep(0.3)
        PhysicalKeys.press(KeyChord([.command, .shift], .u), pid: pid)
        try waitForTitle(app, item, "extension-command:fixture-command")
        app.note("The editor field got focus through AppKit; ⌘A, the text cmd+shift+u and the shortcut ⇧⌘U itself were keyboard events posted by the window server to Brk's process (CGEvent.postToPid), so they took AppKit's full event path into the field editor and into Chromium, which ran the extension command.")
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
        try app.waitUntil("selected EasyList list readback") {
            let value = try SitePolicyScenarios.controls(app)
            return value.rulesError == nil && value.filterLists.contains { $0.id == FilterListRecord.importedID && $0.key != nil }
        }
        app.sleep(0.5)
        let before = app.site.requestCount("/page2.html")
        try SitePolicyScenarios.evaluate(app, item, "fetch('/page2.html').then(()=>document.title='import:allowed').catch(()=>document.title='import:blocked')")
        try waitForTitle(app, item, "import:blocked")
        try expect(app.site.requestCount("/page2.html") == before, "imported URL-prefix rule did not block")
        try Data("! nothing Brk can use\nexample.com#$#hide-if-contains ad\n".utf8).write(to: source)
        try app.dispatch(.site(.selectedBlockingRules(source, context)))
        try app.waitUntil("a refresh without usable rules reports an error") { try SitePolicyScenarios.controls(app).rulesError?.contains("no filter rules") == true }
        try SitePolicyScenarios.evaluate(app, item, "fetch('/page2.html').then(()=>document.title='retained:allowed').catch(()=>document.title='retained:blocked')")
        try waitForTitle(app, item, "retained:blocked")
        app.note("Blocked main frame, cross-origin iframe and redirected destination produced zero target-server hits. A selected EasyList file blocked a new URL; a refresh with no usable rules retained that working list.")
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
            try SitePolicyScenarios.evaluate(app, item, "(async()=>{if(document.hidden)await new Promise(resolve=>document.addEventListener('visibilitychange',()=>{if(!document.hidden)resolve()},{once:true}));if(window.extElement){extElement.pause();extElement.remove()}" + setup + ";await new Promise(resolve=>setTimeout(resolve,0));document.title=" + js(marker) + "+" + readback + "})().catch(e=>document.title='matrix-error:'+e.message)")
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
                try app.waitUntil("native frozen policy for " + name, timeout: 8) {
                    guard case .pageObservations(let observations) = try app.send(.pageObservations) else { return false }
                    return observations[PageID(window: app.window!, item: item)]?.websitePolicyStatus?.frozen == true
                }
                let baseline = app.site.requestCount("/ext-media-tick")
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
        try matrix("muted-html-video", setup: "window.extElement=document.createElement('video');extElement.muted=true;extElement.loop=true;extElement.src='/ext-policy-video.webm';document.body.append(extElement);await extElement.play()", active: true)
        try matrix("paused-html-video", setup: "document.body.append(extElement);extElement.pause()", active: false)
        try matrix("running-silent-webaudio", setup: "await start(true);clearInterval(timer)", active: false)
        app.note("Audible WebAudio and playback intent for muted HTML audio/video protected hidden scheduling, including Chromium's automatic hidden-media pause. Suspended WebAudio, visibly paused HTML media and a running silent WebAudio source allowed freezing. The typed PiP consumer still awaits captures-media integration.")
    }

    @Sendable static func controls(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, item, "Site policy fixture")
        try app.dispatch(.site(.controls))
        try app.waitUntil("native policy and OS readback") { try SitePolicyScenarios.controls(app).applied?.osAuthorization?.count == 4 }
        try app.perform(.pasteboard("Ext-copy-pending"))
        try control(app, "siteCopyURL", .press)
        try app.waitUntil("actual copied page URL") {
            guard case .text(let copied) = try app.send(.readPasteboard) else { return false }
            return copied == app.site.url("site-policy.html").absoluteString
        }
        try control(app, "siteExportLink", .press)
        try app.waitUntil("real link export save panel") { try app.native().appWindows.contains { $0.className == "NSSavePanel" && $0.isVisible } }
        try app.perform(.sheetButton(title: "Cancel"))
        try app.waitUntil("link export cancellation") {
            let facts = try app.native()
            return facts.sheetClass == nil && !facts.appWindows.contains { $0.className == "NSSavePanel" && $0.isVisible }
        }
        let destination = app.dataDirectory.appendingPathComponent("Ext-link-export.json")
        try control(app, "siteExportLink", .press)
        try app.waitUntil("selected link export save panel") { try app.native().sheetClass == "NSSavePanel" }
        guard case .failed = try app.send(.selectLinkExportFixture(window: WindowID("Ext-wrong-owner"), path: destination.path)) else {
            throw Check(description: "another owner selected the link export destination")
        }
        try expect(!FileManager.default.fileExists(atPath: destination.path), "rejected owner wrote export bytes")
        try app.perform(.selectLinkExportFixture(window: app.window!, path: destination.path))
        try app.waitUntil("actual link export bytes") { FileManager.default.fileExists(atPath: destination.path) }
        guard case .failed = try app.send(.selectLinkExportFixture(window: app.window!, path: destination.path)) else {
            throw Check(description: "a completed export accepted another selection")
        }
        let data = try Data(contentsOf: destination)
        let exported = try JSONDecoder().decode(ExportDocument.self, from: data)
        try expect(exported.entries == [.link(title: "Site policy fixture", url: app.site.url("site-policy.html"))], "export bytes do not describe the active page")
        try data.write(to: app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/Ext-controls-link-export.json"))
        try app.dispatch(.profile(.create(name: "Ext Profile", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings), let other = settings.profiles.first(where: { $0.profile.name == "Ext Profile" })?.profile.id else { throw Check(description: "profile missing") }
        try app.dispatch(.profile(.assign(.current, to: other)))
        try app.waitUntil("site controls rebind to profile") { try SitePolicyScenarios.controls(app).profileName == "Ext Profile" && SitePolicyScenarios.controls(app).target?.context == .profile(other) }
        _ = try app.screenshotSiteControls("origin-profile-os-readback")
        app.note("Actual OS status readback did not request authorization. Copy, export cancellation and selected-destination JSON bytes describe the active page. The real save panel was shown/cancelled; output used an explicit owner-bound post-selection fixture and the production writer. Remote chooser confirmation and physical folder selection are not claimed. Boost/capture actions await their owning slices.")
    }
}
