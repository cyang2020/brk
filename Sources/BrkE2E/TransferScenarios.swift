import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum TransferScenarios {
    static let all: [Scenario] = [
        Scenario("T1", "simultaneous downloads cancel independently, stop server bytes and preserve collisions", cefOnly: "CEF transfer callbacks", concurrent),
        Scenario("T2", "accepted POST download survives source-tab close with its original request", cefOnly: "CEF transfer lease", postClose),
        Scenario("T3", "accepted download survives source-window closure", cefOnly: "CEF transfer lease", windowClose),
        Scenario("T4", "reassignment retains original browser, policy and destination", cefOnly: "CEF contexts", reassign),
        Scenario("T5", "last private window revokes transport before drain; a new epoch can download", cefOnly: "CEF private epochs", privateExpiry),
        Scenario("T6", "profile deletion revokes retained transfers and reports final scheduled deletion", cefOnly: "CEF context disposal", deleteProfile),
        Scenario("T7", "quit cancels an already retained transfer and drains its native host", cefOnly: "CEF shutdown", retainedQuit),
        Scenario("T8", "pending destination sheet is nonblocking and cancelled with its source owner", cefOnly: "native sheet ownership", pendingSheet),
        Scenario("T9", "simultaneous transfers in two profiles keep independent context and files", cefOnly: "CEF contexts", twoProfiles),
        Scenario("T10", "profile disposal during readiness cannot recreate revoked browser demand", cefOnly: "CEF profile loader", loaderRace),
        Scenario("T11", "closing the native sheet owner denies the pending download", cefOnly: "native owner teardown", pendingWindowSheet),
        Scenario("T12", "right click opens the native web context menu", cefOnly: "native menu tracking", webContextMenu),
        Scenario("T13", "old download progress preserves a pending document and its prior history title", cefOnly: "download/navigation overlap", navigationDuringTransfer),
        Scenario("T14", "private attachment admission clears page demand without public metadata", cefOnly: "private attachment response", privateAttachment),
        Scenario("T15", "mandatory page closure does not recreate the page and reports its download outcome", cefOnly: "native closure with an active transfer", scriptClose),
    ]
    static let size = 4_194_304

    private static func webContextMenu(_ app: AppUnderTest) throws {
        let page = try home(app)
        try app.evaluate(page, "addEventListener('contextmenu',()=>document.title='Context event seen',{once:true});document.title='Context probe ready'")
        try app.waitUntil("context probe ready") { try tab(page.item, in: app.view())?.title == "Context probe ready" }
        guard let frame = try app.native().pages[page]?.surfaceFrame else { throw Check(description: "page surface missing") }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard case .menuItems(let titles) = try app.send(.captureContextMenu(window: page.window, point: point)) else {
            throw Check(description: "context menu capture failed")
        }
        let domTitle = try tab(page.item, in: app.view())?.title ?? "none"
        try expect(titles.contains("Reload") && titles.count >= 3, "native web menu missing: \(titles); DOM=\(domTitle)")
        app.note("Native NSMenu tracking recorded: \(titles.joined(separator: ", ")); tracking cancelled without choosing an action.")
    }

    private static func navigationDuringTransfer(_ app: AppUnderTest) throws {
        _ = try folder(app); let page = try home(app)
        try start(app, "transfer-navigation", in: page); try library(app)
        let first = try receiving(app, name: "transfer-navigation.bin")
        let pending = app.site.url("held-document")
        var released = false
        defer { if !released { app.site.releaseHeldDocument() } }
        try app.dispatch(.commandBar(.open(.editCurrent)))
        try app.dispatch(.commandBar(.submit(pending.absoluteString)))
        try app.waitUntil("held document parsed") { try tab(page.item, in: app.view())?.title == "Held document" }
        try library(app)
        try app.waitUntil("old transfer progresses while the main document remains pending") {
            try rows(app).contains { $0.id == first.id && $0.received > first.received }
        }
        guard case .pageObservations(let observations) = try app.send(.pageObservations) else { throw Check(description: "no observations") }
        try expect(observations[page]?.requestedURL == pending, "old progress erased the newer navigation")
        try app.evaluate(page, "document.title='Provisional transfer title'")
        try app.waitUntil("provisional title") { try tab(page.item, in: app.view())?.title == "Provisional transfer title" }
        try app.dispatch(.library(.open(.history)))
        guard case .library(let history)? = try app.view().overlay else { throw Check(description: "no history") }
        try expect(history.history.first { $0.url == app.site.url("index.html") }?.title == "Fixture Home", "provisional title rewrote the prior History record")
        try app.recordWindows("navigation-history")
        app.site.releaseHeldDocument()
        released = true
        try library(app); try app.dispatch(.library(.cancelDownload(first.id)))
        try app.waitUntil("transfer cancellation") { try rows(app).contains { $0.id == first.id && $0.state == .cancelled } }
        try stopped(app, "/transfer-navigation")
    }

    private static func privateAttachment(_ app: AppUnderTest) throws {
        let dir = try folder(app)
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello),
              let window = hello.windows.first(where: { (try? app.view($0).kind) == .incognito }) else { throw Check(description: "private window missing") }
        _ = try app.send(.load(window: window, url: app.site.url("transfer-private-direct")))
        let item = try app.view(window).content.panes[0].tab
        let page = PageID(window: window, item: item)
        try app.waitUntil("private attachment has actual staged bytes") {
            let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
            return files?.allObjects.compactMap { $0 as? URL }.contains {
                guard let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
                return values.isRegularFile == true && (values.fileSize ?? 0) > 0
            } == true
        }
        guard case .pageObservations(let observations) = try app.send(.pageObservations) else { throw Check(description: "no observations") }
        try expect(observations[page]?.requestedURL == nil && observations[page]?.committedURL == nil, "private attachment retained navigation intent")
        try expect(try app.view(window).content.panes[0].content == .blank, "private attachment retained page content")
        try library(app, in: window)
        try expect(try rows(app, in: window).isEmpty, "private download metadata became visible")
        try app.flush()
        let saved = try String(contentsOf: app.dataDirectory.appendingPathComponent("state.json"), encoding: .utf8)
        try expect(!saved.contains("transfer-private-direct"), "private attachment metadata persisted")
        try dispatch(app, window: window, .window(.close))
        try stopped(app, "/transfer-private-direct")
    }

    private static func scriptClose(_ app: AppUnderTest) throws {
        struct Census: Codable {
            var pages: [PageLogEntry]
            var downloads: [DownloadRow]
            var serverBytes: Int
            var serverStopped: Int
        }
        defer {
            try? library(app)
            let census = Census(pages: (try? app.pageLog()) ?? [], downloads: (try? rows(app)) ?? [],
                                serverBytes: app.site.requestCount("/transfer-script-bytes"),
                                serverStopped: app.site.requestCount("/transfer-script-stopped"))
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(census).write(to: app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/T15-census.json"))
            try? app.recordWindows("script-close")
        }
        let dir = try folder(app)
        let source = app.site.url("index.html?script-source")
        let item = try app.load(source)
        let page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: source)
        try start(app, "transfer-script", in: page, post: true); try library(app)
        _ = try receiving(app, name: "transfer-script.bin")
        try app.dispatch(.library(.close))
        _ = try app.send(.activate(window: page.window))
        try app.evaluate(page, "(()=>{let b=document.createElement('button');b.textContent='Close source';b.style='position:fixed;left:20px;top:100px;width:180px;height:60px';b.onclick=()=>window.close();document.body.append(b);document.title='Close source ready:'+history.length})()")
        try app.waitUntil("close button ready") { try tab(page.item, in: app.view())?.title.hasPrefix("Close source ready:") == true }
        app.note(try tab(page.item, in: app.view())?.title ?? "missing close setup")
        guard let frame = try app.native().pages[page]?.surfaceFrame else { throw Check(description: "source surface missing") }
        try app.click(at: CGPoint(x: frame.minX + 50, y: frame.minY + 130))
        try app.waitUntil("script closed its page") {
            guard case .pageObservations(let values) = try app.send(.pageObservations) else { return false }
            return values[page] == nil
        }
        try library(app)
        var result: DownloadRow?
        try app.waitUntil("native closure reports a terminal transfer") {
            result = try rows(app).first { $0.filename == "transfer-script.bin" }
            return result != nil && result?.state.isActive == false
        }
        if result?.state == .finished {
            try complete(app, name: "transfer-script.bin", at: dir.appendingPathComponent("transfer-script.bin"))
        } else {
            try stopped(app, "/transfer-script")
            try expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("transfer-script.bin").path), "failed transfer reported a completed file")
            try expect(result?.end != nil, "missing native closure failure/cancellation details")
            app.note("Mandatory browser closure reported \(result!.state); recovery disposition \(String(describing: result!.end)).")
        }
        try expect(try app.pageLog().filter { $0.page == page && $0.kind == .created }.count == 1, "download publication recreated the closed page")
    }
    private static func folder(_ app: AppUnderTest, profile: ProfileID = .default, name: String = "downloads") throws -> URL {
        let directory = app.dataDirectory.appendingPathComponent(name, isDirectory: true)
        try app.dispatch(.settings(.profile(profile, .downloadsDirectory(directory.path))))
        return directory
    }
    private static func rows(_ app: AppUnderTest, in window: WindowID? = nil) throws -> [DownloadRow] {
        if case .library(let library)? = try app.view(window).overlay { return library.downloads }
        return []
    }
    private static func library(_ app: AppUnderTest, in window: WindowID? = nil) throws {
        _ = try app.send(.dispatch(window: window ?? app.window, command: .library(.open(.downloads))))
    }
    private static func start(_ app: AppUnderTest, _ path: String, in page: PageID? = nil, post: Bool = false) throws {
        let page = try page ?? PageID(window: app.view().id, item: app.view().content.panes[0].tab)
        let address = app.site.url(path).absoluteString
        let encoded = String(data: try JSONEncoder().encode(address), encoding: .utf8)!
        let script = post
            ? "(()=>{let f=document.createElement('form');f.method='POST';f.action=\(encoded);f.innerHTML='<input name=secret value=original-body>';document.body.append(f);f.submit()})()"
            : "(()=>{let f=document.createElement('iframe');f.style.display='none';f.src=\(encoded);document.body.append(f)})()"
        try app.evaluate(page, script)
    }
    private static func clickDownload(_ app: AppUnderTest, _ path: String, in page: PageID) throws {
        _ = try app.send(.dispatch(window: page.window, command: .library(.close)))
        _ = try app.send(.activate(window: page.window))
        let encoded = String(data: try JSONEncoder().encode(app.site.url(path).absoluteString), encoding: .utf8)!
        try app.evaluate(page, "(()=>{document.getElementById('transfer-link')?.remove();let a=document.createElement('a');a.id='transfer-link';a.href=\(encoded);a.textContent='Download';a.style='position:fixed;left:20px;top:20px;width:180px;height:60px;z-index:99999;background:white';document.body.append(a);document.title='Transfer link ready'})()")
        try app.waitUntil("download link ready") { try tab(page.item, in: app.view(page.window))?.title == "Transfer link ready" }
        guard let frame = try app.native(page.window).pages[page]?.surfaceFrame else { throw Check(description: "no download surface") }
        try app.click(at: CGPoint(x: frame.minX + 35, y: frame.minY + 35))
    }
    private static func receiving(_ app: AppUnderTest, name: String, in window: WindowID? = nil) throws -> DownloadRow {
        var result: DownloadRow?
        try app.waitUntil("bytes for \(name)", timeout: 12) {
            result = try rows(app, in: window).first { $0.filename == name }
            return result?.state == .inProgress && (result?.received ?? 0) > 0
        }
        return result!
    }
    private static func complete(_ app: AppUnderTest, name: String, at url: URL, byte: UInt8 = 65, in window: WindowID? = nil) throws {
        try app.waitUntil("completed \(name)", timeout: 18) { try rows(app, in: window).contains { $0.filename == name && $0.state == .finished } }
        let data = try Data(contentsOf: url)
        try expect(data == Data(repeating: byte, count: size), "receipt bytes differ for \(name)")
        try expect(!(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)).contains { $0.hasPrefix(".brk-transfer-") }, "staging remains after final transfer")
        let receipts = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("receipts", isDirectory: true)
        try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
        try data.write(to: receipts.appendingPathComponent(app.scenarioID + "-" + name))
        app.note("\(name): \(data.count) bytes, every byte \(byte); receipt copied before fixture cleanup")
    }
    private static func stopped(_ app: AppUnderTest, _ path: String) throws {
        try app.waitUntil("server transport cessation", timeout: 10) { app.site.requestCount(path + "-stopped") > 0 }
        let bytes = app.site.requestCount(path + "-bytes")
        try expect(bytes > 0 && bytes < size, "cancellation received full response: \(bytes)")
        Thread.sleep(forTimeInterval: 0.15)
        try expect(app.site.requestCount(path + "-bytes") == bytes, "server kept writing after cancellation")
        app.note("\(path): server stopped at \(bytes)/\(size) bytes")
    }
    private static func profile(_ app: AppUnderTest, name: String) throws -> ProfileID {
        try app.dispatch(.profile(.create(name: name, icon: nil)))
        guard case .settings(let settings) = try app.send(.settings), let id = settings.profiles.first(where: { $0.profile.name == name })?.profile.id else { throw Check(description: "missing profile") }
        return id
    }
    private static func home(_ app: AppUnderTest, in window: WindowID? = nil) throws -> PageID {
        let window = try window ?? app.view().id
        let page = PageID(window: window, item: try app.view(window).content.panes[0].tab)
        try app.waitForPageInput(page, at: app.site.url("index.html"))
        return page
    }
    private static func concurrent(_ app: AppUnderTest) throws {
        let dir = try folder(app); let page = try home(app)
        try start(app, "transfer-one", in: page); try library(app)
        let first = try receiving(app, name: "transfer-one.bin")
        try clickDownload(app, "transfer-two?name=shared.bin", in: page)
        try library(app)
        _ = try receiving(app, name: "shared.bin")
        try Data("preexisting".utf8).write(to: dir.appendingPathComponent("shared.bin"))
        try app.dispatch(.library(.cancelDownload(first.id)))
        try app.waitUntil("native cancellation") { try rows(app).contains { $0.id == first.id && $0.state == .cancelled } }
        try stopped(app, "/transfer-one")
        try expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("transfer-one.bin").path), "cancelled destination remains")
        try complete(app, name: "shared (1).bin", at: dir.appendingPathComponent("shared (1).bin"))
        try expect(try String(contentsOf: dir.appendingPathComponent("shared.bin"), encoding: .utf8) == "preexisting", "collision overwritten")
    }
    private static func postClose(_ app: AppUnderTest) throws {
        let dir = try folder(app); let page = try home(app)
        try start(app, "transfer-post", in: page, post: true); try library(app)
        _ = try receiving(app, name: "transfer-post.bin")
        try app.dispatch(.tab(.close(.item(page.item))))
        try library(app)
        try complete(app, name: "transfer-post.bin", at: dir.appendingPathComponent("transfer-post.bin"), byte: 80)
        try expect(app.site.requestCount("/transfer-post-valid-post") == 1 && app.site.requestCount("/transfer-post") == 1, "original POST was reconstructed or replayed")
    }
    private static func windowClose(_ app: AppUnderTest) throws {
        let dir = try folder(app)
        try app.dispatch(.window(.new))
        guard case .hello(let hello) = try app.send(.hello), let w = hello.windows.first(where: { $0 != app.window }) else { throw Check(description: "missing second window") }
        _ = try app.send(.load(window: w, url: app.site.url("index.html")))
        let page = try home(app, in: w)
        try start(app, "transfer-window", in: page); try library(app, in: w)
        _ = try receiving(app, name: "transfer-window.bin", in: w)
        _ = try app.send(.dispatch(window: w, command: .window(.close)))
        try library(app)
        try complete(app, name: "transfer-window.bin", at: dir.appendingPathComponent("transfer-window.bin"))
    }
    private static func reassign(_ app: AppUnderTest) throws {
        let dir = try folder(app); let page = try home(app)
        let before = try app.native().pages[page]?.browserID
        try start(app, "transfer-reassign", in: page); try library(app)
        _ = try receiving(app, name: "transfer-reassign.bin")
        let other = try profile(app, name: "Other")
        _ = try folder(app, profile: other, name: "wrong-owner")
        try app.dispatch(.profile(.assign(.current, to: other)))
        try app.waitUntil("replacement browser") { let id = try app.native().pages[page]?.browserID; return id != nil && id != before }
        // The original public record belongs to Default. A second window on a Default space observes it.
        try app.dispatch(.space(.create(title: "Default", icon: .none, theme: .default)))
        try app.dispatch(.profile(.assign(.current, to: .default)))
        _ = try folder(app, name: "later-policy")
        try library(app)
        try complete(app, name: "transfer-reassign.bin", at: dir.appendingPathComponent("transfer-reassign.bin"))
        try expect(app.site.requestCount("/transfer-reassign") == 1, "download replayed")
    }
    private static func privateExpiry(_ app: AppUnderTest) throws {
        let dir = try folder(app)
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello), let w = hello.windows.first(where: { $0 != app.window }) else { throw Check(description: "missing private window") }
        _ = try app.send(.load(window: w, url: app.site.url("index.html")))
        let page = try home(app, in: w)
        try app.evaluate(page, "document.cookie='epoch=old; path=/';localStorage.setItem('epoch','old')")
        try start(app, "transfer-private-old", in: page)
        try app.waitUntil("private transfer bytes") { app.site.requestCount("/transfer-private-old-bytes") > 65536 }
        _ = try app.send(.dispatch(window: w, command: .window(.close)))
        try app.dispatch(.window(.newIncognito))
        try stopped(app, "/transfer-private-old")
        guard case .hello(let fresh) = try app.send(.hello), let next = fresh.windows.first(where: { $0 != app.window }) else { throw Check(description: "missing new private window") }
        _ = try app.send(.load(window: next, url: app.site.url("index.html")))
        let nextPage = try home(app, in: next)
        try app.evaluate(nextPage, "document.title=(!document.cookie.includes('epoch=old')&&!localStorage.getItem('epoch'))?'Fresh private epoch':'Leaked private epoch'")
        try app.waitUntil("fresh private storage") {
            guard case .tab(let row)? = try app.view(next).scratch?.rows.first else { return false }
            return row.title == "Fresh private epoch"
        }
        try start(app, "download?private-new=1", in: nextPage)
        try app.waitUntil("new epoch download") { (try? Data(contentsOf: dir.appendingPathComponent("fixture.txt"))) == Data("fixture download\n".utf8) }
        try library(app); try expect(try rows(app).isEmpty, "private transfer entered public Library")
        try app.flush()
        let state = try String(contentsOf: app.dataDirectory.appendingPathComponent("state.json"), encoding: .utf8)
        try expect(!state.contains("transfer-private") && !state.contains("private-new"), "private metadata was saved")
        try expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["fixture.txt"], "expired private transfer left output or staging files")
    }
    private static func deleteProfile(_ app: AppUnderTest) throws {
        let p = try profile(app, name: "Dispose")
        let dir = try folder(app, profile: p)
        try app.dispatch(.profile(.assign(.current, to: p)))
        let page = try home(app)
        try start(app, "transfer-delete", in: page); try library(app)
        _ = try receiving(app, name: "transfer-delete.bin")
        try app.dispatch(.profile(.assign(.current, to: .default)))
        try app.dispatch(.profile(.delete(p)))
        try stopped(app, "/transfer-delete")
        try app.waitUntil("final disposal") {
            guard case .settings(let settings) = try app.send(.settings) else { return false }
            return settings.deletingProfiles.isEmpty
        }
        let marker = try String(contentsOf: app.dataDirectory.appendingPathComponent("profiles-to-delete"), encoding: .utf8)
        try expect(marker.contains("Profile-" + p.rawValue), "deletion was not scheduled")
        try expect(FileManager.default.fileExists(atPath: app.dataDirectory.appendingPathComponent("Chromium/Profile-" + p.rawValue).path), "physical deletion incorrectly happened while runtime held profile")
        try expect((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty == true, "cancelled profile transfer left output")
        try app.restart()
        try expect(!FileManager.default.fileExists(atPath: app.dataDirectory.appendingPathComponent("Chromium/Profile-" + p.rawValue).path), "scheduled profile deletion did not run at next launch")
    }
    private static func retainedQuit(_ app: AppUnderTest) throws {
        let dir = try folder(app); let page = try home(app)
        try start(app, "transfer-quit", in: page); try library(app)
        _ = try receiving(app, name: "transfer-quit.bin")
        try app.dispatch(.tab(.close(.item(page.item))))
        let quit = try app.quit(); try expect(quit.clean, "leased quit failed: \(quit.exit)")
        try stopped(app, "/transfer-quit")
        try expect((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty == true, "leased quit left files")
    }
    private static func pendingSheet(_ app: AppUnderTest) throws {
        _ = try folder(app); let page = try home(app)
        try app.dispatch(.settings(.profile(.default, .promptForDownloadLocation(true))))
        try start(app, "transfer-panel", in: page)
        try app.waitUntil("owned save sheet") { try app.native().appWindows.contains { $0.isVisible && $0.className.contains("SavePanel") } }
        // The control call returns while the native sheet is open, proving the sheet does not block the app loop.
        try app.dispatch(.tab(.close(.item(page.item))))
        try library(app)
        try app.waitUntil("sheet cancellation") {
            try !app.native().appWindows.contains { $0.isVisible && $0.className.contains("SavePanel") }
                && rows(app).contains { $0.state == .cancelled }
        }
        try stopped(app, "/transfer-panel")
    }
    private static func twoProfiles(_ app: AppUnderTest) throws {
        let dir1 = try folder(app); let first = try home(app)
        try start(app, "transfer-profile-one", in: first); try library(app)
        _ = try receiving(app, name: "transfer-profile-one.bin")
        let p = try profile(app, name: "Concurrent")
        let dir2 = try folder(app, profile: p, name: "second")
        try app.dispatch(.window(.new))
        guard case .hello(let hello) = try app.send(.hello), let w = hello.windows.first(where: { $0 != app.window }) else { throw Check(description: "missing second window") }
        _ = try app.send(.dispatch(window: w, command: .space(.create(title: "Second", icon: .none, theme: .default))))
        _ = try app.send(.dispatch(window: w, command: .profile(.assign(.current, to: p))))
        _ = try app.send(.load(window: w, url: app.site.url("index.html")))
        let second = try home(app, in: w)
        try start(app, "transfer-profile-two", in: second); try library(app, in: w)
        _ = try receiving(app, name: "transfer-profile-two.bin", in: w)
        try library(app)
        try expect(try rows(app).contains { $0.filename == "transfer-profile-one.bin" && $0.state == .inProgress }, "transfers did not overlap")
        try complete(app, name: "transfer-profile-one.bin", at: dir1.appendingPathComponent("transfer-profile-one.bin"))
        try complete(app, name: "transfer-profile-two.bin", at: dir2.appendingPathComponent("transfer-profile-two.bin"), in: w)
    }
    private static func loaderRace(_ app: AppUnderTest) throws {
        let p = try profile(app, name: "Loading")
        try app.dispatch(.profile(.assign(.current, to: p)))
        try app.dispatch(.profile(.assign(.current, to: .default)))
        try app.dispatch(.profile(.delete(p)))
        try app.waitUntil("loader drained after revocation", timeout: 12) {
            guard case .settings(let settings) = try app.send(.settings) else { return false }
            return settings.deletingProfiles.isEmpty
        }
        _ = try home(app)
        try app.restart()
        try expect(!FileManager.default.fileExists(atPath: app.dataDirectory.appendingPathComponent("Chromium/Profile-" + p.rawValue).path), "revoked loader recreated profile")
    }
    private static func pendingWindowSheet(_ app: AppUnderTest) throws {
        let directory = try folder(app)
        try app.dispatch(.settings(.profile(.default, .promptForDownloadLocation(true))))
        try app.dispatch(.window(.new))
        guard case .hello(let hello) = try app.send(.hello), let window = hello.windows.first(where: { $0 != app.window }) else { throw Check(description: "missing sheet owner") }
        _ = try app.send(.load(window: window, url: app.site.url("index.html")))
        let page = try home(app, in: window)
        try start(app, "transfer-panel-window", in: page)
        try app.waitUntil("owned save sheet") { try app.native(window).appWindows.contains { $0.isVisible && $0.className.contains("SavePanel") } }
        _ = try app.send(.dispatch(window: window, command: .window(.close)))
        try library(app)
        try app.waitUntil("owner sheet dismissal and native cancellation") {
            try !app.native().appWindows.contains { $0.isVisible && $0.className.contains("SavePanel") }
                && rows(app).contains { $0.state == .cancelled }
        }
        try stopped(app, "/transfer-panel-window")
        try expect(!FileManager.default.fileExists(atPath: directory.path), "unaccepted sheet created output")
    }

}
