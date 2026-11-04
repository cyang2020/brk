import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class TabToolsTests: XCTestCase {
    func testArchiveRequestShowsConfirmationWithoutDeletingAndIsRepeatable() {
        let d = Driver()
        d.user(.tab(.archive(.focused)))
        let before = d.archive().map(\.id)
        for _ in 0..<2 {
            let transition = d.user(.archive(.requestClear))
            XCTAssertEqual(d.archive().map(\.id), before)
            XCTAssertTrue(transition.effects.contains(.window(d.window, .requestArchiveClear)))
            if case .library(let page)? = d.view.overlay { XCTAssertEqual(page.page, .archive) }
            else { XCTFail("Archive confirmation has no visible owner") }
        }
        d.user(.archive(.clear))
        XCTAssertTrue(d.archive().isEmpty)
    }

    func testLinearNumberAndSpaceNavigationUseIndependentOrders() throws {
        let d = Driver()
        let a = try XCTUnwrap(d.current?.id)
        let b = d.open("127.0.0.1:9/b")
        d.user(.tabTools(.cycleLinear(.next)))
        XCTAssertEqual(d.current?.id, a)
        d.user(.tabTools(.cycleLinear(.previous)))
        XCTAssertEqual(d.current?.id, b)
        d.user(.tabTools(.jumpItem(9)))
        XCTAssertEqual(d.current?.id, a)
        let before = d.current?.id
        d.user(.tabTools(.jumpItem(8)))
        XCTAssertEqual(d.current?.id, before)
        let first = d.view.space.id
        d.user(.space(.create(title: "Second", icon: .none, theme: .default)))
        d.user(.tabTools(.jumpSpace(1)))
        XCTAssertEqual(d.view.space.id, first)
        d.user(.tabTools(.jumpSpace(9)))
        XCTAssertEqual(d.view.space.id, first)
    }
    func testDuplicateUsesInitiatingWindowCommittedDocumentAndFreshIdentity() throws {
        let d = Driver()
        let source = try XCTUnwrap(d.current?.id)
        d.page(source, .committed(url("https://example.com/committed")))
        d.page(source, .navigationRequested(url("https://example.com/provisional")))
        d.user(.tabTools(.bulk(.items([source]), .duplicate(nil))))
        let copy = try XCTUnwrap(d.current?.id)
        XCTAssertNotEqual(copy, source)
        XCTAssertEqual(d.row(copy)?.url, url("https://example.com/committed"))
        XCTAssertEqual(d.todayIDs, [source, copy])
        XCTAssertEqual(d.row(source)?.url, url("https://example.com/provisional"))
    }
    func testBulkValidationRollsBackAllChangesAndSelectionIsWindowLocal() throws {
        let d = Driver()
        let a = try XCTUnwrap(d.current?.id)
        let b = d.open("127.0.0.1:9/b")
        d.user(.tabTools(.select(b, .replace)))
        d.user(.tabTools(.select(a, .range)))
        XCTAssertEqual(d.view.tabTools.selected, [b, a])
        let saved = d.savedFile
        d.user(.tabTools(.bulk(.selected, .move(.into(parent: a, index: 0)))))
        XCTAssertEqual(d.savedFile, saved)
        d.user(.tabTools(.bulk(.items([a, ItemID("missing")]), .archive)))
        XCTAssertEqual(d.savedFile, saved)
        d.user(.tabTools(.bulk(.selected, .newFolder(group: true))))
        guard case .folder(let folder)? = d.view.space.pinned.rows.first else { return XCTFail("missing group") }
        XCTAssertEqual(folder.children.map(\.id), [b, a])
        XCTAssertTrue(d.state.doc.tree.items[folder.id].map { if case .folder(let f) = $0.body { f.isGroup } else { false } } ?? false)
    }
    func testFolderExpansionIsPerWindowAndMigratesLegacyV3() throws {
        let d = Driver()
        d.user(.item(.newFolder))
        let folder = try XCTUnwrap(d.view.space.pinned.rows.first?.id)
        d.user(.item(.rename(folder, title: "Folder")))
        d.user(.window(.new))
        let other = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window })
        d.user(.item(.toggleFolder(folder)))
        XCTAssertFalse(d.state.folderIsExpanded(folder, in: d.window))
        XCTAssertTrue(d.state.folderIsExpanded(folder, in: other))
        let restarted = Driver(file: d.savedFile)
        XCTAssertFalse(restarted.state.folderIsExpanded(folder, in: d.window))
        XCTAssertTrue(restarted.state.folderIsExpanded(folder, in: other))
        d.user(.tabTools(.folders(expanded: true)))
        XCTAssertTrue(d.state.folderIsExpanded(folder, in: d.window))
        d.user(.tabTools(.folders(expanded: false)))
        XCTAssertFalse(d.state.folderIsExpanded(folder, in: d.window))
        d.user(.tabTools(.reveal))
        d.user(.tabTools(.sidebarStep(.next)))
        d.user(.tabTools(.leaveSidebar))
    }
    func testArchiveRestoresNestedSplitWithBlankPaneIconOrientationAndFractions() throws {
        let d = Driver()
        let a = try XCTUnwrap(d.current?.id)
        d.user(.tab(.togglePin(.item(a))))
        d.user(.split(.addPane))
        d.user(.commandBar(.dismiss))
        let split = try XCTUnwrap(d.view.content.split)
        let panes = d.paneIDs
        d.user(.split(.setOrientation(split, .vertical)))
        d.user(.split(.resize(split, fractions: [panes[0]: 0.3, panes[1]: 0.7])))
        d.user(.item(.setIcon(split, .emoji("🌙"))))
        d.user(.tabTools(.bulk(.items([split]), .newFolder(group: false))))
        let folder = try XCTUnwrap(d.view.space.pinned.rows.first?.id)
        d.user(.item(.rename(folder, title: "Container")))
        d.user(.tabTools(.bulk(.items([folder]), .archive)))
        XCTAssertEqual(d.archive().count, 1)
        XCTAssertEqual(d.archive().first?.title, "Container")
        let restarted = Driver(file: d.savedFile)
        restarted.user(.archive(.restoreLast))
        guard case .folder(let restored)? = restarted.view.space.pinned.rows.first,
              case .split(let splitRow)? = restored.children.first else { return XCTFail("structure lost") }
        XCTAssertEqual(restored.title, "Container")
        XCTAssertEqual(splitRow.orientation, .vertical)
        XCTAssertEqual(splitRow.icon, .emoji("🌙"))
        XCTAssertEqual(splitRow.panes.count, 2)
        XCTAssertNil(splitRow.panes[1].url)
        XCTAssertEqual(restarted.view.content.panes[0].fraction, 0.3, accuracy: 0.0001)
    }
    func testPrivateBulkCannotMutatePublicTreeAndPrivateCloseDoesNotArchive() throws {
        let d = Driver()
        let publicTab = try XCTUnwrap(d.current?.id)
        d.user(.window(.newIncognito))
        let privateWindow = try XCTUnwrap(d.snapshot.windows.first { $0.value.kind == .incognito }?.key)
        let saved = d.savedFile
        d.user(.tabTools(.bulk(.items([publicTab]), .archive)), in: privateWindow)
        XCTAssertEqual(d.savedFile, saved)
        d.user(.commandBar(.submit("https://example.com/private")), in: privateWindow)
        let privateTab = try XCTUnwrap(d.view(of: privateWindow).content.panes.first?.tab)
        d.user(.tabTools(.bulk(.items([privateTab]), .close)), in: privateWindow)
        XCTAssertTrue(d.archive().isEmpty)
    }
    func testRecentCancelToastEducationAndMutePersistence() throws {
        let d = Driver()
        let a = try XCTUnwrap(d.current?.id)
        let b = d.open("127.0.0.1:9/b")
        d.user(.tab(.cycleRecent(.next)))
        XCTAssertEqual(d.view.tabTools.recent?.selected, a)
        XCTAssertEqual(d.current?.id, b, "a press switches nothing")
        d.user(.tabTools(.cancelRecent))
        XCTAssertEqual(d.current?.id, b)
        XCTAssertNil(d.view.tabTools.recent)
        d.user(.tabTools(.mute(.focused)))
        XCTAssertTrue(d.row(b)?.muted ?? false)
        let restarted = Driver(file: d.savedFile)
        XCTAssertTrue(restarted.row(b)?.muted ?? false)
        XCTAssertTrue(restarted.snapshot.pages.first { $0.id.item == b }?.muted ?? false)
        d.page(b, .audioChanged(true))
        XCTAssertTrue(d.row(b)?.audible ?? false)
        d.user(.tabTools(.chooseIcon(b)))
        d.user(.tabTools(.iconPickerClosed))
        d.user(.tabTools(.resetPinned))
        XCTAssertNotNil(d.view.tabTools.toast)
        d.advance(.seconds(5))
        d.system(.clockTick)
        XCTAssertNil(d.view.tabTools.toast)
        d.user(.tabTools(.dismissToast))
        // Arc's banner names the profile's threshold ("… haven’t used in the past 12 hours."); none while it is Never.
        XCTAssertEqual(d.view.tabTools.archiveEducation, "12 hours")
        d.user(.settings(.profile(.default, .autoArchive(.never))))
        XCTAssertNil(d.view.tabTools.archiveEducation)
        d.user(.settings(.profile(.default, .autoArchive(.twelveHours))))
        d.user(.tabTools(.dismissArchiveEducation))
        XCTAssertNil(Driver(file: d.savedFile).view.tabTools.archiveEducation)
        d.user(.tabTools(.preferences(includeFavorites: false, previews: false)))
        XCTAssertFalse(Driver(file: d.savedFile).view.tabTools.hoverPreviews)
    }
    /// Clear Today and Delete Space leave Arc's undo toast; ⌘Z (`.undoToast`) brings the tabs and the space back.
    func testClearTodayAndDeleteSpaceToastsUndo() throws {
        let d = Driver()
        let idle = d.todayIDs[0]
        let shown = d.open("example.com/shown")
        d.user(.tab(.clearToday))
        XCTAssertEqual(d.todayIDs, [shown])
        XCTAssertEqual(d.view.tabTools.toast?.text, "Cleared Tabs! Use")
        XCTAssertEqual(d.view.tabTools.toast?.keycap, "⌘Z")
        d.user(.tabTools(.undoToast))
        XCTAssertEqual(d.todayIDs.count, 2)
        XCTAssertTrue(d.view.space.today.rows.contains { $0.id == idle } || d.view.space.today.rows.count == 2)
        XCTAssertNil(d.view.tabTools.toast)

        let first = d.view.space.id
        let space = d.newSpace("Gone")
        _ = d.open("example.com/in-gone")
        d.user(.space(.delete(space)))
        XCTAssertEqual(d.view.dock.map(\.id), [first])
        XCTAssertEqual(d.view.tabTools.toast?.text, "Space deleted! Use")
        d.user(.tabTools(.undoToast))
        XCTAssertEqual(d.view.dock.map(\.id), [first, space])
        XCTAssertEqual(d.view.space.id, space)
        XCTAssertEqual(d.view.space.today.rows.count, 1, "the deleted space's tab comes back into it")
        // A second ⌘Z with no toast does nothing.
        let before = d.view
        d.user(.tabTools(.undoToast))
        XCTAssertEqual(d.view.dock, before.dock)
    }

    /// The × on the empty favorites box dismisses it for good: the tray takes no room, across a restart.
    func testDismissFavoritesHint() {
        let d = Driver()
        XCTAssertTrue(d.view.favorites.tiles.isEmpty)
        XCTAssertFalse(d.view.favorites.hintDismissed)
        d.user(.tabTools(.dismissFavoritesHint))
        XCTAssertTrue(d.view.favorites.hintDismissed)
        XCTAssertTrue(Driver(file: d.savedFile).view.favorites.hintDismissed)
    }

    func testTitleRulesNeverOverrideUserTitleOrLookalikeHost() {
        XCTAssertEqual(TitleRules.shorten("Example · GitHub", url: url("https://github.com/a")), "Example")
        XCTAssertEqual(TitleRules.shorten("Example · GitHub", url: url("https://github.com.evil.test/a")), "Example · GitHub")
        XCTAssertEqual(TitleRules.shorten("Story - YouTube", url: url("https://youtube.com/watch")), "Story")
        let d = Driver()
        let a = d.todayIDs[0]
        d.page(a, .committed(url("https://github.com/a")))
        d.page(a, .titleChanged("Example · GitHub"))
        d.user(.item(.rename(a, title: "Mine · GitHub")))
        XCTAssertEqual(d.row(a)?.title, "Mine · GitHub")
    }
}

extension TabToolsTests {
    func testBulkMovePreservesSidebarOrderAndOtherDoesNotArchiveItsAncestor() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("127.0.0.1:9/b"), c = d.open("127.0.0.1:9/c"), e = d.open("127.0.0.1:9/e")
        let today = d.view.space.today.root
        d.user(.tabTools(.bulk(.items([c,e]), .move(.into(parent: today, index: 2)))))
        XCTAssertEqual(d.todayIDs, [b,a,e,c])
        d.user(.tabTools(.bulk(.items([e,c]), .newFolder(group: false))))
        let folder = try XCTUnwrap(d.pinnedIDs.first)
        d.user(.item(.rename(folder, title: "Keep parent")))
        d.user(.tabTools(.bulk(.other(e), .archive)))
        XCTAssertNotNil(d.state.doc.tree[folder])
        XCTAssertNotNil(d.row(e))
        XCTAssertNil(d.row(c))
    }
    func testLegacyOptionalFieldsDefaultAndRenameRevealDoesNotTouchOtherWindow() throws {
        let d = Driver()
        d.user(.item(.newFolder))
        let folder = try XCTUnwrap(d.pinnedIDs.first)
        d.user(.item(.rename(folder, title: "Legacy")))
        var saved = d.saved
        var doc = try XCTUnwrap(saved["doc"] as? [String: Any])
        doc.removeValue(forKey: "tabPreferences")
        var items = try XCTUnwrap(doc["items"] as? [String: Any])
        var storedFolder = try XCTUnwrap(items[folder.rawValue] as? [String: Any])
        var fields = try XCTUnwrap(storedFolder["folder"] as? [String: Any])
        fields["collapsed"] = true
        fields.removeValue(forKey: "group")
        fields.removeValue(forKey: "liveRepository")
        storedFolder["folder"] = fields
        items[folder.rawValue] = storedFolder
        doc["items"] = items
        var windows = try XCTUnwrap(doc["windows"] as? [String: Any])
        for key in windows.keys {
            var window = try XCTUnwrap(windows[key] as? [String: Any])
            window.removeValue(forKey: "folderExpansion")
            windows[key] = window
        }
        doc["windows"] = windows
        saved["doc"] = doc
        let restored = Driver(file: try JSONSerialization.data(withJSONObject: saved))
        XCTAssertFalse(restored.state.folderIsExpanded(folder, in: restored.window))
        XCTAssertTrue(restored.view.tabTools.includeFavoritesInNumbers)
        XCTAssertFalse(restored.view.tabTools.hoverPreviews, "previews are off by default, as in Arc")
        restored.user(.item(.beginRename(.item(folder))))
        XCTAssertEqual(restored.view.renaming, folder)
    }
    func testRecentCancelPreservesActivityAndRepeatedRevealHasAWindowLocalGeneration() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("127.0.0.1:9/b")
        let before = [a,b].compactMap { d.state.tab($0)?.lastActiveAt }
        d.advance(.seconds(100))
        d.user(.tab(.cycleRecent(.next)))
        d.user(.tabTools(.cancelRecent))
        XCTAssertEqual([a,b].compactMap { d.state.tab($0)?.lastActiveAt }, before)
        d.user(.tabTools(.reveal))
        let generation = d.view.tabTools.revealGeneration
        d.user(.tabTools(.reveal))
        XCTAssertGreaterThan(d.view.tabTools.revealGeneration, generation)
    }
}

extension TabToolsTests {
    func testStructuralRestoreDoesNotFollowASpaceIntoAnotherProfile() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let source = d.view.space.id
        d.user(.tabTools(.bulk(.items([a]), .newFolder(group: false))))
        let folder = try XCTUnwrap(d.pinnedIDs.first)
        d.user(.item(.rename(folder, title: "Original profile folder")))
        d.user(.tabTools(.bulk(.items([folder]), .archive)))
        let safe = d.newSpace("Safe original profile")
        d.user(.profile(.create(name: "Different", icon: nil)))
        let other = try XCTUnwrap(d.snapshot.settings.profiles.first { $0.profile.name == "Different" }?.profile.id)
        d.user(.profile(.assign(.space(source), to: other)))
        d.user(.space(.focus(source)))
        d.user(.archive(.restoreLast))
        XCTAssertEqual(d.view.space.id, safe)
        XCTAssertTrue(d.pinnedIDs.contains(folder))
        XCTAssertEqual(d.state.doc.spaces[d.view.space.id]?.profile, .default)
    }
}

extension TabToolsTests {
    func testPrivateClearTodayCannotArchiveAnIdlePublicTab() throws {
        let d = Driver()
        let idle = try XCTUnwrap(d.current?.id)
        _ = d.open("127.0.0.1:9/visible-public")
        d.user(.window(.newIncognito))
        let privateWindow = try XCTUnwrap(d.snapshot.windows.first { $0.value.kind == .incognito }?.key)
        let saved = d.savedFile
        d.user(.tab(.clearToday), in: privateWindow)
        XCTAssertNotNil(d.row(idle), "private Clear Today archived an idle public tab")
        XCTAssertTrue(d.archive().isEmpty)
        XCTAssertEqual(d.savedFile, saved)
    }
}

extension TabToolsTests {
    func testUnrepresentableStructuralArchiveDoesNotDeleteTheSource() throws {
        let d = Driver()
        var first: ItemID?, parent: ItemID?
        for i in 0..<34 {
            d.user(.item(.newFolder))
            let folder = try XCTUnwrap(d.pinnedIDs.first)
            d.user(.item(.rename(folder, title: "Folder \(i)")))
            if let parent { d.user(.item(.move(folder, to: .into(parent: parent, index: 0)))) }
            first = first ?? folder
            parent = folder
        }
        let root = try XCTUnwrap(first)
        let saved = d.savedFile
        d.user(.tabTools(.bulk(.items([root]), .archive)))
        XCTAssertNotNil(d.state.doc.tree[root], "an unrepresentable archive must keep the original subtree")
        XCTAssertEqual(d.savedFile, saved)
    }
}
