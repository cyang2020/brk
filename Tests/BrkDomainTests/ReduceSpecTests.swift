import BrkBase
import CoreGraphics
import Foundation
import XCTest

@testable import BrkDomain

// The behavioral spec, ported case by case from the Electron version's domain tests (each name and doc comment is
// the original sentence with commands renamed to the Swift vocabulary). State is built only through the public
// surface, as `Driver` does: StateCodec.restore(nil, ...) plus commands, never literal state; assertions read what
// views and the engine read (snapshots, pages, effects, saved bytes).
//
// Dropped from the port: prototype-member-ids.test.ts (Swift dictionaries have no prototype members). Where the
// Swift contract differs from Electron's the case says so in its comment (pages created from `initialURL` instead
// of navigated; the command bar box instead of a full-window overlay; lazy restore loads the current space only).

final class ReduceSpecTests: XCTestCase {
    // MARK: - electron-v1:src/domain/reduce.test.ts
    // MARK: reduce: tabs
    /// .commandBar(.submit) with the new-tab bar open adds a tab at the top of the current space Today and focuses it (project row status current)
    func test_commandbarSubmitWithTheNewTabBarOpenAddsATabAtTheTopOfTheCurrentSpaceToday() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.bar?.placement, .centered)
        XCTAssertEqual(d.bar?.initialQuery, "")
        XCTAssertEqual(d.view.focus, .commandBarInput)
        let t = d.user(.commandBar(.submit("127.0.0.1:9/b")))
        let rows = d.view.space.today.rows
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].id, a)
        guard case .tab(let b) = rows[0] else { return XCTFail("\(rows[0])") }
        XCTAssertEqual(b.url, url("http://127.0.0.1:9/b"))
        XCTAssertEqual(b.status, .current)
        XCTAssertEqual(b.section, .today)
        XCTAssertTrue(b.loaded)
        XCTAssertEqual(b.title, "127.0.0.1:9/b")
        XCTAssertEqual(d.row(a)?.status, .idle)
        XCTAssertNil(d.view.overlay)
        XCTAssertEqual(d.view.content.panes, [Pane(tab: b.id, content: .page(PageID(window: d.window, item: b.id)), fraction: 1, focused: true)])
        XCTAssertEqual(d.view.focus, .page(PageID(window: d.window, item: b.id)))
        XCTAssertEqual(d.loadedIDs, [a, b.id])
        XCTAssertEqual(d.snapshot.pages.first { $0.id == PageID(window: d.window, item: b.id) }, PageSpec(id: PageID(window: d.window, item: b.id), initialURL: url("http://127.0.0.1:9/b"), context: .profile(.default)))
        XCTAssertTrue(t.docChanged)
        XCTAssertEqual(t.effects, [], "the engine creates the page from PageSpec.initialURL")
    }

    /// .commandBar(.submit) refuses input that resolves to nothing and keeps the bar open
    func test_commandbarSubmitRefusesInputThatResolvesToNothingAndKeepsTheBarOpen() throws {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        assertUnchanged(d.state, d.user(.commandBar(.submit("   "))))
        XCTAssertNotNil(d.bar)
    }

    /// .commandBar(.submit) with no bar open behaves like the new-tab bar
    func test_commandbarSubmitWithNoBarOpenBehavesLikeTheNewTabBar() throws {
        let d = Driver()
        d.user(.commandBar(.submit("arc browser")))
        XCTAssertEqual(d.current?.url, url("https://www.google.com/search?q=arc%20browser"))
        XCTAssertEqual(d.todayIDs.count, 2)
    }

    /// .commandBar(.submit) with a navigate target sets the tab url and emits Effect.page(.navigate) without adding a row
    func test_commandbarSubmitWithANavigateTargetSetsTheTabUrlAndEmitsEffectPageNavigate() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.commandBar(.open(.editCurrent)))
        XCTAssertEqual(d.bar?.placement, .overURLPill)
        XCTAssertEqual(d.bar?.initialQuery, "http://127.0.0.1:9/a")
        let t = d.user(.commandBar(.submit("example.com/x")))
        XCTAssertEqual(t.effects, [.page(PageID(window: d.window, item: a), .navigate(url("https://example.com/x")))])
        XCTAssertEqual(d.todayIDs, [a])
        XCTAssertEqual(d.row(a)?.url, url("https://example.com/x"))
        XCTAssertEqual(d.view.urlPill, URLPillSnapshot(text: "example.com/x", loading: false, canGoBack: false, canGoForward: false, host: "example.com"))
        XCTAssertNil(d.view.overlay)
    }

    /// .commandBar(.open) with the same target is a no-op that keeps the opening identity; a different target is a new opening
    func test_commandbarOpenWithTheSameTargetIsANoOpThatKeepsTheOpeningIdentityADifferent() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.commandBar(.open(.newTab)))
        let first = try XCTUnwrap(d.bar?.openID)
        assertUnchanged(d.state, d.user(.commandBar(.open(.newTab))))
        d.user(.commandBar(.open(.editCurrent)))
        XCTAssertEqual(d.bar?.placement, .overURLPill)
        XCTAssertEqual(d.bar?.openID, first + 1)
        d.page(a, .titleChanged("A"))
        XCTAssertEqual(d.bar?.openID, first + 1)
    }

    /// an archive command picked from the command bar closes the bar, while archive commands keep the archive page open
    func test_anArchiveCommandPickedFromTheCommandBarClosesTheBarWhileArchiveCommands() throws {
        let d = Driver()
        let t = d.open("https://a.test/")
        d.user(.tab(.close(.item(t))))
        d.user(.commandBar(.open(.newTab)))
        d.user(.archive(.restoreLast))
        XCTAssertNil(d.view.overlay)
        XCTAssertTrue(d.todayIDs.contains(t))
        d.user(.library(.open(.archive)))
        d.user(.settings(.autoArchive(.oneHour)))
        guard case .library? = d.view.overlay else { return XCTFail("archive closed") }
        d.user(.archive(.clear))
        guard case .library? = d.view.overlay else { return XCTFail("archive closed") }
    }

    /// .commandBar(.open) edit-current is centered while the sidebar is hidden, and new-tab when nothing is shown
    func test_commandbarOpenEditCurrentIsCenteredWhileTheSidebarIsHiddenAndNewTabWhen() throws {
        let d = Driver()
        d.user(.sidebar(.toggle))
        d.user(.commandBar(.open(.editCurrent)))
        XCTAssertEqual(d.bar?.placement, .centered)
        XCTAssertEqual(d.bar?.initialQuery, "http://127.0.0.1:9/a")
        let empty = Driver(startURL: nil)
        XCTAssertNotNil(empty.bar, "a fresh profile without a start URL opens the bar")
        empty.user(.commandBar(.open(.editCurrent)))
        XCTAssertEqual(empty.bar?.placement, .centered)
        XCTAssertEqual(empty.bar?.initialQuery, "")
        empty.user(.commandBar(.submit("example.com")))
        XCTAssertEqual(empty.todayIDs.count, 1)
        XCTAssertEqual(empty.current?.url, url("https://example.com/"))
    }

    /// the command bar lists open tabs with the focused one first, then by recency, and the history
    func test_theCommandBarListsOpenTabsWithTheFocusedOneFirstThenByRecencyAndTheHistory() throws {
        let d = Driver()
        d.user(.library(.clearHistory))
        let a = d.todayIDs[0]
        d.advance(minute)
        let b = d.open("127.0.0.1:9/b")
        d.page(b, .committed(url("http://127.0.0.1:9/b")))
        d.page(b, .titleChanged("Bee"))
        d.advance(minute)
        d.user(.tab(.focus(a)))
        d.user(.commandBar(.open(.newTab)))
        let bar = try XCTUnwrap(d.bar)
        XCTAssertEqual(bar.tabs, [
            SwitchCandidate(tab: a, title: "127.0.0.1:9/a", url: start, favicon: nil, spaceTitle: "Space 1", inCurrentSpace: true, isFocused: true),
            SwitchCandidate(tab: b, title: "Bee", url: url("http://127.0.0.1:9/b"), favicon: nil, spaceTitle: "Space 1", inCurrentSpace: true, isFocused: false),
        ])
        XCTAssertEqual(bar.history, [HistoryCandidate(url: url("http://127.0.0.1:9/b"), title: "Bee", visitedAt: T0.advanced(by: minute))])
        // What the menu would enable now, with a listing; of the two Pinned rows the one that applies (F4).
        XCTAssertEqual(bar.actions, ActionID.allCases.filter { $0.spec.commandBar != nil && d.view.enabledActions.contains($0) && $0 != .expandPinnedSection })
        XCTAssertTrue(bar.actions.contains(.addSplitView))
    }

    /// .commandBar(.dismiss) closes the bar; any other user command closes it too, including archive and settings commands
    func test_commandbarDismissClosesTheBarAnyOtherUserCommandClosesItTooIncludingArchive() throws {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        d.user(.commandBar(.dismiss))
        XCTAssertNil(d.view.overlay)
        assertUnchanged(d.state, d.user(.commandBar(.dismiss)))
        d.user(.commandBar(.open(.newTab)))
        d.user(.settings(.autoArchive(.oneHour)))
        XCTAssertNil(d.view.overlay)
        d.user(.commandBar(.open(.newTab)))
        d.user(.sidebar(.toggle))
        XCTAssertNil(d.view.overlay)
        d.user(.commandBar(.open(.newTab)))
        d.user(.library(.open(.archive)))
        guard case .library? = d.view.overlay else { return XCTFail("the archive replaces the bar") }
    }

    /// .tab(.focus) on the already focused tab returns the same state object (no rev bump, docChanged false)
    func test_tabFocusOnTheAlreadyFocusedTabReturnsTheSameStateObjectNoRevBumpDocChanged() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        // Later than the tab's last stamp, so a stray re-stamp would show as a change.
        d.advance(hour)
        let before = d.state
        let rev = d.view.rev
        let t = d.user(.tab(.focus(a)))
        assertUnchanged(before, t)
        XCTAssertEqual(t.effects, [])
        XCTAssertEqual(d.view.rev, rev)
    }

    /// .tab(.focus) on another tab bumps rev, shows it, and is ignored for an unknown id
    func test_tabFocusOnAnotherTabBumpsRevShowsItAndIsIgnoredForAnUnknownId() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("example.com")
        let rev = d.view.rev
        d.user(.tab(.focus(a)))
        XCTAssertEqual(d.view.rev, rev + 1)
        XCTAssertEqual(d.paneIDs, [a])
        XCTAssertEqual(d.row(b)?.status, .idle)
        assertUnchanged(d.state, d.user(.tab(.focus(ItemID("nope")))))
    }

    /// .tab(.togglePin) moves Today -> end of Pinned and sets pinnedUrl = url; again moves it to the top of Today and clears pinnedUrl
    func test_tabTogglePinMovesTodayEndOfPinnedAndSetsPinnedUrlUrlAgainMovesItToTheTop() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.tab(.togglePin(.focused)))
        let b = d.open("example.com")
        let c = d.open("example.org")
        d.user(.tab(.togglePin(.item(c))))
        XCTAssertEqual(d.pinnedIDs, [a, c])
        XCTAssertEqual(d.todayIDs, [b])
        XCTAssertEqual(d.row(c)?.section, .pinned)
        XCTAssertEqual(d.row(c)?.canReset, false)
        XCTAssertEqual(d.row(c)?.status, .current)
        XCTAssertEqual(d.paneIDs, [c])
        d.page(c, .committed(url("https://example.org/next")))
        XCTAssertEqual(d.row(c)?.canReset, true)
        d.user(.tab(.togglePin(.focused)))
        XCTAssertEqual(d.todayIDs, [c, b])
        XCTAssertEqual(d.pinnedIDs, [a])
        XCTAssertEqual(d.row(c)?.section, .today)
        XCTAssertEqual(d.row(c)?.canReset, false)
        XCTAssertEqual(d.row(c)?.url, url("https://example.org/next"))
        d.user(.tab(.togglePin(.focused)))
        XCTAssertEqual(d.row(c)?.section, .pinned)
        XCTAssertEqual(d.row(c)?.canReset, false, "pinned again with the url it has now")
    }

    /// .tab(.close) on a Today tab archives it with reason manual and focuses the most recent other tab of the space
    func test_tabCloseOnATodayTabArchivesItWithReasonManualAndFocusesTheMostRecentOther() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.advance(hour)
        let b = d.open("127.0.0.1:9/b")
        d.advance(hour)
        let c = d.open("127.0.0.1:9/c")
        d.advance(hour)
        d.user(.tab(.focus(b)))
        d.advance(hour)
        d.user(.tab(.focus(c)))
        let t = d.user(.tab(.close(.focused)))
        XCTAssertTrue(t.docChanged)
        XCTAssertEqual(d.todayIDs, [b, a])
        XCTAssertEqual(d.current?.id, b)
        XCTAssertFalse(d.loadedIDs.contains(c))
        let entry = try XCTUnwrap(d.archive().first)
        XCTAssertEqual(entry.title, "127.0.0.1:9/c")
        XCTAssertEqual(entry.url, url("http://127.0.0.1:9/c"))
        XCTAssertEqual(entry.reason, .manual)
        XCTAssertEqual(entry.fromSpaceTitle, "Space 1")
        XCTAssertEqual(entry.archivedAt, T0.advanced(by: .seconds(4 * 3_600)))
    }

    /// the Pinned-tab menu is Arc's (P12-b): Close and Keep Pinned sits in Edit Pinned Page, and Remove Pin unpins
    func test_thePinnedTabMenuIsArcsWithCloseAndKeepPinnedUnderEditPinnedPageAndRemovePin() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.tab(.togglePin(.item(a))))
        let menu = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.item(a), at: .zero)))))
        XCTAssertEqual(layout(menu), ["Copy Link", "Share ▸", "|", "Change Icon…", "Rename…", "Mute", "Customize Page…", "Edit Pinned Page ▸", "|",
                                      "Open in Split View", "Duplicate", "Move to ▸", "|", "Remove Pin"])
        XCTAssertEqual(isEnabled(menu, "Mute"), false, "nothing is playing")
        XCTAssertEqual(command(menu, "Close and Keep Pinned"), .tab(.close(.item(a))))
        XCTAssertEqual(command(menu, "Export…"), .app(.export(.items([a]))))
        let remove = try XCTUnwrap(command(menu, "Remove Pin"))
        XCTAssertEqual(remove, .tab(.togglePin(.item(a))))
        d.user(remove)
        XCTAssertFalse(d.pinnedIDs.contains(a))
        XCTAssertTrue(d.todayIDs.contains(a))
    }

    /// .tab(.archive) keeps a Today tab menu to a single Archive Tab entry (.tab(.close))
    func test_tabArchiveKeepsATodayTabMenuToASingleArchiveTabEntryTabClose() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let menu = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.item(a), at: .zero)))))
        XCTAssertEqual(titles(menu).filter { $0 == "Archive Tab" || $0 == "Close and Keep Pinned" }, ["Archive Tab"])
        XCTAssertEqual(command(menu, "Archive Tab"), .tab(.close(.item(a))))
    }

    /// .tab(.close) on a Pinned tab keeps the row, drops it from loaded, and moves activeBySpace to the most recent other loaded tab
    func test_tabCloseOnAPinnedTabKeepsTheRowDropsItFromLoadedAndMovesActiveBySpaceTo() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.tab(.togglePin(.focused)))
        d.advance(minute)
        let b = d.open("example.com")
        d.advance(minute)
        d.user(.tab(.focus(a)))
        d.user(.tab(.close(.focused)))
        XCTAssertEqual(d.pinnedIDs, [a])
        XCTAssertEqual(d.row(a)?.loaded, false)
        XCTAssertEqual(d.row(a)?.status, .idle)
        XCTAssertEqual(d.loadedIDs, [b])
        XCTAssertEqual(d.paneIDs, [b])
        XCTAssertEqual(d.archive(), [])
        // Closing an unloaded pinned tab again changes nothing.
        assertUnchanged(d.state, d.user(.tab(.close(.item(a)))))
    }

    /// .tab(.close) on the only loaded tab of a space deletes the activeBySpace entry: project reports no panes and normalize does not refill it
    func test_tabCloseOnTheOnlyLoadedTabOfASpaceDeletesTheActiveBySpaceEntryProjectReports() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.tab(.togglePin(.focused)))
        d.user(.tab(.close(.focused)))
        XCTAssertEqual(d.view.content.panes, [])
        XCTAssertEqual(d.view.focus, FocusTarget.none)
        XCTAssertEqual(d.loadedIDs, [])
        d.user(.sidebar(.resize(width: 300)))
        d.system(.clockTick)
        XCTAssertEqual(d.paneIDs, [])
        // A `.focused` command with nothing shown is a no-op.
        assertUnchanged(d.state, d.user(.tab(.close(.focused))))
        d.user(.tab(.focus(a)))
        XCTAssertEqual(d.paneIDs, [a])
        XCTAssertEqual(d.row(a)?.loaded, true)
    }

    /// .tab(.reset) on a pinned tab whose url drifted restores pinnedUrl and emits Effect.page(.navigate)
    func test_tabResetOnAPinnedTabWhoseUrlDriftedRestoresPinnedUrlAndEmitsEffectPageNavigate() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.tab(.togglePin(.focused)))
        assertUnchanged(d.state, d.user(.tab(.reset(.focused))))
        XCTAssertFalse(d.view.enabledActions.contains(.resetTab))
        d.page(a, .committed(url("http://127.0.0.1:9/elsewhere")))
        XCTAssertTrue(d.view.enabledActions.contains(.resetTab))
        let t = d.user(.tab(.reset(.focused)))
        XCTAssertEqual(t.effects, [.page(PageID(window: d.window, item: a), .navigate(start))])
        XCTAssertEqual(d.row(a)?.url, start)
        XCTAssertEqual(d.row(a)?.canReset, false)
    }

    /// .tab(.step) walks sidebarOrder without wrapping; a split counts as one stop
    func test_tabStepWalksSidebarOrderWithoutWrappingASplitCountsAsOneStop() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let fav = d.open("fav.example.com")
        d.user(.item(.move(fav, to: .into(parent: d.view.favorites.root, index: 0))))
        let pin = d.open("pin.example.com")
        d.user(.tab(.togglePin(.item(pin))))
        let x = d.open("x.example.com")
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("y.example.com")))
        let split = try XCTUnwrap(d.view.content.split)
        // Sidebar order: Favorites [fav], Pinned [pin], Today [split(x, y), a].
        XCTAssertEqual(d.todayIDs, [split, a])
        d.user(.tab(.focus(fav)))
        assertUnchanged(d.state, d.user(.tab(.step(.previous))))
        d.user(.tab(.step(.next)))
        XCTAssertEqual(d.paneIDs, [pin])
        d.user(.tab(.step(.next)))
        XCTAssertEqual(d.paneIDs.count, 2)
        XCTAssertEqual(d.paneIDs.first, x)
        XCTAssertEqual(d.view.content.split, split)
        d.user(.tab(.step(.next)))
        XCTAssertEqual(d.paneIDs, [a])
        assertUnchanged(d.state, d.user(.tab(.step(.next))))
        d.user(.tab(.step(.previous)))
        XCTAssertEqual(d.view.content.split, split)
    }

    /// .tab(.cycleRecent) freezes the recent order on the first press; the commit stamps the net on-screen change
    func test_tabCycleRecentFreezesTheRecentOrderOnTheFirstPressTheCommitStampsTheNet() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.advance(hour)
        let b = d.open("127.0.0.1:9/b")
        d.advance(hour)
        let c = d.open("127.0.0.1:9/c")
        // Recency: c (shown), b (left the screen at T0+2h), a (left at T0+1h).
        d.advance(.seconds(3 * 3_600))  // T0 + 5h
        d.system(.window(d.window, .modifiersChanged(held: [.control])))
        // Each press moves the switcher's selection; c stays on screen until Control is released (Arc).
        d.user(.tab(.cycleRecent(.next)))
        XCTAssertEqual(d.view.tabTools.recent?.selected, b)
        d.user(.tab(.cycleRecent(.next)))
        XCTAssertEqual(d.view.tabTools.recent?.selected, a)
        d.user(.tab(.cycleRecent(.next)))
        XCTAssertEqual(d.view.tabTools.recent?.selected, c)
        d.user(.tab(.cycleRecent(.previous)))
        XCTAssertEqual(d.view.tabTools.recent?.selected, a)
        XCTAssertEqual(d.paneIDs, [c])
        d.system(.window(d.window, .modifiersChanged(held: [])))  // Control released: commit
        XCTAssertEqual(d.paneIDs, [a])
        assertUnchanged(d.state, d.system(.window(d.window, .modifiersChanged(held: []))))
        // Nothing is stamped per step. At commit the net change is stamped against the pre-cycle screen: c (shown
        // when the walk began) left and a (chosen) entered, both at T0+5h. b keeps its T0+2h stamp.
        // So at T0+14h b is 12h idle and archived, while c (stamped T0+5h) and the on-screen a survive.
        d.advance(.seconds(9 * 3_600))  // T0 + 14h
        d.system(.clockTick)
        XCTAssertEqual(d.todayIDs, [c, a])
    }

    /// .tab(.cycleRecent) with one tab is a no-op
    func test_tabCycleRecentWithOneTabIsANoOp() throws {
        let d = Driver()
        assertUnchanged(d.state, d.user(.tab(.cycleRecent(.next))))
    }

    /// any user command other than .tab(.cycleRecent) commits a pending cycle (robust against a lost Control keyUp)
    func test_anyUserCommandOtherThanTabCycleRecentCommitsAPendingCycleRobustAgainstA() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.advance(hour)
        let b = d.open("127.0.0.1:9/b")
        d.advance(hour)
        d.user(.tab(.cycleRecent(.next)))  // the switcher selects a; b stays shown
        XCTAssertEqual(d.paneIDs, [b])
        d.user(.sidebar(.toggle))  // an unrelated command commits the cycle: a is shown
        XCTAssertEqual(d.paneIDs, [a])
        // Nothing left to commit: Control was never reported down, and releasing it changes nothing.
        assertUnchanged(d.state, d.system(.window(d.window, .modifiersChanged(held: []))))
        d.user(.tab(.cycleRecent(.next)))  // a fresh walk from the now-shown tab
        XCTAssertEqual(d.view.tabTools.recent?.selected, b)
        XCTAssertEqual(d.paneIDs, [a])
    }

    /// .page events for an archived or unknown tab is ignored: same state object
    func test_pageEventsForAnArchivedOrUnknownTabIsIgnoredSameStateObject() throws {
        let d = Driver()
        let b = d.open("example.com")
        d.user(.tab(.close(.item(b))))
        let before = d.state
        assertUnchanged(before, d.page(b, .titleChanged("late")))
        assertUnchanged(before, d.page(b, .loadingChanged(isLoading: true, canGoBack: false, canGoForward: false)))
        assertUnchanged(before, d.page(ItemID("ghost"), .committed(url("https://x.y/"))))
    }

    /// .page events is ignored for an unloaded pinned tab, and the same patch twice changes nothing the second time
    func test_pageEventsIsIgnoredForAnUnloadedPinnedTabAndTheSamePatchTwiceChangesNothing() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.page(a, .titleChanged("A"))
        d.page(a, .faviconChanged(url("http://127.0.0.1:9/f.ico")))
        d.page(a, .loadingChanged(isLoading: true, canGoBack: true, canGoForward: false))
        XCTAssertEqual(d.row(a)?.title, "A")
        XCTAssertEqual(d.row(a)?.favicon, url("http://127.0.0.1:9/f.ico"))
        XCTAssertEqual(d.row(a)?.loading, true)
        XCTAssertEqual(d.view.urlPill, URLPillSnapshot(text: "127.0.0.1:9/a", loading: true, canGoBack: true, canGoForward: false, host: "127.0.0.1"))
        XCTAssertTrue(d.view.enabledActions.contains(.goBack))
        XCTAssertFalse(d.view.enabledActions.contains(.goForward))
        assertUnchanged(d.state, d.page(a, .titleChanged("A")))
        assertUnchanged(d.state, d.page(a, .loadingChanged(isLoading: true, canGoBack: true, canGoForward: false)))
        d.user(.tab(.togglePin(.item(a))))
        d.open("example.com")
        d.user(.tab(.close(.item(a))))
        assertUnchanged(d.state, d.page(a, .titleChanged("later")))
    }

    /// .page events url pushes a history entry, deduplicated by url and capped at Metrics.persistence.historyCap
    func test_pageEventsUrlPushesAHistoryEntryDeduplicatedByUrlAndCappedAtMetricsPersistence() throws {
        let d = Driver()
        d.user(.library(.clearHistory))
        let a = d.todayIDs[0]
        func visit(_ text: String) {
            d.advance(.milliseconds(1))
            d.page(a, .committed(url(text)))
        }
        func savedHistory() -> [String] { (d.savedDoc["history"] as? [[String: Any]] ?? []).compactMap { $0["url"] as? String } }
        visit("http://127.0.0.1:9/one")
        visit("http://127.0.0.1:9/two")
        visit("http://127.0.0.1:9/one")
        visit("about:blank")
        XCTAssertEqual(savedHistory(), ["http://127.0.0.1:9/one", "http://127.0.0.1:9/two"])
        let cap = Metrics.persistence.historyCap.value
        XCTAssertEqual(cap, 500)
        for i in 0..<cap { visit("http://127.0.0.1:9/p\(i)") }
        let urls = savedHistory()
        XCTAssertEqual(urls.count, 500)
        XCTAssertEqual(urls.first, "http://127.0.0.1:9/p499")
        XCTAssertFalse(urls.contains("http://127.0.0.1:9/one"))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.bar?.history.count, 500)
        XCTAssertEqual(d.bar?.history.first?.url, url("http://127.0.0.1:9/p499"))
    }

    /// .openRequested from a Favorites tab opens in the window current space Today; background keeps focus
    func test_openrequestedFromAFavoritesTabOpensInTheWindowCurrentSpaceTodayBackground() throws {
        let d = Driver()
        let fav = d.open("fav.example.com")
        d.user(.item(.move(fav, to: .into(parent: d.view.favorites.root, index: 0))))
        let work = d.newSpace("Work")
        d.user(.tab(.focus(fav)))
        XCTAssertEqual(d.view.space.id, work)
        XCTAssertEqual(d.paneIDs, [fav])
        d.page(fav, .openRequested(url("https://example.com/bg"), .backgroundTab))
        let bg = try XCTUnwrap(d.todayIDs.first)
        XCTAssertEqual(d.row(bg)?.url, url("https://example.com/bg"))
        XCTAssertEqual(d.row(bg)?.status, .idle)
        XCTAssertEqual(d.row(bg)?.section, .today)
        XCTAssertEqual(d.paneIDs, [fav])
        d.page(fav, .openRequested(url("https://example.com/fg"), .foregroundTab))
        XCTAssertEqual(d.todayIDs.count, 2)
        XCTAssertEqual(d.current?.url, url("https://example.com/fg"))
        XCTAssertEqual(d.current?.section, .today)
        XCTAssertEqual(d.view.space.id, work)
    }

    /// .openRequested refuses a disallowed URL, a file URL from a web page, and an unknown opener
    func test_openrequestedRefusesADisallowedURLAFileURLFromAWebPageAndAnUnknownOpener() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let before = d.state
        assertUnchanged(before, d.page(a, .openRequested(url("javascript:alert(1)"), .foregroundTab)))
        assertUnchanged(before, d.page(a, .openRequested(url("file:///etc/passwd"), .foregroundTab)))
        assertUnchanged(before, d.page(a, .openRequested(url("chrome://settings"), .popup)))
        assertUnchanged(before, d.page(ItemID("ghost"), .openRequested(url("https://example.com/"), .foregroundTab)))
        d.page(a, .openRequested(url("https://example.com/"), .popup))
        XCTAssertEqual(d.current?.url, url("https://example.com/"), "a popup opens as a foreground tab in v1")
    }

    /// .gainedFocus on a pane of the active split sets focusedId so a later .tab(.close) resolves focused to that pane
    func test_gainedfocusOnAPaneOfTheActiveSplitSetsFocusedIdSoALaterTabCloseResolves() throws {
        let d = Driver()
        let x = d.todayIDs[0]
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("y.example.com")))
        let y = d.paneIDs[1]
        XCTAssertEqual(d.view.content.panes.map(\.focused), [false, true])
        d.page(x, .gainedFocus)
        XCTAssertEqual(d.view.content.panes.map(\.focused), [true, false])
        XCTAssertEqual(d.row(x)?.status, .current)
        XCTAssertEqual(d.row(y)?.status, .visible)
        XCTAssertEqual(d.view.focus, .page(PageID(window: d.window, item: x)))
        assertUnchanged(d.state, d.page(x, .gainedFocus))
        d.user(.tab(.close(.focused)))
        XCTAssertEqual(d.archive().first?.url, start)
        // The split dissolved into its other pane, which is still shown.
        XCTAssertEqual(d.todayIDs, [y])
        XCTAssertEqual(d.view.space.today.rows.first?.kind, .tab)
        XCTAssertEqual(d.paneIDs, [y])
    }

    /// .gainedFocus on a tab that is not a pane is a no-op
    func test_gainedfocusOnATabThatIsNotAPaneIsANoOp() throws {
        let d = Driver()
        assertUnchanged(d.state, d.page(d.todayIDs[0], .gainedFocus))
    }

    /// browsing commands resolve the focused tab into effects; an unloaded or unknown target emits nothing
    func test_browsingCommandsResolveTheFocusedTabIntoEffectsAnUnloadedOrUnknownTarget() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let page = PageID(window: d.window, item: a)
        func effects(_ command: Command) -> [Effect] {
            let before = d.state
            let t = d.user(command)
            XCTAssertTrue(t.state == before, "\(command) changed state")
            XCTAssertFalse(t.changed)
            return t.effects
        }
        XCTAssertEqual(effects(.page(.back(.focused))), [.page(page, .goBack)])
        XCTAssertEqual(effects(.page(.forward(.item(a)))), [.page(page, .goForward)])
        XCTAssertEqual(effects(.page(.reload(.item(a), ignoringCache: true))), [.page(page, .reload(ignoringCache: true))])
        XCTAssertEqual(effects(.page(.stop(.focused))), [.page(page, .stop)])
        XCTAssertEqual(effects(.page(.zoom(.zoomIn))), [.page(page, .zoom(.zoomIn))])
        XCTAssertEqual(effects(.page(.toggleDevTools)), [.page(page, .toggleDevTools)])
        XCTAssertEqual(effects(.page(.copyURL(.plain))), [.copyToPasteboard("http://127.0.0.1:9/a")])
        XCTAssertEqual(effects(.app(.toggleFullScreen)), [.window(d.window, .toggleFullScreen)])
        XCTAssertEqual(effects(.app(.minimize)), [.window(d.window, .miniaturize)])
        XCTAssertEqual(effects(.app(.quit)), [.app(.quit)])
        XCTAssertEqual(effects(.app(.hide)), [.app(.hide)])
        XCTAssertEqual(effects(.app(.hideOthers)), [.app(.hideOthers)])
        XCTAssertEqual(effects(.app(.exit)), [.window(d.window, .leaveFullScreen)], "Esc with nothing to close")
        XCTAssertEqual(effects(.page(.reload(.item(ItemID("ghost")), ignoringCache: false))), [])
        d.user(.tab(.togglePin(.item(a))))
        d.open("example.com")
        d.user(.tab(.close(.item(a))))
        XCTAssertEqual(effects(.page(.back(.item(a)))), [], "an unloaded pinned tab has no page")
    }

    /// Esc ("Exit") closes the open overlay and nothing else; with a rename or dialog open it cancels that first.
    func testExitClosesTheOverlayWithoutLeavingFullScreen() throws {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.user(.app(.exit)).effects, [])
        XCTAssertNil(d.view.overlay)
        d.user(.item(.beginRename(.focused)))
        XCTAssertEqual(d.user(.app(.exit)).effects, [])
        XCTAssertNil(d.view.renaming)
        d.user(.sidebar(.openDialog(.newSpace)))
        XCTAssertEqual(d.user(.app(.exit)).effects, [])
        XCTAssertNil(d.view.dialog)
        XCTAssertEqual(d.user(.app(.exit)).effects, [.window(d.window, .leaveFullScreen)])
    }

    // MARK: page lifecycle (Swift additions: the engine's crash, self-close and close reports)
    /// A crashed renderer shows Arc's sad-tab card and asks the engine to recover; the next commit shows the page.
    func testRendererGoneShowsTheCrashedCardAndAsksForRecovery() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let t = d.page(a, .rendererGone)
        XCTAssertEqual(t.effects, [.page(PageID(window: d.window, item: a), .recover)])
        XCTAssertEqual(d.view.content.panes.map(\.content), [.crashed(PageID(window: d.window, item: a))])
        XCTAssertEqual(d.view.focus, FocusTarget.none)
        d.page(a, .committed(start))
        XCTAssertEqual(d.view.content.panes.map(\.content), [.page(PageID(window: d.window, item: a))])
        XCTAssertEqual(d.view.focus, .page(PageID(window: d.window, item: a)))
    }

    /// A page that closes itself (window.close()) leaves no blank card: a Today tab is archived and the window shows
    /// the most recent other tab; a Pinned tab keeps its row and loses its page (regression finding 7).
    func testAPageClosingItselfLeavesNoBlankCard() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("127.0.0.1:9/close.html")
        let t = d.page(b, .closedByPage)
        XCTAssertEqual(t.effects, [])
        XCTAssertEqual(d.todayIDs, [b, a])
        XCTAssertEqual(d.paneIDs, [a])
        XCTAssertEqual(d.snapshot.pages.map(\.id), [PageID(window: d.window, item: a)])
        XCTAssertTrue(d.archive().isEmpty)
        d.user(.tab(.togglePin(.item(a))))
        d.page(a, .closedByPage)
        XCTAssertEqual(d.pinnedIDs, [a])
        XCTAssertEqual(d.row(a)?.loaded, false)
        XCTAssertEqual(d.snapshot.pages, [])
        XCTAssertEqual(d.view.content.panes, [])
        assertUnchanged(d.state, d.page(a, .closedByPage))
    }

    /// The engine's close report clears what the page reported (loading, back/forward); the tab keeps its row.
    func testClosedClearsLivePageState() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.page(a, .loadingChanged(isLoading: true, canGoBack: true, canGoForward: false))
        XCTAssertTrue(d.view.urlPill.loading)
        d.page(a, .closed)
        XCTAssertEqual(d.view.urlPill, URLPillSnapshot(text: "127.0.0.1:9/a", loading: false, canGoBack: false, canGoForward: false, host: "127.0.0.1"))
        XCTAssertEqual(d.row(a)?.loaded, true)
        assertUnchanged(d.state, d.page(a, .closed))
    }

    /// Closing the window with its close button keeps it in the file for the next launch (v1 has one window).
    func testWindowCloseKeepsTheWindowForTheNextLaunch() throws {
        let d = Driver()
        assertUnchanged(d.state, d.system(.window(d.window, .closed)))
        XCTAssertEqual(Driver(file: d.savedFile).snapshot.windows.count, 1)
    }

    // MARK: reduce: tree
    /// .item(.move) refuses moving a folder into its own descendant (state unchanged)
    func test_itemMoveRefusesMovingAFolderIntoItsOwnDescendantStateUnchanged() throws {
        let d = Driver()
        d.user(.item(.newFolder))
        let outer = d.pinnedIDs[0]
        d.user(.item(.newFolder))
        let inner = d.pinnedIDs[0]
        d.user(.item(.move(inner, to: .into(parent: outer, index: 0))))
        guard case .folder(let row)? = d.view.space.pinned.rows.first else { return XCTFail("no folder") }
        XCTAssertEqual(row.id, outer)
        XCTAssertEqual(row.children.map(\.id), [inner])
        assertUnchanged(d.state, d.user(.item(.move(outer, to: .into(parent: inner, index: 0)))))
        assertUnchanged(d.state, d.user(.item(.move(outer, to: .into(parent: outer, index: 0)))))
    }

    /// Today accepts topic folders; Favorites stays flat and ordinary moves cannot insert into a split.
    func test_itemMoveAllowsTodayFoldersAndRefusesFavoritesAndSplitPlacement() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.item(.newFolder))
        let folder = d.pinnedIDs[0]
        let today = d.view.space.today.root
        XCTAssertTrue(d.user(.item(.move(folder, to: .into(parent: today, index: 0)))).docChanged)
        XCTAssertEqual(d.state.doc.tree[folder]?.parent, today)
        assertUnchanged(d.state, d.user(.item(.move(folder, to: .into(parent: d.view.favorites.root, index: 0)))))
        let b = d.open("example.com")
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("example.org")))
        d.commitRequested()
        let split = try XCTUnwrap(d.view.content.split)
        assertUnchanged(d.state, d.user(.item(.move(a, to: .into(parent: split, index: 0)))))
        assertUnchanged(d.state, d.user(.item(.move(today, to: .into(parent: d.view.space.pinned.root, index: 0)))))
        XCTAssertEqual(d.paneIDs.first, b)
    }

    /// .item(.move) within the same parent counts the index after the item is detached, so applying it twice is a no-op
    func test_itemMoveWithinTheSameParentCountsTheIndexAfterTheItemIsDetachedSoApplying() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("example.com")
        let c = d.open("example.org")
        XCTAssertEqual(d.todayIDs, [c, b, a])
        let today = d.view.space.today.root
        let move = Command.item(.move(c, to: .into(parent: today, index: 1)))
        d.user(move)
        XCTAssertEqual(d.todayIDs, [b, c, a])
        assertUnchanged(d.state, d.user(move))
        d.user(.item(.move(b, to: .into(parent: today, index: 99))))
        XCTAssertEqual(d.todayIDs, [c, a, b])
    }

    /// .item(.move) to a dock space puts a Today item at the top of that space Today and a Pinned item at the end of its Pinned
    func test_itemMoveToADockSpacePutsATodayItemAtTheTopOfThatSpaceTodayAndAPinnedItem() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let first = d.view.space.id
        let p1 = d.open("p1.example.com")
        d.user(.tab(.togglePin(.item(p1))))
        let work = d.newSpace("Work", color: ThemePresets.brand[3])
        let w1 = d.open("w1.example.com")
        d.user(.tab(.togglePin(.item(w1))))
        let w2 = d.open("w2.example.com")
        d.user(.space(.focus(first)))
        d.user(.item(.move(a, to: .space(work))))
        d.user(.item(.move(p1, to: .space(work))))
        XCTAssertEqual(d.todayIDs, [])
        XCTAssertEqual(d.pinnedIDs, [])
        // p1 was shown in the first space and no other loaded tab is left there: the first space shows nothing.
        XCTAssertEqual(d.view.content.panes, [])
        d.user(.space(.focus(work)))
        XCTAssertEqual(d.todayIDs, [a, w2])
        XCTAssertEqual(d.pinnedIDs, [w1, p1])
        XCTAssertEqual(d.row(p1)?.canReset, false)
    }

    /// .item(.newFolder) adds a folder at the top of Pinned in rename mode and expands Pinned; .item(.toggleFolder) collapses it
    func test_itemNewFolderAddsAFolderAtTheTopOfPinnedInRenameModeAndExpandsPinnedItem() throws {
        let d = Driver()
        d.user(.space(.togglePinnedSection(.current)))
        XCTAssertTrue(d.view.space.pinned.collapsed)
        d.user(.item(.newFolder))
        guard case .folder(let folder)? = d.view.space.pinned.rows.first else { return XCTFail("no folder") }
        XCTAssertEqual(folder.title, "New Folder")
        XCTAssertFalse(folder.collapsed)
        XCTAssertEqual(folder.children, [])
        XCTAssertFalse(d.view.space.pinned.collapsed)
        XCTAssertEqual(d.view.renaming, folder.id)
        XCTAssertEqual(d.view.focus, .renameField(folder.id))
        d.user(.item(.toggleFolder(folder.id)))
        guard case .folder(let collapsed)? = d.view.space.pinned.rows.first else { return XCTFail("no folder") }
        XCTAssertTrue(collapsed.collapsed)
        d.user(.item(.toggleFolder(folder.id)))
        guard case .folder(let open)? = d.view.space.pinned.rows.first else { return XCTFail("no folder") }
        XCTAssertFalse(open.collapsed)
    }

    /// .item(.deleteFolder) archives every tab inside with reason container-deleted and removes the folder
    func test_itemDeleteFolderArchivesEveryTabInsideWithReasonContainerDeletedAndRemoves() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.item(.newFolder))
        let folder = d.pinnedIDs[0]
        let b = d.open("example.com")
        for id in [a, b] { d.user(.item(.move(id, to: .into(parent: folder, index: 0)))) }
        guard case .folder(let row)? = d.view.space.pinned.rows.first else { return XCTFail("no folder") }
        XCTAssertEqual(row.children.map(\.id), [b, a])
        d.user(.item(.deleteFolder(folder)))
        XCTAssertEqual(d.pinnedIDs, [])
        let archive = d.archive()
        XCTAssertEqual(archive.map(\.url), [url("https://example.com/"), start])
        XCTAssertEqual(archive.map(\.reason), [.containerDeleted, .containerDeleted])
        XCTAssertEqual(d.loadedIDs, [])
        XCTAssertEqual(d.view.content.panes, [])
        XCTAssertNil(d.view.renaming, "the folder being renamed is gone")
    }

    /// .item(.rename) with null cancels; with "" clears customTitle; a page title update never clobbers customTitle
    func test_itemRenameWithNullCancelsWithClearsCustomTitleAPageTitleUpdateNeverClobbers() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.item(.beginRename(.focused)))
        XCTAssertEqual(d.view.renaming, a)
        XCTAssertEqual(d.view.focus, .renameField(a))
        d.user(.item(.rename(a, title: nil)))
        XCTAssertNil(d.view.renaming)
        XCTAssertEqual(d.row(a)?.title, "127.0.0.1:9/a")
        d.user(.item(.rename(a, title: "  Mine  ")))
        d.page(a, .titleChanged("Page Title"))
        XCTAssertEqual(d.row(a)?.title, "Mine")
        d.user(.item(.rename(a, title: "")))
        XCTAssertEqual(d.row(a)?.title, "Page Title")
        d.user(.item(.rename(a, title: String(repeating: "x", count: 600))))
        XCTAssertEqual(d.row(a)?.title.count, 500)
        d.user(.item(.newFolder))
        let folder = d.pinnedIDs[0]
        d.user(.item(.rename(folder, title: "Reading")))
        d.user(.item(.rename(folder, title: "   ")))
        guard case .folder(let row)? = d.view.space.pinned.rows.first else { return XCTFail("no folder") }
        XCTAssertEqual(row.title, "Reading")
    }

    /// .item(.beginRename) with the sidebar hidden peeks it so the input is visible
    func test_itemBeginRenameWithTheSidebarHiddenPeeksItSoTheInputIsVisible() throws {
        let d = Driver()
        d.user(.sidebar(.toggle))
        d.user(.item(.beginRename(.focused)))
        XCTAssertEqual(d.view.sidebar, SidebarSnapshot(visible: false, width: 228, peek: true))
        assertUnchanged(d.state, d.user(.item(.beginRename(.item(ItemID("ghost"))))))
    }

    /// Rename Current Item on a tab inside a collapsed folder of a collapsed Pinned section expands both, so the
    /// field can show (electron-wave1-review.md finding 3, wrong in the Electron version).
    func testBeginRenameExpandsCollapsedAncestors() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.tab(.togglePin(.focused)))
        d.user(.item(.newFolder))
        let folder = d.pinnedIDs[0]
        d.user(.item(.move(a, to: .into(parent: folder, index: 0))))
        d.user(.item(.toggleFolder(folder)))
        d.user(.space(.togglePinnedSection(.current)))
        XCTAssertTrue(d.view.space.pinned.collapsed)
        d.user(.item(.beginRename(.focused)))
        XCTAssertEqual(d.view.renaming, a)
        XCTAssertFalse(d.view.space.pinned.collapsed)
        guard case .folder(let row)? = d.view.space.pinned.rows.first else { return XCTFail("no folder") }
        XCTAssertFalse(row.collapsed)
        XCTAssertEqual(row.children.map(\.id), [a])
    }

    /// Favorites reorder inside their grid with the same index rule as every move (electron-wave1-review.md finding 2).
    func testFavoritesReorderInsideTheGrid() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("b.example.com")
        let root = d.view.favorites.root
        d.user(.item(.move(a, to: .into(parent: root, index: 0))))
        d.user(.item(.move(b, to: .into(parent: root, index: 1))))
        XCTAssertEqual(d.favoriteIDs, [a, b])
        d.user(.item(.move(b, to: .into(parent: root, index: 0))))
        XCTAssertEqual(d.favoriteIDs, [b, a])
        XCTAssertEqual(d.view.favorites.tiles.map(\.section), [.favorites, .favorites])
        assertUnchanged(d.state, d.user(.item(.move(b, to: .into(parent: root, index: 0)))))
    }

    // MARK: reduce: split
    /// .split(.addPane) on a tab replaces it in place by a split of [tab, empty pane] and opens the command bar targeting the empty pane
    func test_splitAddPaneOnATabReplacesItInPlaceByASplitOfTabEmptyPaneAndOpensTheCommand() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("example.com")
        d.user(.tab(.focus(a)))
        d.user(.split(.addPane))
        let v = d.view
        XCTAssertEqual(v.space.today.rows.map(\.kind), [.tab, .split])
        XCTAssertEqual(v.space.today.rows[0].id, b)
        guard case .split(let split) = v.space.today.rows[1] else { return XCTFail("no split") }
        XCTAssertEqual(split.status, .current)
        XCTAssertEqual(split.panes.map(\.id).first, a)
        XCTAssertEqual(split.panes.map(\.url), [start, nil])
        XCTAssertEqual(split.panes.map(\.title), ["127.0.0.1:9/a", "New Tab"])
        XCTAssertEqual(split.panes.map(\.status), [.visible, .current])
        XCTAssertEqual(v.content.split, split.id)
        let pane = v.content.panes[1].tab
        XCTAssertEqual(v.content.panes.map(\.fraction), [0.5, 0.5])
        XCTAssertEqual(v.content.panes.map(\.focused), [false, true])
        XCTAssertEqual(v.content.panes.map(\.content), [.page(PageID(window: d.window, item: a)), .blank])
        XCTAssertEqual(d.snapshot.pages.first { $0.id == PageID(window: d.window, item: pane) }?.initialURL, Optional<URL>.none, "no browser for an empty pane")
        guard case .commandBar(let bar)? = v.overlay else { return XCTFail("no bar") }
        XCTAssertEqual(bar.placement, .centered)
        XCTAssertEqual(bar.initialQuery, "")
        let t = d.user(.commandBar(.submit("127.0.0.1:9/page2.html")))
        // The pane had no page, so its page is created from its new url (PageSpec.initialURL), not navigated.
        XCTAssertEqual(t.effects, [])
        XCTAssertNil(d.view.overlay)
        XCTAssertEqual(d.row(pane)?.url, url("http://127.0.0.1:9/page2.html"))
        XCTAssertEqual(d.snapshot.pages.first { $0.id == PageID(window: d.window, item: pane) }?.initialURL, url("http://127.0.0.1:9/page2.html"))
        XCTAssertEqual(d.view.focus, .page(PageID(window: d.window, item: pane)))
    }

    /// .split(.addPane) with nothing shown, or on a Favorites tab, is a no-op
    func test_splitAddPaneWithNothingShownOrOnAFavoritesTabIsANoOp() throws {
        let empty = Driver(startURL: nil)
        empty.user(.commandBar(.dismiss))
        assertUnchanged(empty.state, empty.user(.split(.addPane)))
        XCTAssertFalse(empty.view.enabledActions.contains(.addSplitView))
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.item(.move(a, to: .into(parent: d.view.favorites.root, index: 0))))
        assertUnchanged(d.state, d.user(.split(.addPane)))
        XCTAssertFalse(d.view.enabledActions.contains(.addSplitView))
    }

    /// .split(.addPane) on a split with Metrics.content.maxPanes panes is a no-op
    func test_splitAddPaneOnASplitWithMetricsContentMaxPanesPanesIsANoOp() throws {
        let d = Driver()
        for i in 2...4 {
            d.user(.split(.addPane))
            d.user(.commandBar(.submit("p\(i).example.com")))
        }
        XCTAssertEqual(d.view.content.panes.count, 4)
        XCTAssertEqual(d.view.content.panes.map(\.fraction), [0.25, 0.25, 0.25, 0.25])
        XCTAssertFalse(d.view.enabledActions.contains(.addSplitView))
        assertUnchanged(d.state, d.user(.split(.addPane)))
    }

    /// .split(.addPane) inserts the new pane after the focused pane with an equal share
    func test_splitAddPaneInsertsTheNewPaneAfterTheFocusedPaneWithAnEqualShare() throws {
        let d = Driver()
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("b.example.com")))
        let (a, b) = (d.paneIDs[0], d.paneIDs[1])
        d.user(.split(.resize(try XCTUnwrap(d.view.content.split), fractions: [a: 3, b: 1])))
        d.page(a, .gainedFocus)
        d.user(.split(.addPane))
        let ids = d.paneIDs
        XCTAssertEqual([ids[0], ids[2]], [a, b])
        XCTAssertEqual(d.view.content.panes.map(\.focused), [false, true, false])
        let fractions = d.view.content.panes.map(\.fraction)
        XCTAssertEqual(fractions[1], 1.0 / 3, accuracy: 1e-10)
        XCTAssertEqual(fractions[0] / fractions[2], 3, accuracy: 1e-10)
    }

    /// .split(.closePane) leaving one pane dissolves the split into that tab, in place (normalize)
    func test_splitClosePaneLeavingOnePaneDissolvesTheSplitIntoThatTabInPlaceNormalize() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("example.com")
        d.user(.tab(.focus(a)))
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("example.org")))
        d.commitRequested()
        let pane = d.paneIDs[1]
        XCTAssertTrue(d.view.enabledActions.contains(.removeSplitView))
        d.user(.split(.closePane))
        XCTAssertEqual(d.view.space.today.rows.map(\.kind), [.tab, .tab])
        XCTAssertEqual(d.todayIDs, [b, a])
        XCTAssertEqual(d.paneIDs, [a])
        XCTAssertNil(d.view.content.split)
        XCTAssertFalse(d.view.enabledActions.contains(.removeSplitView))
        XCTAssertEqual(d.archive().first?.url, url("https://example.org/"))
        XCTAssertEqual(d.archive().first?.reason, .manual)
        XCTAssertFalse(d.loadedIDs.contains(pane))
        assertUnchanged(d.state, d.user(.split(.closePane)))
    }

    /// .split(.closePane) in Pinned moves the pane out after the split and unloads it instead of archiving
    func test_splitClosePaneInPinnedMovesThePaneOutAfterTheSplitAndUnloadsItInsteadOf() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.tab(.togglePin(.item(a))))
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("example.org")))
        d.commitRequested()
        let pane = d.paneIDs[1]
        d.user(.split(.closePane))
        XCTAssertEqual(d.view.space.pinned.rows.map(\.kind), [.tab, .tab])
        XCTAssertEqual(d.pinnedIDs, [a, pane])
        XCTAssertEqual(d.row(pane)?.loaded, false)
        XCTAssertEqual(d.row(pane)?.section, .pinned)
        XCTAssertEqual(d.row(pane)?.url, url("https://example.org/"))
        XCTAssertEqual(d.paneIDs, [a])
        XCTAssertEqual(d.archive(), [])
    }

    /// .split(.resize) normalizes fractions to sum 1 and clamps each to at least Metrics.content.minPaneFraction
    func test_splitResizeNormalizesFractionsToSum1AndClampsEachToAtLeastMetricsContent() throws {
        let d = Driver()
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("example.org")))
        d.commitRequested()
        let split = try XCTUnwrap(d.view.content.split)
        let (a, b) = (d.paneIDs[0], d.paneIDs[1])
        d.user(.split(.resize(split, fractions: [a: 3, b: 1])))
        XCTAssertEqual(d.view.content.panes.map(\.fraction), [0.75, 0.25])
        let extreme = Command.split(.resize(split, fractions: [a: 0.99, b: 0.01]))
        d.user(extreme)
        let fractions = d.view.content.panes.map(\.fraction)
        XCTAssertEqual(fractions[1], 0.15, accuracy: 1e-10)
        XCTAssertEqual(fractions[0], 0.85, accuracy: 1e-10)
        assertUnchanged(d.state, d.user(extreme))
        assertUnchanged(d.state, d.user(.split(.resize(split, fractions: [a: 1, ItemID("ghost"): 1]))))
        assertUnchanged(d.state, d.user(.split(.resize(split, fractions: [a: 1, b: -1]))))
    }

    /// moving a pane out of its split with .item(.move) leaves a one-pane split that normalize dissolves
    func test_movingAPaneOutOfItsSplitWithItemMoveLeavesAOnePaneSplitThatNormalizeDissolves() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("example.org")))
        d.commitRequested()
        let pane = d.paneIDs[1]
        d.user(.item(.move(pane, to: .into(parent: d.view.space.pinned.root, index: 0))))
        XCTAssertEqual(d.todayIDs, [a])
        XCTAssertEqual(d.view.space.today.rows.first?.kind, .tab)
        XCTAssertEqual(d.pinnedIDs, [pane])
        XCTAssertEqual(d.row(pane)?.canReset, false)
        // The dissolved split was shown; the window now shows the pane that took its slot.
        XCTAssertEqual(d.paneIDs, [a])
    }

    /// A split's orientation is saved with it and shown in the snapshot (Arc: `layoutOrientation`).
    func testSplitOrientationIsSavedAndProjected() throws {
        let d = Driver()
        d.user(.split(.addPane))
        let split = try XCTUnwrap(d.view.content.split)
        d.user(.split(.setOrientation(split, .vertical)))
        XCTAssertEqual(d.view.content.orientation, .vertical)
        guard case .split(let row)? = d.view.space.today.rows.first else { return XCTFail("no split") }
        XCTAssertEqual(row.orientation, .vertical)
        assertUnchanged(d.state, d.user(.split(.setOrientation(split, .vertical))))
        assertUnchanged(d.state, d.user(.split(.setOrientation(ItemID("ghost"), .horizontal))))
        XCTAssertEqual(Driver(file: d.savedFile).view.content.orientation, .vertical)
    }

    /// A custom icon on a tab, folder or split shows on its row and survives a restart; nil restores the default.
    func testCustomIconsOnTabsFoldersAndSplits() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.item(.setIcon(a, .emoji("📌"))))
        XCTAssertEqual(d.row(a)?.icon, .emoji("📌"))
        d.user(.item(.newFolder))
        let folder = d.pinnedIDs[0]
        d.user(.item(.setIcon(folder, .named(.book))))
        d.user(.split(.addPane))
        let split = try XCTUnwrap(d.view.content.split)
        d.user(.item(.setIcon(split, .symbol("star.fill"))))
        let r = Driver(file: d.savedFile)
        guard case .folder(let f)? = r.view.space.pinned.rows.first, case .split(let s)? = r.view.space.today.rows.first else {
            return XCTFail("rows")
        }
        XCTAssertEqual(f.icon, .named(.book))
        XCTAssertEqual(s.icon, .symbol("star.fill"))
        XCTAssertEqual(r.row(a)?.icon, .emoji("📌"))
        d.user(.item(.setIcon(a, nil)))
        XCTAssertNil(d.row(a)?.icon)
        assertUnchanged(d.state, d.user(.item(.setIcon(ItemID("ghost"), .emoji("x")))))
    }

    // MARK: reduce: spaces and archive
    /// Arc's space dialogs (2026-11-03 captures P26, P10 c, P28): Rename opens the rename dialog with the dock's
    /// name, Change Space Icon… the icon popover, Edit Theme… the theme panel, which stays open while its edits are
    /// saved; a rename or an icon closes its dialog. The delete confirmation takes focus, Esc cancels it, and a
    /// confirmed deletion shows the undo toast.
    func test_spaceDialogsRenameIconThemeAndTheDeleteConfirmation() throws {
        let d = Driver()
        let first = d.view.space.id
        let work = d.newSpace("Work", color: ThemePresets.drab[3])
        d.user(.sidebar(.openDialog(.rename(.current))))
        XCTAssertEqual(d.view.dialog, .rename(id: work, title: "Work"))
        XCTAssertEqual(d.view.focus, .spaceDialog)
        d.user(.space(.update(work, title: "Work 2", icon: nil, theme: nil)))
        XCTAssertNil(d.view.dialog)
        XCTAssertEqual(d.view.space.title, "Work 2")
        d.user(.sidebar(.openDialog(.icon(.space(work)))))
        XCTAssertEqual(d.view.dialog, .icon(id: work, icon: .none))
        d.user(.space(.update(work, title: nil, icon: .custom(.emoji("📘")), theme: nil)))
        XCTAssertNil(d.view.dialog)
        d.user(.sidebar(.openDialog(.theme(.current))))
        var pastel = SpaceTheme(colors: [ThemePresets.pastel[1]], texture: .grain, intensity: 0.6, appearance: .auto)
        d.user(.space(.update(work, title: nil, icon: nil, theme: pastel)))
        guard case .theme(work, let saved)? = d.view.dialog else { return XCTFail("the theme panel closed on an edit") }
        XCTAssertEqual(saved.colors, pastel.colors)
        pastel.intensity = 0.1
        d.user(.space(.update(work, title: nil, icon: nil, theme: pastel)))
        guard case .theme(work, let lighter)? = d.view.dialog else { return XCTFail("the theme panel closed on the second edit") }
        XCTAssertEqual(lighter.intensity, 0.1)
        d.user(.app(.exit))
        XCTAssertNil(d.view.dialog, "Esc closes the theme panel")
        d.user(.space(.requestDelete(work)))
        let request = try XCTUnwrap(d.view.pendingSpaceDeletion)
        XCTAssertEqual(d.view.focus, .spaceDialog, "the delete dialog takes focus so Return confirms")
        d.user(.app(.exit))
        XCTAssertNil(d.view.pendingSpaceDeletion, "Esc cancels the confirmation")
        XCTAssertEqual(d.view.dock.count, 2)
        d.user(.space(.requestDelete(work)))
        let again = try XCTUnwrap(d.view.pendingSpaceDeletion)
        XCTAssertNotEqual(again.token, request.token)
        d.user(.space(.confirmDelete(work, token: again.token, confirmed: true)))
        XCTAssertEqual(d.view.dock.map(\.id), [first])
        XCTAssertEqual(d.view.tabTools.toast?.text.hasPrefix("Space deleted!"), true, "Arc's undo toast")
    }

    /// New Space on the Space manager closes the Library: Create a Space takes the sidebar's place.
    func test_newSpaceFromTheSpaceManagerClosesTheLibrary() {
        let d = Driver()
        d.user(.library(.open(.spaces)))
        guard case .library? = d.view.overlay else { return XCTFail("no Library") }
        d.user(.sidebar(.openDialog(.newSpace)))
        XCTAssertEqual(d.view.dialog, .newSpace)
        XCTAssertNil(d.view.overlay)
    }

    /// A profile dialog opened over Create a Space takes focus and Esc closes it first.
    func test_aProfileDialogOverCreateASpaceTakesFocusAndEscFirst() {
        let d = Driver()
        d.user(.sidebar(.openDialog(.newSpace)))
        d.user(.profile(.openDialog(.create)))
        XCTAssertEqual(d.view.focus, .profileDialog)
        d.user(.app(.exit))
        XCTAssertNil(d.view.profileDialog)
        XCTAssertEqual(d.view.dialog, .newSpace)
    }

    /// .space(.create) creates an empty space, switches to it and closes the dialog; a blank title gets the fallback name
    func test_spaceCreateCreatesAnEmptySpaceSwitchesToItAndClosesTheDialogABlankTitle() throws {
        let d = Driver()
        d.user(.sidebar(.openDialog(.newSpace)))
        XCTAssertEqual(d.view.dialog, .newSpace)
        XCTAssertEqual(d.view.focus, .spaceDialog)
        d.user(.space(.create(title: "  ", icon: .custom(.named(.folder)),
                              theme: SpaceTheme(colors: [ThemePresets.pastel[2]], texture: .grain, intensity: 0.25, appearance: .auto))))
        let v = d.view
        XCTAssertEqual(v.space.title, "Space 2")
        XCTAssertEqual(v.space.icon, .custom(.named(.folder)))
        XCTAssertEqual(v.space.pinned.rows.count, 0)
        XCTAssertEqual(v.space.today.rows.count, 0)
        XCTAssertEqual(v.dock.map(\.title), ["Space 1", "Space 2"])
        XCTAssertEqual(v.dock.map(\.active), [false, true])
        XCTAssertEqual(v.dock[1].color, RGBA(hex: "#ECD2EA"))
        XCTAssertEqual(v.content.panes, [])
        XCTAssertNil(v.dialog)
        let stored = d.savedDoc["spaces"] as? [String: [String: Any]]
        XCTAssertEqual(stored?[v.space.id.rawValue]?["title"] as? String, "", "the fallback name is never stored")
    }

    /// .space(.focus) switches the gradient and rows and returns to that space last active item
    func test_spaceFocusSwitchesTheGradientAndRowsAndReturnsToThatSpaceLastActiveItem() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let first = d.view.space.id
        let firstTheme = d.view.theme
        let work = d.newSpace("Work")
        let w1 = d.open("127.0.0.1:9/page2.html")
        XCTAssertNotEqual(d.view.theme, firstTheme)
        XCTAssertEqual(d.view.dock.map(\.color), [ThemePresets.brand[0], RGBA(hex: "#2D4468")])
        d.user(.space(.focus(first)))
        XCTAssertEqual(d.view.space.id, first)
        XCTAssertEqual(d.todayIDs, [a])
        XCTAssertEqual(d.paneIDs, [a])
        XCTAssertEqual(d.view.theme, firstTheme)
        XCTAssertEqual(d.view.dock.map(\.active), [true, false])
        // Both tabs stay loaded: switching back is instant.
        XCTAssertEqual(d.loadedIDs, [a, w1])
        assertUnchanged(d.state, d.user(.space(.focus(first))))
        d.user(.space(.focus(work)))
        XCTAssertEqual(d.paneIDs, [w1])
    }

    /// .space(.step) moves to the neighbour without wrapping
    func test_spaceStepMovesToTheNeighbourWithoutWrapping() throws {
        let d = Driver()
        let first = d.view.space.id
        let second = d.newSpace("B", color: ThemePresets.brand[1])
        XCTAssertFalse(d.view.enabledActions.contains(.focusNextSpace))
        assertUnchanged(d.state, d.user(.space(.step(.next))))
        d.user(.space(.step(.previous)))
        XCTAssertEqual(d.view.space.id, first)
        XCTAssertFalse(d.view.enabledActions.contains(.focusPreviousSpace))
        assertUnchanged(d.state, d.user(.space(.step(.previous))))
        d.user(.space(.step(.next)))
        XCTAssertEqual(d.view.space.id, second)
    }

    /// .space(.move) reorders the dock with the index clamped
    func test_spaceMoveReordersTheDockWithTheIndexClamped() throws {
        let d = Driver()
        for title in ["B", "C"] { d.newSpace(title, color: ThemePresets.brand[1]) }
        let ids = d.view.dock.map(\.id)
        let (s1, s2, s3) = (ids[0], ids[1], ids[2])
        d.user(.space(.move(s3, index: 0)))
        XCTAssertEqual(d.view.dock.map(\.id), [s3, s1, s2])
        d.user(.space(.move(s3, index: 50)))
        XCTAssertEqual(d.view.dock.map(\.id), [s1, s2, s3])
        assertUnchanged(d.state, d.user(.space(.move(s3, index: 2))))
        d.user(.space(.move(s3, index: -4)))
        XCTAssertEqual(d.view.dock.map(\.id), [s3, s1, s2])
    }

    /// .space(.update) patches title, icon and theme and closes the rename dialog; the same values change nothing
    func test_spaceUpdatePatchesTitleIconAndThemeAndClosesTheRenameDialogTheSameValuesChange() throws {
        let d = Driver()
        let space = d.view.space.id
        d.user(.sidebar(.openDialog(.rename(.current))))
        guard case .rename(space, _)? = d.view.dialog else { return XCTFail("no rename dialog") }
        let theme = SpaceTheme(colors: [ThemePresets.greyscale[7]], wheel: .complementary, texture: .denim, noise: 0.3, intensity: 0.6, appearance: .dark)
        d.user(.space(.update(space, title: "Home", icon: .custom(.emoji("🏠")), theme: theme)))
        XCTAssertNil(d.view.dialog)
        XCTAssertEqual(d.view.space.title, "Home")
        XCTAssertEqual(d.view.space.icon, .custom(.emoji("🏠")))
        XCTAssertEqual(d.view.theme, resolveTheme(theme))
        XCTAssertEqual(d.view.dock.first?.color, ThemePresets.greyscale[7])
        assertUnchanged(d.state, d.user(.space(.update(space, title: "Home", icon: .custom(.emoji("🏠")), theme: theme))))
        d.user(.space(.update(space, title: " ", icon: nil, theme: nil)))
        XCTAssertEqual(d.view.space.title, "Home", "a blank title keeps the old one")
    }

    /// .space(.togglePinnedSection) collapses and expands the current space Pinned section
    func test_spaceTogglePinnedSectionCollapsesAndExpandsTheCurrentSpacePinnedSection() throws {
        let d = Driver()
        d.user(.space(.togglePinnedSection(.current)))
        XCTAssertTrue(d.view.space.pinned.collapsed)
        d.user(.space(.togglePinnedSection(.space(d.view.space.id))))
        XCTAssertFalse(d.view.space.pinned.collapsed)
    }

    /// .space(.delete) of the last space is refused
    func test_spaceDeleteOfTheLastSpaceIsRefused() throws {
        let d = Driver()
        assertUnchanged(d.state, d.user(.space(.delete(d.view.space.id))))
    }

    /// .space(.delete) archives its Pinned and Today tabs with reason container-deleted and moves windows on it to the neighbour in spaceOrder
    func test_spaceDeleteArchivesItsPinnedAndTodayTabsWithReasonContainerDeletedAndMoves() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let first = d.view.space.id
        let work = d.newSpace("Work", color: ThemePresets.drab[0])
        let w1 = d.open("w1.example.com")
        d.user(.tab(.togglePin(.item(w1))))
        d.user(.item(.newFolder))
        let w2 = d.open("w2.example.com")
        d.user(.space(.delete(work)))
        XCTAssertEqual(d.view.dock.map(\.id), [first])
        XCTAssertEqual(d.view.space.id, first)
        XCTAssertEqual(d.paneIDs, [a])
        let archive = d.archive()
        XCTAssertEqual(archive.map(\.url), [url("https://w1.example.com/"), url("https://w2.example.com/")])
        XCTAssertEqual(archive.map(\.reason), [.containerDeleted, .containerDeleted])
        XCTAssertEqual(archive.map(\.fromSpaceTitle), [nil, nil], "the source space is gone")
        XCTAssertEqual(d.loadedIDs, [a])
        XCTAssertFalse(d.allTabRows.contains { $0.id == w2 })
    }

    /// .clockTick archives idle Today tabs older than the threshold but never a visible tab, a Pinned tab or a Favorites tab
    func test_clocktickArchivesIdleTodayTabsOlderThanTheThresholdButNeverAVisibleTabA() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let pinned = d.open("pinned.example.com")
        d.user(.tab(.togglePin(.item(pinned))))
        let fav = d.open("fav.example.com")
        d.user(.item(.move(fav, to: .into(parent: d.view.favorites.root, index: 0))))
        let idle = d.open("idle.example.com")
        let b = d.open("127.0.0.1:9/page2.html")
        d.advance(.seconds(12 * 3_600) - .milliseconds(1))
        assertUnchanged(d.state, d.system(.clockTick))
        d.advance(hour)
        let t = d.system(.clockTick)
        XCTAssertTrue(t.docChanged)
        XCTAssertEqual(d.todayIDs, [b])
        XCTAssertEqual(d.pinnedIDs, [pinned])
        XCTAssertEqual(d.favoriteIDs, [fav])
        let archive = d.archive()
        XCTAssertEqual(archive.map(\.url), [url("https://idle.example.com/"), start])
        XCTAssertEqual(archive.map(\.reason), [.auto, .auto])
        XCTAssertFalse(d.loadedIDs.contains(a))
        XCTAssertFalse(d.loadedIDs.contains(idle))
    }

    /// .clockTick twice at the same time is a no-op the second time (same state object)
    func test_clocktickTwiceAtTheSameTimeIsANoOpTheSecondTimeSameStateObject() throws {
        let d = Driver()
        d.open("example.com")
        d.advance(.seconds(13 * 3_600))
        d.system(.clockTick)
        assertUnchanged(d.state, d.system(.clockTick))
    }

    /// .clockTick with autoArchiveAfter never archives nothing
    func test_clocktickWithAutoArchiveAfterNeverArchivesNothing() throws {
        let d = Driver()
        d.open("example.com")
        d.user(.settings(.autoArchive(.never)))
        d.advance(.seconds(400 * 86_400))
        assertUnchanged(d.state, d.system(.clockTick))
        XCTAssertEqual(d.todayIDs.count, 2)
    }

    /// .settings(.autoArchive) changes the threshold the sweep uses and the archive view shows
    func test_settingsAutoArchiveChangesTheThresholdTheSweepUsesAndTheArchiveViewShows() throws {
        let d = Driver()
        d.open("example.com")
        d.user(.settings(.autoArchive(.oneHour)))
        XCTAssertEqual(d.archive(), [])
        d.user(.library(.open(.archive)))
        guard case .library(let library)? = d.view.overlay, let page = library.archive else { return XCTFail("no archive") }
        XCTAssertEqual(page.threshold, .oneHour)
        assertUnchanged(d.state, d.user(.settings(.autoArchive(.oneHour))))
        d.advance(hour)
        d.system(.clockTick)
        XCTAssertEqual(d.todayIDs.count, 1)
    }

    /// .tab(.clearToday) keeps the tabs visible in any window
    func test_tabClearTodayKeepsTheTabsVisibleInAnyWindow() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("pane.example.com")))
        let split = try XCTUnwrap(d.view.content.split)
        let other = d.open("other.example.com")
        d.user(.tab(.focus(a)))
        d.user(.tab(.clearToday))
        XCTAssertEqual(d.todayIDs, [split])
        XCTAssertEqual(d.archive().map(\.url), [url("https://other.example.com/")])
        XCTAssertEqual(d.archive().map(\.reason), [.clearToday])
        XCTAssertFalse(d.loadedIDs.contains(other))
        assertUnchanged(d.state, d.user(.tab(.clearToday)))
    }

    /// .library(.open(.archive)) opens the archive in the content card and is idempotent; .archive(.clear) empties it
    func test_archiveOpenOpensTheArchiveInTheContentCardAndIsIdempotentArchiveClearEmpties() throws {
        let d = Driver()
        let b = d.open("example.com")
        d.user(.tab(.close(.item(b))))
        XCTAssertTrue(d.view.enabledActions.contains(.clearArchive))
        d.user(.library(.open(.archive)))
        guard case .library(let library)? = d.view.overlay, let page = library.archive else { return XCTFail("no archive") }
        XCTAssertEqual(page.groups.map(\.bucket), [.today])
        XCTAssertEqual(page.groups.first?.entries.map(\.url), [url("https://example.com/")])
        XCTAssertEqual(d.view.focus, FocusTarget.none, "the archive page, not the page under it")
        assertUnchanged(d.state, d.user(.library(.open(.archive))))
        let t = d.user(.archive(.clear))
        XCTAssertTrue(t.docChanged)
        XCTAssertEqual(d.view.overlay, .library(LibrarySnapshot(openID: page.openID, page: .archive,
                                                                archive: ArchiveSnapshot(openID: page.openID, groups: [], threshold: .twelveHours),
                                                                downloads: [])))
        XCTAssertFalse(d.view.enabledActions.contains(.clearArchive))
        assertUnchanged(d.state, d.user(.archive(.clear)))
    }

    /// .archive(.restore) puts the tab back in its source section when the space still exists, else at the top of the dispatching window current space Today
    func test_archiveRestorePutsTheTabBackInItsSourceSectionWhenTheSpaceStillExistsElse() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let first = d.view.space.id
        d.user(.tab(.togglePin(.item(a))))
        d.user(.item(.newFolder))
        let folder = d.pinnedIDs[0]
        d.user(.item(.move(a, to: .into(parent: folder, index: 0))))
        let b = d.open("b.example.com")
        d.user(.item(.deleteFolder(folder)))
        d.user(.library(.open(.archive)))
        let entry = try XCTUnwrap(d.archive().first)
        d.user(.archive(.restore(entry.id)))
        // Back at the end of its space's Pinned (the folder is gone), focused, with its pinned identity.
        XCTAssertEqual(d.pinnedIDs, [a])
        XCTAssertEqual(d.row(a)?.section, .pinned)
        XCTAssertEqual(d.row(a)?.url, start)
        XCTAssertEqual(d.row(a)?.canReset, false)
        XCTAssertEqual(d.row(a)?.status, .current)
        guard case .library? = d.view.overlay else { return XCTFail("the archive stays open") }
        XCTAssertEqual(d.archive(), [])
        // A tab whose space was deleted comes back to the current space's Today.
        let gone = d.newSpace("Gone", color: ThemePresets.brand[0])
        let g = d.open("g.example.com")
        d.user(.space(.focus(first)))
        d.user(.space(.delete(gone)))
        d.user(.archive(.restore(try XCTUnwrap(d.archive().first).id)))
        XCTAssertEqual(d.todayIDs, [g, b])
        XCTAssertEqual(d.current?.id, g)
        assertUnchanged(d.state, d.user(.archive(.restore(ArchiveID("ghost")))))
    }

    /// .archive(.restoreLast) restores archive[0] and focuses it; with an empty archive it is a no-op
    func test_archiveRestoreLastRestoresArchive0AndFocusesItWithAnEmptyArchiveItIsANo() throws {
        let d = Driver()
        XCTAssertFalse(d.view.enabledActions.contains(.reopenLastClosedTab))
        assertUnchanged(d.state, d.user(.archive(.restoreLast)))
        let a = d.todayIDs[0]
        let b = d.open("b.example.com")
        let c = d.open("c.example.com")
        d.user(.tab(.close(.item(b))))
        d.user(.tab(.close(.item(c))))
        XCTAssertEqual(d.todayIDs, [a])
        d.user(.archive(.restoreLast))
        XCTAssertEqual(d.todayIDs, [c, a])
        XCTAssertEqual(d.current?.id, c)
        d.user(.archive(.restoreLast))
        XCTAssertEqual(d.todayIDs, [b, c, a])
        XCTAssertEqual(d.current?.id, b)
    }

    /// .archive(.restoreLast) prefers the newest manual/clear entry over an auto-archived one that landed later
    func test_archiveRestoreLastPrefersTheNewestManualClearEntryOverAnAutoArchivedOne() throws {
        let d = Driver()
        d.advance(hour)
        d.open("127.0.0.1:9/b")
        d.advance(hour)
        let closed = d.open("127.0.0.1:9/closed")
        d.user(.tab(.close(.item(closed))))  // the user closes it: a manual entry
        d.advance(.seconds(13 * 3_600))
        d.system(.clockTick)  // the sweep then auto-archives the idle start tab (a newer entry)
        XCTAssertEqual(d.archive().map(\.reason), [.auto, .manual])
        d.user(.archive(.restoreLast))
        XCTAssertTrue(d.todayIDs.contains(closed), "Cmd+Shift+T brings back the user's closed tab, not the sweep's")
    }

    /// a restored tab is not swept again at once even if it was idle for long
    func test_aRestoredTabIsNotSweptAgainAtOnceEvenIfItWasIdleForLong() throws {
        let d = Driver()
        let b = d.open("b.example.com")
        d.user(.tab(.focus(d.todayIDs[1])))
        d.advance(.seconds(13 * 3_600))
        d.system(.clockTick)
        XCTAssertFalse(d.todayIDs.contains(b))
        d.user(.archive(.restoreLast))
        d.user(.tab(.focus(d.todayIDs[1])))
        d.system(.clockTick)
        XCTAssertTrue(d.todayIDs.contains(b))
    }

    /// archive entries are capped at Metrics.persistence.archiveCap, oldest dropped
    func test_archiveEntriesAreCappedAtMetricsPersistenceArchiveCapOldestDropped() throws {
        let d = Driver()
        let cap = Metrics.persistence.archiveCap.value
        XCTAssertEqual(cap, 2000)
        for i in 0...cap {
            let id = d.open("t\(i).example.com")
            d.user(.tab(.close(.item(id))))
        }
        let entries = d.archive()
        XCTAssertEqual(entries.count, 2000)
        XCTAssertEqual(entries.first?.url, url("https://t2000.example.com/"))
        XCTAssertFalse(entries.contains { $0.url == url("https://t0.example.com/") })
        XCTAssertEqual((d.savedDoc["archive"] as? [Any])?.count, 2000)
    }

    // MARK: window chrome
    /// .sidebar(.toggle) hides the sidebar (content fills the window) and again restores it
    func test_sidebarToggleHidesTheSidebarContentFillsTheWindowAndAgainRestoresIt() throws {
        let d = Driver()
        d.user(.sidebar(.toggle))
        XCTAssertEqual(d.view.sidebar, SidebarSnapshot(visible: false, width: 228, peek: false))
        d.user(.sidebar(.toggle))
        XCTAssertEqual(d.view.sidebar, SidebarSnapshot(visible: true, width: 228, peek: false))
        // The content rect for both states is WindowLayout's (LayoutSpecTests).
    }

    /// .sidebar(.peek) floats the hidden sidebar only while it is hidden; toggling ends the peek
    func test_sidebarPeekFloatsTheHiddenSidebarOnlyWhileItIsHiddenTogglingEndsThePeek() throws {
        let d = Driver()
        assertUnchanged(d.state, d.user(.sidebar(.peek(true))))
        d.user(.sidebar(.toggle))
        d.user(.sidebar(.peek(true)))
        XCTAssertEqual(d.view.sidebar, SidebarSnapshot(visible: false, width: 228, peek: true))
        d.user(.sidebar(.peek(false)))
        XCTAssertFalse(d.view.sidebar.peek)
        d.user(.sidebar(.peek(true)))
        d.user(.sidebar(.toggle))
        XCTAssertEqual(d.view.sidebar, SidebarSnapshot(visible: true, width: 228, peek: false))
    }

    /// .sidebar(.openDialog) opens the space dialog (peeking a hidden sidebar), moves focus to the sidebar, and null closes it
    func test_sidebarOpenDialogOpensTheSpaceDialogPeekingAHiddenSidebarMovesFocusToThe() throws {
        let d = Driver()
        d.user(.sidebar(.toggle))
        d.user(.sidebar(.openDialog(.rename(.current))))
        guard case .rename? = d.view.dialog else { return XCTFail("no dialog") }
        XCTAssertTrue(d.view.sidebar.peek)
        XCTAssertEqual(d.view.focus, .spaceDialog)
        assertUnchanged(d.state, d.user(.sidebar(.openDialog(.rename(.current)))))
        assertUnchanged(d.state, d.user(.sidebar(.openDialog(.rename(.space(SpaceID("ghost")))))))
        d.user(.sidebar(.openDialog(nil)))
        XCTAssertNil(d.view.dialog)
        XCTAssertEqual(d.view.focus, .page(PageID(window: d.window, item: d.todayIDs[0])))
    }

    /// .sidebar(.popupMenu) emits a native menu built from state whose entries dispatch real commands
    func test_sidebarPopupMenuEmitsANativeMenuBuiltFromStateWhoseEntriesDispatchRealCommands() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let work = d.newSpace("Work", color: ThemePresets.drab[3])
        d.user(.space(.step(.previous)))
        let t = d.user(.sidebar(.popupMenu(.item(a), at: CGPoint(x: 40, y: 120))))
        XCTAssertFalse(t.changed)
        guard case .popupMenu(let window, let menu, let at)? = t.effects.first else { return XCTFail("no popup") }
        XCTAssertEqual(window, d.window)
        XCTAssertEqual(at, CGPoint(x: 40, y: 120))
        XCTAssertEqual(layout(menu), ["Copy Link", "Share ▸", "|", "Change Icon…", "Rename…", "Mute", "Customize Page…", "|",
                                      "Open in Split View", "Duplicate", "Move to ▸", "|", "Archive Tab", "Archive Tabs Below"])
        XCTAssertEqual(isEnabled(menu, "Archive Tabs Below"), false, "nothing below the only tab")
        XCTAssertEqual(titles(try XCTUnwrap(submenu(menu, "Move to"))), ["Space 1", "Work"])
        XCTAssertEqual(isEnabled(menu, "Space 1"), false, "the tab's own space")
        d.user(try XCTUnwrap(command(menu, "Work")))
        d.user(.space(.focus(work)))
        XCTAssertEqual(d.todayIDs, [a])
        let space1 = try XCTUnwrap(d.state.doc.spaceOrder.first)
        let space = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.space(work), at: .zero)))))
        XCTAssertEqual(layout(space), ["Change Space Icon…", "Rename Space…", "Edit Theme Color…", "Set Profile ▸", "|", "New Folder", "Live Folders ▸", "|",
                                       "Share Space…", "Export “Work” into Folder ▸", "|", "Manage Spaces…", "|", "Delete Space"])
        XCTAssertEqual(command(space, "Rename Space…"), .sidebar(.openDialog(.rename(.space(work)))))
        XCTAssertEqual(command(space, "Change Space Icon…"), .sidebar(.openDialog(.icon(.space(work)))))
        XCTAssertEqual(command(space, "Edit Theme Color…"), .sidebar(.openDialog(.theme(.space(work)))))
        XCTAssertEqual(command(space, "Share Space…"), .app(.export(.space(.space(work)))))
        XCTAssertEqual(command(space, "Delete Space"), .space(.delete(work)))
        XCTAssertEqual(try XCTUnwrap(submenu(space, "Set Profile")).entries.first, .choice(title: "Default", command: .profile(.assign(.space(work), to: .default)), on: true))
        XCTAssertEqual(titles(try XCTUnwrap(submenu(space, "Export “Work” into Folder"))), ["Space 1", "Bookmarks Folder on Disk…"])
        XCTAssertEqual(command(space, "Space 1"), .tabTools(.spaceIntoFolder(work, into: space1)))
        let plus = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.plusButton, at: .zero)))))
        XCTAssertEqual(plus.entries.compactMap { (entry: MenuEntry) -> Command? in
            if case .action(_, let c, _) = entry { return c }
            return nil
        },
                       [.commandBar(.open(.newTab)), .item(.newFolder), .sidebar(.openDialog(.newSpace)), .tabTools(.site(.connectGitHub(favorite: nil))), .tabTools(.site(.connectCalendar))])
        d.user(.item(.newFolder))
        let folder = d.pinnedIDs[0]
        let folderMenu = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.item(folder), at: .zero)))))
        XCTAssertEqual(layout(folderMenu), ["Share Folder…", "|", "New Nested Folder…", "Turn “New Folder” into Space", "Copy All Links", "|",
                                            "Change Icon…", "Rename…", "|", "Duplicate", "Move to ▸", "|", "Delete"])
        XCTAssertEqual(command(folderMenu, "Delete"), .item(.deleteFolder(folder)))
        XCTAssertEqual(isEnabled(folderMenu, "Copy All Links"), false, "an empty folder has no links")
        XCTAssertEqual(d.user(.sidebar(.popupMenu(.item(ItemID("ghost")), at: .zero))).effects, [])
        XCTAssertEqual(d.user(.sidebar(.popupMenu(.space(SpaceID("ghost")), at: .zero))).effects, [])
    }

    // MARK: persistence (StateCodec.restore / StateCodec.encode)
    /// A profile with every kind of thing in it: two spaces, Favorites, a folder, a split, archive, history, bounds.
    private func richDriver() -> Driver {
        let d = Driver()
        let a = d.todayIDs[0]
        d.page(a, .committed(start))
        d.page(a, .titleChanged("Fixture Home"))
        d.page(a, .faviconChanged(url("http://127.0.0.1:9/favicon.ico")))
        let fav = d.open("fav.example.com")
        d.user(.item(.move(fav, to: .into(parent: d.view.favorites.root, index: 0))))
        d.user(.item(.newFolder))
        d.user(.item(.rename(d.pinnedIDs[0], title: "Reading")))
        let gone = d.open("gone.example.com")
        d.user(.tab(.close(.item(gone))))
        d.user(.space(.create(title: "Work", icon: .custom(.named(.briefcase)),
                              theme: SpaceTheme(colors: [ThemePresets.drab[8]], texture: .tweed, intensity: 0.4, appearance: .dark))))
        let w1 = d.open("127.0.0.1:9/index.html")
        d.user(.tab(.togglePin(.item(w1))))
        d.open("127.0.0.1:9/page2.html")
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("127.0.0.1:9/fail")))
        d.commitRequested()
        d.user(.item(.rename(w1, title: "Index")))
        d.user(.item(.setIcon(w1, .named(.star))))
        d.user(.sidebar(.resize(width: 300)))
        d.user(.settings(.autoArchive(.twentyFourHours)))
        d.system(.window(d.window, .geometry(bounds: CGRect(x: 10, y: 20, width: 1400, height: 900), contentSize: CGSize(width: 1400, height: 872))))
        return d
    }

    /// What survives a restart, in the terms the e2e restart scenario compares (load state aside).
    private func reduction(_ v: WindowSnapshot) -> [String] {
        func rows(_ list: [Row]) -> [String] {
            list.map { row in
                switch row {
                case .tab(let t): "tab \(t.id) \(t.url?.absoluteString ?? "-") \(t.title) reset:\(t.canReset) \(t.status) \(String(describing: t.icon))"
                case .folder(let f): "folder \(f.id) \(f.title) \(f.collapsed) [\(rows(f.children).joined(separator: ", "))]"
                case .split(let s): "split \(s.id) \(s.status) [\(s.panes.map { "\($0.id) \($0.url?.absoluteString ?? "-") \($0.title) \($0.status)" })]"
                }
            }
        }
        return ["dock \(v.dock.map { "\($0.id) \($0.title) \($0.icon) \($0.color)" })", "space \(v.space.id) \(v.space.title)",
                "theme \(v.theme)", "favorites \(rows(v.favorites.tiles.map(Row.tab)))", "pinned \(rows(v.space.pinned.rows))",
                "today \(rows(v.space.today.rows))", "width \(v.sidebar.width)",
                "content \(v.content.panes.map { "\($0.tab) \($0.fraction) \($0.focused)" })"]
    }

    /// StateCodec.encode then StateCodec.restore round-trips Doc exactly (items, spaces, order, favorites, archive, history, windows, settings) and rebuilds Session fresh
    func test_statecodecEncodeThenStateCodecRestoreRoundTripsDocExactlyItemsSpacesOrder() throws {
        let d = richDriver()
        d.user(.commandBar(.open(.newTab)))
        let file = d.savedFile
        let r = Driver(file: file)
        XCTAssertEqual(r.outcome, .restored(repairs: []))
        XCTAssertEqual(r.savedFile, file, "identical bytes")
        XCTAssertEqual(reduction(r.view), reduction(d.view))
        XCTAssertEqual(r.archive(), d.archive())
        XCTAssertEqual(r.view.bounds, CGRect(x: 10, y: 20, width: 1400, height: 900))
        XCTAssertEqual(r.view.sidebar.width, 300)
        XCTAssertEqual(r.view.content.orientation, .horizontal)
        // Session is fresh: no overlay, rev 0, and only the shown panes of the current space are loaded (lazy).
        XCTAssertNil(r.view.overlay)
        XCTAssertEqual(StateCodec.restore(file, seed: RestoreSeed(startURL: nil, contentSize: Driver.contentSize), ctx: d.ctx).state.session.rev, 0)
        XCTAssertEqual(r.loadedIDs, Set(r.paneIDs))
        XCTAssertEqual(r.paneIDs.count, 2)
        XCTAssertGreaterThan(d.loadedIDs.count, 3)
        // Showing the other space loads what it shows, and nothing else.
        r.user(.space(.focus(r.view.dock[0].id)))
        XCTAssertEqual(r.paneIDs.count, 1)
        XCTAssertEqual(r.loadedIDs.count, 3)
    }

    /// StateCodec.restore of null is a fresh profile with one space, one window and one Today tab at startUrl
    func test_statecodecRestoreOfNullIsAFreshProfileWithOneSpaceOneWindowAndOneTodayTab() throws {
        let d = Driver(file: nil)
        XCTAssertEqual(d.outcome, .fresh)
        XCTAssertEqual(d.snapshot.windows.count, 1)
        let v = d.view
        XCTAssertEqual(v.dock.map(\.title), ["Space 1"])
        XCTAssertEqual(v.dock.map(\.icon), [.none])
        XCTAssertEqual(v.dock.map(\.active), [true])
        XCTAssertEqual(v.space.pinned.rows.count, 0)
        XCTAssertEqual(v.favorites.tiles.count, 0)
        XCTAssertEqual(v.space.today.rows.count, 1)
        guard case .tab(let tab)? = v.space.today.rows.first else { return XCTFail("no tab") }
        XCTAssertEqual(tab.url, start)
        XCTAssertEqual(tab.status, .current)
        XCTAssertTrue(tab.loaded)
        XCTAssertEqual(tab.title, "127.0.0.1:9/a")
        XCTAssertEqual(v.sidebar, SidebarSnapshot(visible: true, width: Metrics.sidebar.defaultWidth.value, peek: false))
        XCTAssertEqual(v.content.panes, [Pane(tab: tab.id, content: .page(PageID(window: d.window, item: tab.id)), fraction: 1, focused: true)])
        XCTAssertEqual(d.snapshot.pages, [PageSpec(id: PageID(window: d.window, item: tab.id), initialURL: start, context: .profile(.default))])
        XCTAssertEqual(d.saved["version"] as? Int, 3)
    }

    /// StateCodec.restore repairs an orphan child reference and reports it in RestoreOutcome.restored(repairs:)
    func test_statecodecRestoreRepairsAnOrphanChildReferenceAndReportsItInRestoreOutcome() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("b.example.com")
        var file = jsonObject(d.savedFile)
        var doc = file["doc"] as! [String: Any]
        var items = doc["items"] as! [String: Any]
        var today = items[d.view.space.today.root.rawValue] as! [String: Any]
        // The Today root lists a missing id and has lost b (whose parent still names it).
        today["children"] = ["ghost", a.rawValue]
        items[d.view.space.today.root.rawValue] = today
        doc["items"] = items
        file["doc"] = doc
        let r = Driver(file: jsonData(file))
        guard case .restored(let repairs) = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssertGreaterThanOrEqual(repairs.count, 2)
        XCTAssertTrue(repairs.contains { $0.contains("ghost") }, "\(repairs)")
        XCTAssertTrue(repairs.contains { $0.contains(b.rawValue) }, "\(repairs)")
        XCTAssertEqual(r.todayIDs, [a, b])
        // Repaired once, the file is clean: restoring the repaired state reports nothing.
        XCTAssertEqual(Driver(file: r.savedFile).outcome, .restored(repairs: []))
    }

    /// StateCodec repairs a missing root while preserving the newly supported Today group.
    func test_statecodecRestoreRepairsMissingRootAndPreservesTodayGroup() throws {
        let d = Driver()
        d.user(.item(.newFolder))
        let folder = d.pinnedIDs[0]
        let pinnedRoot = d.view.space.pinned.root.rawValue, todayRoot = d.view.space.today.root.rawValue
        var file = jsonObject(d.savedFile)
        var doc = file["doc"] as! [String: Any]
        var items = doc["items"] as! [String: Any]
        var pinned = items[pinnedRoot] as! [String: Any], today = items[todayRoot] as! [String: Any]
        var folderItem = items[folder.rawValue] as! [String: Any]
        pinned["children"] = []
        today["children"] = (today["children"] as! [String]) + [folder.rawValue]
        folderItem["parent"] = todayRoot
        items[pinnedRoot] = pinned
        items[todayRoot] = today
        items[folder.rawValue] = folderItem
        doc["items"] = items
        doc["favorites"] = ["default": "missing-root"]
        file["doc"] = doc
        let r = Driver(file: jsonData(file))
        guard case .restored(let repairs) = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssertGreaterThanOrEqual(repairs.count, 2, "\(repairs)")
        XCTAssertEqual(r.pinnedIDs, [])
        XCTAssertEqual(r.todayIDs, d.todayIDs + [folder])
        XCTAssertEqual(r.view.favorites.tiles.count, 0)
        XCTAssertNotEqual(r.view.favorites.root, ItemID("missing-root"))
        XCTAssertEqual(Driver(file: r.savedFile).outcome, .restored(repairs: []))
    }

    /// StateCodec.restore repairs a stored split: one with a missing pane dissolves into the other, in place, and the
    /// window that showed it shows that pane; a focus on a missing pane and widths of non-panes are dropped.
    func testRestoreRepairsAStoredSplit() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("b.example.com")
        d.user(.tab(.focus(a)))
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("c.example.com")))
        let split = try XCTUnwrap(d.view.content.split)
        let c = d.paneIDs[1]
        var file = jsonObject(d.savedFile)
        var doc = file["doc"] as! [String: Any]
        var items = doc["items"] as! [String: Any]
        var splitItem = items[split.rawValue] as! [String: Any]
        splitItem["children"] = [a.rawValue, "ghost-pane"]
        items[split.rawValue] = splitItem
        items[c.rawValue] = nil
        doc["items"] = items
        file["doc"] = doc
        let r = Driver(file: jsonData(file))
        guard case .restored(let repairs) = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssertTrue(repairs.contains { $0.contains("ghost-pane") }, "\(repairs)")
        XCTAssertTrue(repairs.contains { $0.contains(split.rawValue) }, "\(repairs)")
        XCTAssertEqual(r.todayIDs, [b, a])
        XCTAssertEqual(r.paneIDs, [a], "the window shows the pane that took the split's place")
        XCTAssertNil(r.view.content.split)
        XCTAssertEqual(Driver(file: r.savedFile).outcome, .restored(repairs: []))
    }

    /// StateCodec.restore rejects a file with an unknown version, and a file whose doc has no spaces
    func test_statecodecRestoreRejectsAFileWithAnUnknownVersionAndAFileWhoseDocHasNoSpaces() throws {
        let d = Driver()
        let file = jsonObject(d.savedFile)
        var future = file
        future["version"] = 99
        var noSpaces = file
        var doc = file["doc"] as! [String: Any]
        doc["spaces"] = [String: Any]()
        noSpaces["doc"] = doc
        let cases: [(Data, CodecError?)] = [
            (jsonData(future), .unknownVersion(99)), (jsonData(noSpaces), .noSpaces), (Data(#"{"version":1"#.utf8), nil), (Data("null".utf8), nil),
        ]
        for (data, expected) in cases {
            let r = Driver(file: data)
            guard case .rejected(let error) = r.outcome else { XCTFail("\(r.outcome)"); continue }
            if let expected { XCTAssertEqual(error, expected) } else {
                guard case .unreadable(let why) = error else { XCTFail("\(error)"); continue }
                XCTAssertFalse(why.isEmpty)
            }
            // ...and starts fresh.
            XCTAssertEqual(r.allTabRows.map(\.url), [start])
        }
    }

    /// StateCodec.restore of a fresh profile encodes to a versioned envelope; garbage and an unknown version are rejected
    /// with the reason, and the state alongside is the fresh one (runs now: envelope and fresh profile are real)
    func test_statecodecEnvelopeVersionAndRejection() throws {
        let ids = Counter()
        let ctx = Context(now: Instant(milliseconds: 1_790_000_000_000), newID: ids.next)
        let seed = RestoreSeed(startURL: Driver.startURL, contentSize: Driver.contentSize)
        let fresh = StateCodec.restore(nil, seed: seed, ctx: ctx)
        XCTAssertEqual(fresh.outcome, .fresh)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: StateCodec.encode(fresh.state)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, StateCodec.currentVersion)
        let doc = try XCTUnwrap(json["doc"] as? [String: Any])
        XCTAssertEqual((doc["items"] as? [String: Any])?.count, 4, "favorites, pinned and today roots plus the start tab")
        XCTAssertEqual(StateCodec.encode(fresh.state), StateCodec.encode(fresh.state), "deterministic bytes")
        let garbage = StateCodec.restore(Data("not json".utf8), seed: seed, ctx: ctx)
        guard case .rejected(.unreadable) = garbage.outcome else { return XCTFail("\(garbage.outcome)") }
        let future = StateCodec.restore(Data(#"{"version": 99, "doc": {}}"#.utf8), seed: seed, ctx: ctx)
        XCTAssertEqual(future.outcome, .rejected(.unknownVersion(99)))
        let fallback = try XCTUnwrap(try JSONSerialization.jsonObject(with: StateCodec.encode(future.state)) as? [String: Any])
        XCTAssertEqual(((fallback["doc"] as? [String: Any])?["spaces"] as? [String: Any])?.count, 1, "a rejected file starts fresh")
    }

    /// a restored Today tab whose page later fails to load keeps its url and title (failure is live state only)
    func test_aRestoredTodayTabWhosePageLaterFailsToLoadKeepsItsUrlAndTitleFailureIsLive() throws {
        let d = Driver()
        let fail = d.open("127.0.0.1:9/fail")
        d.page(fail, .titleChanged("Fail Page"))
        let file = d.savedFile
        let r = Driver(file: file)
        XCTAssertEqual(r.current?.id, fail)
        r.page(fail, .loadingChanged(isLoading: true, canGoBack: false, canGoForward: false))
        r.page(fail, .loadFailed(code: -324, description: "ERR_EMPTY_RESPONSE", url: "http://127.0.0.1:9/fail"))
        XCTAssertEqual(r.row(fail)?.url, url("http://127.0.0.1:9/fail"))
        XCTAssertEqual(r.row(fail)?.title, "Fail Page")
        XCTAssertEqual(r.row(fail)?.loading, false)
        XCTAssertEqual(r.savedFile, file)
        let again = Driver(file: r.savedFile)
        XCTAssertEqual(again.row(fail)?.url, url("http://127.0.0.1:9/fail"))
        XCTAssertEqual(again.row(fail)?.title, "Fail Page")
    }

    // MARK: layout clamps (domain side)
    /// .sidebar(.resize) clamps the width to Metrics.sidebar.minWidth...maxWidth
    func test_sidebarResizeClampsTheWidthToMetricsSidebarMinWidthMaxWidth() throws {
        let d = Driver()
        d.user(.sidebar(.resize(width: 50)))
        XCTAssertEqual(d.view.sidebar.width, 164)
        d.user(.sidebar(.resize(width: 10_000)))
        XCTAssertEqual(d.view.sidebar.width, 500)
        let t = d.user(.sidebar(.resize(width: 300.4)))
        XCTAssertTrue(t.docChanged)
        XCTAssertEqual(d.view.sidebar.width, 300)
        assertUnchanged(d.state, d.user(.sidebar(.resize(width: 300))))
        assertUnchanged(d.state, d.user(.sidebar(.resize(width: .nan))))
        // 0 is the drag-to-hide result: hidden, the width kept for the next show.
        d.user(.sidebar(.resize(width: 0)))
        XCTAssertEqual(d.view.sidebar, SidebarSnapshot(visible: false, width: 300, peek: false))
        d.user(.sidebar(.resize(width: 250)))
        XCTAssertEqual(d.view.sidebar, SidebarSnapshot(visible: true, width: 250, peek: false))
    }

    /// .geometry updates contentSize so project reflects the new size, and persists bounds
    func test_geometryUpdatesContentSizeSoProjectReflectsTheNewSizeAndPersistsBounds() throws {
        let d = Driver()
        let bounds = CGRect(x: 5, y: 6, width: 1000, height: 700)
        let t = d.system(.window(d.window, .geometry(bounds: bounds, contentSize: CGSize(width: 1000, height: 672))))
        XCTAssertTrue(t.docChanged)
        XCTAssertEqual(d.view.bounds, bounds)
        assertUnchanged(d.state, d.system(.window(d.window, .geometry(bounds: bounds, contentSize: CGSize(width: 1000, height: 672)))))
        // A size change alone is session state: re-render, nothing to save.
        let resized = d.system(.window(d.window, .geometry(bounds: bounds, contentSize: CGSize(width: 1000, height: 650))))
        XCTAssertTrue(resized.changed)
        XCTAssertFalse(resized.docChanged)
        XCTAssertEqual(Driver(file: d.savedFile).view.bounds, bounds)
        assertUnchanged(d.state, d.system(.window(WindowID("ghost"), .geometry(bounds: bounds, contentSize: CGSize(width: 1, height: 1)))))
    }

    /// normalize clamps a stored sidebar width outside the range on restore
    func test_normalizeClampsAStoredSidebarWidthOutsideTheRangeOnRestore() throws {
        let d = Driver()
        var file = jsonObject(d.savedFile)
        var doc = file["doc"] as! [String: Any]
        var windows = doc["windows"] as! [String: Any]
        var window = windows[d.window.rawValue] as! [String: Any]
        window["sidebarWidth"] = 5000
        windows[d.window.rawValue] = window
        doc["windows"] = windows
        file["doc"] = doc
        let r = Driver(file: jsonData(file))
        XCTAssertEqual(r.view.sidebar.width, 500)
        guard case .restored(let repairs) = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssertTrue(repairs.contains { $0.contains("5000") }, "\(repairs)")
    }

    /// a user command for a window that does not exist is dropped
    func test_aUserCommandForAWindowThatDoesNotExistIsDropped() throws {
        let d = Driver()
        assertUnchanged(d.state, reduce(d.state, .user(WindowID("ghost"), .sidebar(.toggle)), d.ctx))
        let press = KeyPress(chord: KeyChord(.command, .t), phase: .down, isRepeat: false, editableFieldFocused: false)
        assertUnchanged(d.state, reduce(d.state, .key(WindowID("ghost"), KeyInput(press: press, stage: .beforePage, pressID: PressID(raw: 1))), d.ctx))
    }

    // MARK: handler groups
    /// are disjoint, so spreading them into one table cannot shadow a handler
    /// (Swift: `Work.run` switches over the top-level case, so a command reaches exactly its own area's rules; the
    /// case names below are unique and each names its own area first.)
    func test_areDisjointSoSpreadingThemIntoOneTableCannotShadowAHandler() throws {
        let names = CommandInventory.commands.map(CommandInventory.name)
        XCTAssertEqual(Set(names).count, names.count, "two samples share a case name")
        for (command, name) in zip(CommandInventory.commands, names) {
            XCTAssertEqual(name.split(separator: ".").first.map(String.init), CommandInventory.area(command), name)
        }
    }

    /// cover every UiCommand type, and every command type has a behavior test above
    func test_coverEveryUiCommandTypeAndEveryCommandTypeHasABehaviorTestAbove() throws {
        XCTAssertEqual(CommandInventory.commands.count, 236, "a Command case was added: add its sample and a behavior test")
        XCTAssertEqual(CommandInventory.events.count, 51, "a SystemEvent case was added: add its sample and a behavior test")
        let sources = try CommandInventory.testSources()
        let missing = (CommandInventory.commands.map(CommandInventory.name) + CommandInventory.events.map(CommandInventory.name))
            .filter { name in sources.range(of: CommandInventory.pattern(for: name), options: .regularExpression) == nil }
        XCTAssertEqual(missing, [], "no test dispatches these")
        // And reduce is total over every case: each sample against a rich state and against a fresh one, unknown ids
        // included, without trapping; the rich state survives a restart afterwards.
        let d = richDriver()
        for command in CommandInventory.commands { d.user(command) }
        for event in CommandInventory.events { d.system(event) }
        let r = Driver()
        for command in CommandInventory.commands { r.user(command) }
        guard case .restored = Driver(file: d.savedFile).outcome else { return XCTFail("the state after every command does not restore") }
    }

    // MARK: - electron-v1:src/domain/auto-archive-stamps-on-leaving-screen.test.ts
    // MARK: auto-archive stamps a tab as it leaves the screen
    /// a tab read for 11 hours then left with Ctrl+Tab is not archived one hour later
    func test_aTabReadFor11HoursThenLeftWithCtrlTabIsNotArchivedOneHourLater() throws {
        let d = Driver()
        let b = d.open("http://127.0.0.1:9/b")  // A leaves, B shown from T0
        d.advance(.seconds(11 * 3_600))  // read B for 11 hours
        d.system(.window(d.window, .modifiersChanged(held: [.control])))
        d.user(.tab(.cycleRecent(.next)))  // Ctrl+Tab to A
        d.system(.window(d.window, .modifiersChanged(held: [])))  // Control released: B left the screen now
        d.advance(hour + minute)  // B was last on screen 1h01m ago, under the 12h threshold
        d.system(.clockTick)
        XCTAssertTrue(d.todayIDs.contains(b))
    }

    /// a tab read for 13 hours then dropped on another space is not archived by the next sweep
    func test_aTabReadFor13HoursThenDroppedOnAnotherSpaceIsNotArchivedByTheNextSweep() throws {
        let d = Driver()
        let first = d.view.space.id
        let work = d.newSpace("Work")
        d.user(.space(.focus(first)))
        let x = d.open("http://127.0.0.1:9/x")  // shown in the first space from T0
        d.advance(.seconds(13 * 3_600))  // read X for 13 hours
        d.user(.item(.move(x, to: .space(work))))  // drag X onto Work's dock icon
        d.advance(minute)  // next sweep
        d.system(.clockTick)
        d.user(.space(.focus(work)))
        XCTAssertTrue(d.todayIDs.contains(x))
    }

    /// a tab left continuously on screen past the threshold is kept, and stamped only when it finally leaves
    func test_aTabLeftContinuouslyOnScreenPastTheThresholdIsKeptAndStampedOnlyWhenItFinally() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.advance(.seconds(13 * 3_600))  // A has been on screen the whole time
        d.system(.clockTick)
        XCTAssertTrue(d.todayIDs.contains(a))  // visible is never archived
        let b = d.open("http://127.0.0.1:9/b")  // A leaves the screen now (stamped at 13h)
        d.advance(.seconds(11 * 3_600))  // 11h since A left, under 12h
        d.system(.clockTick)
        XCTAssertTrue(d.todayIDs.contains(a))
        XCTAssertTrue(d.todayIDs.contains(b))
    }

    // MARK: - electron-v1:src/domain/background-tab-loads.test.ts
    // MARK: a background-opened tab loads
    /// .openRequested background:true marks the tab loaded and keeps focus on the opener
    func test_openrequestedBackgroundTrueMarksTheTabLoadedAndKeepsFocusOnTheOpener() throws {
        let d = Driver()
        let opener = d.paneIDs[0]
        d.page(opener, .openRequested(url("http://127.0.0.1:9/bg"), .backgroundTab))
        let added = d.loadedIDs.subtracting([opener])
        XCTAssertEqual(added.count, 1)
        let bg = try XCTUnwrap(added.first)
        // Focus stays on the opener (it is still the shown pane).
        XCTAssertEqual(d.paneIDs, [opener])
        XCTAssertEqual(d.view.focus, .page(PageID(window: d.window, item: opener)))
        // The engine is told to create its page, with its url.
        var expected = PageSpec(id: PageID(window: d.window, item: bg), initialURL: url("http://127.0.0.1:9/bg"), context: .profile(.default))
        expected.websitePolicy.visible = false
        XCTAssertEqual(d.snapshot.pages.first { $0.id == PageID(window: d.window, item: bg) }, expected)
    }

    /// a foreground .openRequested still focuses the new tab and loads it
    func test_aForegroundOpenRequestedStillFocusesTheNewTabAndLoadsIt() throws {
        let d = Driver()
        let opener = d.paneIDs[0]
        d.page(opener, .openRequested(url("http://127.0.0.1:9/fg"), .foregroundTab))
        let shown = d.paneIDs[0]
        XCTAssertNotEqual(shown, opener)
        XCTAssertTrue(d.loadedIDs.contains(shown))
        XCTAssertEqual(d.row(shown)?.url, url("http://127.0.0.1:9/fg"))
    }

    /// restore stays lazy: only the shown tab is loaded after a restart, not every stored tab
    func test_restoreStaysLazyOnlyTheShownTabIsLoadedAfterARestartNotEveryStoredTab() throws {
        let d = Driver()
        let opener = d.paneIDs[0]
        d.page(opener, .openRequested(url("http://127.0.0.1:9/bg"), .backgroundTab))
        XCTAssertEqual(d.snapshot.pages.count, 2)
        let next = Driver(file: d.savedFile)
        // The shown tab loads; the previously-background tab is not shown and is not loaded at launch.
        XCTAssertEqual(next.snapshot.pages.map(\.id.item), next.paneIDs)
        XCTAssertEqual(next.paneIDs, [opener])
    }

    // MARK: - electron-v1:src/domain/empty-split-pane-not-archived.test.ts
    // MARK: empty split pane is not archived
    /// closing the focused empty pane with Ctrl+Shift+- archives nothing
    func test_closingTheFocusedEmptyPaneWithCtrlShiftArchivesNothing() throws {
        let d = Driver()
        d.user(.split(.addPane))  // the start tab becomes a split of [tab, empty pane], empty pane focused
        d.user(.commandBar(.dismiss))  // Escape: the pane stays empty (no URL)
        XCTAssertEqual(d.view.content.panes.map(\.content).last, .blank)
        d.user(.split(.closePane))  // close the focused empty pane
        XCTAssertEqual(d.archive(), [])
        XCTAssertNil(d.view.content.split)  // the split dissolved back to the one real tab
        XCTAssertEqual(d.view.space.today.rows.map(\.kind), [.tab])
    }

    /// clearing Today with an off-screen empty split pane archives only tabs that have a URL
    func test_clearingTodayWithAnOffScreenEmptySplitPaneArchivesOnlyTabsThatHaveAURL() throws {
        let d = Driver()
        d.user(.split(.addPane))
        d.user(.commandBar(.dismiss))  // an empty pane remains in the split, which is on screen
        let b = d.open("http://127.0.0.1:9/b")  // the split leaves the screen
        d.advance(.seconds(13 * 3_600))
        d.system(.clockTick)  // auto-archive sweeps the idle split (one real tab + one empty pane) as one item
        let entries = d.archive()
        XCTAssertTrue(entries.allSatisfy { $0.url != nil })
        XCTAssertEqual(entries.map(\.url), [start])
        XCTAssertEqual(d.todayIDs, [b])
    }

    // MARK: - electron-v1:src/domain/sidebar-peek-keeps-archive.test.ts
    // MARK: peek and resize keep the archive open
    /// hide the sidebar, open the archive, peek: the archive stays open and the sidebar floats over it
    func test_hideTheSidebarOpenTheArchivePeekTheArchiveStaysOpenAndTheSidebarFloatsOver() throws {
        let d = Driver()
        d.user(.sidebar(.toggle))
        d.user(.library(.open(.archive)))
        guard case .library? = d.view.overlay else { return XCTFail("no archive") }
        d.user(.sidebar(.peek(true)))
        XCTAssertTrue(d.view.sidebar.peek)
        guard case .library? = d.view.overlay else { return XCTFail("the peek closed the archive") }
    }

    /// dragging the resize handle while the archive is open keeps it open
    func test_draggingTheResizeHandleWhileTheArchiveIsOpenKeepsItOpen() throws {
        let d = Driver()
        d.user(.library(.open(.archive)))
        d.user(.sidebar(.resize(width: 300)))
        XCTAssertEqual(d.view.sidebar.width, 300)
        guard case .library? = d.view.overlay else { return XCTFail("the resize closed the archive") }
    }

    /// a resize still keeps an open command bar, while toggling the sidebar closes it
    func test_aResizeStillKeepsAnOpenCommandBarWhileTogglingTheSidebarClosesIt() throws {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        d.user(.sidebar(.resize(width: 300)))
        XCTAssertNotNil(d.bar)
        d.user(.sidebar(.toggle))
        XCTAssertNil(d.view.overlay)
    }

    // MARK: - electron-v1:src/domain/space-fallback-title.test.ts
    // MARK: fallback space title
    /// a fresh profile shows "Space 1" but stores an empty title
    func test_aFreshProfileShowsSpace1ButStoresAnEmptyTitle() throws {
        let d = Driver()
        XCTAssertEqual(d.view.dock.map(\.title), ["Space 1"])
        XCTAssertEqual(d.view.space.title, "Space 1")
        let spaces = d.savedDoc["spaces"] as? [String: [String: Any]]
        XCTAssertEqual(spaces?.values.map { $0["title"] as? String }, [""])
    }

    /// deleting a space and creating another does not duplicate "Space N"
    func test_deletingASpaceAndCreatingAnotherDoesNotDuplicateSpaceN() throws {
        let d = Driver()
        d.newSpace("")
        d.newSpace("")
        XCTAssertEqual(d.view.dock.map(\.title), ["Space 1", "Space 2", "Space 3"])
        d.user(.space(.delete(d.view.dock[1].id)))
        XCTAssertEqual(d.view.dock.map(\.title), ["Space 1", "Space 2"])
        d.newSpace("")
        XCTAssertEqual(d.view.dock.map(\.title), ["Space 1", "Space 2", "Space 3"])
    }

    /// a named space keeps its name; the archive fromSpaceTitle also derives "Space N"
    func test_aNamedSpaceKeepsItsNameTheArchiveFromSpaceTitleAlsoDerivesSpaceN() throws {
        let d = Driver()
        // Archive the start tab; its source space has an empty stored title shown as "Space 1".
        d.user(.tab(.close(.item(d.paneIDs[0]))))
        XCTAssertEqual(d.archive().first?.fromSpaceTitle, "Space 1")
        d.newSpace("Work")
        XCTAssertEqual(d.view.dock.map(\.title), ["Space 1", "Work"])
    }
}
