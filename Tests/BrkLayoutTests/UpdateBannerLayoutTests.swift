import BrkBase
import BrkDomain
import CoreGraphics
import XCTest
@testable import BrkLayout

final class UpdateBannerLayoutTests: XCTestCase {
    private let release = UpdateRelease(version: "0.0.1", build: 44)

    func testUpdateTakesSpaceFromTheScrollableListWithoutMovingRowsOrDock() throws {
        let driver = LayoutDriver()
        for floating in [false, true] {
            for width in [164.0, 228.0, 347.0] {
                var view = driver.view
                view.sidebar.width = width
                view.sidebar.visible = !floating
                view.sidebar.peek = floating
                let before = try XCTUnwrap(driver.frames(view).sidebar)
                view.sidebar.update = .available(release)
                let window = driver.frames(view)
                let after = try XCTUnwrap(window.sidebar)
                let banner = try XCTUnwrap(after.updateBanner)
                XCTAssertEqual(after.dock, before.dock)
                XCTAssertEqual(after.rows, before.rows)
                XCTAssertEqual(after.tablistViewport.origin, before.tablistViewport.origin)
                XCTAssertLessThan(after.tablistViewport.height, before.tablistViewport.height)
                XCTAssertEqual(after.tablistViewport.maxY, banner.minY)
                XCTAssertTrue(after.frame.contains(banner))
                XCTAssertLessThan(banner.maxY, after.dock.minY)
                XCTAssertEqual(window.frame(of: .tabTool("install-update")), banner)
            }
        }
    }

    func testPlayersAndExpandedVolumeStayAboveTheUpdateAndKeepTheListAboveThem() throws {
        let driver = LayoutDriver()
        var view = driver.view
        view.sidebar.visible = false
        view.sidebar.peek = true
        view.sidebar.update = .downloading(release, fraction: 0.4)
        let rest = try XCTUnwrap(driver.frames(view).sidebar)
        let tabs = [ItemID("older"), ItemID("newer")]
        for hover in [nil, MiniPlayerHover(expanded: true), MiniPlayerHover(expanded: true, volumeOpen: tabs[0])] {
            let frames = MiniPlayerLayout.applying(tabs, hover: hover, to: rest)
            let banner = try XCTUnwrap(frames.updateBanner)
            XCTAssertEqual(frames.miniPlayers.count, tabs.count)
            for player in frames.miniPlayers {
                XCTAssertLessThan(player.rect.maxY, banner.minY)
                XCTAssertLessThan(frames.tablistViewport.maxY, player.rect.minY)
            }
            let removed = MiniPlayerLayout.applying([], hover: hover, to: frames)
            XCTAssertEqual(removed.tablistViewport, rest.tablistViewport, "removing the last player keeps the updater reservation")
        }
    }

    /// Arc's open card lives in the banner panel between the list and the dock: it grows upward from the pill and the
    /// list ends at its top, so no row shows beside or behind it, and no row moves.
    func testOpenCardTakesItsHeightFromTheListWithoutMovingRowsOrDock() throws {
        let driver = LayoutDriver()
        let open = Metrics.updateBanner.cardHeight.value
        for floating in [false, true] {
            for width in [164.0, 228.0, 347.0] {
                var view = driver.view
                view.sidebar.width = width
                view.sidebar.visible = !floating
                view.sidebar.peek = floating
                view.sidebar.update = .available(release)
                let rest = try XCTUnwrap(driver.frames(view).sidebar)
                let pill = try XCTUnwrap(rest.updateBanner)
                let opened = UpdateCardLayout.opening(rest, to: open, players: [])
                let card = try XCTUnwrap(opened.updateBanner)
                XCTAssertEqual(card.maxY, pill.maxY, "the card keeps the pill's foot")
                XCTAssertEqual(card.minX, pill.minX)
                XCTAssertEqual(card.width, pill.width)
                XCTAssertEqual(card.height, open)
                XCTAssertEqual(opened.tablistViewport.maxY, card.minY, "the list ends at the card's top")
                XCTAssertEqual(opened.tablistViewport.origin, rest.tablistViewport.origin)
                XCTAssertEqual(opened.rows, rest.rows)
                XCTAssertEqual(opened.dock, rest.dock)
                XCTAssertEqual(UpdateCardLayout.opening(rest, to: pill.height, players: []), rest, "a card no taller than the pill changes nothing")
            }
        }
    }

    func testPlayersRiseWithTheOpenCardAndTheListEndsAboveThem() throws {
        let driver = LayoutDriver()
        var view = driver.view
        view.sidebar.update = .ready(release)
        let tabs = [ItemID("older"), ItemID("newer")]
        let rest = MiniPlayerLayout.applying(tabs, to: try XCTUnwrap(driver.frames(view).sidebar))
        let pill = try XCTUnwrap(rest.updateBanner)
        let rise = Metrics.updateBanner.cardHeight.value - pill.height
        for hover in [nil, MiniPlayerHover(expanded: true)] {
            let before = MiniPlayerLayout.applying(tabs, hover: hover, to: rest)
            let opened = UpdateCardLayout.opening(rest, to: Metrics.updateBanner.cardHeight.value, players: tabs, hover: hover)
            let card = try XCTUnwrap(opened.updateBanner)
            XCTAssertEqual(opened.miniPlayers.map(\.rect), before.miniPlayers.map { $0.rect.offsetBy(dx: 0, dy: -rise) })
            for player in opened.miniPlayers { XCTAssertLessThan(player.rect.maxY, card.minY) }
            XCTAssertLessThan(opened.tablistViewport.maxY, opened.miniPlayers.map(\.rect.minY).min() ?? 0)
            XCTAssertEqual(opened.rows, rest.rows)
        }
        view.sidebar.update = nil
        let none = try XCTUnwrap(driver.frames(view).sidebar)
        XCTAssertEqual(UpdateCardLayout.opening(none, to: 88, players: tabs), none, "no banner, nothing to open")
    }

    /// Arc's other banners (the auto-archive education card) stand in the same panel, padded on every side: above the
    /// update pill (or the dock), with the list and the mini players ending above them instead of scrolling behind.
    func testEducationCardStandsInThePanelAboveThePillAndTheListEndsAboveIt() throws {
        let driver = LayoutDriver()
        let inset = Metrics.updateBanner.bannerInset.value
        for update in [nil, UpdatePresentation.available(release)] {
            var view = driver.view
            view.sidebar.update = update
            let rest = try XCTUnwrap(driver.frames(view).sidebar)
            let opened = BannerPanelLayout.applying(BannerPanel(banner: 120), to: rest, players: [])
            let card = try XCTUnwrap(opened.banner)
            XCTAssertEqual(card.height, 120)
            XCTAssertEqual(card.minX, rest.frame.minX + inset)
            XCTAssertEqual(card.maxX, rest.frame.maxX - inset)
            XCTAssertEqual(card.maxY, (rest.updateBanner?.minY ?? rest.dock.minY) - inset)
            XCTAssertEqual(opened.tablistViewport.maxY, card.minY - inset)
            XCTAssertEqual(opened.tablistViewport.origin, rest.tablistViewport.origin)
            XCTAssertEqual(opened.rows, rest.rows)
            XCTAssertEqual(opened.updateBanner, rest.updateBanner)
            let players = BannerPanelLayout.applying(BannerPanel(banner: 120), to: rest, players: [ItemID("song")])
            let player = try XCTUnwrap(players.miniPlayers.first)
            XCTAssertLessThan(player.rect.maxY, card.minY - inset)
            XCTAssertLessThan(players.tablistViewport.maxY, player.rect.minY)
        }
        var view = driver.view
        view.sidebar.update = .available(release)
        let rest = try XCTUnwrap(driver.frames(view).sidebar)
        let both = BannerPanelLayout.applying(BannerPanel(updateCard: Metrics.updateBanner.cardHeight.value, banner: 120), to: rest, players: [])
        XCTAssertEqual(try XCTUnwrap(both.banner).maxY, try XCTUnwrap(both.updateBanner).minY - inset, "the education card rises with the open update card")
    }

    func testCreateSpaceAndLibraryDoNotLeaveAnUpdateControlOverTheirFlows() throws {
        let driver = LayoutDriver()
        var view = driver.view
        view.sidebar.update = .ready(release)
        view.dialog = .newSpace
        let creating = try XCTUnwrap(driver.frames(view).sidebar)
        XCTAssertNil(creating.updateBanner)
        XCTAssertEqual(creating.tablistViewport.maxY, creating.dock.minY)
        driver.user(.library(.open(nil)))
        view = driver.view
        view.sidebar.update = .ready(release)
        XCTAssertNotNil(driver.frames(view).library)
        XCTAssertNil(driver.frames(view).sidebar)
        view = driver.view
        view.overlay = nil
        view.sidebar.visible = false
        view.sidebar.peek = false
        XCTAssertNil(driver.frames(view).frame(of: .tabTool("install-update")))
    }
}
