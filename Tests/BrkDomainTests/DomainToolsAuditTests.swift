import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Fixes from the 2026-11-12 audit of tab tools, Live Folders, profiles, site policies, splits and agent tab moves.
final class DomainToolsAuditTests: XCTestCase {
    private func request(_ transition: Transition) throws -> SiteRequest {
        try XCTUnwrap(transition.effects.compactMap { if case .siteRequest(let r) = $0 { r } else { nil } }.first)
    }
    private func folderRow(_ id: ItemID, _ d: Driver) -> FolderRow? {
        d.view.space.pinned.rows.lazy.compactMap { if case .folder(let f) = $0, f.id == id { f } else { nil } }.first
    }
    /// A new Live Folder for `repository` with one pull request row; returns the folder.
    private func liveFolder(_ d: Driver, _ repository: String) throws -> ItemID {
        let r = try request(d.user(.tabTools(.site(.connectGitHub(favorite: nil)))))
        let link = PullRequestLink(title: "Fix", url: url("https://github.com/\(repository)/pull/1"))
        d.system(.siteResult(r.id, .pullRequests(repository: repository, [link])))
        return try XCTUnwrap(d.view.space.pinned.rows.first?.id)
    }
    /// The start page's document, committed and still loading.
    private func loadingTarget(_ d: Driver) throws -> SiteTarget {
        let page = d.snapshot.pages[0].id
        let browser = try XCTUnwrap(d.state.session.live[page]?.browser)
        d.page(page.item, .documentChanged(.loading(DocumentToken(browser: browser, sequence: 1))))
        return try XCTUnwrap(d.state.siteTarget(in: d.window, allowLoading: true))
    }

    // MARK: Undo toasts (bug 17)

    /// ⌘Z on "Space deleted!" brings the Space back as it was: its pinned folder with its name and tabs, its split, and
    /// Today in its order.
    func testUndoDeleteSpaceBringsBackFoldersSplitsAndOrder() throws {
        let d = Driver()
        let space = d.newSpace("Gone")
        let pinned = d.open("https://gone.example/pinned")
        d.user(.tab(.togglePin(.item(pinned))))
        let w1 = d.open("https://gone.example/w1"), w2 = d.open("https://gone.example/w2")
        d.user(.tabTools(.bulk(.items([w1, w2]), .newFolder(group: false))))
        let folder = try XCTUnwrap(d.view.space.pinned.rows.first?.id)
        d.user(.item(.rename(folder, title: "Work")))
        let t1 = d.open("https://gone.example/t1"), t2 = d.open("https://gone.example/t2")
        d.user(.split(.joinRow(t1, onto: t2, at: 1)))
        _ = d.open("https://gone.example/t3")
        let pinnedBefore = d.view.space.pinned.rows, todayBefore = d.view.space.today.rows
        guard case .folder(let work)? = pinnedBefore.first, work.title == "Work", work.children.count == 2 else { return XCTFail("setup: \(pinnedBefore)") }
        XCTAssertTrue(todayBefore.contains { if case .split = $0 { true } else { false } }, "setup: no split")

        d.user(.space(.delete(space)))
        d.user(.tabTools(.undoToast))
        XCTAssertEqual(d.view.space.id, space)
        XCTAssertEqual(d.view.space.pinned.rows.map(\.id), pinnedBefore.map(\.id), "Pinned as it was")
        guard case .folder(let back)? = d.view.space.pinned.rows.first else { return XCTFail("the folder is gone: \(d.view.space.pinned.rows)") }
        XCTAssertEqual(back.title, "Work")
        XCTAssertEqual(back.children.map(\.id), work.children.map(\.id))
        XCTAssertEqual(d.view.space.today.rows.map(\.id), todayBefore.map(\.id), "Today as it was, split included")
        XCTAssertTrue(d.state.doc.archive.isEmpty, "the deleted Space's archive entries are used up")
    }

    /// ⌘Z on "Cleared Tabs!" puts every tab back where it was, around the tab that stayed.
    func testUndoClearTodayPutsTabsBackWhereTheyWere() throws {
        let d = Driver()
        _ = d.open("https://clear.example/d")
        _ = d.open("https://clear.example/c")
        let b = d.open("https://clear.example/b")
        _ = d.open("https://clear.example/a")
        let before = d.todayIDs
        d.user(.tab(.focus(b)))
        d.user(.tab(.clearToday))
        XCTAssertEqual(d.todayIDs, [b])
        d.user(.tabTools(.undoToast))
        XCTAssertEqual(d.todayIDs, before)
    }

    // MARK: Live Folders (bugs 19, 46)

    /// A refresh takes away only the pull request rows a refresh put there; a tab or folder the user added stays, after
    /// a relaunch too.
    func testLiveFolderRefreshKeepsRowsTheUserAdded() throws {
        let d = Driver()
        let folder = try liveFolder(d, "fixture/repo")
        let mine = d.open("https://example.com/mine")
        d.user(.item(.move(mine, to: .into(parent: folder, index: Int.max))))
        d.user(.tabTools(.newNestedFolder(folder)))
        let nested = try XCTUnwrap(d.state.doc.tree[folder]?.children.first { d.state.doc.tree[$0]?.kind == .folder })
        let next = PullRequestLink(title: "Next", url: url("https://github.com/fixture/repo/pull/2"))
        let refresh = try request(d.user(.tabTools(.site(.refreshFolder(folder)))))
        d.system(.siteResult(refresh.id, .pullRequests(repository: "fixture/repo", [next])))
        let children = try XCTUnwrap(d.state.doc.tree[folder]?.children)
        XCTAssertTrue(children.contains(mine), "the user's tab was deleted")
        XCTAssertTrue(children.contains(nested), "the user's folder was deleted")
        XCTAssertEqual(children.count, 3, "the old pull request row goes, the new one comes: \(children)")

        let restarted = Driver(file: d.savedFile)
        let empty = try request(restarted.user(.tabTools(.site(.refreshFolder(folder)))))
        restarted.system(.siteResult(empty.id, .pullRequests(repository: "fixture/repo", [])))
        XCTAssertEqual(Set(restarted.state.doc.tree[folder]?.children ?? []), [mine, nested], "after a relaunch the feed's own row still goes, the user's rows stay")
    }

    /// A refresh dropped because the window started another site request leaves its folder able to refresh again.
    func testDroppedLiveFolderRefreshDoesNotStayLoading() throws {
        let d = Driver()
        let a = try liveFolder(d, "fixture/a"), b = try liveFolder(d, "fixture/b")
        d.user(.tabTools(.site(.refreshFolder(a))))
        XCTAssertEqual(folderRow(a, d)?.live?.state, .loading)
        d.user(.tabTools(.site(.refreshFolder(b))))
        XCTAssertEqual(folderRow(b, d)?.live?.state, .loading)
        XCTAssertNotEqual(folderRow(a, d)?.live?.state, .loading, "A's request was replaced, so A is not loading any more")
        d.advance(.seconds(301))
        XCTAssertTrue(d.state.liveFolderNeedsRefresh(a, now: d.now), "opening A once its rows are old refreshes it")
    }

    // MARK: Profiles (bug 26)

    /// Deleting a profile deletes its Easels (and their pictures), AI conversations and AI pages.
    func testDeletingAProfileDeletesItsEaselsAndConversations() throws {
        let d = Driver()
        d.user(.profile(.create(name: "Work", icon: nil)))
        let work = try XCTUnwrap(d.state.doc.profiles.keys.first { $0 != .default })
        _ = d.newSpace("Work")
        d.user(.profile(.assign(.current, to: work)))
        d.user(.easel(.create))
        let easel = try XCTUnwrap(d.state.doc.easels.values.first { $0.profile == work }?.id)
        let conversation = AIRequestID("work-conversation"), page = AIPageID("work-page")
        d.system(.conversationsLoaded([StoredConversation(id: conversation, profile: work, title: "Work question", createdAt: T0, tabs: true)],
                                      [AIPageRecord(id: page, title: "Work page", html: URL(fileURLWithPath: "/tmp/brk-test-pages/work.html"), height: 200, data: nil,
                                                    conversation: conversation, profile: work, createdAt: T0, readPages: false)]))
        XCTAssertNotNil(d.state.doc.conversations[conversation])
        d.user(.profile(.assign(.current, to: .default)))
        let t = d.user(.profile(.delete(work)))
        XCTAssertNil(d.state.doc.profiles[work], "setup: the profile was not deleted")
        XCTAssertNil(d.state.doc.easels[easel], "the Easel would show in the Default profile's Library after a relaunch")
        XCTAssertTrue(t.effects.contains(.easel(.deleteFiles(easel))), "its pictures stay on disk")
        XCTAssertNil(d.state.doc.conversations[conversation], "the conversation's file would stay on disk")
        XCTAssertNil(d.state.doc.aiPages[page])
    }

    // MARK: Splits (bugs 44, 68)

    /// "Open in Split View" on a Favorite opens its page beside what was shown; the Favorite stays a Favorite.
    func testOpenInSplitViewOnAFavoriteMakesASplit() throws {
        let d = Driver()
        let original = d.paneIDs[0], favorite = d.open("https://fixture.example/favorite")
        d.user(.item(.move(favorite, to: .into(parent: d.view.favorites.root, index: 0))))
        d.user(.tab(.focus(original)))
        d.user(.tabTools(.openInSplit(.items([favorite]))))
        XCTAssertNotNil(d.view.content.split, "no split")
        XCTAssertEqual(d.paneIDs.count, 2)
        XCTAssertTrue(d.paneIDs.contains(original))
        XCTAssertFalse(d.paneIDs.contains(favorite), "the Favorite itself cannot join a split")
        XCTAssertTrue(d.view.favorites.tiles.contains { $0.id == favorite })
    }

    /// A refused "Add Bottom Split" on a full split leaves its layout alone.
    func testRefusedAddPaneAtLeavesAFullSplitsOrientation() throws {
        let d = Driver()
        let a = d.paneIDs[0], b = d.open("https://fixture.example/b"), c = d.open("https://fixture.example/c"), e = d.open("https://fixture.example/e")
        d.user(.split(.joinRow(b, onto: a, at: 1)))
        let split = try XCTUnwrap(d.view.content.split)
        d.user(.split(.joinRow(c, onto: split, at: 2)))
        d.user(.split(.joinRow(e, onto: split, at: 3)))
        XCTAssertEqual(d.paneIDs.count, Metrics.content.maxPanes.value)
        XCTAssertEqual(d.view.content.orientation, .horizontal)
        d.user(.split(.addPaneAt(.bottom)))
        XCTAssertEqual(d.view.tabTools.toast?.text, ToastCopy.cannotAddPane)
        XCTAssertEqual(d.view.content.orientation, .horizontal, "refused, yet the panes were restacked")
    }

    // MARK: Overlays (bug 60)

    /// The pointer crossing an AI panel row or the Library button closes no command bar or Peek.
    func testPointerHoverKeepsCommandBarAndPeekOpen() throws {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        d.user(.assist(.hoverConversation(nil)))
        d.user(.library(.flyout(.hovered)))
        XCTAssertNotNil(d.bar, "hovering closed the command bar")
        d.user(.app(.exit))
        d.user(.peek(.open(url("https://example.com/peek"))))
        guard case .peek? = d.view.overlay else { return XCTFail("setup: no Peek") }
        d.user(.library(.flyout(.hovered)))
        d.user(.assist(.hoverConversation(nil)))
        guard case .peek? = d.view.overlay else { return XCTFail("hovering closed the Peek") }
    }

    // MARK: Agent moves (bug 61)

    private func enabled() -> Driver {
        let d = Driver()
        for feature in AIFeature.allCases { d.user(.settings(.max(.feature(feature, true)))) }
        d.system(.aiProvidersDetected([.claude, .codex]))
        return d
    }
    @discardableResult
    private func act(_ d: Driver, _ act: AgentAct) -> AgentActOutcome? {
        d.system(.agentAct(AgentActRequest(call: "c1", window: d.window, act: act))).effects.lazy.compactMap { effect -> AgentActOutcome? in
            if case .agentActDone("c1", let outcome) = effect { outcome } else { nil }
        }.first
    }

    /// An agent's move runs a drag's rules: a tab it pins keeps the address it shows as its pinned address, and a tab it
    /// moves counts as used now, so the next sweep does not archive it.
    func testAgentMovesPinWithTheShownAddressAndStampTheTab() throws {
        let d = enabled()
        let space = d.view.space.id
        let tab = d.open("https://agent-pin.example/")
        d.page(tab, .committed(url("https://agent-pin.example/next")))
        guard case .done? = act(d, .move([tab], to: AgentDestination(space: space, section: .pinned))) else { return XCTFail("move") }
        XCTAssertEqual(d.state.tab(tab)?.pinnedURL, url("https://agent-pin.example/next"), "pinned to the address it first opened, not the one it shows")

        d.user(.settings(.autoArchive(.oneHour)))
        let old = d.open("https://agent-old.example/")
        d.user(.tab(.togglePin(.item(old))))
        d.user(.tab(.focus(tab)))
        d.advance(.seconds(7_200))
        guard case .done? = act(d, .move([old], to: AgentDestination(space: space, section: .today))) else { return XCTFail("move to Today") }
        d.system(.clockTick)
        XCTAssertTrue(d.todayIDs.contains(old), "the sweep archived a tab the agent had just moved")
    }

    // MARK: Site controls (bug 66)

    /// While the page still loads, the site controls' switches save, and the Boost tile edits this site's Boost.
    func testSiteControlsActOnAPageStillLoading() throws {
        let d = Driver()
        let target = try loadingTarget(d)
        XCTAssertNil(d.state.siteTarget(in: d.window), "setup: the page is still loading")
        var rule = d.state.sitePreferences(target.context).rule(for: target.origin)
        rule.keepAlive = true
        d.user(.site(.rule(target, rule)))
        XCTAssertTrue(d.state.sitePreferences(target.context).rule(for: target.origin).keepAlive, "the switch snapped back")
        d.user(.boost(.editCurrent))
        XCTAssertEqual(d.state.session.windows[d.window]?.boostEditor?.draft.scope, .origin(target.origin), "a Boost for every site")
    }

    /// A remembered permission does not freeze the app-wide ad blocker and cookie-banner choices for its site; a choice
    /// made for the site itself still wins.
    func testRememberedPermissionKeepsFollowingGlobalBlocking() throws {
        let d = Driver()
        let target = try loadingTarget(d)
        d.user(.site(.permission(target, target.origin, [.notifications], .deny)))
        d.user(.settings(.general(.blockAds(false))))
        d.user(.settings(.general(.hideCookieBanners(true))))
        func rule(_ d: Driver) -> SiteRule { d.state.websitePolicy(for: target.page).preferences.rule(for: target.origin) }
        XCTAssertFalse(rule(d).blocking, "the site kept blocking ads after Block ads was turned off")
        XCTAssertTrue(rule(d).hideCookieBanners)
        XCTAssertEqual(rule(d).permissions[.notifications], .deny)
        XCTAssertFalse(rule(Driver(file: d.savedFile)).blocking, "after a relaunch")
        var own = rule(d)
        own.blocking = true
        d.user(.site(.rule(target, own)))
        d.user(.settings(.general(.blockAds(true))))
        d.user(.settings(.general(.blockAds(false))))
        XCTAssertTrue(rule(d).blocking, "the site's own choice wins")
    }

    // MARK: Little Arc (bug 67)

    /// Manage Extensions from a Little Arc opens the page there and adds nothing to the main sidebar.
    func testManageExtensionsFromLittleArcOpensThere() throws {
        let d = Driver()
        let before = d.todayIDs
        d.user(.window(.newLittle(url("https://example.com/little"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little }?.id)
        d.commitRequested(in: little)
        d.user(.site(.extensions), in: little)
        XCTAssertEqual(d.todayIDs, before, "a blank row in the main sidebar")
        let tabs = d.state.session.scratch[little]?.allTabs() ?? []
        XCTAssertTrue(tabs.contains { d.state.session.live[PageID(window: little, item: $0)]?.requestedURL == url("chrome://extensions/") },
                      "the extensions page did not open in the Little Arc")
    }

    // MARK: Sidebar keys (bug 107)

    /// Down after Ctrl+Space on a Favorite goes to the first row.
    func testDownFromARevealedFavoriteGoesToTheFirstRow() throws {
        let d = Driver()
        let favorite = d.open("https://fixture.example/fav")
        _ = d.open("https://fixture.example/other")
        d.user(.item(.move(favorite, to: .into(parent: d.view.favorites.root, index: 0))))
        d.user(.tab(.focus(favorite)))
        d.user(.tabTools(.reveal))
        d.user(.tabTools(.sidebarStep(.next)))
        XCTAssertEqual(d.state.session.windows[d.window]?.revealItem, d.state.visibleRows(in: d.window).first)
    }
}
