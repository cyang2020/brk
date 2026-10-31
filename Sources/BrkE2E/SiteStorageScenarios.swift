import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum SiteStorageScenarios {
    static let all = [Scenario("SitePolicy-private-reset", "last private window disposal resets all fixture storage and leaves no app-owned content trace", cefOnly: "off-record storage", privateReset)]
    @Sendable static func privateReset(_ app: AppUnderTest) throws {
        func makeWindow() throws -> WindowID {
            try app.dispatch(.window(.newIncognito))
            guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "hello failed") }
            for id in hello.windows where id != app.window { if try app.view(id).kind == .incognito { return id } }
            throw Check(description: "private window missing")
        }
        func load(_ window: WindowID) throws -> ItemID {
            guard case .loaded(let item) = try app.send(.load(window: window, url: app.site.url("site-policy.html"))) else { throw Check(description: "private load failed") }
            try app.waitForPageInput(PageID(window: window, item: item), at: app.site.url("site-policy.html"))
            return item
        }
        let first = try makeWindow(), item = try load(first)
        let secret = "SE-private-8e680e30-" + UUID().uuidString
        try app.perform(.evaluate(page: PageID(window: first, item: item), script: "seedSite('\(secret)')"))
        try app.waitUntil("private storage fixture seeded") { try tabRows(app.view(first).scratch?.rows ?? []).first(where: { $0.id == item })?.title == "seed:" + secret }
        try app.send(.dispatch(window: first, command: .site(.appearance(.dark))))
        try app.send(.dispatch(window: first, command: .window(.close)))
        let second = try makeWindow(), reader = try load(second)
        try app.perform(.evaluate(page: PageID(window: second, item: reader), script: "readSite()"))
        try app.waitUntil("new private session sees empty storage") {
            guard let title = tabRows(try app.view(second).scratch?.rows ?? []).first(where: { $0.id == reader })?.title, title.hasPrefix("storage:"),
                  let data = String(title.dropFirst(8)).data(using: .utf8), let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            try expect(value["local"] is NSNull && value["idb"] as? Bool == false && value["cache"] as? Bool == false && value["worker"] as? Bool == false,
                       "private storage survived disposal: \(value)")
            try expect(!(value["cookie"] as? String ?? "").contains(secret) && !(value["serverCookie"] as? String ?? "").contains(secret), "private cookie survived disposal")
            return true
        }
        try app.send(.dispatch(window: second, command: .window(.close)))
        try app.flush()
        let quit = try app.quit(); try expect(quit.clean, "private storage shutdown was not clean")
        var hits: [String] = []
        if let walker = FileManager.default.enumerator(at: app.dataDirectory, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let path as URL in walker {
                guard (try? path.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      let data = try? Data(contentsOf: path), data.range(of: Data(secret.utf8)) != nil else { continue }
                hits.append(path.path.replacingOccurrences(of: app.dataDirectory.path, with: ""))
            }
        }
        try expect(hits.isEmpty, "private fixture content entered app-owned files: \(hits)")
        app.note("Close/reopen without quitting resets cookies, localStorage, IndexedDB and Cache Storage. After clean quit, the unique private content marker was absent from every readable regular file under this scenario's owned data root. OS unified logs are outside this audit.")
    }
}
