import BrkBase
import BrkControl
import BrkDomain
import Foundation
import CoreGraphics

enum AudioScenarios {
    static let all = [
        Scenario("Audio1", "identical URLs, two windows, navigation, retired browser and close isolation", cefOnly: "Chrome audibility", windows),
        Scenario("Audio2", "two profiles, two private windows and a replacement private epoch", cefOnly: "Chrome context isolation", profiles),
        Scenario("Audio3", "foreign-frame tone, silent source, stop and no web-callable observer", cefOnly: "Chrome foreign-frame audibility", foreignFrame),
        Scenario("Audio4", "audible while loading and close during an unfinished response", cefOnly: "Chrome live document lifetime", loading),
    ]
    private static func audioTab(_ id: ItemID, in view: WindowSnapshot) -> TabRow? {
        tab(id, in: view) ?? tabRows(view.scratch?.rows ?? []).first { $0.id == id }
    }
    static func staysSilent(_ app: AppUnderTest, _ item: ItemID, seconds: Double = 1) throws {
        let page = PageID(window: app.window!, item: item)
        try app.waitUntil("healthy audibility reader for the silent page") {
            let native = try app.native().pages[page]
            return native?.audioTabID != nil && native?.audioError == nil
        }
        let deadline = uptime() + seconds
        repeat {
            guard let row = try audioTab(item, in: app.view()) else { throw Check(description: "audio row missing from this window") }
            try expect(!row.audible, "silent source incorrectly became audible")
            try expect(try app.native().pages[page]?.audioError == nil, "silent reading was unavailable")
            Thread.sleep(forTimeInterval: 0.1)
        } while uptime() < deadline
    }
    private static func open(_ app: AppUnderTest, url: URL? = nil) throws -> ItemID {
        let url = url ?? app.site.url("tab-tools-audio.html")
        let item = try app.load(url)
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: url)
        try app.waitUntil("exact browser target mapped in its context") { try facts(app, item).audioTabID != nil }
        return item
    }
    private static func facts(_ app: AppUnderTest, _ item: ItemID) throws -> PageFacts {
        guard let facts = try app.native().pages[PageID(window: app.window!, item: item)] else { throw Check(description: "missing page facts") }
        return facts
    }
    private static func button(_ app: AppUnderTest, _ x: Double, _ y: Double = 50) throws {
        let card = try app.native().computed.cards[0].rect
        try app.click(at: CGPoint(x: card.minX + x, y: card.minY + y))
    }
    private static func play(_ app: AppUnderTest, _ item: ItemID) throws {
        try button(app, 80)
        try app.waitUntil("oscillator started with nonzero samples") { try audioTab(item, in: app.view())?.title.contains("running tone source=true") == true }
        try app.waitUntil("exact browser audible") { try audioTab(item, in: app.view())?.audible == true }
    }
    private static func newWindow(_ app: AppUnderTest, privateMode: Bool = false) throws -> WindowID {
        guard case .hello(let before) = try app.send(.hello) else { throw Check(description: "missing hello") }
        try app.dispatch(.window(privateMode ? .newIncognito : .new))
        guard case .hello(let after) = try app.send(.hello), let new = after.windows.first(where: { !before.windows.contains($0) }) else { throw Check(description: "new window missing") }
        app.window = new
        _ = try app.send(.activate(window: new))
        return new
    }

    @Sendable static func windows(_ app: AppUnderTest) throws {
        let first = app.window!
        let a = try open(app)
        try app.dispatch(.tab(.togglePin(.item(a))))
        try play(app, a)
        let aFacts = try facts(app, a)
        let b = try open(app)
        try staysSilent(app, b)
        try expect(try audioTab(a, in: app.view())?.audible == true, "opening identical URL silenced the wrong tab")
        let bFacts = try facts(app, b)
        try expect(aFacts.audioTargetID != bFacts.audioTargetID && aFacts.audioTabID != bFacts.audioTabID, "identical URLs shared target identity")
        try app.recordWindows("identical-url-pages")
        let second = try newWindow(app)
        try app.dispatch(.tab(.focus(a)))
        try app.waitForPageInput(PageID(window: second, item: a), at: app.site.url("tab-tools-audio.html"))
        try app.waitUntil("second realization mapped") { try facts(app, a).audioTabID != nil }
        try staysSilent(app, a)
        try expect(try facts(app, a).audioTargetID != aFacts.audioTargetID, "shared logical tab reused native target")
        try expect(try audioTab(a, in: app.view(first))?.audible == true, "window realization leaked its silent state")
        try app.recordWindows("two-windows-identical-urls")
        app.window = first; _ = try app.send(.activate(window: first))
        try app.dispatch(.tab(.focus(a)))
        try app.click(.tabTool("audio-" + a.rawValue))
        try app.waitUntil("saved mute applies to both realizations") {
            try facts(app, a).audioMuted == true && app.native(second).pages[PageID(window: second, item: a)]?.audioMuted == true
        }
        try app.dispatch(.tab(.focus(b)))
        try expect(try facts(app, b).audioMuted == false, "mute crossed into second tab")
        try app.dispatch(.tab(.focus(a)))
        try app.click(.tabTool("audio-" + a.rawValue))
        try app.dispatch(.commandBar(.open(.editCurrent)))
        try app.dispatch(.commandBar(.submit(app.site.url("page2.html").absoluteString)))
        try app.waitForPageInput(PageID(window: first, item: a), at: app.site.url("page2.html"))
        // tabs.audible deliberately includes Chromium's recent-audio grace period across navigation.
        var quietSince: Double?
        try app.waitUntil("Chromium's recent-audio state becomes stably quiet after navigation") {
            guard try audioTab(a, in: app.view())?.audible == false,
                  try facts(app, a).audioError == nil else { quietSince = nil; return false }
            if quietSince == nil { quietSince = uptime() }
            return uptime() - quietSince! >= 1
        }
        try staysSilent(app, a)
        try app.recordWindows("navigated")
        try app.dispatch(.tabTools(.resetPinned))
        try app.waitForPageInput(PageID(window: first, item: a), at: app.site.url("tab-tools-audio.html"))
        try play(app, a)
        try app.dispatch(.tab(.close(.item(a))))
        try app.waitUntil("pinned browser retired") { try app.native().pages[PageID(window: first, item: a)] == nil }
        try app.dispatch(.tab(.focus(a)))
        try app.waitForPageInput(PageID(window: first, item: a), at: app.site.url("tab-tools-audio.html"))
        try app.waitUntil("replacement mapped") { try facts(app, a).audioTabID != nil }
        try expect(try facts(app, a).audioTargetID != aFacts.audioTargetID, "retired browser target survived replacement")
        try staysSilent(app, a, seconds: 2)
        try app.recordWindows("retired-and-replaced")
        try play(app, a)
        try app.recordWindows("replacement-can-play")
    }

    @Sendable static func profiles(_ app: AppUnderTest) throws {
        let first = app.window!
        let a = try open(app); try play(app, a)
        let publicFacts = try facts(app, a)
        let workWindow = try newWindow(app)
        let work = try createSpace(app, title: "Audio Work")
        try app.dispatch(.profile(.create(name: "Audio Work", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings), let profile = settings.profiles.first(where: { $0.profile.name == "Audio Work" })?.profile.id else { throw Check(description: "Work profile missing") }
        try app.dispatch(.profile(.assign(.space(work), to: profile)))
        let b = try open(app)
        try staysSilent(app, b)
        let workFacts = try facts(app, b)
        try expect(publicFacts.audioObserverID != workFacts.audioObserverID, "profiles shared observer")
        try play(app, b)
        try expect(try audioTab(a, in: app.view(first))?.audible == true, "Work observer changed default page")
        try app.dispatch(.profile(.assign(.space(work), to: .default)))
        try app.waitForPageInput(PageID(window: workWindow, item: b), at: app.site.url("tab-tools-audio.html"))
        try app.waitUntil("profile reassignment replaces the audible browser") {
            try facts(app, b).audioTabID != nil && facts(app, b).audioTargetID != workFacts.audioTargetID
        }
        try staysSilent(app, b)
        try expect(try facts(app, b).audioObserverID == publicFacts.audioObserverID, "reassigned browser kept its old profile observer")
        try expect(try audioTab(a, in: app.view(first))?.audible == true, "profile reassignment changed another window's audio")
        try app.recordWindows("profile-reassignment")
        try app.dispatch(.profile(.assign(.space(work), to: profile)))
        try app.waitForPageInput(PageID(window: workWindow, item: b), at: app.site.url("tab-tools-audio.html"))
        try app.waitUntil("Work browser remapped") { try facts(app, b).audioTabID != nil }
        try staysSilent(app, b)
        try play(app, b)
        let resumedWorkFacts = try facts(app, b)
        let privateOne = try newWindow(app, privateMode: true)
        let p = try open(app); try staysSilent(app, p); try play(app, p)
        let privateFacts = try facts(app, p)
        try expect(privateFacts.audioObserverID != publicFacts.audioObserverID && privateFacts.audioObserverID != resumedWorkFacts.audioObserverID, "private observer shared persistent context")
        let privateTwo = try newWindow(app, privateMode: true)
        let q = try open(app); try staysSilent(app, q)
        try expect(try facts(app, q).audioObserverID == privateFacts.audioObserverID, "same private epoch did not share its own observer")
        try expect(try audioTab(p, in: app.view(privateOne))?.audible == true, "private window states crossed")
        try expect(try audioTab(a, in: app.view(first))?.audible == true && audioTab(b, in: app.view(workWindow))?.audible == true, "private observer changed persistent pages")
        try app.recordWindows("profiles-private-two-windows")
        try app.dispatch(.window(.close))
        app.window = privateOne
        try app.dispatch(.window(.close))
        app.window = first
        let replacement = try newWindow(app, privateMode: true)
        let r = try open(app); try staysSilent(app, r, seconds: 2)
        try expect(try facts(app, r).audioObserverID != privateFacts.audioObserverID, "observer survived retired private epoch")
        try play(app, r)
        try app.recordWindows("private-new-epoch")
        app.note("Private windows \(privateOne), \(privateTwo) closed; replacement \(replacement) has a distinct observer and native target.")
    }

    @Sendable static func foreignFrame(_ app: AppUnderTest) throws {
        let receipt = UUID().uuidString
        let item = try open(app, url: app.site.url("tab-tools-audio-frame.html?receipt=\(receipt)"))
        try button(app, 80, 150)
        try app.waitUntil("foreign frame running silent source receipt") { app.site.requestCount("/audio-proof/\(receipt)/running-silence-true") > 0 }
        try staysSilent(app, item)
        try button(app, 80)
        try app.waitUntil("foreign frame nonzero source receipt") { app.site.requestCount("/audio-proof/\(receipt)/running-tone-true") > 0 }
        try app.waitUntil("foreign frame makes only its browser audible") { try audioTab(item, in: app.view())?.audible == true }
        try app.recordWindows("foreign-frame-audible")
        _ = try app.screenshot("foreign-frame-audible")
        try app.click(.tabTool("audio-" + item.rawValue))
        try expect(try facts(app, item).audioMuted == true, "foreign-frame tab did not mute")
        try app.click(.tabTool("audio-" + item.rawValue))
        try expect(try facts(app, item).audioMuted == false, "foreign-frame tab did not unmute")
        try button(app, 280)
        try app.waitUntil("foreign frame stopped-source receipt") { app.site.requestCount("/audio-proof/\(receipt)/closed-silence-false") > 0 }
        try app.waitUntil("foreign frame stopped audibility") { try audioTab(item, in: app.view())?.audible == false }
        try app.recordWindows("foreign-frame-stopped")
        // Ordinary web code gets neither extension APIs nor a native observer entry point.
        try app.evaluate(PageID(window: app.window!, item: item), "document.title = 'web privileges ' + [typeof window.chrome?.tabs, typeof window.chrome?.debugger, typeof window.brkAudio].join(','); window.postMessage({kind:'audioChanged',audible:true}, '*'); console.log('brk audio true');")
        try app.waitUntil("ordinary web document has no audio privileges") { try audioTab(item, in: app.view())?.title == "web privileges undefined,undefined,undefined" }
        try staysSilent(app, item)
        try app.recordWindows("web-cannot-publish-audio")
    }

    @Sendable static func loading(_ app: AppUnderTest) throws {
        defer { app.site.releaseAudioDocument() }
        let receipt = UUID().uuidString
        let item = try app.load(app.site.url("audio-loading?receipt=\(receipt)"))
        let page = PageID(window: app.window!, item: item)
        try app.waitUntil("interactive fixture with an unfinished main response") {
            guard app.site.requestCount("/audio-proof/\(receipt)/ready") > 0,
                  case .pageObservations(let values) = try app.send(.pageObservations),
                  let observation = values[page], case .loading = observation.document else { return false }
            return try app.native().pages[page]?.hasKeyboardFocus == true
        }
        try button(app, 80)
        try app.waitUntil("running nonzero source before the main response ends") { app.site.requestCount("/audio-proof/\(receipt)/running-tone-true") > 0 }
        try app.waitUntil("Chrome audibility before main-document completion") { try audioTab(item, in: app.view())?.audible == true }
        guard case .pageObservations(let observations) = try app.send(.pageObservations) else { throw Check(description: "document observations missing") }
        let evidence = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/Audio4-loading-observations.json")
        try JSONEncoder().encode(observations).write(to: evidence)
        app.note("Held audio response completions before audible assertion: \(app.site.requestCount("audio-loading-completed"))")
        try expect(app.site.requestCount("audio-loading-completed") == 0, "fixture completed its pending response before the audible observation")
        guard let observation = observations[page], case .loading = observation.document else { throw Check(description: "audio was only observed after the pending document completed") }
        try app.recordWindows("audible-during-load")
        _ = try app.screenshot("audible-during-load")
        try app.dispatch(.tab(.close(.item(item))))
        try app.waitUntil("playing loading browser retired") { try audioTab(item, in: app.view()) == nil }
        guard let home = try currentTab(app.view())?.id else { throw Check(description: "home tab missing after close") }
        try staysSilent(app, home)
        try app.recordWindows("closed-during-load")
    }
}
