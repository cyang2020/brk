import BrkBase
@testable import BrkDomain
import XCTest

/// Arc's toasts as its binary names them (`ToastController`) and the references show them (Q11-b, P15, P33-d), and the
/// + popover's rows (Q11-a). verify/visual-pairs/run-20261103/r4-14/POPUPS.md has the table.
final class ToastCatalogTests: XCTestCase {
    private func toast(_ d: Driver) -> ToastSnapshot? { d.view.tabTools.toast }

    func testCopyURLToastCarriesShareExceptInAPrivateWindow() throws {
        let d = Driver()
        let tab = d.open("example.com/one")
        for format in [CopyURLFormat.plain, .markdown, .quote] {
            d.user(.tabTools(.dismissToast))
            d.user(.page(.copyURL(format)))
            XCTAssertEqual(toast(d)?.text, ToastCopy.copiedCurrentURL, "\(format)")
            XCTAssertEqual(toast(d)?.action?.symbol, "square.and.arrow.up")
            XCTAssertEqual(toast(d)?.action?.command, .app(.export(.items([tab]))))
        }
        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.state.doc.windows.first { $0.value.kind == .incognito }?.key)
        d.user(.commandBar(.open(.newTab)), in: incognito)
        d.user(.commandBar(.submit("example.com/private")), in: incognito)
        d.user(.page(.copyURL(.plain)), in: incognito)
        XCTAssertEqual(d.view(of: incognito).tabTools.toast?.text, ToastCopy.copiedCurrentURL)
        XCTAssertNil(d.view(of: incognito).tabTools.toast?.action, "a private tab has nothing to share")
    }

    func testQuoteLinkToast() {
        let d = Driver()
        d.user(.tabTools(.quoteLinkCopied))
        XCTAssertEqual(toast(d)?.text, "Copied Link")
        XCTAssertEqual(toast(d)?.subtitle, "With Quote")
    }

    func testCopyLinksSaysOneOrMany() {
        let d = Driver()
        let one = d.open("example.com/one"), two = d.open("example.com/two")
        d.user(.tabTools(.copyLinks(.items([one]))))
        XCTAssertEqual(toast(d)?.text, ToastCopy.copiedCurrentURL)
        XCTAssertEqual(toast(d)?.action?.command, .app(.export(.items([one]))))
        d.user(.tabTools(.copyLinks(.items([one, two]))))
        XCTAssertEqual(toast(d)?.text, "Copied item links")
        XCTAssertNil(toast(d)?.action)
    }

    func testPinAndUnpinNameTheSpace() {
        let d = Driver()
        let title = d.state.displayTitle(of: d.view.space.id)
        let tab = d.open("example.com/one")
        d.user(.tab(.togglePin(.item(tab))))
        XCTAssertEqual(toast(d)?.text, "Pinned Tab to “\(title)”")
        d.user(.tab(.togglePin(.item(tab))))
        XCTAssertEqual(toast(d)?.text, "Un-Pinned Tab from “\(title)”")
    }

    func testMovingToAnotherSpaceOffersToGoThere() {
        let d = Driver()
        let home = d.view.space.id
        let tab = d.open("example.com/one"), other = d.open("example.com/two")
        let away = d.newSpace("Away")
        d.user(.space(.focus(home)))
        d.user(.tabTools(.dismissToast))
        d.user(.item(.move(tab, to: .space(home))))
        XCTAssertNil(toast(d), "a move inside the shown space goes where the user can see it")
        d.user(.item(.move(tab, to: .space(away))))
        XCTAssertEqual(toast(d)?.text, "Tab moved! Click to go there.")
        XCTAssertEqual(toast(d)?.click, .tab(.focus(tab)))
        d.user(.tabTools(.dismissToast))
        d.user(.tabTools(.bulk(.items([other]), .move(.space(away)))))
        XCTAssertEqual(toast(d)?.text, "Tab moved! Click to go there.")
    }

    func testRestoreAndClearArchive() throws {
        let d = Driver()
        let title = d.state.displayTitle(of: d.view.space.id)
        let tab = d.open("example.com/one")
        _ = d.open("example.com/two")
        d.user(.tab(.close(.item(tab))))
        let entry = try XCTUnwrap(d.state.doc.archive.first?.id)
        d.user(.archive(.restore(entry)))
        XCTAssertEqual(toast(d)?.text, "Tab restored to \(title)")
        XCTAssertNil(toast(d)?.click)

        d.user(.tab(.close(.item(tab))))
        d.user(.library(.open(.archive)))
        let again = try XCTUnwrap(d.state.doc.archive.first?.id)
        d.user(.archive(.restore(again)))
        XCTAssertEqual(toast(d)?.text, "Tab restored to \(title). Click to view.", "the Library hides the tab")
        XCTAssertEqual(toast(d)?.click, .library(.close))

        d.user(.tab(.close(.item(tab))))
        d.user(.archive(.clear))
        XCTAssertEqual(toast(d)?.text, "Archive Cleared")
    }

    func testAutoArchiveSaysHowMany() {
        let d = Driver()
        d.user(.settings(.autoArchive(.twelveHours)))
        let idle = d.open("example.com/idle")
        let shown = d.open("example.com/shown")
        let swept = d.todayIDs.count - 1
        d.user(.tabTools(.dismissToast))
        d.advance(.seconds(13 * 3600))
        d.system(.clockTick)
        XCTAssertFalse(d.todayIDs.contains(idle))
        XCTAssertEqual(d.todayIDs, [shown])
        XCTAssertEqual(toast(d)?.text, "Auto archived \(swept) tabs")
    }

    func testFullSplitSaysSo() {
        let d = Driver()
        _ = d.open("example.com/one")
        for _ in 0..<(Metrics.content.maxPanes.value - 1) {
            d.user(.split(.addPane))
            d.user(.commandBar(.dismiss))
            XCTAssertNil(toast(d))
        }
        d.user(.split(.addPane))
        XCTAssertEqual(toast(d)?.text, "Cannot Add New Pane")
    }

    func testFullScreenToastLeavesWithTheFullScreen() {
        let d = Driver()
        let tab = d.open("example.com/one")
        d.page(tab, .fullscreenChanged(true))
        XCTAssertEqual(toast(d)?.text, "To exit full screen, press")
        XCTAssertEqual(toast(d)?.keycap, "esc")
        d.page(tab, .fullscreenChanged(false))
        XCTAssertNil(toast(d))
    }

    func testUndoToastsAllSayUse() throws {
        let d = Driver()
        let one = d.open("example.com/one"), two = d.open("example.com/two")
        _ = d.open("example.com/three")
        d.user(.tabTools(.bulk(.items([one, two]), .newFolder(group: true))))
        let group = try XCTUnwrap(d.view.space.pinned.rows.first { if case .folder(let f) = $0 { f.group } else { false } }?.id
            ?? d.view.space.today.rows.first { if case .folder(let f) = $0 { f.group } else { false } }?.id)
        d.user(.tabTools(.closeGroup(group)))
        XCTAssertEqual(toast(d)?.text, "Closed Tab Group! Use")
        XCTAssertEqual(toast(d)?.keycap, "⌘Z")
        XCTAssertEqual(toast(d)?.trailing, "to undo")
    }

    func testBulkArchiveIsUndoableAndOtherBulkActionsSayNothing() {
        let d = Driver()
        let one = d.open("example.com/one"), two = d.open("example.com/two")
        _ = d.open("example.com/three")
        d.user(.tabTools(.bulk(.items([one]), .duplicate(nil))))
        XCTAssertNil(toast(d), "Arc has no toast for a duplicate")
        d.user(.tabTools(.bulk(.items([one, two]), .archive)))
        XCTAssertEqual(toast(d)?.text, "Cleared Tabs! Use")
        d.user(.tabTools(.undoToast))
        XCTAssertTrue(d.todayIDs.contains(one) && d.todayIDs.contains(two))
    }

    func testBoostImportSaysInstalled() throws {
        let d = Driver()
        _ = d.open("example.com/one")
        let profile = try XCTUnwrap(d.state.boostProfile(in: d.window))
        d.system(.boost(.imported(d.window, profile, [])))
        XCTAssertNil(toast(d), "an empty file installed nothing")
        d.system(.boost(.imported(d.window, profile, [Boost(id: "b", name: "One", scope: .allSites)])))
        XCTAssertEqual(toast(d)?.text, "Boost installed!")
    }

    func testImportSaysSoInArcsWords() throws {
        let d = Driver()
        let target = try XCTUnwrap(d.state.sidebarImportTarget(in: d.window))
        d.system(.sidebarData(.imported(d.window, target: target, SidebarImportPreview(visits: []), favorites: false)))
        XCTAssertEqual(toast(d)?.text, "Success! We imported all of your stuff")
        var partly = SidebarImportPreview(visits: [])
        partly.rejected = 2
        d.system(.sidebarData(.imported(d.window, target: target, partly, favorites: false)))
        XCTAssertEqual(toast(d)?.text, "Only some of your data imported. Please try again!")
    }

    func testPlusMenuRows() {
        let d = Driver()
        let rows = d.view.plusMenu
        XCTAssertEqual(rows.map { $0.map(\.title) }, [["New Space", "New Folder"], ["New Easel", "New Boost"], ["New Split", "New Tab"]])
        XCTAssertEqual(rows.flatMap { $0 }.map(\.keys), [[], [], ["⌃", "⇧", "E"], [], ["⌃", "⇧", "="], ["⌘", "T"]])
        XCTAssertEqual(rows.flatMap { $0 }.map(\.command), [.sidebar(.openDialog(.newSpace)), .item(.newFolder), .easel(.create), .boost(.create), .split(.addPane), .commandBar(.open(.newTab))])
        XCTAssertTrue(rows.flatMap { $0 }.allSatisfy(\.enabled))
    }

    func testPlusMenuFollowsAChangedShortcut() {
        let d = Driver()
        d.user(.settings(.shortcuts(.setChord(.newTab, KeyChord(.command, .y)))))
        XCTAssertEqual(d.view.plusMenu.last?.last?.keys, ["⌘", "Y"])
    }

    func testPlusMenuInAPrivateWindowKeepsWhatWorksThere() throws {
        let d = Driver()
        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.state.doc.windows.first { $0.value.kind == .incognito }?.key)
        let enabled = d.view(of: incognito).plusMenu.flatMap { $0 }.filter(\.enabled).map(\.title)
        XCTAssertEqual(enabled, ["New Split", "New Tab"])
    }
}
