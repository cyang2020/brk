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
        XCTAssertEqual(d.view(of: window).tabTools.recent?.items.map(\.id), [b, a], "only the private window's tabs")
        XCTAssertEqual(d.view(of: window).tabTools.recent?.selected, a)
        d.user(.tab(.cycleRecent(.next)), in: window)
        XCTAssertEqual(d.view(of: window).tabTools.recent?.selected, b)
        d.user(.tab(.cycleRecent(.next)), in: window)
        d.system(.window(window, .modifiersChanged(held: [])))
        XCTAssertEqual(d.view(of: window).content.panes.map(\.tab), [a], "the release shows the selection")
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
        d.commitRequested(in: little.id)
        XCTAssertFalse(little.sidebar.visible)
        let tab = try XCTUnwrap(little.scratch?.rows.first?.id)
        XCTAssertEqual(little.scratch?.kind, .scratch)
        XCTAssertEqual(little.content.panes.map(\.tab), [tab])
        XCTAssertEqual(d.snapshot.pages.first { $0.id == PageID(window: little.id, item: tab) }?.context, .profile(.default))
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
        d.commitRequested(in: little.id)
        d.user(.window(.openIn(.space(work))), in: little.id)
        XCTAssertNil(d.snapshot.windows[little.id])
        XCTAssertEqual(d.view.space.id, work)
        XCTAssertEqual(d.current?.url, url("https://example.com/little"))
        XCTAssertEqual(d.current?.section, .today)
    }

    /// "Open in" from a Little Arc holding a second tab (a link it opened in the background) archives that tab, as
    /// closing the Little Arc does, instead of dropping it with no trace
    func test_openInArchivesTheLittleArcsOtherTabs() throws {
        let d = Driver()
        d.user(.window(.newLittle(url("https://example.com/little"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little }?.id)
        d.commitRequested(in: little)
        let shown = try XCTUnwrap(d.view(of: little).content.panes.first?.tab)
        d.page(shown, .openRequested(url("https://example.com/second"), .backgroundTab), in: little)
        d.commitRequested(in: little)
        d.user(.window(.openIn(.current)), in: little)
        XCTAssertNil(d.snapshot.windows[little])
        XCTAssertEqual(d.current?.url, url("https://example.com/little"))
        XCTAssertEqual(d.archive().map(\.url), [url("https://example.com/second")])
    }

    /// Cmd+N from a Little Arc opens a normal standard window: the sidebar shown and a standard window's default size,
    /// not the Little Arc's hidden sidebar and small frame
    func test_newWindowFromALittleArcIsANormalWindow() throws {
        let d = Driver()
        d.user(.window(.newLittle(url("https://example.com/little"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little }?.id)
        let panel = CGRect(x: 400, y: 400, width: 490, height: 329)
        d.system(.window(little, .geometry(bounds: panel, contentSize: panel.size)))
        let before = Set(d.snapshot.windows.keys)
        d.user(.window(.new), in: little)
        let added = try XCTUnwrap(Set(d.snapshot.windows.keys).subtracting(before).first)
        XCTAssertEqual(d.view(of: added).kind, .standard)
        XCTAssertTrue(d.view(of: added).sidebar.visible)
        XCTAssertNil(d.view(of: added).bounds, "no frame to cascade from: the host opens it at the standard default size")
    }

    /// Closing the last standard window while an incognito window stays open (AppKit does not quit then) closes it
    /// like any other window: its pages unload, so nothing it played keeps playing out of sight
    func test_closingTheLastStandardWindowWithAPrivateWindowOpenUnloadsIt() throws {
        let d = Driver()
        d.user(.window(.newIncognito))
        XCTAssertTrue(d.snapshot.pages.contains { $0.id.window == d.window })
        d.system(.window(d.window, .closed))
        XCTAssertFalse(d.snapshot.windows.keys.contains(d.window))
        XCTAssertFalse(d.snapshot.pages.contains { $0.id.window == d.window })
    }

    /// With the last standard window closed and an incognito window still open, a link from another app opens in a new
    /// standard window, not in the closed one nobody can see
    func test_aLinkAfterTheLastStandardWindowClosedOpensInANewWindow() throws {
        let d = Driver()
        d.user(.settings(.links(.externalLinksInLittleArc(false))))
        d.user(.window(.newIncognito))
        d.system(.window(d.window, .closed))
        let link = url("https://example.com/from-another-app")
        d.system(.externalURL(link))
        let opened = d.snapshot.windows.values.filter { $0.kind == .standard && $0.id != d.window }
        XCTAssertEqual(opened.count, 1)
        let window = try XCTUnwrap(opened.first?.id)
        let pane = try XCTUnwrap(d.view(of: window).content.panes.first?.tab)
        XCTAssertEqual(d.state.address(of: pane, in: window, for: .visible), link)
    }

    /// .peek(.open) shows a scratch tab's page over the content; Esc closes it and drops the tab; a sidebar focus closes it too
    func test_peekOpensOverTheContentAndClosesOnExit() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.peek(.open(url("https://example.com/peeked"))))
        guard case .peek(let peek)? = d.view.overlay else { return XCTFail("\(String(describing: d.view.overlay))") }
        XCTAssertEqual(peek.tab.url, url("https://example.com/peeked"))
        XCTAssertEqual(peek.tab.section, .scratch)
        XCTAssertEqual(d.view.focus, .page(PageID(window: d.window, item: peek.tab.id)))
        XCTAssertEqual(d.view.content.panes.map(\.tab), [a], "the content under the peek is unchanged")
        XCTAssertTrue(d.view.enabledActions.contains(.openTabIn))
        d.user(.page(.reload(.focused, ignoringCache: false)))
        guard case .peek? = d.view.overlay else { return XCTFail("a page command closed the peek") }
        d.user(.app(.exit))
        XCTAssertNil(d.view.overlay)
        XCTAssertNil(d.snapshot.pages.first { $0.id == PageID(window: d.window, item: peek.tab.id) }, "the peeked tab's page is gone")
        d.user(.peek(.open(url("https://example.com/again"))))
        d.user(.tab(.focus(a)))
        XCTAssertNil(d.view.overlay, "choosing a sidebar tab closes the peek")
        d.user(.peek(.open(url("https://example.com/third"))))
        d.user(.peek(.close))
        XCTAssertNil(d.view.overlay)
    }

    /// Cmd+T over a Peek replaces the card and drops the peeked tab and its page, as Esc does; they used to stay loaded
    /// and hidden, with no row to close them
    func test_commandBarOverAPeekDropsThePeekedTab() throws {
        let d = Driver()
        d.user(.peek(.open(url("https://example.com/peeked"))))
        guard case .peek(let peek)? = d.view.overlay else { return XCTFail("\(String(describing: d.view.overlay))") }
        d.user(.commandBar(.open(.newTab)))
        XCTAssertNotNil(d.bar)
        d.user(.commandBar(.dismiss))
        XCTAssertFalse(d.loadedIDs.contains(peek.tab.id))
        XCTAssertEqual(d.state.session.scratch[d.window]?.allTabs(), [])
    }

    /// The Peek's ⤢ button (Arc 1.170, the 2026-11-03 capture P22c): the peeked tab moves to the end of Today with its
    /// id, so its page (same window, same item) stays live and keeps its scroll position; it is focused and the card closes
    func test_peekOpenAsTabAppendsTheSamePageToTodayAndFocusesIt() throws {
        let d = Driver()
        let before = d.todayIDs
        d.user(.peek(.open(url("https://example.com/peeked"))))
        guard case .peek(let peek)? = d.view.overlay else { return XCTFail("no peek") }
        let page = PageID(window: d.window, item: peek.tab.id)
        XCTAssertTrue(d.view.space.today.rows.contains { if case .tab(let t) = $0 { t.peeking } else { false } }, "the shown row carries the Peek marker")
        d.user(.peek(.openAsTab))
        XCTAssertNil(d.view.overlay)
        XCTAssertEqual(d.todayIDs, before + [peek.tab.id], "the peeked tab is the last tab of Today, with its id")
        XCTAssertEqual(d.view.content.panes.map(\.tab), [peek.tab.id])
        XCTAssertNotNil(d.snapshot.pages.first { $0.id == page }, "the peeked page is still live (Arc keeps its scroll)")
        XCTAssertFalse(d.view.space.today.rows.contains { if case .tab(let t) = $0 { t.peeking } else { false } })
    }

    /// The Peek's split button: the peeked page joins the shown Today tab in a split, on its right, keeping its page
    func test_peekOpenInSplitGroupsTheShownTabWithThePeekedPage() throws {
        let d = Driver()
        let shown = try XCTUnwrap(d.view.content.panes.first?.tab)
        d.user(.peek(.open(url("https://example.com/peeked"))))
        guard case .peek(let peek)? = d.view.overlay else { return XCTFail("no peek") }
        d.user(.peek(.openInSplit))
        XCTAssertNil(d.view.overlay)
        XCTAssertEqual(d.view.content.panes.map(\.tab), [shown, peek.tab.id])
        XCTAssertEqual(d.view.content.panes.first { $0.focused }?.tab, peek.tab.id)
        XCTAssertNotNil(d.snapshot.pages.first { $0.id == PageID(window: d.window, item: peek.tab.id) })
    }

    /// A blank window (Ctrl+Cmd+N) lists its own tabs: its scratch section is what the sidebar shows
    func test_blankWindowListsItsOwnTabs() throws {
        let d = Driver()
        d.user(.window(.newBlank))
        let window = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .blank }?.id)
        d.user(.commandBar(.submit("https://example.com/home")), in: window)
        d.user(.commandBar(.open(.newTab)), in: window)
        d.user(.commandBar(.submit("https://example.com/docs")), in: window)
        let rows = try XCTUnwrap(d.view(of: window).scratch?.rows)
        XCTAssertEqual(rows.compactMap { row -> URL? in if case .tab(let t) = row { t.url } else { nil } }, [url("https://example.com/docs"), url("https://example.com/home")],
                       "newest first, as Arc lists them under This Window")
        XCTAssertEqual(rows.compactMap { row -> RowStatus? in if case .tab(let t) = row { t.status } else { nil } }, [.current, .idle])
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

    /// The link menu's Open Link in Incognito Window (Arc's link menu, Q07-b) opened the link as a Today tab of the
    /// opener's profile, with its cookies and a history entry. It opens in a new incognito window.
    func test_openLinkInIncognitoWindowOpensAPrivateWindow() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let today = d.todayIDs
        d.page(a, .openRequested(url("https://example.com/private"), .incognitoWindow))
        let window = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito })
        guard case .tab(let row)? = window.scratch?.rows.first else { return XCTFail("the private window has no tab") }
        XCTAssertEqual(row.url, url("https://example.com/private"))
        XCTAssertEqual(window.content.panes.map(\.tab), [row.id])
        XCTAssertEqual(d.todayIDs, today, "nothing opened in the standard window's profile")
        XCTAssertEqual(d.view.content.panes.map(\.tab), [a])
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

    /// Air Traffic Control's two-line rows (Q06-a): a "Contains" route matches any link whose URL contains its text, an
    /// empty New Route row matches nothing, "Matches" keeps the host glob; the Default pop-up decides the rest
    func test_containsRoutesAndTheDefaultDestination() throws {
        let d = Driver()
        let work = d.newSpace("Work")
        d.user(.space(.focus(d.snapshot.settings.spaces[0].id)))
        let id = LinkRouteID("meet")
        d.user(.settings(.links(.addRoute(LinkRoute(id: id, pattern: "", destination: .space(work), match: .contains)))))
        XCTAssertEqual(d.snapshot.settings.routes.map(\.route.pattern), [""], "New Route adds an empty row")
        d.system(.externalURL(url("https://meet.google.com/abc")))
        XCTAssertEqual(d.snapshot.windows.values.filter { $0.kind == .little }.count, 1, "the empty row matches nothing; the default is Little Arc")
        d.user(.settings(.links(.updateRoute(LinkRoute(id: id, pattern: " Meet.Google.com ", destination: .space(work), match: .contains)))))
        let route = try XCTUnwrap(d.snapshot.settings.routes.first?.route)
        XCTAssertEqual(route.pattern, "meet.google.com")
        XCTAssertTrue(route.matches(url("https://meet.google.com/abc-defg")))
        XCTAssertTrue(route.matches(url("https://accounts.google.com/?continue=https://meet.google.com/x")), "Contains looks at the whole URL")
        XCTAssertFalse(route.matches(url("https://google.com/meet")))
        assertUnchanged(d.state, d.user(.settings(.links(.updateRoute(LinkRoute(id: id, pattern: "two words", destination: .space(work), match: .contains))))))
        d.system(.externalURL(url("https://meet.google.com/abc")))
        XCTAssertEqual(d.view.space.id, work, "the Contains route sent the link to Work")
        d.user(.settings(.links(.updateRoute(LinkRoute(id: id, pattern: "meet.google.com", destination: .space(work), match: .matches)))))
        XCTAssertFalse(try XCTUnwrap(d.snapshot.settings.routes.first?.route).matches(url("https://x.com/?u=meet.google.com")), "Matches compares the host")
        d.user(.settings(.links(.removeRoute(id))))
        d.user(.settings(.links(.defaultRoute(.mostRecentSpace))))
        let littles = d.snapshot.windows.values.filter { $0.kind == .little }.count
        d.system(.externalURL(url("https://example.com/most-recent")))
        XCTAssertEqual(d.snapshot.windows.values.filter { $0.kind == .little }.count, littles, "Default: Most Recent Space opens no Little Arc")
        XCTAssertEqual(d.current?.url, url("https://example.com/most-recent"))
    }

    /// the sweep closes a Little Arc idle past the Links threshold and archives its tab (reason auto); "never" keeps it; a second tick at the same time changes nothing
    func test_idleLittleArcsAreArchivedAfterTheLinksThreshold() throws {
        let d = Driver()
        d.user(.settings(.links(.littleArcAutoArchive(.oneHour))))
        d.user(.window(.newLittle(url("https://example.com/little"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little })
        d.commitRequested(in: little.id)
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

    /// Cmd+W while peeking closes the peeked tab (archived, restorable) and leaves the tab underneath alone; reload acts on the peeked page
    func test_closeAndBrowsingActOnThePeekedTab() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.peek(.open(url("https://example.com/peeked"))))
        guard case .peek(let peek)? = d.view.overlay else { return XCTFail("no peek") }
        d.commitRequested()
        let t = d.user(.page(.reload(.focused, ignoringCache: false)))
        XCTAssertEqual(t.effects, [.page(PageID(window: d.window, item: peek.tab.id), .reload(ignoringCache: false))], "reload acts on the peeked page")
        d.user(.tab(.close(.focused)))
        XCTAssertNil(d.view.overlay, "Cmd+W closed the Peek")
        XCTAssertEqual(d.todayIDs, [a], "the tab underneath is untouched")
        XCTAssertEqual(d.view.content.panes.map(\.tab), [a])
        XCTAssertEqual(d.archive().map(\.url), [url("https://example.com/peeked")], "the peeked page is in the archive, restorable")
        XCTAssertNil(d.snapshot.pages.first { $0.id == PageID(window: d.window, item: peek.tab.id) })
        d.user(.window(.newLittle(url("https://example.com/l"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little })
        d.commitRequested(in: little.id)
        d.system(.window(little.id, .modifiersChanged(held: .shift)))
        let tab = try XCTUnwrap(little.scratch?.rows.first?.id)
        d.page(tab, .openRequested(url("https://example.com/inside"), .foregroundTab), in: little.id)
        XCTAssertNil(d.view(of: little.id).overlay, "a Little Arc does not peek")
        XCTAssertEqual(d.view(of: little.id).scratch?.rows.count, 2, "the link opened in the Little Arc's own container")
    }

    /// Cmd+W on a Little Arc's only tab archives it and the window goes; Esc on an empty Little Arc's command bar closes the window too
    func test_aLittleArcWithoutItsTabCloses() throws {
        let d = Driver()
        d.user(.window(.newLittle(url("https://example.com/little"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little })
        d.commitRequested(in: little.id)
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
