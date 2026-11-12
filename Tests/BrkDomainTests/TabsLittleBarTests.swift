import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Round 3, R3-6: tab hover cards, Favorite overlays, tab groups, Little Arc entry and idleness, Live Folder states,
/// command bar actions.
final class TabsLittleBarTests: XCTestCase {
    private func request(_ transition: Transition) throws -> SiteRequest {
        try XCTUnwrap(transition.effects.compactMap { if case .siteRequest(let r) = $0 { r } else { nil } }.first)
    }
    private func favorite(_ d: Driver, _ id: ItemID) throws {
        let root = try XCTUnwrap(d.state.doc.favorites[.default])
        d.user(.item(.move(id, to: .into(parent: root, index: 0))))
    }
    private func tile(_ d: Driver, _ id: ItemID) -> TabRow? { d.view.favorites.tiles.first { $0.id == id } }
    private func menu(_ d: Driver, _ id: ItemID) throws -> MenuModel { try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.item(id), at: .zero))))) }

    // MARK: Favorite overlays (A014)

    func testCalendarSubtitleCountsDownToTheNextMeetingWithinADay() throws {
        let d = Driver(startURL: url("https://calendar.google.com/"))
        let item = d.todayIDs[0]
        try favorite(d, item)
        let r = try request(d.user(.tabTools(.site(.connectCalendar))))
        let soon = CalendarMeeting(title: "Standup", url: url("https://meet.example.com/a"), start: T0.advanced(by: .seconds(12 * 60)), end: T0.advanced(by: .seconds(40 * 60)))
        d.system(.siteResult(r.id, .calendar([soon])))
        XCTAssertEqual(tile(d, item)?.subtitle, "in 12m")
        XCTAssertNil(tile(d, item)?.badgeTint)
        d.advance(.seconds(12 * 60))
        XCTAssertEqual(tile(d, item)?.subtitle, nil, "the selected export expired after five minutes")
        let late = try request(d.user(.tabTools(.site(.connectCalendar))))
        let tomorrow = CalendarMeeting(title: "Later", url: url("https://meet.example.com/b"), start: d.now.advanced(by: .seconds(3 * 3600)), end: d.now.advanced(by: .seconds(4 * 3600)))
        d.system(.siteResult(late.id, .calendar([tomorrow])))
        XCTAssertEqual(tile(d, item)?.subtitle, "in 3h")
        XCTAssertTrue(titles(try menu(d, item)).contains("Show Time to Next Meeting"))
        d.user(.tabTools(.siteDisplay(host: "calendar.google.com", .nextMeeting, on: false)))
        XCTAssertNil(tile(d, item)?.subtitle, "Show Time to Next Meeting off")
        let far = try request(d.user(.tabTools(.site(.connectCalendar))))
        d.user(.tabTools(.siteDisplay(host: "calendar.google.com", .nextMeeting, on: true)))
        d.system(.siteResult(far.id, .calendar([CalendarMeeting(title: "Next week", url: url("https://meet.example.com/c"), start: d.now.advanced(by: .seconds(3 * 86_400)), end: d.now.advanced(by: .seconds(3 * 86_400 + 600)))])))
        XCTAssertNil(tile(d, item)?.subtitle, "nothing within a day: no subtitle")
    }

    // MARK: Hover cards (A031)

    func testCalendarFavoriteCardListsTheComingMeetingsOnlyWithPreviewsOn() throws {
        let d = Driver(startURL: url("https://calendar.google.com/"))
        let item = d.todayIDs[0]
        try favorite(d, item)
        let r = try request(d.user(.tabTools(.site(.connectCalendar))))
        let running = CalendarMeeting(title: "Planning", url: url("https://meet.example.com/a"), start: T0.advanced(by: .seconds(-60)), end: T0.advanced(by: .seconds(1800)))
        let done = CalendarMeeting(title: "Done", url: url("https://meet.example.com/x"), start: T0.advanced(by: .seconds(-7200)), end: T0.advanced(by: .seconds(-3600)))
        let plain = CalendarMeeting(title: "Lunch", url: url("http://example.com/lunch"), start: T0.advanced(by: .seconds(7200)), end: T0.advanced(by: .seconds(9000)))
        d.system(.siteResult(r.id, .calendar([plain, done, running])))
        XCTAssertNil(tile(d, item)?.hoverCard, "Arc Previews are off by default")
        d.user(.tabTools(.preferences(includeFavorites: true, previews: true)))
        guard case .calendar(let site, let meetings)? = tile(d, item)?.hoverCard else { return XCTFail("no calendar card") }
        XCTAssertEqual(site, "Google Calendar")
        XCTAssertEqual(meetings.map(\.title), ["Planning", "Lunch"], "ended meetings drop, soonest first")
        XCTAssertEqual(meetings.map(\.joinURL), [url("https://meet.example.com/a"), nil], "Join only for an https link")
        XCTAssertTrue(titles(try menu(d, item)).contains("Show Hover Preview"))
        d.user(.tabTools(.siteDisplay(host: "calendar.google.com", .hoverPreview, on: false)))
        XCTAssertNil(tile(d, item)?.hoverCard, "Show Hover Preview off")
    }

    // MARK: Tab groups (A035)

    private func group(_ d: Driver) throws -> (group: ItemID, tabs: [ItemID]) {
        let a = d.todayIDs[0]
        let b = d.open("https://example.com/b")
        d.user(.tabTools(.bulk(.items([a, b]), .newFolder(group: true))))
        d.user(.item(.rename(try XCTUnwrap(d.view.space.pinned.rows.first?.id), title: "Research")))
        guard case .folder(let f)? = d.view.space.pinned.rows.first, f.group else { throw XCTSkip("no group") }
        return (f.id, f.children.map(\.id))
    }

    func testClosingAGroupArchivesItAsOneUnitAndUndoBringsItBack() throws {
        let d = Driver()
        let (g, tabs) = try group(d)
        d.user(.tabTools(.closeGroup(g)))
        XCTAssertNil(d.state.doc.tree[g], "the header goes with its tabs")
        XCTAssertTrue(tabs.allSatisfy { d.state.doc.tree[$0] == nil })
        XCTAssertEqual(d.view.tabTools.toast?.keycap, "⌘Z")
        XCTAssertEqual(d.archive().count, 1, "one structural entry")
        d.user(.tabTools(.undoToast))
        guard case .folder(let back)? = d.view.space.pinned.rows.first else { return XCTFail("group not restored") }
        XCTAssertTrue(back.group)
        XCTAssertEqual(back.title, "Research")
        XCTAssertEqual(back.children.count, 2)
    }

    func testRemovingTheHeaderKeepsTheTabsInPlaceAndIsUndoable() throws {
        let d = Driver()
        let (g, tabs) = try group(d)
        let menu = try menu(d, g)
        XCTAssertEqual(layout(menu), ["Rename Group…", "Remove Group Header", "|", "Copy All Links", "|", "Close Tab Group"])
        d.user(.tabTools(.removeGroupHeader(g)))
        XCTAssertNil(d.state.doc.tree[g])
        XCTAssertEqual(Array(d.pinnedIDs.prefix(2)), tabs, "the tabs take the header's place, in order")
        d.user(.tabTools(.undoToast))
        guard case .folder(let back)? = d.view.space.pinned.rows.first else { return XCTFail("header not restored") }
        XCTAssertEqual(back.id, g)
        XCTAssertEqual(back.title, "Research")
        XCTAssertEqual(back.children.map(\.id), tabs)
    }

    func testAGroupDroppedOnAGroupMergesAndAnEmptiedGroupGoes() throws {
        let d = Driver()
        let (first, firstTabs) = try group(d)
        let c = d.open("https://example.com/c")
        d.user(.tabTools(.bulk(.items([c]), .newFolder(group: true))))
        let second = try XCTUnwrap(d.view.space.pinned.rows.first?.id)
        XCTAssertNotEqual(second, first)
        d.user(.item(.move(second, to: .into(parent: first, index: 2))))
        XCTAssertNil(d.state.doc.tree[second], "the dropped group's header goes")
        XCTAssertEqual(d.state.doc.tree[first]?.children, firstTabs + [c])
        // Dragging the tabs out one by one: the group goes with the last.
        let root = try XCTUnwrap(d.state.doc.spaces[d.view.space.id]?.todayRoot)
        for tab in firstTabs + [c] { d.user(.item(.move(tab, to: .into(parent: root, index: 0)))) }
        XCTAssertNil(d.state.doc.tree[first], "Arc has no empty group")
        // A tab dropped on a group joins it.
        let (other, _) = try group(d)
        let e = d.open("https://example.com/e")
        d.user(.item(.move(e, to: .into(parent: other, index: 0))))
        XCTAssertEqual(d.state.doc.tree[other]?.children.first, e)
    }

    // MARK: Live Folders (A092)

    func testLiveFolderStatesLoadingFailedEmptyStaleAndOpenRefreshes() throws {
        let d = Driver()
        let r = try request(d.user(.tabTools(.site(.connectGitHub(favorite: nil)))))
        let link = PullRequestLink(title: "Fix", url: url("https://github.com/fixture/repo/pull/1"))
        d.system(.siteResult(r.id, .pullRequests(repository: "fixture/repo", [link])))
        func live() -> LiveFolderSnapshot? { if case .folder(let f)? = d.view.space.pinned.rows.first { f.live } else { nil } }
        let folder = try XCTUnwrap(d.view.space.pinned.rows.first?.id)
        XCTAssertEqual(live()?.state, .ready(1))
        XCTAssertEqual(live()?.source, "fixture/repo")
        if case .folder(let f)? = d.view.space.pinned.rows.first { XCTAssertEqual(f.title, "fixture/repo", "the title carries no status") }
        d.user(.tabTools(.dismissToast))   // "Live Folder Created"
        let refresh = try request(d.user(.tabTools(.site(.refreshFolder(folder)))))
        XCTAssertEqual(live()?.state, .loading)
        XCTAssertNil(d.view.tabTools.toast, "a Live Folder shows its own spinner, no toast")
        d.system(.siteResult(refresh.id, .failed("GitHub refresh failed.")))
        XCTAssertEqual(live()?.state, .failed("GitHub refresh failed."))
        XCTAssertEqual(d.state.doc.tree[folder]?.children.count, 1, "a failure keeps the rows")
        let empty = try request(d.user(.tabTools(.site(.refreshFolder(folder)))))
        d.system(.siteResult(empty.id, .pullRequests(repository: "fixture/repo", [])))
        XCTAssertEqual(live()?.state, .empty)
        d.advance(.seconds(301))
        XCTAssertEqual(live()?.state, .stale)
        d.user(.item(.toggleFolder(folder)))   // closes
        let reopen = d.user(.item(.toggleFolder(folder)))
        XCTAssertNotNil(try? request(reopen), "opening an old Live Folder refreshes it")
        XCTAssertEqual(live()?.state, .loading)
        let restarted = Driver(file: d.savedFile)
        guard case .folder(let saved)? = restarted.view.space.pinned.rows.first else { return XCTFail() }
        XCTAssertEqual(saved.live?.state, .notLoaded, "nothing refreshed since launch")
    }

    // MARK: Type travel (A068)

    private func travel(_ d: Driver, _ title: String) -> Command? {
        d.user(.commandBar(.open(.newTab)))
        defer { d.user(.commandBar(.dismiss)) }
        return d.bar?.travel.first { $0.title == title }?.command
    }

    func testTypeTravelMuteAllReplacePinnedUndoExtensionsAndPasswords() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("https://example.com/b")
        d.user(.tab(.focus(a)))
        d.page(a, .audioChanged(true))
        d.page(b, .audioChanged(true))
        XCTAssertNil(travel(d, "Unmute All Tabs"))
        d.user(try XCTUnwrap(travel(d, "Mute All Tabs")))
        XCTAssertEqual(d.row(a)?.muted, true)
        XCTAssertEqual(d.row(b)?.muted, true)
        d.user(try XCTUnwrap(travel(d, "Unmute All Tabs")))
        XCTAssertEqual(d.row(a)?.muted, false)

        d.user(.tab(.togglePin(.item(b))))
        d.user(.tab(.focus(b)))
        XCTAssertNil(travel(d, TypeTravelCopy.replacePinned), "not drifted")
        d.page(b, .committed(url("https://example.com/b/moved")))
        d.user(try XCTUnwrap(travel(d, TypeTravelCopy.replacePinned)))
        XCTAssertEqual(d.state.tab(b)?.pinnedURL, url("https://example.com/b/moved"))

        d.user(.tab(.clearToday))
        XCTAssertNotNil(travel(d, "Undo Cleared Tabs"), "the toast names what Undo brings back: \(d.view.tabTools.toast?.text ?? "")")

        let ext = BrowserExtension(id: "abc", name: "Fixture Action", version: "1", enabled: true, supportsNativeAction: true)
        let quiet = BrowserExtension(id: "def", name: "No Action", version: "1", enabled: true)
        d.system(.extensionsRead(ExtensionCatalog(context: .profile(.default), extensions: [ext, quiet], error: nil)))
        d.user(.tab(.focus(b)))
        XCTAssertEqual(travel(d, "Fixture Action"), .site(.invokeExtension("abc")))
        XCTAssertNil(travel(d, "No Action"), "only extensions with an action are listed")
        XCTAssertEqual(travel(d, "Open Password Manager"), .settings(.openBrowserPage(.passwords, profile: nil)))
    }

    func testTheTypeTravelCommandsActDirectly() throws {
        let d = Driver()
        let tab = d.todayIDs[0]
        d.user(.tabTools(.bulk(.items([tab]), .newFolder(group: false))))
        let folder = try XCTUnwrap(d.pinnedIDs.first)
        d.user(.item(.toggleFolder(folder)))
        d.user(.tabTools(.openFolder(folder)))
        XCTAssertTrue(d.state.folderIsExpanded(folder, in: d.window), ".openFolder opens it")
        d.page(tab, .committed(url("https://example.com/drifted")))
        d.user(.tabTools(.replacePinned(tab)))
        XCTAssertEqual(d.state.tab(tab)?.pinnedURL, url("https://example.com/drifted"))
        d.page(tab, .audioChanged(true))
        d.user(.tabTools(.muteAll(true)))
        XCTAssertEqual(d.row(tab)?.muted, true)
        d.user(.split(.addPaneAt(.bottom)))
        XCTAssertEqual(d.view.content.orientation, .vertical)
        XCTAssertEqual(d.paneIDs.first, tab, "bottom: the new pane follows")
    }

    // MARK: Little Arc (A085, A086)

    private func little(_ d: Driver, _ address: String) throws -> (WindowID, ItemID) {
        d.user(.settings(.links(.littleArcAutoArchive(.oneHour))))
        let before = Set(d.snapshot.windows.keys)
        d.user(.window(.newLittle(url(address))))
        let id = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little && !before.contains($0.id) }?.id)
        d.commitRequested(in: id)
        return (id, try XCTUnwrap(d.state.session.scratch[id]?.allTabs().first))
    }

    func testLittleArcIdlenessIsRealInputNotKeyStatus() throws {
        let d = Driver()
        let (panel, _) = try little(d, "https://example.com/little")
        d.system(.window(panel, .becameKey))
        d.advance(.seconds(3_601))
        d.system(.clockTick)
        XCTAssertNil(d.snapshot.windows[panel], "being the key window for an hour without input is idle")
        let (used, _) = try little(d, "https://example.com/used")
        d.system(.window(used, .becameKey))
        d.advance(.seconds(3_000))
        d.system(.window(used, .activity))
        d.advance(.seconds(1_000))
        d.system(.clockTick)
        XCTAssertNotNil(d.snapshot.windows[used], "a click 1000 s ago is use")
        d.advance(.seconds(2_700))
        d.system(.clockTick)
        XCTAssertNil(d.snapshot.windows[used])
    }

    /// Scrolling reports activity dozens of times a second; each change recomputes and redraws every window (the sidebar
    /// lagged with a large imported sidebar). Only a stamp 10 s old or older moves.
    func testActivityUnderTenSecondsAfterTheLastStampChangesNothing() {
        let d = Driver()
        XCTAssertFalse(d.state.activityIsRecent(in: d.window, now: d.now), "no stamp yet")
        XCTAssertTrue(d.system(.window(d.window, .activity)).changed, "the first report stamps the window")
        d.advance(.seconds(3))
        XCTAssertTrue(d.state.activityIsRecent(in: d.window, now: d.now), "the store may skip this report")
        XCTAssertFalse(d.system(.window(d.window, .activity)).changed, "a scroll 3 s later redraws nothing")
        d.advance(.seconds(7))
        XCTAssertFalse(d.state.activityIsRecent(in: d.window, now: d.now))
        XCTAssertTrue(d.system(.window(d.window, .activity)).changed, "10 s after the stamp it moves")
        XCTAssertEqual(d.state.session.windows[d.window]?.lastInteraction, d.now)
    }

    func testLittleArcPlayingSoundIsNeverArchived() throws {
        let d = Driver()
        let (panel, tab) = try little(d, "https://example.com/music")
        d.page(tab, .audioChanged(true), in: panel)
        d.advance(.seconds(7_200))
        d.system(.clockTick)
        XCTAssertNotNil(d.snapshot.windows[panel], "playing sound keeps it")
        d.page(tab, .audioChanged(false), in: panel)
        d.system(.clockTick)
        XCTAssertNil(d.snapshot.windows[panel], "silent and idle: archived")
        XCTAssertEqual(d.archive().first?.url, url("https://example.com/music"))
    }
}
