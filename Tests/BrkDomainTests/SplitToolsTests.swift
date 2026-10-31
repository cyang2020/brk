import BrkBase
import XCTest
@testable import BrkDomain

final class SplitToolsTests: XCTestCase {
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
        d.user(.split(.toggleExpanded))
        XCTAssertTrue(d.view.content.expanded)
        XCTAssertFalse(d.view(of: other).content.expanded)
        XCTAssertEqual(d.snapshot.pages, pages)
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

    func testDropRefusesFavoritesSectionsProfilesStaleTargetsAndFullSplits() throws {
        let d = Driver()
        let original = d.paneIDs[0], source = d.open("https://fixture.example/source")
        d.user(.tab(.focus(original)))
        d.user(.tab(.togglePin(.item(source))))
        var before = d.state
        assertUnchanged(before, d.user(.split(.dropTab(offer(d, source, original), edge: .right))))
        d.user(.tab(.togglePin(.item(source))))
        d.user(.split(.dropTab(offer(d, source, original), edge: .right)))
        let split = try XCTUnwrap(d.view.content.split)
        for n in 3...4 { d.user(.split(.addPane)); d.user(.commandBar(.submit("https://fixture.example/\(n)"))); d.commitRequested() }
        let extra = d.open("https://fixture.example/extra")
        d.user(.tab(.focus(split)))
        before = d.state
        assertUnchanged(before, d.user(.split(.dropTab(offer(d, extra, split), edge: .top))))
        assertUnchanged(d.state, d.user(.split(.dropTab(offer(d, extra, original), edge: .right))))
        XCTAssertEqual(d.paneIDs.count, 4)
        XCTAssertFalse(d.view.enabledActions.contains(.addSplitView))
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
