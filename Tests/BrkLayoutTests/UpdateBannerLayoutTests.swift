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
