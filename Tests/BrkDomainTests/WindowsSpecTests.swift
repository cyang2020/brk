import BrkBase
import CoreGraphics
import Foundation
import XCTest
@testable import BrkDomain

/// Owner: F3. Window kinds (standard, incognito, Little Arc), Peek, "Open in", and links from other apps.
final class WindowsSpecTests: XCTestCase {
    func test_incognitoCloseNeverArchivesAndSelectsAnotherPrivateTab() throws {
        let d = Driver()
        let standard = d.paneIDs
        d.user(.window(.newIncognito))
        let window = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.commandBar(.submit("https://example.com/private-a")), in: window)
        let a = try XCTUnwrap(d.view(of: window).scratch?.rows.first?.id)
        d.user(.commandBar(.submit("https://example.com/private-b")), in: window)
        d.user(.tab(.close(.focused)), in: window)
        XCTAssertEqual(d.view(of: window).content.panes.map(\.tab), [a])
        XCTAssertTrue(d.archive().isEmpty, "closing an incognito tab must not put its URL in the normal archive")
        d.user(.tab(.archive(.item(a))), in: window)
        XCTAssertTrue(d.view(of: window).scratch?.rows.isEmpty == true)
        XCTAssertTrue(d.view(of: window).content.panes.isEmpty)
        XCTAssertTrue(d.archive().isEmpty)
        XCTAssertEqual(d.paneIDs, standard)
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("private-"))
    }

    func test_incognitoTabWalkingUsesOnlyItsScratchContainer() throws {
        let d = Driver()
        let standard = d.paneIDs
        d.user(.window(.newIncognito))
        let window = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.commandBar(.submit("https://example.com/private-a")), in: window)
        let a = try XCTUnwrap(d.view(of: window).scratch?.rows.first?.id)
        d.user(.commandBar(.submit("https://example.com/private-b")), in: window)
        let b = try XCTUnwrap(d.view(of: window).scratch?.rows.first?.id)
        d.user(.tab(.step(.next)), in: window)
        XCTAssertEqual(d.view(of: window).content.panes.map(\.tab), [a])
        d.user(.tab(.step(.previous)), in: window)
        XCTAssertEqual(d.view(of: window).content.panes.map(\.tab), [b])
        d.system(.window(window, .modifiersChanged(held: .control)))
        d.user(.tab(.cycleRecent(.next)), in: window)
        XCTAssertEqual(d.view(of: window).content.panes.map(\.tab), [a])
        d.user(.tab(.cycleRecent(.next)), in: window)
        XCTAssertEqual(d.view(of: window).content.panes.map(\.tab), [b])
        d.system(.window(window, .modifiersChanged(held: [])))
        XCTAssertEqual(d.paneIDs, standard)
    }

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
        XCTAssertNil(v.bounds, "the first window had reported no frame, so the new one has none to cascade from")
        let frame = CGRect(x: 300, y: 300, width: 1280, height: 776)
        d.system(.window(second, .geometry(bounds: frame, contentSize: frame.size)))
        d.user(.window(.new), in: second)
        let third = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window && $0 != second })
        let step = Metrics.littleArc.cascade.value
        XCTAssertEqual(d.view(of: third).bounds, frame.offsetBy(dx: step, dy: -step), "a new window cascades from the window it was asked from")
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

    /// a Little Arc's layout starts from Arc's default size before AppKit reports a frame; the next Little Arc cascades by 30 from the last one's frame; neither is saved
    func test_littleArcStartsAtArcsDefaultSizeAndCascades() throws {
        let d = Driver()
        d.user(.window(.newLittle(url("https://example.com/a"))))
        let first = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little })
        XCTAssertEqual(d.state.session.windows[first.id]?.contentSize, Metrics.littleArc.defaultSize.value)
        XCTAssertNil(first.bounds, "the first Little Arc has no frame yet; the host centers it at the default size")
        let frame = CGRect(x: 100, y: 200, width: Metrics.littleArc.defaultSize.value.width, height: Metrics.littleArc.defaultSize.value.height)
        d.system(.window(first.id, .geometry(bounds: frame, contentSize: Metrics.littleArc.defaultSize.value)))
        d.user(.window(.newLittle(url("https://example.com/b"))))
        let second = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little && $0.id != first.id })
        let step = Metrics.littleArc.cascade.value
        XCTAssertEqual(second.bounds, frame.offsetBy(dx: step, dy: -step), "the second Little Arc cascades down and right")
        XCTAssertEqual(d.snapshot.windows.values.filter { $0.kind == .little }.count, 2)
        XCTAssertEqual(Driver(file: d.savedFile).snapshot.windows.count, 1, "Little Arc windows are never saved")
    }

    /// the sweep closes a Little Arc idle past the Links threshold and archives its tab (reason auto); "never" keeps it; a second tick at the same time changes nothing
    func test_idleLittleArcsAreArchivedAfterTheLinksThreshold() throws {
        let d = Driver()
        d.user(.settings(.links(.littleArcAutoArchive(.oneHour))))
        d.user(.window(.newLittle(url("https://example.com/little"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little })
        d.advance(.seconds(1_800))
        d.system(.clockTick)
        XCTAssertNotNil(d.snapshot.windows[little.id], "half an hour is not idle enough")
        d.advance(.seconds(1_801))
        d.system(.clockTick)
        XCTAssertNil(d.snapshot.windows[little.id], "an hour idle closes the Little Arc")
        XCTAssertEqual(d.archive().map(\.url), [url("https://example.com/little")])
        XCTAssertEqual(d.archive().first?.reason, .auto)
        XCTAssertEqual(d.snapshot.pages.count, 1, "its page is gone; the standard window's tab stays")
        XCTAssertEqual(d.view.space.today.rows.count, 1, "the standard window's Today is untouched")
        assertUnchanged(d.state, d.system(.clockTick))
        d.user(.settings(.links(.littleArcAutoArchive(.never))))
        d.user(.window(.newLittle(url("https://example.com/kept"))))
        d.advance(.seconds(31 * 86_400))
        d.system(.clockTick)
        XCTAssertEqual(d.snapshot.windows.values.filter { $0.kind == .little }.count, 1, "'never' keeps a Little Arc open")
        let restored = try XCTUnwrap(d.archive().first?.id)
        d.user(.archive(.restore(restored)))
        XCTAssertEqual(d.current?.url, url("https://example.com/little"), "an archived Little Arc tab restores into the current space's Today")
    }

    /// Set as Default Browser asks the app to register through NSWorkspace; the bundle step scripts/build.sh runs (scripts/declare-url-types.sh) writes http and https into CFBundleURLTypes, and running it twice leaves the same plist (W2-7 proves the GetURL path on the app)
    func test_theAppRegistersAsDefaultBrowserAndDeclaresHttpSchemes() throws {
        let d = Driver()
        let t = d.user(.app(.setAsDefaultBrowser))
        XCTAssertEqual(t.effects, [.app(.registerAsDefaultBrowser)])
        XCTAssertFalse(t.changed, "registering changes no state")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("scripts/build.sh"), encoding: .utf8).contains("scripts/declare-url-types.sh"),
                      "build.sh does not run the URL-types step")
        let plist = FileManager.default.temporaryDirectory.appendingPathComponent("brk-f3-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: plist) }
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "dev.brk.test"], format: .xml, options: 0).write(to: plist)
        func declare() throws -> [String] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [root.appendingPathComponent("scripts/declare-url-types.sh").path, plist.path]
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let dict = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any])
            let types = try XCTUnwrap(dict["CFBundleURLTypes"] as? [[String: Any]])
            XCTAssertEqual(types.map { $0["CFBundleTypeRole"] as? String }, ["Viewer", "Viewer"])
            return types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        }
        XCTAssertEqual(try declare(), ["http", "https"])
        XCTAssertEqual(try declare(), ["http", "https"], "a second run must leave the same declaration")
    }

    /// the "Open in" menu lists every space in dock order, then "Open in current Space"; each entry moves the held tab where it says
    func test_theOpenInMenuListsEverySpace() throws {
        let d = Driver()
        let work = d.newSpace("Work")
        let menu = OpenInMenu.model(spaces: d.view.dock)
        let actions = menu.entries.compactMap { entry -> (String, Command)? in
            if case .action(let title, let command, let enabled) = entry { XCTAssertTrue(enabled); return (title, command) }
            return nil
        }
        XCTAssertEqual(actions.map(\.0), d.view.dock.map(\.title) + [OpenInMenu.currentSpaceTitle])
        XCTAssertEqual(actions.map(\.1), d.view.dock.map { Command.window(.openIn(.space($0.id))) } + [.window(.openIn(.current))])
        XCTAssertEqual(menu.entries[menu.entries.count - 2], .separator, "a separator before 'Open in current Space'")
        XCTAssertEqual(d.view.dock.map(\.title), ["Space 1", "Work"])
        d.user(.space(.focus(d.snapshot.settings.spaces[0].id)))
        d.user(.window(.newLittle(url("https://example.com/moved"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little })
        d.user(actions[1].1, in: little.id)
        XCTAssertNil(d.snapshot.windows[little.id])
        XCTAssertEqual(d.view.space.id, work, "the Work entry moved the tab to Work")
        XCTAssertEqual(d.current?.url, url("https://example.com/moved"))
        XCTAssertEqual(OpenInMenu.buttonTitle(space: "Work"), "Open in Work")
    }

    /// Cmd+W while peeking closes the peeked tab (archived, restorable) and leaves the tab underneath alone; reload acts on the peeked page
    func test_closeAndBrowsingActOnThePeekedTab() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.peek(.open(url("https://example.com/peeked"))))
        guard case .peek(let peek)? = d.view.overlay else { return XCTFail("no peek") }
        let t = d.user(.page(.reload(.focused, ignoringCache: false)))
        XCTAssertEqual(t.effects, [.page(PageID(peek.tab.id), .reload(ignoringCache: false))], "reload acts on the peeked page")
        d.user(.tab(.close(.focused)))
        XCTAssertNil(d.view.overlay, "Cmd+W closed the Peek")
        XCTAssertEqual(d.todayIDs, [a], "the tab underneath is untouched")
        XCTAssertEqual(d.view.content.panes.map(\.tab), [a])
        XCTAssertEqual(d.archive().map(\.url), [url("https://example.com/peeked")], "the peeked page is in the archive, restorable")
        XCTAssertNil(d.snapshot.pages.first { $0.id == PageID(peek.tab.id) })
        d.user(.window(.newLittle(url("https://example.com/l"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little })
        d.system(.window(little.id, .modifiersChanged(held: .shift)))
        let tab = try XCTUnwrap(little.scratch?.rows.first?.id)
        d.page(tab, .openRequested(url("https://example.com/inside"), .foregroundTab))
        XCTAssertNil(d.view(of: little.id).overlay, "a Little Arc does not peek")
        XCTAssertEqual(d.view(of: little.id).scratch?.rows.count, 2, "the link opened in the Little Arc's own container")
    }

    /// Cmd+W on a Little Arc's only tab archives it and the window goes; Esc on an empty Little Arc's command bar closes the window too
    func test_aLittleArcWithoutItsTabCloses() throws {
        let d = Driver()
        d.user(.window(.newLittle(url("https://example.com/little"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little })
        d.user(.tab(.close(.focused)), in: little.id)
        XCTAssertNil(d.snapshot.windows[little.id], "the emptied Little Arc closed")
        XCTAssertEqual(d.archive().map(\.url), [url("https://example.com/little")])
        XCTAssertEqual(d.archive().first?.reason, .manual)
        XCTAssertEqual(d.snapshot.pages.count, 1)
        d.user(.window(.newLittle(nil)))
        let empty = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little })
        XCTAssertNotNil(empty.overlay, "an empty Little Arc waits with its command bar")
        d.user(.app(.exit), in: empty.id)
        XCTAssertNil(d.snapshot.windows[empty.id], "Esc on the empty bar closes the Little Arc")
        XCTAssertEqual(d.snapshot.windows.count, 1)
    }

    /// routes are normalized and validated: a typed scheme or path is dropped, an empty or wildcard-only pattern and a missing space are refused; matching is by host, "*." for subdomains
    func test_routesAreNormalizedAndMatchByHost() throws {
        let d = Driver()
        let work = d.newSpace("Work")
        d.user(.settings(.links(.addRoute(LinkRoute(id: LinkRouteID("r1"), pattern: " HTTPS://Open.Spotify.com/track/ ", destination: .space(work))))))
        XCTAssertEqual(d.snapshot.settings.routes.map(\.route.pattern), ["open.spotify.com"])
        for bad in ["", "*", "*.", "https://", "two words.com"] {
            assertUnchanged(d.state, d.user(.settings(.links(.addRoute(LinkRoute(id: LinkRouteID("bad-\(bad)"), pattern: bad, destination: .littleArc))))))
        }
        assertUnchanged(d.state, d.user(.settings(.links(.addRoute(LinkRoute(id: LinkRouteID("gone"), pattern: "a.com", destination: .space(SpaceID("missing"))))))))
        d.user(.settings(.links(.updateRoute(LinkRoute(id: LinkRouteID("r1"), pattern: "*.Spotify.com.", destination: .space(work))))))
        let route = try XCTUnwrap(d.snapshot.settings.routes.first?.route)
        XCTAssertEqual(route.pattern, "*.spotify.com")
        XCTAssertTrue(route.matches(url("https://open.spotify.com/x")))
        XCTAssertTrue(route.matches(url("https://SPOTIFY.com")))
        XCTAssertFalse(route.matches(url("https://notspotify.com")))
        XCTAssertFalse(route.matches(url("about:blank")))
        XCTAssertTrue(LinkRoute(id: LinkRouteID("x"), pattern: "spotify.com", destination: .littleArc).matches(url("http://spotify.com/")))
        XCTAssertFalse(LinkRoute(id: LinkRouteID("x"), pattern: "spotify.com", destination: .littleArc).matches(url("http://open.spotify.com/")))
        XCTAssertTrue(sameSite("news.example.com", "www.example.com"))
        XCTAssertTrue(sameSite("a.co.uk", "a.co.uk"))
        XCTAssertFalse(sameSite("a.co.uk", "b.co.uk"))
        XCTAssertTrue(sameSite("shop.a.co.uk", "a.co.uk"))
        XCTAssertFalse(sameSite("127.0.0.1", "127.0.0.2"))
        XCTAssertFalse(sameSite("example.com", "example.org"))
    }
}
