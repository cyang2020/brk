import BrkBase
import XCTest
@testable import BrkDomain

final class SplitToolsTests: XCTestCase {
    func testTargetedClosePreservesForegroundAndRejectsStandaloneTarget() throws {
        let d = Driver()
        d.user(.split(.addPane)); d.user(.commandBar(.submit("https://fixture.example/pane")))
        let pane = d.paneIDs[1]
        let foreground = d.open("https://fixture.example/foreground")
        let unchanged = d.savedFile
        d.user(.split(.closePaneAt(foreground)))
        XCTAssertEqual(d.savedFile, unchanged)
        d.user(.split(.closePaneAt(pane)))
        XCTAssertEqual(d.paneIDs, [foreground])
        XCTAssertFalse(d.snapshot.pages.contains { $0.id.item == pane })
    }

    func testFindRejectsAContentDropCapturedBeforeItsBarOpened() throws {
        let d = Driver(), target = d.paneIDs[0]
        let source = d.open("https://fixture.example/source")
        d.user(.tab(.focus(target)))
        let offered = try XCTUnwrap(d.view.content.drop?.offers[source])
        d.user(.find(.open(replace: false)))
        XCTAssertNotNil(d.view.find)
        XCTAssertNil(d.view.content.drop)
        d.user(.split(.dropTab(offered, edge: .right)))
        XCTAssertNil(d.view.content.split)
        XCTAssertEqual(d.paneIDs, [target])
    }

    private func offer(_ d: Driver, _ source: ItemID, _ target: ItemID) -> SplitDropOffer {
        let tree = d.state.tree(of: d.window)!
        let orientation: SplitOrientation = if case .split(let s)? = tree[target]?.body { s.orientation } else { .horizontal }
        return SplitDropOffer(window: d.window, source: source, target: target, sourceParent: tree[source]!.parent!,
                              targetParent: tree[target]!.parent!, panes: d.state.panes(of: target), orientation: orientation,
                              context: d.state.browsingContext(of: source))
    }
    private func four(_ d: Driver) {
        for i in 2...4 {
            d.user(.split(.addPane))
            d.user(.commandBar(.submit("https://fixture.example/\(i)")))
            d.commitRequested()
        }
    }

    func testExpansionIsLocalReversibleAndDoesNotChangePageDemandOrSavedData() throws {
        let d = Driver()
        four(d)
        let split = try XCTUnwrap(d.view.content.split)
        d.user(.window(.new))
        let other = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window })
        d.user(.tab(.focus(d.paneIDs[0])), in: other)
        let pages = d.snapshot.pages, saved = d.savedFile
        let observations = d.snapshot.observations
        d.user(.split(.toggleExpanded))
        XCTAssertTrue(d.view.content.expanded)
        XCTAssertFalse(d.view(of: other).content.expanded)
        let visible = Set(d.snapshot.windows.values.flatMap { window in
            window.content.presentedPanes.compactMap { pane -> PageID? in
                if case .page(let id) = pane.content { return id }; return nil
            }
        })
        let expected = pages.map { page -> PageSpec in
            var page = page
            page.websitePolicy.visible = visible.contains(page.id)
            return page
        }
        XCTAssertEqual(d.snapshot.pages, expected, "Expansion changes visibility while preserving each native request")
        XCTAssertEqual(d.snapshot.observations, observations)
        XCTAssertEqual(d.savedFile, saved)
        d.user(.split(.focusPane(1)))
        XCTAssertTrue(d.view.content.expanded)
        XCTAssertEqual(d.view.content.split, split)
        XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, d.paneIDs[0])
        d.user(.split(.restore))
        XCTAssertFalse(d.view.content.expanded)
        XCTAssertFalse(Driver(file: d.savedFile).view.content.expanded)
    }

    func testSeparateAllPreservesOrderPinAddressesLiveIdentityAndEachWindowsFocus() throws {
        let d = Driver()
        four(d)
        let panes = d.paneIDs
        d.user(.tab(.togglePin(.focused)))
        let homes = panes.map { d.state.tab($0)?.pinnedURL }
        d.user(.window(.new))
        let other = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window })
        d.user(.tab(.focus(panes[1])), in: other)
        d.page(panes[1], .committed(url("https://fixture.example/other-window")), in: other)
        let browser = d.snapshot.observations[PageID(window: other, item: panes[1])]?.browser
        d.user(.split(.separateAll))
        XCTAssertEqual(d.pinnedIDs, panes)
        XCTAssertNil(d.view.content.split)
        XCTAssertEqual(d.paneIDs, [panes[3]])
        XCTAssertEqual(d.view(of: other).content.panes.map(\.tab), [panes[1]])
        XCTAssertEqual(d.view(of: other).urlPill.text, "fixture.example/other-window")
        XCTAssertEqual(panes.map { d.state.tab($0)?.pinnedURL }, homes)
        XCTAssertEqual(d.snapshot.observations[PageID(window: other, item: panes[1])]?.browser, browser)
        XCTAssertEqual(Driver(file: d.savedFile).pinnedIDs, panes)
        XCTAssertTrue(d.archive().isEmpty)
    }

    func testSeparateOneKeepsOtherWindowsOnTheirOwnSelectedPane() throws {
        let d = Driver()
        four(d)
        let panes = d.paneIDs, split = try XCTUnwrap(d.view.content.split)
        d.user(.window(.new))
        let other = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window })
        d.user(.tab(.focus(panes[0])), in: other)
        d.user(.split(.separatePane(.item(panes[3]))))
        XCTAssertEqual(d.paneIDs, [panes[3]])
        XCTAssertEqual(d.view(of: other).content.split, split)
        XCTAssertEqual(d.view(of: other).content.panes.first(where: \.focused)?.tab, panes[0])
        XCTAssertEqual(d.todayIDs, [split, panes[3]])
    }

    func testPaneKeysHaveDistinctCommandsNoWrapAndRespectRemaps() {
        let d = Driver()
        four(d)
        let panes = d.paneIDs
        d.key(KeyChord([.control, .option], .one), stage: .beforePage, pressID: 1)
        XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, panes[0])
        d.user(.split(.stepPane(.previous)))
        XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, panes[0])
        d.user(.split(.stepPane(.next)))
        XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, panes[1])
        d.user(.split(.focusPane(9)))
        XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, panes[1])
        d.user(.settings(.shortcuts(.setChord(.splitPane4, KeyChord([.control, .option], .p)))))
        d.key(KeyChord([.control, .option], .p), stage: .beforePage, pressID: 2)
        XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, panes[3])
        XCTAssertEqual(ActionID.selectNextTab.spec.command, .tab(.step(.next)))
        XCTAssertFalse(d.view.enabledActions.contains(.nextSplitPane))
    }

    func testContentDropKeepsItemsAndBrowserTokensAndOrdersEveryEdge() throws {
        for edge in SplitEdge.allCases {
            let d = Driver(), target = Driver.startURL
            let original = d.paneIDs[0]
            let source = d.open("https://fixture.example/source")
            d.user(.tab(.focus(original)))
            let before = d.snapshot.observations.mapValues(\.browser)
            d.user(.split(.dropTab(offer(d, source, original), edge: edge)))
            XCTAssertEqual(d.paneIDs, edge.isLeading ? [source, original] : [original, source])
            XCTAssertEqual(d.view.content.orientation, edge.orientation)
            XCTAssertEqual(d.snapshot.observations.mapValues(\.browser), before)
            XCTAssertEqual(d.state.address(of: original, in: d.window, for: .savedDocument), target)
            XCTAssertEqual(d.state.address(of: source, in: d.window, for: .savedDocument), url("https://fixture.example/source"))
        }
    }

    /// Arc, Q17-drop-favorite-right-half and -then-separated: the split holds a new tab, the tile stays, and the new tab
    /// stays in Today when the split is taken apart.
    func testAFavoriteDroppedOnASlotOpensANewTabAndKeepsItsTile() throws {
        let d = Driver()
        let original = d.paneIDs[0], favorite = d.open("https://fixture.example/apple")
        d.commitRequested()
        d.user(.tab(.focus(original)))
        d.user(.item(.move(favorite, to: .into(parent: d.view.favorites.root, index: 0))))
        let rows = d.view.space.today.rows.count
        d.user(.split(.dropTab(offer(d, favorite, original), edge: .right)))
        XCTAssertEqual(d.view.favorites.tiles.map(\.id), [favorite])
        XCTAssertEqual(d.paneIDs.first, original)
        let new = try XCTUnwrap(d.paneIDs.last)
        XCTAssertNotEqual(new, favorite)
        XCTAssertEqual(d.view.content.panes.last?.focused, true)
        d.commitRequested()
        guard case .split(let row)? = d.view.space.today.rows.first(where: { $0.id == d.view.content.split }) else { return XCTFail("no split row") }
        XCTAssertEqual(row.panes.last?.url?.absoluteString, "https://fixture.example/apple")
        XCTAssertEqual(d.view.space.today.rows.count, rows, "the split takes the place of the row it joined")
        d.user(.split(.separateAll))
        XCTAssertTrue(d.view.space.today.rows.contains { $0.id == new }, "the new tab is not in Today")
        XCTAssertEqual(d.view.favorites.tiles.map(\.id), [favorite])
    }

    /// A slot between two panes: the tab takes that index in the split.
    func testADropBetweenPanesInsertsAtTheIndex() throws {
        let d = Driver()
        let first = d.paneIDs[0]
        d.user(.split(.addPane)); d.user(.commandBar(.submit("https://fixture.example/2"))); d.commitRequested()
        let second = d.paneIDs[1]
        let split = try XCTUnwrap(d.view.content.split)
        let extra = d.open("https://fixture.example/extra")
        d.user(.tab(.focus(split)))
        d.user(.split(.dropTab(offer(d, extra, split), edge: .right, at: 1)))
        XCTAssertEqual(d.paneIDs, [first, extra, second])
    }

    func testDropRefusesFavoritesProfilesStaleTargetsAndFullSplits() throws {
        let d = Driver()
        let original = d.paneIDs[0], source = d.open("https://fixture.example/source")
        d.user(.tab(.focus(original)))
        d.user(.item(.move(source, to: .into(parent: d.view.favorites.root, index: 0))))
        // A Favorite on the page offers the same slots (Q13-e); the drop keeps it and splits with a new tab at its address.
        XCTAssertNotNil(d.view.content.drop?.offers[source], "a Favorites tile offered no content drop")
        d.user(.split(.dropTab(offer(d, source, original), edge: .right)))
        XCTAssertTrue(d.view.favorites.tiles.contains { $0.id == source })
        XCTAssertEqual(d.view.content.panes.count, 2)
        XCTAssertFalse(d.view.content.panes.contains { $0.tab == source })
        var before = d.state
        let split = try XCTUnwrap(d.view.content.split)
        for n in 3...4 { d.user(.split(.addPane)); d.user(.commandBar(.submit("https://fixture.example/\(n)"))); d.commitRequested() }
        let extra = d.open("https://fixture.example/extra")
        d.user(.tab(.focus(split)))
        before = d.state
        assertUnchanged(before, d.user(.split(.dropTab(offer(d, extra, split), edge: .top))))
        assertUnchanged(d.state, d.user(.split(.dropTab(offer(d, extra, original), edge: .right))))
        XCTAssertEqual(d.paneIDs.count, 4)
        XCTAssertTrue(d.view.enabledActions.contains(.addSplitView), "a full split answers the shortcut with Cannot Add New Pane")
    }

    /// Arc, Q17-drop-pinned-right-half and -then-separated: a pinned tab released on a slot stays pinned; the split, where
    /// the Today tab was, holds a new Today tab at its address, on the right and focused; apart, it is a row of Today.
    func testAPinnedTabDroppedOnASlotOpensANewTabAndStaysPinned() throws {
        let d = Driver()
        let original = d.paneIDs[0], source = d.open("https://fixture.example/pinned")
        d.commitRequested()
        d.user(.item(.move(source, to: .into(parent: d.view.space.pinned.root, index: 0))))
        d.user(.tab(.focus(original)))
        let offered = try XCTUnwrap(d.view.content.drop?.offers[source], "a pinned tab was not offered the content drop")
        let rows = d.view.space.today.rows.count
        d.user(.split(.dropTab(offered, edge: .right)))
        XCTAssertEqual(d.view.space.pinned.rows.map(\.id), [source], "the pinned tab moved")
        XCTAssertEqual(d.paneIDs.first, original)
        let new = try XCTUnwrap(d.paneIDs.last)
        XCTAssertNotEqual(new, source)
        XCTAssertEqual(d.view.content.panes.last?.focused, true)
        let split = try XCTUnwrap(d.view.content.split)
        d.commitRequested()
        guard case .split(let row)? = d.view.space.today.rows.first(where: { $0.id == split }) else { return XCTFail("the split is not in Today") }
        XCTAssertEqual(row.panes.last?.url, url("https://fixture.example/pinned"))
        XCTAssertEqual(d.view.space.today.rows.count, rows, "the split takes the place of the row it joined")
        d.user(.split(.separateAll))
        XCTAssertTrue(d.view.space.today.rows.contains { $0.id == new }, "the new tab is not in Today")
        XCTAssertEqual(d.view.space.pinned.rows.map(\.id), [source])
    }

    /// A tab in a pinned folder follows the same rule (P23-d shows the hold; the release has not been seen on Arc).
    func testAPinnedFolderTabDroppedOnASlotStaysInItsFolder() throws {
        let d = Driver()
        let original = d.paneIDs[0], source = d.open("https://fixture.example/pinned")
        d.commitRequested()
        d.user(.item(.newFolder))
        let folder = try XCTUnwrap(d.view.space.pinned.rows.first?.id)
        d.user(.item(.move(source, to: .into(parent: folder, index: 0))))
        d.user(.tab(.focus(original)))
        d.user(.split(.dropTab(try XCTUnwrap(d.view.content.drop?.offers[source]), edge: .left)))
        XCTAssertEqual(d.paneIDs.count, 2)
        XCTAssertEqual(d.paneIDs.last, original)
        XCTAssertNotEqual(d.paneIDs.first, source)
        guard case .folder(let pinnedFolder)? = d.view.space.pinned.rows.first(where: { $0.id == folder }) else { return XCTFail("folder lost") }
        XCTAssertEqual(pinnedFolder.children.map(\.id), [source])
    }

    // MARK: A drop on a framed pane (Arc, Q17 second probe)

    /// A split [first, second, ...] of `count` panes in Today and the shown one, with an extra Today tab `source` above it.
    private func splitAndSource(_ d: Driver, count: Int = 2) throws -> (split: ItemID, panes: [ItemID], source: ItemID) {
        let source = d.paneIDs[0]
        let first = d.open("https://fixture.example/first")
        d.commitRequested()
        for n in 2...count {
            d.user(.split(.addPane)); d.user(.commandBar(.submit("https://fixture.example/\(n)"))); d.commitRequested()
        }
        XCTAssertEqual(d.paneIDs.first, first)
        return (try XCTUnwrap(d.view.content.split), d.paneIDs, source)
    }

    func testADropOnAFramedPaneReplacesItAndTheOldTabFollowsTheSplit() throws {
        for pane in 0...2 {
            let d = Driver()
            let (split, panes, source) = try splitAndSource(d, count: 3)
            d.user(.split(.setOrientation(split, .vertical)))
            d.user(.split(.resize(split, fractions: [panes[0]: 0.2, panes[1]: 0.3, panes[2]: 0.5])))
            let shares = d.view.content.panes.map(\.fraction)
            let observations = d.snapshot.observations
            d.user(.split(.replacePane(try XCTUnwrap(d.view.content.drop?.offers[source]), pane: pane)))
            var expected = panes
            expected[pane] = source
            XCTAssertEqual(d.paneIDs, expected, "pane \(pane)")
            XCTAssertEqual(d.view.content.split, split, "the split changed")
            XCTAssertEqual(d.view.content.orientation, .vertical)
            XCTAssertEqual(d.view.content.panes.map(\.fraction), shares, "the shares changed")
            XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, source)
            let rows = d.view.space.today.rows.map(\.id)
            let at = try XCTUnwrap(rows.firstIndex(of: split))
            XCTAssertEqual(rows[at + 1], panes[pane], "the old tab is not right after the split")
            XCTAssertFalse(rows.contains(source))
            for (page, observation) in observations where page.item == panes[pane] {
                XCTAssertEqual(d.snapshot.observations[page], observation, "the old tab's page changed")
            }
        }
    }

    /// Arc's own case: two panes, the tab dragged from above the split, the right pane replaced: the split must not dissolve.
    func testADropOnAPaneOfTwoKeepsTheSplitAndItsPlace() throws {
        let d = Driver()
        let (split, panes, source) = try splitAndSource(d)
        let before = d.view.space.today.rows.map(\.id)
        d.user(.split(.replacePane(try XCTUnwrap(d.view.content.drop?.offers[source]), pane: 1)))
        XCTAssertEqual(d.paneIDs, [panes[0], source])
        XCTAssertEqual(d.view.content.split, split)
        XCTAssertEqual(d.view.space.today.rows.map(\.id), before.filter { $0 != source }.flatMap { $0 == split ? [split, panes[1]] : [$0] })
        d.user(.split(.separateAll))
        XCTAssertEqual(d.view.space.today.rows.map(\.id).filter { [panes[0], source, panes[1]].contains($0) }, [panes[0], source, panes[1]])
    }

    func testAFavoriteOrPinnedTabDroppedOnAPaneOpensANewTabAndStaysWhereItIs() throws {
        for favorite in [true, false] {
            let d = Driver()
            let (_, panes, source) = try splitAndSource(d)
            let root = favorite ? d.view.favorites.root : d.view.space.pinned.root
            d.user(.item(.move(source, to: .into(parent: root, index: 0))))
            d.user(.split(.replacePane(try XCTUnwrap(d.view.content.drop?.offers[source]), pane: 1)))
            XCTAssertEqual(favorite ? d.view.favorites.tiles.map(\.id) : d.view.space.pinned.rows.map(\.id), [source], "it moved")
            XCTAssertEqual(d.paneIDs.first, panes[0])
            let new = try XCTUnwrap(d.paneIDs.last)
            XCTAssertNotEqual(new, source)
            XCTAssertNotEqual(new, panes[1])
            XCTAssertEqual(d.view.content.panes.last?.focused, true)
            XCTAssertTrue(d.view.space.today.rows.contains { $0.id == panes[1] })
        }
    }

    /// A pinned split keeps its section: the old tab stays pinned, right after it, and the Today tab that took its place is pinned now.
    func testADropOnAPaneOfAPinnedSplitKeepsTheOldTabPinned() throws {
        let d = Driver()
        let (split, panes, source) = try splitAndSource(d)
        d.user(.tab(.togglePin(.focused)))
        XCTAssertEqual(d.view.space.pinned.rows.map(\.id), [split])
        d.user(.split(.replacePane(try XCTUnwrap(d.view.content.drop?.offers[source]), pane: 0)))
        XCTAssertEqual(d.paneIDs, [source, panes[1]])
        XCTAssertEqual(d.view.space.pinned.rows.map(\.id), [split, panes[0]])
        XCTAssertNotNil(d.state.tab(source)?.pinnedURL, "the new pinned pane has no pinned address")
    }

    /// Arc only frames a full split: no slot, but a pane can be replaced and the count stays four.
    func testAFullSplitTakesNoSlotButAPaneCanBeReplaced() throws {
        let d = Driver()
        let (split, panes, source) = try splitAndSource(d, count: 4)
        let offered = try XCTUnwrap(d.view.content.drop?.offers[source], "a full split offered nothing")
        let before = d.state
        assertUnchanged(before, d.user(.split(.dropTab(offered, edge: .right))))
        d.user(.split(.replacePane(offered, pane: 2)))
        XCTAssertEqual(d.paneIDs, [panes[0], panes[1], source, panes[3]])
        XCTAssertEqual(d.view.content.split, split)
        XCTAssertTrue(d.view.space.today.rows.contains { $0.id == panes[2] })
    }

    func testADropOnAPaneRefusesStaleOffersAndBadIndexes() throws {
        let d = Driver()
        let (_, panes, source) = try splitAndSource(d)
        let offered = try XCTUnwrap(d.view.content.drop?.offers[source])
        let before = d.state
        assertUnchanged(before, d.user(.split(.replacePane(offered, pane: 2))))
        assertUnchanged(before, d.user(.split(.replacePane(offered, pane: -1))))
        // Another page shown: the offer no longer names what the window shows.
        d.user(.tab(.focus(source)))
        let later = d.state
        assertUnchanged(later, d.user(.split(.replacePane(offered, pane: 0))))
        XCTAssertEqual(d.paneIDs, [source])
        d.user(.tab(.focus(panes[0])))
        XCTAssertEqual(d.paneIDs, panes)
    }

    /// Arc's P23-e/f: a Today tab dropped on the middle of another Today tab's row makes one split where the target
    /// was, the dragged tab on the left and focused, shown in the window whatever was shown before.
    func testJoinRowSplitsInTheTargetsPlaceWithTheDraggedTabLeading() throws {
        let d = Driver()
        let start = d.paneIDs[0]
        let a = d.open("https://fixture.example/a"), b = d.open("https://fixture.example/b"), c = d.open("https://fixture.example/c")
        XCTAssertEqual(d.todayIDs, [c, b, a, start])
        d.user(.tab(.focus(start)))
        d.user(.split(.joinRow(c, onto: a)))
        let split = try XCTUnwrap(d.view.content.split)
        XCTAssertEqual(d.todayIDs, [b, split, start], "the split takes the target's place")
        XCTAssertEqual(d.paneIDs, [c, a])
        XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, c)
        XCTAssertEqual(d.view.content.orientation, .horizontal)
        XCTAssertEqual(d.state.address(of: a, in: d.window, for: .savedDocument), url("https://fixture.example/a"))
    }

    /// The same drop from a pinned folder's tab onto a Today tab: the split sits in Today where the target was and the
    /// folder is left empty; onto a pinned tab, the split stays in Pinned.
    func testJoinRowTakesAPinnedFolderTabBesideATodayTab() throws {
        let d = Driver()
        let target = d.paneIDs[0], source = d.open("https://fixture.example/pinned"), other = d.open("https://fixture.example/other")
        d.user(.item(.newFolder))
        let folder = try XCTUnwrap(d.view.space.pinned.rows.first?.id)
        d.user(.item(.move(source, to: .into(parent: folder, index: 0))))
        d.user(.split(.joinRow(source, onto: target)))
        let split = try XCTUnwrap(d.view.content.split)
        XCTAssertEqual(d.todayIDs, [other, split])
        XCTAssertEqual(d.paneIDs, [source, target])
        guard case .folder(let pinnedFolder)? = d.view.space.pinned.rows.first(where: { $0.id == folder }) else { return XCTFail("folder lost") }
        XCTAssertTrue(pinnedFolder.children.isEmpty)
        d.user(.split(.separateAll))
        d.user(.item(.move(target, to: .into(parent: d.view.space.pinned.root, index: 1))))
        d.user(.split(.joinRow(other, onto: target)))
        let pinnedSplit = try XCTUnwrap(d.view.content.split)
        XCTAssertEqual(d.pinnedIDs, [folder, pinnedSplit], "onto a pinned tab the split stays pinned")
        XCTAssertEqual(d.paneIDs, [other, target])
    }

    /// Arc's Q15-d and P23-f: the tab takes the side it was dropped on and the focus; the split sits where the target was.
    func testJoinRowTakesTheSideItWasDroppedOn() throws {
        for (index, panes) in [(0, ["source", "target"]), (1, ["target", "source"])] {
            let d = Driver()
            let start = d.paneIDs[0]
            let target = d.open("https://fixture.example/target"), other = d.open("https://fixture.example/other"), source = d.open("https://fixture.example/source")
            d.user(.split(.joinRow(source, onto: target, at: index)))
            let split = try XCTUnwrap(d.view.content.split)
            XCTAssertEqual(d.todayIDs, [other, split, start])
            XCTAssertEqual(d.paneIDs, panes.map { $0 == "source" ? source : target }, "dropped at \(index)")
            XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, source)
            XCTAssertEqual(d.view.content.orientation, .horizontal)
        }
    }

    /// Arc's Q15-f and Q15-g: dropped on a split row at its left end the tab is the first pane, at its right end the last,
    /// focused both ways. Between two panes it goes between them (inferred: Arc's middle was not tried).
    func testJoinRowOntoASplitRowTakesThePlaceUnderThePointer() throws {
        for (index, order) in [(0, [2, 0, 1]), (1, [0, 2, 1]), (2, [0, 1, 2])] {
            let d = Driver()
            let a = d.paneIDs[0], b = d.open("https://fixture.example/b"), c = d.open("https://fixture.example/c")
            d.user(.split(.joinRow(b, onto: a, at: 1)))
            let split = try XCTUnwrap(d.view.content.split)
            d.user(.split(.joinRow(c, onto: split, at: index)))
            XCTAssertEqual(d.view.content.split, split, "a new split instead of the same one")
            XCTAssertEqual(d.paneIDs, order.map { [a, b, c][$0] }, "dropped at \(index)")
            XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, c)
            XCTAssertEqual(d.todayIDs, [split])
        }
    }

    /// A stacked split stays stacked (what Arc does there was not seen); a full split takes no more.
    func testJoinRowKeepsAStackedSplitAndRefusesAFullOne() throws {
        let d = Driver()
        let a = d.paneIDs[0], b = d.open("https://fixture.example/b"), c = d.open("https://fixture.example/c")
        d.user(.split(.joinRow(b, onto: a, at: 1)))
        let split = try XCTUnwrap(d.view.content.split)
        d.user(.split(.orientCurrent(.vertical)))
        d.user(.split(.joinRow(c, onto: split, at: 2)))
        XCTAssertEqual(d.paneIDs, [a, b, c])
        XCTAssertEqual(d.view.content.orientation, .vertical)
        let e = d.open("https://fixture.example/e"), f = d.open("https://fixture.example/f")
        d.user(.split(.joinRow(e, onto: split, at: 3)))
        XCTAssertEqual(d.paneIDs, [a, b, c, e])
        assertUnchanged(d.state, d.user(.split(.joinRow(f, onto: split, at: 4))))
    }

    /// Refused, changing nothing: the tab onto itself, a Favorites tab either way, a folder as the target, a pane as the
    /// source, and a tab of another space.
    func testJoinRowRefusesWhatGroupTabRefuses() throws {
        let d = Driver()
        let start = d.paneIDs[0], a = d.open("https://fixture.example/a"), fav = d.open("https://fixture.example/fav")
        let b = d.open("https://fixture.example/b")
        d.user(.item(.move(fav, to: .into(parent: d.view.favorites.root, index: 0))))
        d.user(.item(.newFolder))
        let folder = try XCTUnwrap(d.view.space.pinned.rows.first?.id)
        assertUnchanged(d.state, d.user(.split(.joinRow(a, onto: a))))
        assertUnchanged(d.state, d.user(.split(.joinRow(fav, onto: a))))
        assertUnchanged(d.state, d.user(.split(.joinRow(a, onto: fav))))
        assertUnchanged(d.state, d.user(.split(.joinRow(a, onto: folder))))
        d.user(.split(.joinRow(a, onto: start)))
        _ = try XCTUnwrap(d.view.content.split)
        assertUnchanged(d.state, d.user(.split(.joinRow(a, onto: b))))
        let other = d.open("https://fixture.example/other")
        d.newSpace("Work")
        let away = d.open("https://fixture.example/away")
        assertUnchanged(d.state, d.user(.split(.joinRow(away, onto: other))))
    }

    /// Arc's split menu: Move Left / Right trade the focused pane with its neighbour (no-op at the ends), Add Left
    /// Split puts an empty pane before the focused one and opens the command bar for it.
    func testSplitMenuMovesThePaneAndAddsBeforeIt() throws {
        let d = Driver()
        d.user(.split(.addPane)); d.user(.commandBar(.submit("https://fixture.example/right"))); d.commitRequested()
        let panes = d.paneIDs
        XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, panes[1])
        let unchanged = d.state
        assertUnchanged(unchanged, d.user(.split(.movePane(.next))))
        d.user(.split(.movePane(.previous)))
        XCTAssertEqual(d.paneIDs, [panes[1], panes[0]])
        XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, panes[1])
        d.user(.split(.movePane(.next)))
        XCTAssertEqual(d.paneIDs, panes)
        d.user(.split(.addPaneBefore))
        XCTAssertEqual(d.paneIDs.count, 3)
        XCTAssertEqual(Array(d.paneIDs.prefix(1)), [panes[0]])
        XCTAssertEqual(d.paneIDs[2], panes[1])
        XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, d.paneIDs[1])
        XCTAssertNotNil(d.bar)
        // On a single tab, the empty pane goes first.
        let single = Driver(), tab = single.paneIDs[0]
        single.user(.split(.addPaneBefore))
        XCTAssertEqual(single.paneIDs.count, 2)
        XCTAssertEqual(single.paneIDs[1], tab)
    }

    func testPrivateSplitsStayInTheirOwnerAndNeverPersistOrArchive() throws {
        let d = Driver(), publicPane = Driver.startURL
        d.user(.window(.newIncognito))
        let owner = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.commandBar(.submit("https://private.example/one")), in: owner)
        d.user(.split(.addPane), in: owner)
        d.user(.commandBar(.submit("https://private.example/two")), in: owner)
        XCTAssertEqual(d.view(of: owner).content.panes.count, 2)
        let split = try XCTUnwrap(d.view(of: owner).content.split)
        assertUnchanged(d.state, d.user(.split(.setOrientation(split, .vertical))))
        d.user(.split(.orientCurrent(.vertical)), in: owner)
        d.user(.split(.closePane), in: owner)
        XCTAssertNil(d.view(of: owner).content.split)
        XCTAssertEqual(d.view(of: owner).content.panes.count, 1)
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("private.example"))
        XCTAssertTrue(d.archive().isEmpty)
        XCTAssertEqual(d.view.urlPill.text, displayURL(publicPane))
    }

    func testOldV3FilesNeedNoNewStoredFieldsAndOrientationAndFractionsRestore() throws {
        let d = Driver()
        four(d)
        let split = try XCTUnwrap(d.view.content.split)
        d.user(.split(.resize(split, fractions: Dictionary(uniqueKeysWithValues: zip(d.paneIDs, [0.1, 0.2, 0.3, 0.4])))))
        d.user(.split(.orientCurrent(.vertical)))
        let restored = Driver(file: d.savedFile)
        XCTAssertEqual(restored.view.content.orientation, .vertical)
        XCTAssertEqual(restored.view.content.panes, d.view.content.panes)
        XCTAssertEqual(restored.saved["version"] as? Int, 3)
    }

    func testStaleOfferCannotDismissAnOverlayOrApplyAfterStructureChanges() throws {
        let d = Driver(), target = Driver.startURL
        let original = d.paneIDs[0], source = d.open("https://fixture.example/source")
        d.user(.tab(.focus(original)))
        let oldOffer = try XCTUnwrap(d.view.content.drop?.offers[source])
        d.user(.commandBar(.open(.newTab)))
        assertUnchanged(d.state, d.user(.split(.dropTab(oldOffer, edge: .right))))
        XCTAssertNotNil(d.bar)
        d.user(.commandBar(.dismiss))
        d.user(.split(.addPane)); d.user(.commandBar(.dismiss))
        assertUnchanged(d.state, d.user(.split(.dropTab(oldOffer, edge: .right))))
        XCTAssertEqual(d.state.address(of: original, in: d.window, for: .savedDocument), target)
    }

    func testHiddenExpandedPaneCannotStealFocusWithALateCallback() {
        let d = Driver()
        four(d)
        let hidden = d.paneIDs[0], current = d.paneIDs[3]
        d.user(.split(.toggleExpanded))
        d.page(hidden, .gainedFocus)
        XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, current)
        XCTAssertEqual(d.view.content.presentedPanes.map(\.tab), [current])
    }

    func testChangingProfileOrPrivateOwnerInvalidatesTheCapturedDrop() throws {
        let d = Driver(), original = Driver.startURL
        let target = d.paneIDs[0], source = d.open("https://fixture.example/source")
        d.user(.tab(.focus(target)))
        let oldOffer = try XCTUnwrap(d.view.content.drop?.offers[source])
        d.user(.profile(.create(name: "Other", icon: nil)))
        let profile = try XCTUnwrap(d.state.doc.profiles.keys.first { $0 != .default })
        d.user(.profile(.assign(.current, to: profile)))
        assertUnchanged(d.state, d.user(.split(.dropTab(oldOffer, edge: .right))))
        XCTAssertEqual(d.state.address(of: target, in: d.window, for: .savedDocument), original)
        d.user(.window(.newIncognito))
        let privateWindow = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.commandBar(.dismiss), in: privateWindow)
        assertUnchanged(d.state, d.user(.split(.dropTab(oldOffer, edge: .right)), in: privateWindow))
    }
}
