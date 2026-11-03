import BrkBase
import BrkControl
import BrkDomain
import Foundation

/// What keeps a hidden page running when its site is set to suspend, judged by real network ticks: muted media in a
/// cross-origin frame, and a video in picture in picture (paused, so only picture in picture protects it).
enum SiteProtectionScenarios {
    static let all = [
        Scenario("SitePolicy-frame-media", "muted media in a cross-origin frame keeps a hidden page running; without it the page freezes",
                 cefOnly: "Chromium page lifecycle", frameMedia),
        Scenario("SitePolicy-pip", "a video in picture in picture keeps its hidden page running until picture in picture ends",
                 cefOnly: "Chromium page lifecycle", pictureInPicture),
    ]

    static func suspend(_ app: AppUnderTest) throws {
        try app.dispatch(.site(.controls))
        guard let target = try SitePolicyScenarios.controls(app).target else { throw Check(description: "site target missing") }
        var rule = SiteRule(); rule.suspendWhenHidden = true
        try app.dispatch(.site(.rule(target, rule))); try app.dispatch(.site(.closeControls))
    }
    static func startTicks(_ app: AppUnderTest, _ item: ItemID, _ tag: String) throws {
        try SitePolicyScenarios.evaluate(app, item, "window.fixtureTick=0;setInterval(()=>fetch('/site-policy-tick-\(tag)?n='+(fixtureTick++),{cache:'no-store'}),100)")
        try app.waitUntil("foreground network ticks") { app.site.requestCount("/site-policy-tick-" + tag) >= 2 }
    }
    /// Ticks over 3 s after the page has had 0.7 s to settle hidden. Chromium runs a hidden page's timers about once a
    /// second, so a running hidden page shows two or more and a frozen one none.
    static func hiddenTicks(_ app: AppUnderTest, _ tag: String) -> Int {
        app.sleep(0.7)
        let before = app.site.requestCount("/site-policy-tick-" + tag)
        app.sleep(3)
        return app.site.requestCount("/site-policy-tick-" + tag) - before
    }

    @Sendable static func frameMedia(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-policy-frames.html")); try waitForTitle(app, item, "Frame media fixture")
        try app.waitUntil("the cross-origin frame's muted video is read as playing", timeout: 12) {
            try tab(item, in: app.view())?.mediaPlayers.contains { $0.id.frame != 0 && !$0.paused } == true
        }
        try suspend(app)
        try startTicks(app, item, "frames")
        let other = try app.load(app.site.url("page2.html"))
        let protected = hiddenTicks(app, "frames")
        try expect(protected >= 2, "the page froze although a cross-origin frame was playing muted media (\(protected) ticks)")
        try app.dispatch(.tab(.focus(item)))
        try SitePolicyScenarios.evaluate(app, item, "document.querySelector('iframe').remove()")
        try app.waitUntil("no media is read after the frame is gone") { try tab(item, in: app.view())?.mediaPlayers.isEmpty == true }
        app.sleep(0.5)
        try app.dispatch(.tab(.focus(other)))
        let frozen = hiddenTicks(app, "frames")
        try expect(frozen == 0, "without the frame the hidden page kept running (\(frozen) ticks)")
        app.note("Hidden with a playing muted video in a cross-origin localhost frame: \(protected) ticks in 3 s. Same page without the frame: \(frozen) ticks, so suspension itself works and the frame's media is what kept it running.")
    }

    @Sendable static func pictureInPicture(_ app: AppUnderTest) throws {
        try app.dispatch(.settings(.advanced(.autoPictureInPicture(false))))
        let url = app.site.url("capture-media.html"), item = try app.load(url)
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: url)
        try app.waitUntil("a ready video") { try tab(item, in: app.view())?.mediaPlayers.contains { $0.kind == .video } == true }
        try suspend(app)
        try startTicks(app, item, "pip")
        try app.perform(.menuAction(ActionID.videoPictureInPicture.rawValue))
        try app.waitUntil("video picture in picture") { try tab(item, in: app.view())?.mediaPlayers.contains(where: \.pictureInPicture) == true }
        try SitePolicyScenarios.evaluate(app, item, "for(const v of document.querySelectorAll('video,audio'))v.pause()")
        try app.waitUntil("the video in picture in picture is paused") {
            try tab(item, in: app.view())?.mediaPlayers.allSatisfy { $0.paused || $0.ended } == true
        }
        guard let player = try tab(item, in: app.view())?.mediaPlayers.first(where: \.pictureInPicture) else { throw Check(description: "PiP player missing") }
        _ = try app.load(app.site.url("page2.html"))
        let protected = hiddenTicks(app, "pip")
        try expect(protected >= 2, "the hidden page froze while its video was in picture in picture (\(protected) ticks)")
        try app.dispatch(.page(.media(.item(item), player.id, .exitPictureInPicture)))
        try app.waitUntil("picture in picture ends") { try tab(item, in: app.view())?.mediaPlayers.contains(where: \.pictureInPicture) == false }
        let frozen = hiddenTicks(app, "pip")
        try expect(frozen == 0, "after picture in picture ended the hidden page kept running (\(frozen) ticks)")
        app.note("Paused video in picture in picture, page hidden and set to suspend: \(protected) ticks in 3 s; after leaving picture in picture: \(frozen).")
    }
}
