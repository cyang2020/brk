import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation

enum DataScenarios {
    static let all = [
        Scenario("DataCookiesRefreshRestart", "cookie refresh: every storage class and two origins/profiles after restart", cefOnly: "CEF storage", cookiesRestart),
        Scenario("DataCacheRefreshRestart", "cache refresh: profile-wide HTTP eviction and other storage/profile survival after restart", cefOnly: "CEF storage", cacheRestart),
        Scenario("DataSiteStorageRestart", "explicit site-storage deletion and two origins/profiles after restart", cefOnly: "CEF storage", storageRestart),
        Scenario("DataProfileClearRestart", "profile clearing preserves records/settings/extensions and isolates two profiles", cefOnly: "CEF request contexts", profileClear),
        Scenario("DataCustomProfileClearRestart", "custom profile cookies/cache/history clear across origins while Default survives restart", cefOnly: "CEF request contexts", customProfileClear),
        Scenario("DataExtensionProfiles", "extension catalog, pins and enable state remain profile-scoped across restart", cefOnly: "CEF extensions", extensionProfiles),
        Scenario("DataPrivateExpiry", "last private window resets every storage class, cancels transport and audits disk/logs", cefOnly: "off-record context", privateExpiry),
        Scenario("DataProtectedOperations", "downloads and pending output block clearing; Find survives; frozen targets resume", cefOnly: "CEF operation ownership", protectedOperations),
        Scenario("DataTransferReassign", "accepted transfer retains original context and destination after reassignment", cefOnly: "CEF transfers", { try TransferScenarios.all.first { $0.id == "T4" }!.run($0) }),
        Scenario("DataTransferDelete", "deletion revokes retained transport then removes its directory next launch", cefOnly: "CEF transfers", { try TransferScenarios.all.first { $0.id == "T6" }!.run($0) }),
    ]

    static func row(_ app: AppUnderTest, _ item: ItemID) throws -> TabRow? {
        let view = try app.view()
        return (allTabs(view) + tabRows(view.scratch?.rows ?? [])).first { $0.id == item }
    }
    static func waitTitle(_ app: AppUnderTest, _ item: ItemID, _ title: String) throws {
        try app.waitUntil("data fixture title: " + title) { try row(app, item)?.title == title }
    }
    static func url(_ app: AppUnderTest, _ host: String = "a.data.localhost") -> URL {
        URL(string: app.site.url("data.html").absoluteString.replacingOccurrences(of: "127.0.0.1", with: host))!
    }
    static func page(_ app: AppUnderTest, host: String = "a.data.localhost") throws -> ItemID {
        let item = try app.load(url(app, host)); try waitTitle(app, item, "Data fixture")
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: url(app, host))
        return item
    }
    static func focus(_ app: AppUnderTest, _ item: ItemID) throws {
        try app.dispatch(.tab(.focus(item)))
        guard let address = try row(app, item)?.url else { throw Check(description: "data URL missing") }
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: address)
    }
    static func seed(_ app: AppUnderTest, _ item: ItemID, _ value: String) throws {
        try SitePolicyScenarios.evaluate(app, item, "seedData('\(value)').catch(e=>document.title='data-error:'+e)")
        try app.waitUntil("all data classes seeded: " + value) {
            let title = try row(app, item)?.title ?? ""
            if title.hasPrefix("data-error:") { throw Check(description: title) }
            return title == "seed:" + value
        }
    }
    static func read(_ app: AppUnderTest, _ item: ItemID, _ tag: String) throws -> [String: Any] {
        let prefix = "data:" + tag + ":"
        try SitePolicyScenarios.evaluate(app, item, "readData('\(tag)').catch(e=>document.title='data-error:'+e)")
        var value: [String: Any] = [:]
        try app.waitUntil("storage readback: " + tag) {
            let title = try row(app, item)?.title ?? ""
            if title.hasPrefix("data-error:") { throw Check(description: title) }
            guard title.hasPrefix(prefix), let data = String(title.dropFirst(prefix.count)).data(using: .utf8),
                  let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            value = result; return true
        }
        return value
    }
    static func verify(_ value: [String: Any], storage: String?, cookies: String?, domain: Bool = true) throws {
        for key in ["local", "idb", "cache"] {
            if let storage { try expect(value[key] as? String == storage, "\(key) differs: \(value)") }
            else { try expect(value[key] is NSNull, "\(key) remains: \(value)") }
        }
        try expect(value["worker"] as? Bool == (storage != nil), "service-worker registration differs: \(value)")
        let header = value["serverCookie"] as? String ?? "", visible = value["cookie"] as? String ?? ""
        let nested = value["nestedCookie"] as? String ?? ""
        for (name, source) in [("sitefixture", visible), ("httponlyfixture", header), ("pathfixture", nested)] {
            try expect(source.contains(name + "=") == (cookies != nil), "\(name) presence differs: \(value)")
            if let cookies { try expect(source.contains(name + "=" + cookies), "\(name) belongs to another context: \(value)") }
        }
        try expect(!visible.contains("httponlyfixture="), "HttpOnly cookie became script-readable")
        if domain {
            try expect(header.contains("domainfixture=") == (cookies != nil), "domain cookie presence differs: \(value)")
            if let cookies { try expect(header.contains("domainfixture=" + cookies), "domain cookie belongs to another profile") }
        }
    }
    static func http(_ app: AppUnderTest, _ item: ItemID, _ tag: String, requests: Int) throws {
        let before = app.site.requestCount("/site-policy-cache.js")
        try SitePolicyScenarios.evaluate(app, item, "readHTTPCache('\(tag)')")
        try waitTitle(app, item, "http:" + tag)
        let delta = app.site.requestCount("/site-policy-cache.js") - before
        try expect(delta == requests, "HTTP cache \(tag): expected \(requests) server requests, got \(delta)")
        app.note("HTTP cache \(tag): server request delta \(delta), cumulative \(before + delta).")
    }
    static func profile(_ app: AppUnderTest, _ name: String) throws -> ProfileID {
        try app.dispatch(.profile(.create(name: name, icon: nil)))
        guard case .settings(let settings) = try app.send(.settings), let id = settings.profiles.first(where: { $0.profile.name == name })?.profile.id else { throw Check(description: "missing profile") }
        return id
    }
    static func assign(_ app: AppUnderTest, _ profile: ProfileID, item: ItemID) throws {
        try app.dispatch(.profile(.assign(.current, to: profile))); try focus(app, item)
    }
    static func captureSettingsWindow(_ app: AppUnderTest, _ name: String) throws {
        guard let number = try app.native().appWindows.first(where: { $0.isVisible && $0.className == "NSWindow" })?.number else { throw Check(description: "visible settings window missing") }
        let root = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("artifacts/" + app.scenarioID)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let command = Process(); command.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        command.arguments = ["-x", "-l", String(number), root.appendingPathComponent(name + ".png").path]
        try command.run(); command.waitUntilExit()
        try expect(command.terminationStatus == 0, "native settings capture failed")
    }
    static func receipt(_ app: AppUnderTest, _ name: String, _ value: Any) throws {
        let root = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("artifacts/" + app.scenarioID)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent(name + ".json"))
    }
    static func clearSite(_ app: AppUnderTest, kinds: Set<SiteDataKind>, scope: SiteDataScope, reload: Bool = false, errorExpected: Bool = false) throws -> ClearSiteDataResult {
        try app.dispatch(.site(.clear(kinds: kinds, scope: scope, reload: reload)))
        try app.click(.settingsField("confirmSiteClear"))
        var result: ClearSiteDataResult?
        try app.waitUntil("native site clear result", timeout: 20) {
            result = try SitePolicyScenarios.controls(app).result
            return result != nil
        }
        try expect((result!.error != nil) == errorExpected, "unexpected clear result: \(String(describing: result))")
        if !errorExpected { try expect(result!.completed == kinds, "partial clear: \(result!)") }
        if reload && !errorExpected {
            try app.waitUntil("only the original page reloads") {
                guard let target = try SitePolicyScenarios.controls(app).target else { return false }
                return target.page == result!.request.target.page && target.document != result!.request.target.document
            }
        }
        return result!
    }
    @Sendable static func cookiesRestart(_ app: AppUnderTest) throws { try refreshRestart(app, kinds: [.cookies], scope: .site) }
    @Sendable static func cacheRestart(_ app: AppUnderTest) throws { try refreshRestart(app, kinds: [.cache], scope: .profile) }
    @Sendable static func storageRestart(_ app: AppUnderTest) throws { try refreshRestart(app, kinds: [.cookies, .storage], scope: .site) }
    static func refreshRestart(_ app: AppUnderTest, kinds: Set<SiteDataKind>, scope: SiteDataScope) throws {
        let a = try page(app); try seed(app, a, "A"); try http(app, a, "A-warm", requests: 1); try http(app, a, "A-cached", requests: 0)
        let b = try page(app, host: "other.localhost"); try seed(app, b, "B"); try http(app, b, "B-warm", requests: 1)
        let other = try profile(app, "Data Other")
        try assign(app, other, item: a); try seed(app, a, "C"); try http(app, a, "C-warm", requests: 1)
        try assign(app, .default, item: a)
        let result = try clearSite(app, kinds: kinds, scope: scope, reload: true)
        try expect(result.error == nil, "clear failed")
        try app.dispatch(.site(.closeControls)); try app.flush(); try app.restart()
        try focus(app, a)
        let afterA = try read(app, a, "A-restart")
        try verify(afterA, storage: kinds.contains(.storage) ? nil : "A", cookies: kinds.contains(.cookies) ? nil : "A")
        try http(app, a, "A-restart", requests: kinds.contains(.cache) ? 1 : 0)
        try focus(app, b)
        let afterB = try read(app, b, "B-restart")
        try verify(afterB, storage: "B", cookies: "B", domain: false)
        try http(app, b, "B-restart", requests: kinds.contains(.cache) ? 1 : 0)
        try assign(app, other, item: a)
        let afterC = try read(app, a, "C-restart")
        try verify(afterC, storage: "C", cookies: "C")
        try http(app, a, "C-restart", requests: 0)
        try receipt(app, "post-restart", ["action": kinds.map(\.rawValue).sorted(), "originA": afterA, "unrelatedOriginB": afterB, "otherProfileC": afterC])
        app.note("Post-restart readback covers exact IndexedDB/Cache Storage values, localStorage, worker registrations, host/all-path/HttpOnly/shared-domain cookies and HTTP cache. Cache clearing intentionally evicts both origins in Default; the other profile's cache survives.")
    }

    static func clearProfile(_ app: AppUnderTest, _ profile: ProfileID, _ kinds: Set<SiteDataKind>, errorExpected: Bool = false) throws -> ClearProfileDataResult {
        try app.dispatch(.site(.clearProfile(profile, kinds)))
        var result: ClearProfileDataResult?
        try app.waitUntil("native profile clear completion", timeout: 20) {
            guard case .settings(let settings) = try app.send(.settings) else { return false }
            result = settings.profiles.first { $0.profile.id == profile }?.clearDataResult
            return result != nil && result?.request.kinds == kinds
        }
        try expect((result!.error != nil) == errorExpected, "unexpected profile result: \(result!)")
        if !errorExpected { try expect(result!.completed == kinds, "partial profile clear") }
        return result!
    }
    @Sendable static func profileClear(_ app: AppUnderTest) throws {
        let a = try page(app); try seed(app, a, "A"); try http(app, a, "A-warm", requests: 1)
        let b = try page(app, host: "other.localhost"); try seed(app, b, "B"); try http(app, b, "B-warm", requests: 1)
        let other = try profile(app, "Data Kept")
        try app.dispatch(.settings(.profile(other, .searchSuggestions(false))))
        try assign(app, other, item: a); try seed(app, a, "C"); try http(app, a, "C-warm", requests: 1)
        try app.dispatch(.settings(.openPane(.profiles)))
        try app.click(.settingsField("clearProfileData-" + ProfileID.default.rawValue))
        try app.press("return")
        try app.waitUntil("settings confirmation clears the named profile", timeout: 20) {
            guard case .settings(let settings) = try app.send(.settings), let result = settings.profiles.first(where: { $0.profile.id == .default })?.clearDataResult else { return false }
            try expect(result.error == nil, result.error ?? "")
            return result.completed == [.cookies, .cache, .history]
        }
        try captureSettingsWindow(app, "profile-privacy-controls")
        try app.dispatch(.settings(.closeWindow))
        try app.flush()
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: app.dataDirectory.appendingPathComponent("state.json"))) as? [String: Any]
        let history = (saved?["doc"] as? [String: Any])?["history"] as? [[String: Any]] ?? []
        try expect(!history.contains { $0["profile"] as? String == ProfileID.default.rawValue }, "Default history was not cleared")
        try expect(history.contains { $0["profile"] as? String == other.rawValue }, "another profile's history was cleared")
        // A profile with no page/context yet is still a valid settings target.
        let unused = try profile(app, "Data Unused")
        _ = try clearProfile(app, unused, [.cookies, .cache, .history])
        _ = try clearProfile(app, other, [.storage], errorExpected: true)
        try verify(try read(app, a, "unsupported-preserves-C"), storage: "C", cookies: "C")
        try expect(!FileManager.default.fileExists(atPath: app.dataDirectory.appendingPathComponent("profiles-to-delete").path), "clearing scheduled profile deletion")
        try app.flush(); try app.restart()
        try app.dispatch(.tab(.focus(a)))
        try app.waitUntil("restored profile document is ready") {
            guard case .pageObservations(let pages) = try app.send(.pageObservations), case .ready? = pages[PageID(window: app.window!, item: a)]?.document else { return false }
            return true
        }
        // Request page input with an actual click after using the native settings window.
        // Deferred context readiness must continue to respect native responders.
        try app.click(.card(0))
        try focus(app, a); let c = try read(app, a, "C-restart"); try verify(c, storage: "C", cookies: "C"); try http(app, a, "C-restart", requests: 0)
        try assign(app, .default, item: a); let av = try read(app, a, "A-restart"); try verify(av, storage: "A", cookies: nil); try http(app, a, "A-restart", requests: 1)
        try focus(app, b); let bv = try read(app, b, "B-restart"); try verify(bv, storage: "B", cookies: nil, domain: false); try http(app, b, "B-restart", requests: 1)
        guard case .settings(let settings) = try app.send(.settings) else { throw Check(description: "settings missing") }
        try expect(settings.profiles.contains { $0.profile.id == unused } && settings.profiles.contains { $0.profile.id == other && !$0.settings.searchSuggestions }, "clear removed profiles or settings")
        try receipt(app, "post-restart", ["defaultA": av, "defaultB": bv, "otherC": c, "profileRecords": settings.profiles.map { $0.profile.name }])
        app.note("Profile cookies/cache/history clear uses CEF request-context callbacks with no live Default page. Unused profile clearing also completed; unsupported origin storage fails before mutation. Profile records, settings and origin storage survive restart. Site visits made by the readback may add new History entries.")
    }

    @Sendable static func customProfileClear(_ app: AppUnderTest) throws {
        let a = try page(app); try seed(app, a, "DEFAULTA"); try http(app, a, "default-A-warm", requests: 1)
        let b = try page(app, host: "other.localhost"); try seed(app, b, "DEFAULTB"); try http(app, b, "default-B-warm", requests: 1)
        let custom = try profile(app, "Data Custom Clear")
        try assign(app, custom, item: a); try seed(app, a, "CUSTOMA"); try http(app, a, "custom-A-warm", requests: 1)
        try focus(app, b); try seed(app, b, "CUSTOMB"); try http(app, b, "custom-B-warm", requests: 1)
        _ = try clearProfile(app, custom, [.cookies, .cache, .history])
        try app.flush()
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: app.dataDirectory.appendingPathComponent("state.json"))) as? [String: Any]
        let history = (saved?["doc"] as? [String: Any])?["history"] as? [[String: Any]] ?? []
        try expect(!history.contains { $0["profile"] as? String == custom.rawValue }, "custom history was not cleared")
        try expect(history.contains { $0["profile"] as? String == ProfileID.default.rawValue }, "Default history was cleared with custom history")
        try app.restart()
        try focus(app, a); let ca = try read(app, a, "custom-A-restart"); try verify(ca, storage: "CUSTOMA", cookies: nil); try http(app, a, "custom-A-restart", requests: 1)
        try focus(app, b); let cb = try read(app, b, "custom-B-restart"); try verify(cb, storage: "CUSTOMB", cookies: nil, domain: false); try http(app, b, "custom-B-restart", requests: 1)
        try assign(app, .default, item: a); let da = try read(app, a, "default-A-restart"); try verify(da, storage: "DEFAULTA", cookies: "DEFAULTA"); try http(app, a, "default-A-restart", requests: 0)
        try focus(app, b); let db = try read(app, b, "default-B-restart"); try verify(db, storage: "DEFAULTB", cookies: "DEFAULTB", domain: false); try http(app, b, "default-B-restart", requests: 0)
        try receipt(app, "post-restart", ["customA": ca, "customB": cb, "defaultA": da, "defaultB": db])
        app.note("Custom-profile clearing evicted cookies and HTTP cache at both origins. Default retained all storage classes, cookies and both HTTP cache entries after restart. Origin storage in the cleared custom profile is intentionally retained under the displayed unsupported profile-wide scope.")
    }

    @Sendable static func extensionProfiles(_ app: AppUnderTest) throws {
        let (first, installed) = try ExtensionScenarios.selectedFixture(app)
        try app.dispatch(.site(.pinExtension(installed.id, true)))
        try app.dispatch(.site(.extensions))
        let manager = currentTab(try app.view())!.id
        try app.waitForPageInput(PageID(window: app.window!, item: manager), at: URL(string: "chrome://extensions/")!)
        try ExtensionScenarios.changeEnabled(app, manager: manager, id: installed.id, on: false)
        let other = try profile(app, "Data Extensions")
        try app.dispatch(.site(.closeControls)); try app.dispatch(.profile(.assign(.current, to: other)))
        let (second, otherInstalled) = try ExtensionScenarios.selectedFixture(app)
        try expect(otherInstalled.id == installed.id && otherInstalled.enabled, "fixture is not independently enabled in other profile")
        try expect(try !SitePolicyScenarios.controls(app).pinnedExtensions.contains(installed.id), "pin leaked")
        try app.dispatch(.site(.closeControls)); try app.dispatch(.tab(.focus(second))); try app.flush(); try app.restart()
        try app.dispatch(.site(.nativeExtensions))
        try app.waitUntil("other catalog after restart") { try SitePolicyScenarios.controls(app).extensionsLoaded == true }
        var value = try SitePolicyScenarios.controls(app)
        try expect(value.extensions.contains { $0.id == installed.id && $0.enabled } && !value.pinnedExtensions.contains(installed.id), "other enable/pin state differs after restart")
        _ = try clearProfile(app, other, [.cookies, .cache, .history])
        try app.dispatch(.site(.closeControls)); try app.dispatch(.tab(.focus(second)))
        let probe = PageID(window: app.window!, item: second)
        guard case .pageObservations(let before) = try app.send(.pageObservations) else { throw Check(description: "extension document missing") }
        try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitUntil("new extension document after profile clear") {
            guard case .pageObservations(let after) = try app.send(.pageObservations), case .ready? = after[probe]?.document else { return false }
            return after[probe]?.document != before[probe]?.document
        }
        try app.waitUntil("extension executes again after profile data clearing") {
            try SitePolicyScenarios.evaluate(app, second, "document.title='data-extension-kept:'+document.documentElement.getAttribute('data-brk-extension')")
            return tab(second, in: try app.view())?.title == "data-extension-kept:installed"
        }
        try app.dispatch(.profile(.assign(.current, to: .default)))
        try app.dispatch(.tab(.focus(first))); try app.dispatch(.site(.nativeExtensions))
        try app.waitUntil("Default catalog after restart") { try SitePolicyScenarios.controls(app).extensionsLoaded == true }
        value = try SitePolicyScenarios.controls(app)
        try expect(value.extensions.contains { $0.id == installed.id && !$0.enabled } && value.pinnedExtensions.contains(installed.id), "Default enable/pin state leaked across profiles")
        try app.dispatch(.site(.closeControls)); try app.dispatch(.profile(.assign(.current, to: other))); try app.dispatch(.site(.nativeExtensions))
        try app.waitUntil("extension catalog after clearing data") { try SitePolicyScenarios.controls(app).extensionsLoaded == true }
        try expect(try SitePolicyScenarios.controls(app).extensions.contains { $0.id == installed.id && $0.enabled }, "data clear removed extension installation")
        app.note("The same harmless extension is disabled and pinned in Default, enabled and unpinned in Data Extensions. Both catalogs retain those independent states after restart; clearing profile cookies/cache/history keeps its extension installation.")
    }
}

extension DataScenarios {
    static func startDownload(_ app: AppUnderTest, _ item: ItemID, _ path: String) throws {
        try SitePolicyScenarios.evaluate(app, item, "(()=>{const f=document.createElement('iframe');f.hidden=true;f.src='\(app.site.url(path).absoluteString)';document.body.append(f)})()")
    }
    static func clickDownload(_ app: AppUnderTest, _ item: ItemID, _ path: String) throws {
        let page = PageID(window: app.window!, item: item)
        _ = try app.send(.activate(window: page.window))
        try SitePolicyScenarios.evaluate(app, item, "(()=>{const a=document.createElement('a');a.href='\(app.site.url(path).absoluteString)';a.textContent='Download';a.style='position:fixed;left:20px;top:20px;width:180px;height:60px;z-index:99999;background:white';document.body.append(a);document.title='Data download ready'})()")
        try waitTitle(app, item, "Data download ready")
        guard let frame = try app.native().pages[page]?.surfaceFrame else { throw Check(description: "private download surface missing") }
        try app.click(at: CGPoint(x: frame.minX + 35, y: frame.minY + 35))
    }
    static func transferStopped(_ app: AppUnderTest, _ path: String) throws {
        try app.waitUntil("expired context stops its transport", timeout: 10) { app.site.requestCount(path + "-stopped") > 0 }
        let bytes = app.site.requestCount(path + "-bytes")
        try expect(bytes > 0 && bytes < 4_194_304, "expired transfer completed unexpectedly")
        app.sleep(0.2)
        try expect(app.site.requestCount(path + "-bytes") == bytes, "expired transport still writes")
        app.note("\(path): server ceased at \(bytes)/4194304 bytes.")
    }
    @Sendable static func privateExpiry(_ app: AppUnderTest) throws {
        let publicWindow = app.window!, publicItem = try page(app)
        try seed(app, publicItem, "PUBLIC"); try http(app, publicItem, "public-warm", requests: 1)
        let folder = app.dataDirectory.appendingPathComponent("explicit-downloads")
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(folder.path))))
        func privateWindow() throws -> WindowID {
            try app.dispatch(.window(.newIncognito))
            guard case .hello(let hello) = try app.send(.hello), let window = hello.windows.first(where: { (try? app.view($0).kind) == .incognito }) else { throw Check(description: "private window missing") }
            return window
        }
        let secret = "DataPrivate-" + UUID().uuidString
        let processID = app.process!.process.processIdentifier
        let first = try privateWindow(); app.window = first
        let item = try page(app); try seed(app, item, secret); try http(app, item, "private-warm", requests: 1)
        try verify(try read(app, item, "private-seeded"), storage: secret, cookies: secret)
        // Explicitly completed downloads are allowed to remain after the private epoch expires.
        try startDownload(app, item, "download?private-completed=1")
        let completed = folder.appendingPathComponent("fixture.txt")
        try app.waitUntil("explicit private file completed") { (try? Data(contentsOf: completed)) == Data("fixture download\n".utf8) }
        try SitePolicyScenarios.evaluate(app, item, "document.title='\(secret)'")
        try clickDownload(app, item, "transfer-DataPrivateActive?name=\(secret).bin")
        try app.waitUntil("private active download") { app.site.requestCount("/transfer-DataPrivateActive-bytes") >= 65536 }
        try app.dispatch(.window(.close)); app.window = publicWindow
        let second = try privateWindow(); app.window = second
        try transferStopped(app, "/transfer-DataPrivateActive")
        let fresh = try page(app)
        let empty = try read(app, fresh, "new-private-epoch")
        try verify(empty, storage: nil, cookies: nil)
        try http(app, fresh, "new-private-epoch", requests: 1)
        try startDownload(app, fresh, "download?private-new-epoch=1")
        try app.waitUntil("new private epoch accepts a download") { (try? Data(contentsOf: folder.appendingPathComponent("fixture (1).txt"))) == Data("fixture download\n".utf8) }
        try app.dispatch(.window(.close)); app.window = publicWindow
        try focus(app, publicItem)
        try verify(try read(app, publicItem, "public-survives"), storage: "PUBLIC", cookies: "PUBLIC")
        try http(app, publicItem, "public-survives", requests: 0)
        try app.flush()
        let quit = try app.quit(); try expect(quit.clean, "private expiry did not drain cleanly")
        try expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["fixture (1).txt", "fixture.txt"], "private cancellation left staging/output")
        var inspected: [String] = [], hits: [String] = []
        let needles = [secret, completed.path, completed.path.replacingOccurrences(of: "/tmp/", with: "/private/tmp/")]
        guard let files = FileManager.default.enumerator(at: app.dataDirectory, includingPropertiesForKeys: [.isRegularFileKey]) else { throw Check(description: "data root audit failed") }
        for case let file as URL in files {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = String(file.path.dropFirst(app.dataDirectory.path.count + 1))
            inspected.append(relative)
            let data = try Data(contentsOf: file)
            if needles.contains(where: { data.range(of: Data($0.utf8)) != nil }) || relative.contains(secret) { hits.append(relative) }
        }
        // Restrict diagnostic-log access to this scenario's own app process and Brk subsystem.
        let diagnostic = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("artifacts/" + app.scenarioID + "/unified-log.ndjson")
        try FileManager.default.createDirectory(at: diagnostic.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: diagnostic.path, contents: nil)
        let output = try FileHandle(forWritingTo: diagnostic)
        let command = Process(); command.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        command.arguments = ["show", "--style", "ndjson", "--last", "10m", "--info", "--debug", "--predicate", "subsystem == 'brk' AND processIdentifier == \(processID)"]
        command.standardOutput = output; command.standardError = output
        try command.run(); command.waitUntilExit(); try output.close()
        let diagnosticData = try Data(contentsOf: diagnostic)
        try expect(command.terminationStatus == 0, "unified-log audit failed: \(String(decoding: diagnosticData.prefix(500), as: UTF8.self))")
        try expect(!needles.contains { diagnosticData.range(of: Data($0.utf8)) != nil }, "private title/download path entered Brk diagnostic logs")
        try receipt(app, "audit", ["fileSet": inspected.sorted(), "hits": hits, "unifiedLogPID": processID,
            "unifiedLogBytes": diagnosticData.count, "unifiedLogStatus": command.terminationStatus,
            "auditScope": "Every regular file recursively under the owned BRK_DATA_DIR (Chromium, state, cef-debug.log, app stderr/stdout and page logs), plus Brk unified logs for this app PID over the last 10 minutes. Byte-string and filename search for unique fixture title/value and completed download absolute path. Explicitly downloaded files may remain. No other user profile, global temporary storage, OS swap, backups or other processes' logs audited.",
            "freshPrivateStorage": empty])
        try expect(hits.isEmpty, "private marker/path entered app-owned disk: \(hits)")
        app.note("Closed/reopened the last private window without quitting: host/domain/all-path/HttpOnly cookies, localStorage, IndexedDB, Cache Storage, workers and HTTP cache reset. Active transport cancelled; explicitly completed files remain; new epoch downloads work; public storage/cache survive. Audit fileSet and exact scope are in artifacts/DataPrivateExpiry/audit.json.")
    }

    @Sendable static func protectedOperations(_ app: AppUnderTest) throws {
        let firstWindow = app.window!, a = try page(app)
        try seed(app, a, "PROTECTED")
        let folder = app.dataDirectory.appendingPathComponent("protected-downloads")
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(folder.path))))
        try startDownload(app, a, "transfer-DataProtected")
        try app.waitUntil("active protected download") { app.site.requestCount("/transfer-DataProtected-bytes") >= 65536 }
        let denied = try clearSite(app, kinds: [.cookies, .storage], scope: .site, errorExpected: true)
        try expect(denied.completed.isEmpty && denied.error!.contains("active downloads"), "download did not block destructive clear")
        _ = try clearProfile(app, .default, [.cookies, .cache, .history], errorExpected: true)
        try verify(try read(app, a, "download-preserved"), storage: "PROTECTED", cookies: "PROTECTED")
        try app.dispatch(.site(.closeControls))
        try app.waitUntil("protected download finishes", timeout: 15) { (try? Data(contentsOf: folder.appendingPathComponent("transfer-DataProtected.bin"))) == Data(repeating: 65, count: 4_194_304) }
        try app.dispatch(.page(.output(.mhtml)))
        try app.waitUntil("pending native output") { try app.native().sheetClass?.contains("SavePanel") == true }
        try app.dispatch(.window(.new))
        guard case .hello(let hello) = try app.send(.hello), let secondWindow = hello.windows.first(where: { $0 != firstWindow }) else { throw Check(description: "second window missing") }
        app.window = secondWindow
        let b = try page(app)
        let pending = try clearSite(app, kinds: [.cookies, .storage], scope: .site, errorExpected: true)
        try expect(pending.completed.isEmpty, "pending output allowed destructive clearing")
        _ = try clearProfile(app, .default, [.cookies, .cache, .history], errorExpected: true)
        try app.perform(.cancelCurrentOutput(window: firstWindow))
        try app.waitUntil("output cancellation finishes") {
            if case .terminal(.cancelled)? = try app.view(firstWindow).output?.stage { return true }; return false
        }
        try app.dispatch(.site(.closeControls))
        try app.dispatch(.find(.open(replace: false))); try app.dispatch(.find(.query(FindQuery(text: "fixture"))))
        try app.waitUntil("open native Find results") { (try app.view().find?.count ?? 0) > 0 }
        let count = try app.view().find?.count
        _ = try clearSite(app, kinds: [.cookies, .storage], scope: .site)
        try expect(try app.view().find?.query.text == "fixture" && app.view().find?.count == count, "non-reloading clear invalidated open Find")
        try verify(try read(app, b, "find-clear"), storage: nil, cookies: nil)
        try app.dispatch(.site(.closeControls)); try app.dispatch(.find(.close))
        try seed(app, b, "FROZEN")
        try app.dispatch(.site(.controls))
        guard let target = try SitePolicyScenarios.controls(app).target else { throw Check(description: "frozen target missing") }
        var rule = SiteRule(); rule.suspendWhenHidden = true
        try app.dispatch(.site(.rule(target, rule)))
        try SitePolicyScenarios.evaluate(app, b, "setInterval(()=>fetch('/data-frozen-tick',{cache:'no-store'}),100)")
        try app.waitUntil("foreground fixture ticks") { app.site.requestCount("/data-frozen-tick") >= 2 }
        let foreground = try page(app, host: "other.localhost")
        try focus(app, b)
        // Capture the immutable request before hiding its target. Confirmation remains on the source window.
        try app.dispatch(.site(.clear(kinds: [.cookies, .storage], scope: .site, reload: false)))
        try app.dispatch(.tab(.focus(foreground)))
        app.sleep(0.6)
        let before = app.site.requestCount("/data-frozen-tick"); app.sleep(0.7)
        try expect(app.site.requestCount("/data-frozen-tick") == before, "target did not actually freeze")
        try app.click(.settingsField("confirmSiteClear"))
        try app.waitUntil("frozen clear finishes", timeout: 20) { try SitePolicyScenarios.controls(app).result?.request.target == target && SitePolicyScenarios.controls(app).result?.completed == [.cookies, .storage] }
        try expect(try currentTab(app.view())?.id == foreground, "clearing hidden target changed the selection")
        try app.dispatch(.site(.closeControls)); try focus(app, b)
        try verify(try read(app, b, "frozen-clear"), storage: nil, cookies: nil)
        try receipt(app, "matrix", ["activeDownload": "rejected, zero classes removed, bytes completed unchanged", "pendingOutput": "rejected from another window in the same profile; native SavePanel cancelled", "openFind": "clear completed without reload; query and count retained", "frozenPage": "server ticks stopped before confirmation; clear completed; hidden selection retained; storage read empty"])
    }
}
