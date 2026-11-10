import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Arc's mini players, as tried on Arc 1.170 (verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-*).
final class MiniPlayerTests: XCTestCase {
    private struct Fixture {
        let driver: Driver
        let playing: ItemID, other: ItemID
        let document: DocumentToken
        var page: PageID { PageID(window: driver.window, item: playing) }
        var players: [MiniPlayerSnapshot] { driver.view.miniPlayers }
        var row: TabRow? { driver.view.space.today.rows.lazy.compactMap { row -> TabRow? in if case .tab(let tab) = row, tab.id == playing { return tab } else { return nil } }.first }

        func report(_ players: [MediaPlayer]) { driver.page(playing, .mediaChanged(document, players, error: nil)) }
    }

    private static func player(_ name: String = "a", paused: Bool = false, silent: Bool = false, next: Bool = false, previous: Bool = false, pip: Bool = false, kind: MediaKind = .audio) -> MediaPlayer {
        MediaPlayer(id: MediaPlayerID(document: "doc", frame: 0, element: name), kind: kind, paused: paused, ended: false, pictureInPicture: pip, silent: silent, hasNextTrack: next, hasPreviousTrack: previous)
    }

    /// Two Today tabs, the first the one that will play; a page document ready in it, and it is on screen.
    private func fixture() throws -> Fixture {
        let d = Driver()
        let tab = d.todayIDs[0]
        d.user(.commandBar(.open(.newTab))); d.user(.commandBar(.submit("https://example.com/other")))
        let other = try XCTUnwrap(d.paneIDs.first)
        d.user(.tab(.focus(tab)))
        let browser = try XCTUnwrap(d.state.session.live[PageID(window: d.window, item: tab)]?.browser)
        let document = DocumentToken(browser: browser, sequence: 1)
        d.page(tab, .documentChanged(.loading(document)))
        d.page(tab, .documentChanged(.ready(document)))
        return Fixture(driver: d, playing: tab, other: other, document: document)
    }

    func testACardAppearsForAPlayingTabThatIsNotOnScreenAndGoesWhenItIsShown() throws {
        let f = try fixture()
        f.report([Self.player()])
        XCTAssertTrue(f.players.isEmpty, "the tab on screen has no card (Q18-media-a)")
        f.driver.user(.tab(.focus(f.other)))
        XCTAssertEqual(f.players.map(\.tab), [f.playing], "Q18-media-c")
        XCTAssertEqual(f.players[0].playing, true)
        f.driver.user(.tab(.focus(f.playing)))
        XCTAssertTrue(f.players.isEmpty, "shown again, the card goes")
    }

    func testATabPausedBeforeItLeavesTheScreenGetsNoCard() throws {
        let f = try fixture()
        f.report([Self.player(paused: true)])
        f.driver.user(.tab(.focus(f.other)))
        XCTAssertTrue(f.players.isEmpty, "Q18-media-x")
    }

    func testACardStaysWhenTheSoundPausesBehindIt() throws {
        let f = try fixture()
        f.report([Self.player()])
        f.driver.user(.tab(.focus(f.other)))
        f.report([Self.player(paused: true)])
        XCTAssertEqual(f.players.map(\.tab), [f.playing], "Q18-media-i: still there")
        XCTAssertEqual(f.players[0].playing, false, "and its button reads Play")
    }

    func testPlayersThePageKeepsSilentOrThatArePictureInPictureGetNoCard() throws {
        let f = try fixture()
        f.report([Self.player(silent: true)])
        f.driver.user(.tab(.focus(f.other)))
        XCTAssertTrue(f.players.isEmpty, "a muted autoplay video makes no sound")
        f.report([Self.player(pip: true, kind: .video)])
        XCTAssertTrue(f.players.isEmpty, "the Picture in Picture window takes its place (Q18-media-w)")
        f.report([Self.player(kind: .video)])
        XCTAssertEqual(f.players.map(\.tab), [f.playing], "back from Picture in Picture")
    }

    func testTheCardGoesWhenThePageHasNoPlayersLeft() throws {
        let f = try fixture()
        f.report([Self.player()])
        f.driver.user(.tab(.focus(f.other)))
        XCTAssertEqual(f.players.count, 1)
        f.report([])
        XCTAssertTrue(f.players.isEmpty)
    }

    func testTheCrossClosesTheCardUntilTheTabHasBeenShownAgain() throws {
        let f = try fixture()
        f.report([Self.player()])
        f.driver.user(.tab(.focus(f.other)))
        let effects = f.driver.user(.page(.closeMiniPlayer(f.playing))).effects
        XCTAssertTrue(f.players.isEmpty)
        XCTAssertFalse(effects.contains { if case .page = $0 { true } else { false } }, "the sound goes on")
        f.report([Self.player()])
        XCTAssertTrue(f.players.isEmpty, "it does not come back by itself (Q18-media-y)")
        f.driver.user(.tab(.focus(f.playing)))
        f.driver.user(.tab(.focus(f.other)))
        XCTAssertEqual(f.players.map(\.tab), [f.playing], "shown and left again, it does")
    }

    func testTheMiddleButtonStopsWhatPlaysAndStartsTheSameAgainWithoutChangingTheTab() throws {
        let f = try fixture()
        let (a, b, c) = (Self.player("a"), Self.player("b"), Self.player("c", paused: true))
        f.report([a, b, c])
        f.driver.user(.tab(.focus(f.other)))
        let panes = f.driver.paneIDs
        let paused = f.driver.user(.page(.mediaSession(.item(f.playing), .pause))).effects
        XCTAssertEqual(paused, [a, b].map { .page(f.page, .media(MediaControl(document: f.document, player: $0.id, operation: .pause))) })
        XCTAssertEqual(f.driver.paneIDs, panes)
        f.report([Self.player("a", paused: true), Self.player("b", paused: true), c])
        let played = f.driver.user(.page(.mediaSession(.item(f.playing), .play))).effects
        XCTAssertEqual(played, [a, b].map { .page(f.page, .media(MediaControl(document: f.document, player: $0.id, operation: .play))) })
    }

    func testPlayWithNothingNotedStartsTheFirstPlayer() throws {
        let f = try fixture()
        f.report([Self.player("a")])
        f.driver.user(.tab(.focus(f.other)))
        f.report([Self.player("a", paused: true), Self.player("b", paused: true)])
        let played = f.driver.user(.page(.mediaSession(.item(f.playing), .play))).effects
        XCTAssertEqual(played, [.page(f.page, .media(MediaControl(document: f.document, player: Self.player("a").id, operation: .play)))])
    }

    func testPreviousAndNextFollowThePagesHandlers() throws {
        let f = try fixture()
        f.report([Self.player()])
        f.driver.user(.tab(.focus(f.other)))
        XCTAssertEqual(f.players[0].hasNextTrack, false)
        XCTAssertEqual(f.players[0].hasPreviousTrack, false)
        XCTAssertTrue(f.driver.user(.page(.mediaSession(.item(f.playing), .nextTrack))).effects.isEmpty, "Q18-media-c: dim and does nothing")
        f.report([Self.player("a"), Self.player("b", next: true, previous: true)])
        XCTAssertEqual(f.players[0].hasNextTrack, true)
        XCTAssertEqual(f.players[0].hasPreviousTrack, true)
        let next = f.driver.user(.page(.mediaSession(.item(f.playing), .nextTrack))).effects
        XCTAssertEqual(next, [.page(f.page, .media(MediaControl(document: f.document, player: Self.player("b").id, operation: .nextTrack)))])
    }

    func testMutingChangesTheRowAndTheCardAndStopsTheMiddleButton() throws {
        let f = try fixture()
        f.report([Self.player()])
        f.driver.page(f.playing, .audioChanged(true))
        XCTAssertEqual(f.row?.speaker, .audible)
        f.driver.user(.tab(.focus(f.other)))
        f.driver.user(.tabTools(.mute(.item(f.playing))))
        XCTAssertEqual(f.row?.speaker, .muted, "Q18-media-g")
        XCTAssertEqual(f.players[0].muted, true)
        XCTAssertTrue(f.driver.user(.page(.mediaSession(.item(f.playing), .pause))).effects.isEmpty, "Q18-media-m: the dimmed button does nothing")
        f.driver.user(.tabTools(.mute(.item(f.playing))))
        XCTAssertEqual(f.row?.speaker, .audible)
    }

    func testTheRowLosesItsSpeakerWhenTheTabFallsSilent() throws {
        let f = try fixture()
        XCTAssertNil(f.row?.speaker)
        f.driver.page(f.playing, .audioChanged(true))
        XCTAssertEqual(f.row?.speaker, .audible)
        f.driver.page(f.playing, .audioChanged(false))
        XCTAssertNil(f.row?.speaker, "Q18-media-i: paused, the row is plain again")
    }

    func testVolumeGoesToEveryPlayerAndIsHeldInsideZeroToOne() throws {
        let f = try fixture()
        let (a, b) = (Self.player("a"), Self.player("b"))
        f.report([a, b])
        f.driver.user(.tab(.focus(f.other)))
        let effects = f.driver.user(.page(.mediaVolume(.item(f.playing), 0.5))).effects
        XCTAssertEqual(effects, [a, b].map { .page(f.page, .media(MediaControl(document: f.document, player: $0.id, operation: .setVolume, volume: 0.5))) })
        XCTAssertEqual(f.players[0].volume, 0.5)
        f.driver.user(.page(.mediaVolume(.item(f.playing), 5)))
        XCTAssertEqual(f.players[0].volume, 1, "held inside 0 to 1")
    }

    func testTwoCardsKeepTheOrderTheyCameIn() throws {
        let f = try fixture()
        f.report([Self.player()])
        f.driver.user(.tab(.focus(f.other)))
        let browser = try XCTUnwrap(f.driver.state.session.live[PageID(window: f.driver.window, item: f.other)]?.browser)
        let second = DocumentToken(browser: browser, sequence: 1)
        f.driver.page(f.other, .documentChanged(.loading(second)))
        f.driver.page(f.other, .documentChanged(.ready(second)))
        f.driver.page(f.other, .mediaChanged(second, [Self.player("z")], error: nil))
        XCTAssertEqual(f.players.map(\.tab), [f.playing], "the tab on screen has none")
        f.driver.user(.commandBar(.open(.newTab))); f.driver.user(.commandBar(.submit("https://example.com/third")))
        XCTAssertEqual(f.players.map(\.tab), [f.playing, f.other], "oldest first, the newest is the front card")
    }

    func testClosingATabRemovesItsCard() throws {
        let f = try fixture()
        f.report([Self.player()])
        f.driver.user(.tab(.focus(f.other)))
        f.driver.user(.tab(.close(.item(f.playing))))
        XCTAssertTrue(f.players.isEmpty)
    }
}
