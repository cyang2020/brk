import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum MediaScenarios {
    static let all = [
        Scenario("MediaControls", "per-player background pause/play, frames and navigation ownership", cefOnly: "Chrome media elements", controls),
        Scenario("MediaSounds", "bundled event sound submits when enabled and stays silent when disabled", cefOnly: "signed sound resources", sounds)]
    static func row(_ app: AppUnderTest, _ item: ItemID) throws -> TabRow? { tab(item, in: try app.view()) }
    @Sendable static func controls(_ app: AppUnderTest) throws {
        let url = app.site.url("capture-media.html")
        let first = try app.load(url)
        let page = PageID(window: app.window!, item: first)
        try app.waitForPageInput(page, at: url)
        try app.waitUntil("real video is observed playing") { try row(app, first)?.mediaPlayers.first?.paused == false }
        let player = try row(app, first)!.mediaPlayers[0]
        let second = try app.load(app.site.url("page2.html"))
        try app.click(.tabTool("media-" + first.rawValue))
        try app.waitUntil("background player's actual paused state") { try row(app, first)?.mediaPlayers.first?.paused == true }
        try expect(try app.view().content.panes.first?.tab == second, "background Pause stole tab selection")
        try app.dispatch(.page(.media(.item(first), player.id, .play)))
        try app.waitUntil("background player's actual playing state") { try row(app, first)?.mediaPlayers.first?.paused == false }
        try app.dispatch(.tab(.focus(first)))
        try app.evaluate(page, "document.title='DOM paused='+document.querySelector('video').paused")
        try app.waitUntil("DOM independently confirms play") { try row(app, first)?.title == "DOM paused=false" }
        try app.evaluate(page, "const f=document.createElement('iframe');f.src='http://localhost:'+location.port+'/media-frame.html';document.body.appendChild(f)")
        try app.waitUntil("foreign frame has its own player identity") { try row(app, first)?.mediaPlayers.contains(where: { $0.id.frame != 0 }) == true }
        let child = try row(app, first)!.mediaPlayers.first { $0.id.frame != 0 }!
        try app.dispatch(.page(.media(.item(first), child.id, .pause)))
        try app.waitUntil("only foreign player pauses") {
            guard let players = try row(app, first)?.mediaPlayers else { return false }
            return players.contains { $0.id == child.id && $0.paused } && players.contains { $0.id == player.id && !$0.paused }
        }
        try app.recordWindows("media-background-and-frame-controls")
        _ = try app.screenshot("media-player-controls")
        try app.evaluate(page, "location.href='page2.html'")
        try app.waitUntil("navigation removes the old player controls") { try row(app, first)?.mediaPlayers.isEmpty == true }
        try app.dispatch(.page(.media(.item(first), player.id, .play)))
        try expect(try row(app, first)?.mediaPlayers.isEmpty == true, "stale control resurrected a navigated player")
    }
    static func submissions(_ app: AppUnderTest) throws -> [[String: Any]] {
        guard case .text(let json) = try app.send(.mediaSounds), let data = json.data(using: .utf8),
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw Check(description: "sound diagnostics missing") }
        return rows
    }
    @Sendable static func sounds(_ app: AppUnderTest) throws {
        _ = try app.load(app.site.url("page2.html"))
        try app.dispatch(.settings(.advanced(.soundEffects(true))))
        let before = try submissions(app).count
        try app.dispatch(.tab(.close(.focused)))
        let played = try submissions(app)
        try expect(played.count == before + 1, "archive did not emit exactly one sound")
        try expect(played.last?["event"] as? String == "tabsArchived" && played.last?["accepted"] as? Bool == true, "NSSound rejected the bundled asset")
        try app.dispatch(.settings(.advanced(.soundEffects(false))))
        _ = try app.load(app.site.url("page2.html"))
        try app.dispatch(.tab(.close(.focused)))
        try expect(try submissions(app).count == played.count, "disabled sound still submitted to audio")
        try app.restart()
        guard case .settings(let settings) = try app.send(.settings) else { throw Check(description: "settings missing") }
        try expect(settings.advanced.soundEffects == false, "disabled setting did not survive restart")
        app.note("NSSound accepted the original PCM cue. Physical speaker output was not recorded.")
    }
}
