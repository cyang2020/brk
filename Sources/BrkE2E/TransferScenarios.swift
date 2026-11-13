import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum TransferScenarios {
    static let all: [Scenario] = [
        Scenario("T1", "simultaneous downloads cancel independently, stop server bytes and preserve collisions", cefOnly: "CEF transfer callbacks", concurrent),
        Scenario("T2", "accepted POST download survives source-tab close with its original request", cefOnly: "CEF transfer lease", postClose),
        Scenario("T7", "quit cancels an already retained transfer and drains its native host", cefOnly: "CEF shutdown", retainedQuit),
    ]
    static let size = 4_194_304



    private static func folder(_ app: AppUnderTest, profile: ProfileID = .default, name: String = "downloads") throws -> URL {
        let directory = app.dataDirectory.appendingPathComponent(name, isDirectory: true)
        try app.dispatch(.settings(.profile(profile, .downloadsDirectory(directory.path))))
        return directory
    }
    private static func rows(_ app: AppUnderTest, in window: WindowID? = nil) throws -> [DownloadRow] {
        if case .library(let library)? = try app.view(window ?? app.window).overlay { return library.downloads }
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
        try app.screenshot("cancelled-and-active")
        try complete(app, name: "shared (1).bin", at: dir.appendingPathComponent("shared (1).bin"))
        try expect(try String(contentsOf: dir.appendingPathComponent("shared.bin"), encoding: .utf8) == "preexisting", "collision overwritten")
        try app.screenshot("completed-and-cancelled")
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
    private static func reassign(_ app: AppUnderTest) throws {
        try reassign(app, path: "transfer-reassign")
    }
    static func reassign(_ app: AppUnderTest, path: String) throws {
        let dir = try folder(app); let page = try home(app)
        let before = try app.native().pages[page]?.browserID
        try start(app, path, in: page); try library(app)
        _ = try receiving(app, name: path + ".bin")
        let other = try profile(app, name: "Other")
        _ = try folder(app, profile: other, name: "wrong-owner")
        try app.dispatch(.profile(.assign(.current, to: other)))
        try app.waitUntil("replacement browser") { let id = try app.native().pages[page]?.browserID; return id != nil && id != before }
        // The original public record belongs to Default. A second window on a Default space observes it.
        try app.dispatch(.space(.create(title: "Default", icon: .none, theme: .default)))
        try app.dispatch(.profile(.assign(.current, to: .default)))
        _ = try folder(app, name: "later-policy")
        try library(app)
        try complete(app, name: path + ".bin", at: dir.appendingPathComponent(path + ".bin"))
        try expect(app.site.requestCount("/" + path) == 1, "download replayed")
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
        try deleteProfile(app, path: "transfer-delete")
    }
    static func deleteProfile(_ app: AppUnderTest, path: String) throws {
        let p = try profile(app, name: "Dispose")
        let dir = try folder(app, profile: p)
        try app.dispatch(.profile(.assign(.current, to: p)))
        let page = try home(app)
        try start(app, path, in: page); try library(app)
        _ = try receiving(app, name: path + ".bin")
        try app.dispatch(.profile(.assign(.current, to: .default)))
        try app.dispatch(.profile(.delete(p)))
        try stopped(app, "/" + path)
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

}
