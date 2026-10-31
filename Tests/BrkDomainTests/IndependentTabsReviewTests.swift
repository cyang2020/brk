import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class IndependentTabsReviewTests: XCTestCase {
    private func request(_ t: Transition) throws -> SiteRequest {
        try XCTUnwrap(t.effects.compactMap { if case .siteRequest(let r) = $0 { r } else { nil } }.first)
    }
    private func otherProfileSpace(_ d: Driver) throws -> (SpaceID, ProfileID) {
        let origin = d.view.space.id
        d.user(.profile(.create(name: "Other", icon: nil)))
        let profile = try XCTUnwrap(d.snapshot.settings.profiles.first { $0.profile.name == "Other" }?.profile.id)
        let space = d.newSpace("Other profile")
        d.user(.profile(.assign(.space(space), to: profile)))
        d.user(.space(.focus(origin)))
        return (space, profile)
    }
    private func liveFolder(_ d: Driver) throws -> ItemID {
        let r = try request(d.user(.tabTools(.site(.connectGitHub(favorite: nil)))))
        d.system(.siteResult(r.id, .pullRequests(repository: "owner/private", [PullRequestLink(title: "Original", url: url("https://github.com/owner/private/pull/1"))])))
        return try XCTUnwrap(d.pinnedIDs.first)
    }
    func testRefreshCannotPublishIntoFolderMovedToAnotherProfile() throws {
        let d = Driver()
        let (other, profile) = try otherProfileSpace(d)
        let folder = try liveFolder(d)
        let r = try request(d.user(.tabTools(.site(.refreshFolder(folder)))))
        d.user(.item(.move(folder, to: .space(other))))
        XCTAssertEqual(d.state.browsingContext(of: d.state.doc.tree[folder]!.children[0]), .profile(profile))
        let saved = d.savedFile
        d.system(.siteResult(r.id, .pullRequests(repository: "owner/private", [PullRequestLink(title: "Late original-profile result", url: url("https://github.com/owner/private/pull/2"))])))
        print("REVIEW moved-folder requestProfile=\(r.profile) targetProfile=\(profile) children=\(d.state.doc.tree[folder]!.children.compactMap { d.state.tab($0)?.title })")
        XCTAssertEqual(d.savedFile, saved, "old-profile source response changed another profile's folder")
    }
    func testBadgeCannotFollowFavoriteAcrossProfiles() throws {
        let d = Driver()
        let (other, profile) = try otherProfileSpace(d)
        let a = d.todayIDs[0]
        d.user(.item(.move(a, to: .into(parent: d.state.doc.favorites[.default]!, index: 0))))
        let r = try request(d.user(.tabTools(.site(.connectGitHub(favorite: a)))))
        d.user(.item(.move(a, to: .into(parent: d.state.doc.favorites[profile]!, index: 0))))
        d.system(.siteResult(r.id, .unread(repository: "owner/private", count: 42)))
        d.user(.space(.focus(other)))
        print("REVIEW cross-profile badge=\(String(describing: d.view.favorites.tiles.first?.badge))")
        XCTAssertNil(d.view.favorites.tiles.first?.badge, "original-profile notification count leaked into other profile")
    }
    func testNewestRefreshWinsAcrossTwoWindows() throws {
        let d = Driver()
        let folder = try liveFolder(d)
        d.user(.window(.new))
        let other = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window })
        let older = try request(d.user(.tabTools(.site(.refreshFolder(folder)))))
        let newer = try request(d.user(.tabTools(.site(.refreshFolder(folder))), in: other))
        let latest = PullRequestLink(title: "New", url: url("https://github.com/owner/private/pull/2"))
        d.system(.siteResult(newer.id, .pullRequests(repository: "owner/private", [latest])))
        let saved = d.savedFile
        d.system(.siteResult(older.id, .pullRequests(repository: "owner/private", [])))
        print("REVIEW newer-refresh then older-refresh children=\(d.state.doc.tree[folder]!.children.count)")
        XCTAssertEqual(d.savedFile, saved, "older window's refresh erased a newer refresh")
    }
    func testBulkMovePreservesPinnedHome() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.tab(.togglePin(.item(a))))
        d.page(a, .committed(url("https://example.com/drift")))
        d.user(.tabTools(.bulk(.items([a]), .move(.into(parent: d.view.space.pinned.root, index: 0)))))
        print("REVIEW after bulk reorder home=\(String(describing: d.state.tab(a)?.pinnedURL)) reset=\(String(describing: d.row(a)?.canReset))")
        XCTAssertEqual(d.state.tab(a)?.pinnedURL, start, "bulk reorder replaced the pinned home with a drifted document")
        XCTAssertEqual(d.row(a)?.canReset, true)
    }
    func testGroupingPreservesExistingPinnedHome() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.tab(.togglePin(.item(a))))
        d.page(a, .committed(url("https://example.com/drift")))
        d.user(.tabTools(.bulk(.items([a]), .newFolder(group: true))))
        XCTAssertEqual(d.state.tab(a)?.pinnedURL, start, "grouping repinned an already pinned tab")
    }
    func testBulkMoveCountsAsActivityBeforeAutoArchive() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        _ = d.open("https://example.com/visible")
        let origin = d.view.space.id
        let destination = d.newSpace("Destination")
        d.user(.space(.focus(origin)))
        d.advance(.seconds(13 * 3600))
        d.user(.tabTools(.bulk(.items([a]), .move(.space(destination)))))
        d.system(.clockTick)
        print("REVIEW moved idle tab remains=\(d.state.tab(a) != nil) archiveCount=\(d.state.doc.archive.count)")
        XCTAssertNotNil(d.state.tab(a), "a just-moved tab immediately auto-archived")
    }
    func testDuplicateActionTargetsNewlyFocusedFavorite() throws {
        let d = Driver()
        let favorite = d.todayIDs[0]
        d.user(.item(.move(favorite, to: .into(parent: d.state.doc.favorites[.default]!, index: 0))))
        let selected = d.open("https://example.com/selected")
        // Row click sets selection; a Favorite click dispatches only tab.focus.
        d.user(.tabTools(.select(selected, .replace)))
        d.user(.tab(.focus(favorite)))
        d.user(ActionID.duplicate.spec.command)
        print("REVIEW duplicate after favorite click favoriteCount=\(d.favoriteIDs.count) todayCount=\(d.todayIDs.count)")
        XCTAssertEqual(d.favoriteIDs.count, 2, "Duplicate Current Tab duplicated a stale sidebar selection")
    }
    func testMenuClearArchiveRequiresConfirmation() throws {
        let d = Driver()
        d.user(.tab(.archive(.focused)))
        XCTAssertEqual(d.archive().count, 1)
        d.user(ActionID.clearArchive.spec.command)
        XCTAssertEqual(d.archive().count, 1, "menu Clear Archive erased data without a confirmation step")
    }
    func testStructuralRestoreKeepsIndependentWindowSlotsAndPinnedHome() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.tab(.togglePin(.item(a))))
        d.user(.split(.addPane)); d.user(.commandBar(.dismiss))
        let split = try XCTUnwrap(d.view.content.split)
        d.user(.window(.new))
        let other = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window })
        d.user(.tab(.focus(a)), in: other)
        d.page(a, .committed(url("https://example.com/other-window")), in: other)
        d.page(a, .committed(url("https://example.com/owner")))
        d.user(.tabTools(.bulk(.items([split]), .archive)))
        d.user(.archive(.restoreLast))
        XCTAssertEqual(d.row(a)?.url, url("https://example.com/owner"))
        XCTAssertEqual(d.state.tab(a)?.pinnedURL, start)
        XCTAssertNil(d.state.doc.windows[other]?.slots[a])
        XCTAssertNil(d.state.tab(d.paneIDs.last!)?.url)
    }
    func testRecentCancelKeepsOriginalWhenAnotherWindowClosesDifferentItem() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        _ = d.open("https://example.com/b")
        let original = d.open("https://example.com/c")
        d.user(.window(.new))
        let other = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window })
        d.user(.tab(.cycleRecent(.next)))
        d.user(.tab(.archive(.item(a))), in: other)
        d.user(.tabTools(.cancelRecent))
        print("REVIEW recent cancel after external removal original=\(original) actual=\(String(describing: d.current?.id))")
        XCTAssertEqual(d.current?.id, original, "repair of the frozen cycle dropped its surviving original target")
    }
    func testPrivateMuteAndLateAudioDoNotCrossContexts() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let publicPage = PageID(window: d.window, item: a)
        let oldToken = try XCTUnwrap(d.state.session.live[publicPage]?.browser)
        d.user(.window(.newIncognito))
        let privateWindow = try XCTUnwrap(d.snapshot.windows.first { $0.value.kind == .incognito }?.key)
        let before = d.savedFile
        d.user(.tabTools(.mute(.item(a))), in: privateWindow)
        XCTAssertEqual(d.savedFile, before)
        d.user(.tabTools(.mute(.item(a))))
        d.user(.window(.new))
        let second = try XCTUnwrap(d.snapshot.windows.first { $0.key != d.window && $0.value.kind == .standard }?.key)
        d.user(.tab(.focus(a)), in: second)
        XCTAssertEqual(d.snapshot.pages.filter { $0.id.item == a }.count, 2)
        XCTAssertTrue(d.snapshot.pages.filter { $0.id.item == a }.allSatisfy(\.muted))
        let (_, profile) = try otherProfileSpace(d)
        d.user(.profile(.assign(.current, to: profile)))
        d.system(.page(oldToken, .audioChanged(true)))
        XCTAssertEqual(d.row(a)?.audible, false)
        let restored = Driver(file: d.savedFile)
        XCTAssertTrue(restored.state.tab(a)?.muted == true)
    }

}

extension IndependentTabsReviewTests {
    func testArchiveCollisionRemapsAndInvalidBulkArchiveIsAtomic() throws {
        var tree = SidebarTree(scope: .global)
        let space = SpaceID("space"), root = ItemID("root"), occupied = ItemID("occupied"), reserved = ItemID("reserved")
        XCTAssertTrue(tree.makeRoot(root, .pinned(space), createdAt: T0))
        let value = Tab(url: start, title: "Kept", lastActiveAt: T0)
        try tree.insert(occupied, .tab(value), at: .into(parent: root, index: 0), createdAt: T0)
        let node = ArchivedNode.split(ItemID("split"), title: "Saved", icon: .emoji("🌙"), orientation: .vertical,
                                      fractions: [0.3, 0.7], children: [.tab(occupied, value), .tab(reserved, Tab(url: nil, title: "", lastActiveAt: T0))])
        var counter = 0
        let result = try tree.insertArchived(node, at: .into(parent: root, index: 1), now: T0, freshIDs: false, reservedIDs: [reserved], newID: { counter += 1; return "new-\(counter)" })
        XCTAssertEqual(tree[occupied]?.body, .tab(valueWithPin(value)))
        XCTAssertEqual(Set(result.tabs.map(\.0)), [ItemID("new-1"), ItemID("new-2")])
        XCTAssertEqual(tree[result.root]?.children, result.tabs.map(\.0))
        let d = Driver()
        let a = d.todayIDs[0]
        var top: ItemID?, parent: ItemID?
        for i in 0..<34 {
            d.user(.item(.newFolder))
            let f = try XCTUnwrap(d.pinnedIDs.first)
            d.user(.item(.rename(f, title: "Nested \(i)")))
            if let parent { d.user(.item(.move(f, to: .into(parent: parent, index: 0)))) }
            top = top ?? f; parent = f
        }
        let saved = d.savedFile
        d.user(.tabTools(.bulk(.items([a, top!]), .archive)))
        XCTAssertEqual(d.savedFile, saved)
        XCTAssertNotNil(d.state.tab(a))
    }
    private func valueWithPin(_ tab: Tab) -> Tab { var t = tab; t.pinnedURL = t.url; return t }
    func testCalendarProfileChangeInvalidatesRequestAndIsNotPersisted() throws {
        let d = Driver()
        let (_, profile) = try otherProfileSpace(d)
        let r = try request(d.user(.tabTools(.site(.connectCalendar))))
        d.user(.profile(.assign(.current, to: profile)))
        let saved = d.savedFile
        d.system(.siteResult(r.id, .calendar([CalendarMeeting(title: "Secret calendar fixture", url: url("https://example.com/meeting"), start: T0, end: T0.advanced(by: hour))])))
        XCTAssertTrue(d.state.session.calendars.isEmpty)
        XCTAssertEqual(d.savedFile, saved)
    }
    func testSingleMoveControlRefreshesActivity() throws {
        let d = Driver(); let a = d.todayIDs[0]
        _ = d.open("https://example.com/visible")
        let origin = d.view.space.id, destination = d.newSpace("Destination")
        d.user(.space(.focus(origin))); d.advance(.seconds(13 * 3600))
        d.user(.item(.move(a, to: .space(destination)))); d.system(.clockTick)
        XCTAssertNotNil(d.state.tab(a))
    }
}
