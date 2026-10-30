import BrkBase
import CoreGraphics
import Foundation
import XCTest
@testable import BrkDomain

/// Owner: F3. Window kinds (standard, incognito, Little Arc), Peek, "Open in", and links from other apps.
final class WindowsSpecTests: XCTestCase {
    /// .window(.new) opens a second standard window on the same space that shares the sidebar
    func test_newWindowSharesTheSidebar() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.window(.new))
        let second = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window })
        let v = d.view(of: second)
        XCTAssertEqual(v.kind, .standard)
        XCTAssertEqual(v.space.id, d.view.space.id)
        XCTAssertEqual(v.space.today.rows.map(\.id), [a], "the same Today rows")
        XCTAssertNotNil(v.overlay, "a new window opens with the command bar")
        XCTAssertNil(v.scratch)
        let b = d.open("http://127.0.0.1:9/b")
        XCTAssertEqual(d.view(of: second).space.today.rows.map(\.id), [b, a], "a tab opened in one window shows in the other's sidebar")
        XCTAssertEqual(Driver(file: d.savedFile).snapshot.windows.count, 2, "standard windows are saved")
    }

    /// .window(.newLittle(url)) opens a Little Arc window: one tab in its own container, no sidebar, not saved
    func test_littleArcHoldsOneScratchTabAndIsNotSaved() throws {
        let d = Driver()
        d.user(.window(.newLittle(url("https://example.com/little"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little })
        XCTAssertFalse(little.sidebar.visible)
        let tab = try XCTUnwrap(little.scratch?.rows.first?.id)
        XCTAssertEqual(little.scratch?.kind, .scratch)
        XCTAssertEqual(little.content.panes.map(\.tab), [tab])
        XCTAssertEqual(d.snapshot.pages.first { $0.id == PageID(tab) }?.context, .profile(.default))
        XCTAssertEqual(d.view.space.today.rows.count, 1, "the standard window's Today is untouched")
        XCTAssertEqual(Driver(file: d.savedFile).snapshot.windows.count, 1, "ephemeral windows are not saved")
        XCTAssertTrue(little.enabledActions.contains(.openTabIn))
        XCTAssertFalse(little.enabledActions.contains(.pinTab))
    }

    /// "Open in" moves a Little Arc's tab to the top of the target space's Today, shows it in a standard window and closes the Little Arc
    func test_openInMovesTheLittleArcTabIntoASpace() throws {
        let d = Driver()
        let work = d.newSpace("Work")
        d.user(.window(.newLittle(url("https://example.com/little"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little })
        d.user(.window(.openIn(.space(work))), in: little.id)
        XCTAssertNil(d.snapshot.windows[little.id])
        XCTAssertEqual(d.view.space.id, work)
        XCTAssertEqual(d.current?.url, url("https://example.com/little"))
        XCTAssertEqual(d.current?.section, .today)
    }

    /// Shift+Cmd+W on a Little Arc archives its tab (Restore Last Closed Tab brings it back); on the last standard window it closes the window
    func test_closeWindow() throws {
        let d = Driver()
        d.user(.window(.newLittle(url("https://example.com/little"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little })
        d.user(.window(.close), in: little.id)
        XCTAssertNil(d.snapshot.windows[little.id])
        XCTAssertEqual(d.archive().map(\.url), [url("https://example.com/little")])
        XCTAssertEqual(d.archive().first?.reason, .manual)
        let t = d.user(.window(.close))
        XCTAssertEqual(t.effects, [.window(d.window, .close)])
        XCTAssertNotNil(d.snapshot.windows[d.window], "the last standard window stays in state; AppKit closes and quits")
    }

    /// .peek(.open) shows a scratch tab's page over the content; Esc closes it and drops the tab; a sidebar focus closes it too
    func test_peekOpensOverTheContentAndClosesOnExit() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.peek(.open(url("https://example.com/peeked"))))
        guard case .peek(let peek)? = d.view.overlay else { return XCTFail("\(String(describing: d.view.overlay))") }
        XCTAssertEqual(peek.tab.url, url("https://example.com/peeked"))
        XCTAssertEqual(peek.tab.section, .scratch)
        XCTAssertEqual(d.view.focus, .page(PageID(peek.tab.id)))
        XCTAssertEqual(d.view.content.panes.map(\.tab), [a], "the content under the peek is unchanged")
        XCTAssertTrue(d.view.enabledActions.contains(.openTabIn))
        d.user(.page(.reload(.focused, ignoringCache: false)))
        guard case .peek? = d.view.overlay else { return XCTFail("a page command closed the peek") }
        d.user(.app(.exit))
        XCTAssertNil(d.view.overlay)
        XCTAssertNil(d.snapshot.pages.first { $0.id == PageID(peek.tab.id) }, "the peeked tab's page is gone")
        d.user(.peek(.open(url("https://example.com/again"))))
        d.user(.tab(.focus(a)))
        XCTAssertNil(d.view.overlay, "choosing a sidebar tab closes the peek")
        d.user(.peek(.open(url("https://example.com/third"))))
        d.user(.peek(.close))
        XCTAssertNil(d.view.overlay)
    }

    /// Shift+click (Shift held when the page asks to open a link) opens a Peek when the Links setting allows it; Opt+Cmd opens a Little Arc
    func test_modifierClicksFollowTheLinksSettings() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.system(.window(d.window, .modifiersChanged(held: .shift)))
        d.page(a, .openRequested(url("https://example.com/shift"), .foregroundTab))
        guard case .peek? = d.view.overlay else { return XCTFail("Shift+click did not peek") }
        d.user(.peek(.close))
        d.system(.window(d.window, .modifiersChanged(held: [.option, .command])))
        d.page(a, .openRequested(url("https://example.com/little"), .backgroundTab))
        XCTAssertEqual(d.snapshot.windows.values.filter { $0.kind == .little }.count, 1)
        d.system(.window(d.window, .modifiersChanged(held: [])))
        d.user(.settings(.links(.shiftClickPeek(false))))
        d.system(.window(d.window, .modifiersChanged(held: .shift)))
        d.page(a, .openRequested(url("https://example.com/plain"), .foregroundTab))
        XCTAssertNil(d.view.overlay)
        XCTAssertEqual(d.current?.url, url("https://example.com/plain"), "with the setting off, Shift+click is a plain tab")
    }

    /// a link from another app follows the first matching route, else the Links settings, else the most recent space
    func test_externalURLsAreRouted() throws {
        let d = Driver()
        let work = d.newSpace("Work")
        d.user(.space(.focus(d.snapshot.settings.spaces[0].id)))
        d.user(.settings(.links(.addRoute(LinkRoute(id: LinkRouteID("r1"), pattern: "*.spotify.com", destination: .space(work))))))
        d.system(.externalURL(url("https://open.spotify.com/track/1")))
        XCTAssertEqual(d.view.space.id, work, "the route sent the link to Work")
        XCTAssertEqual(d.current?.url, url("https://open.spotify.com/track/1"))
        d.system(.externalURL(url("https://example.com/elsewhere")))
        XCTAssertEqual(d.snapshot.windows.values.filter { $0.kind == .little }.count, 1, "'Links from other apps open in Little Arc' is on by default")
        d.user(.settings(.links(.externalLinksInLittleArc(false))))
        d.system(.externalURL(url("https://example.com/tab")))
        XCTAssertEqual(d.current?.url, url("https://example.com/tab"), "with the setting off the link opens as a tab in the current space")
        assertUnchanged(d.state, d.system(.externalURL(url("javascript:alert(1)"))))
    }

    // MARK: F3 stubs

    func test_littleArcIsAnNSPanelAtArcsDefaultSizeWithTheHintStrip() throws {
        throw XCTSkip("F3: LittleWindowController hosts a .little window in an NSPanel at Metrics.littleArc.defaultSize, cascading by 30, with Arc's 'Open in' hint")
    }

    func test_idleLittleArcsAreArchivedAfterTheLinksThreshold() throws {
        let d = Driver()
        d.user(.settings(.links(.littleArcAutoArchive(.oneHour))))
        throw XCTSkip("F3: sweepAutoArchive closes Little Arc windows idle past LinkSettings.littleArcAutoArchive (Arc: AutoArchiveType.littleArc)")
    }

    func test_theAppRegistersAsDefaultBrowserAndDeclaresHttpSchemes() throws {
        throw XCTSkip("F3: CFBundleURLTypes for http and https in the built bundle; DefaultBrowser.register through NSWorkspace; W2-7 proves the GetURL path")
    }

    func test_theOpenInMenuListsEverySpace() throws {
        throw XCTSkip("F3: Cmd+O shows Arc's 'Open in' menu (every space, then 'Open in current Space'), each entry dispatching .window(.openIn(.space(id)))")
    }
}
