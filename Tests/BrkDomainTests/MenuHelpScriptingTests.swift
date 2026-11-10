import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Round 3, R3-5: the menu rows that were greyed out (View > Developer, Check for Updates…, the Help menu), the Dock
/// tile's downloads and AppleScript's view of windows, tabs and spaces.
final class MenuHelpScriptingTests: XCTestCase {
    private func ready(_ d: Driver, _ tab: ItemID) throws {
        let page = PageID(window: d.window, item: tab)
        let browser = try XCTUnwrap(d.state.session.live[page]?.browser)
        let document = DocumentToken(browser: browser, sequence: (d.state.session.live[page]?.documentSequence ?? 0) + 1)
        d.page(tab, .documentChanged(.loading(document)))
        d.page(tab, .documentChanged(.ready(document)))
    }

    // MARK: Menu bar coverage

    /// every row Arc's menu shows does something: no visible row is a later wave except the ones the parent holds
    /// (Notes, which Arc 1.170 does not show either and BrkApp hides; New Easel became real with the Easel group)
    func testNoVisibleMenuRowIsAPlaceholder() {
        let later = ActionID.allCases.filter { $0.spec.later != nil }
        XCTAssertEqual(Set(later), [.newNote, .newNoteInSplitView, .exportArcNotes])
        for action in [ActionID.checkForUpdates, .releaseNotes, .contactTheTeam, .visitHelpCenter, .restoreData, .recordTrace, .cancelTrace,
                       .openTaskManager, .copyArcInfo] {
            guard case .app(.help) = action.spec.command else { return XCTFail("\(action) is not a Help action: \(action.spec.command)") }
        }
    }

    // MARK: View > Developer

    /// "Turn on Developer Mode for this site" (Ctrl+D) is the site controls' switch: on, the pill shows the whole
    /// address and the row reads Turn off; it needs a site, and is per site
    func testDeveloperModeRowTogglesTheFocusedSitesSwitch() throws {
        let d = Driver()
        let tab = d.open("https://www.example.test/docs/page?x=1")
        try ready(d, tab)
        XCTAssertTrue(d.view.enabledActions.contains(.toggleDeveloperMode))
        XCTAssertFalse(d.view.urlPill.developerMode)
        d.user(.site(.toggleDeveloperMode))
        XCTAssertTrue(d.view.urlPill.developerMode)
        XCTAssertEqual(d.view.urlPill.host, "https://www.example.test/docs/page?x=1")
        let target = try XCTUnwrap(d.state.siteTarget(in: d.window))
        XCTAssertEqual(d.state.sitePreferences(target.context).rule(for: target.origin).developerMode, true, "the site controls' row reads the same switch")
        let restored = Driver(file: d.savedFile)
        XCTAssertEqual(restored.state.doc.sitePreferences[.default]?.rules[target.origin.value]?.developerMode, true, "remembered per site")
        let other = d.open("https://other.test/a")
        try ready(d, other)
        XCTAssertFalse(d.view.urlPill.developerMode, "another site keeps its own switch")
        d.user(.tab(.focus(tab)))
        d.user(ActionID.toggleDeveloperMode.spec.command)
        XCTAssertFalse(d.view.urlPill.developerMode)
        XCTAssertEqual(d.view.urlPill.host, "example.test")
    }

    /// Allow JavaScript from Apple Events: off by default (as in Arc and Chrome), the row flips it, it is saved
    func testJavaScriptFromAppleEventsIsAPersistedSwitch() {
        let d = Driver()
        XCTAssertNil(d.snapshot.settings.general.javaScriptFromAppleEvents)
        d.user(.settings(.general(.toggleJavaScriptFromAppleEvents)))
        XCTAssertEqual(d.snapshot.settings.general.javaScriptFromAppleEvents, true)
        XCTAssertEqual(Driver(file: d.savedFile).snapshot.settings.general.javaScriptFromAppleEvents, true)
        d.user(ActionID.allowJavaScriptFromAppleEvents.spec.command)
        XCTAssertNil(d.snapshot.settings.general.javaScriptFromAppleEvents)
    }

    // MARK: Help

    /// a page a Help row resolved opens as a new focused tab of the window's space; an address the bar would refuse
    /// is ignored
    func testHelpPageOpensAsANewTab() {
        let d = Driver()
        let notes = URL(fileURLWithPath: "/Applications/Brk.app/Contents/Resources/Help/release-notes.html")
        let before = d.todayIDs.count
        d.user(.app(.help(.open(notes))))
        XCTAssertEqual(d.todayIDs.count, before + 1)
        XCTAssertEqual(d.current?.url, notes)
        let count = d.todayIDs.count
        d.user(.app(.help(.open(URL(string: "javascript:alert(1)")!))))
        XCTAssertEqual(d.todayIDs.count, count)
    }

    // MARK: AppleScript

    /// `set URL of tab` loads the address in that tab, in place; a scheme the bar refuses is ignored
    func testScriptNavigationLoadsInPlace() throws {
        let d = Driver()
        let tab = d.open("https://one.test/")
        let target = URL(string: "https://two.test/next")!
        let t = d.user(.page(.navigate(.item(tab), target)))
        XCTAssertTrue(t.effects.contains(.page(PageID(window: d.window, item: tab), .navigate(target))), "\(t.effects)")
        XCTAssertEqual(d.current?.id, tab)
        let refused = d.user(.page(.navigate(.item(tab), URL(string: "javascript:void(0)")!)))
        XCTAssertFalse(refused.effects.contains { if case .page(_, .navigate) = $0 { true } else { false } })
    }

    /// a window's scripting tabs are its space's Favorites, Pinned and Today with Arc's locations; spaces in dock
    /// order; the active tab and space; an incognito window has its own tabs and no spaces
    func testScriptingViewOfWindowsTabsAndSpaces() throws {
        let d = Driver()
        let today = d.open("https://today.test/")
        let pinned = d.open("https://pinned.test/")
        d.user(.tab(.togglePin(.item(pinned))))
        let tabs = d.state.scriptTabs(in: d.window)
        XCTAssertEqual(tabs.first { $0.id == pinned }?.location, .pinned)
        XCTAssertEqual(tabs.first { $0.id == today }?.location, .unpinned)
        XCTAssertEqual(tabs.first { $0.id == today }?.url, URL(string: "https://today.test/"))
        XCTAssertEqual(Set(tabs.map(\.id)), Set(d.allTabRows.map(\.id)), "the tabs the sidebar shows")
        let window = try XCTUnwrap(d.state.scriptWindow(d.window))
        XCTAssertEqual(window.activeTab, d.state.focusedPane(in: d.window))
        XCTAssertEqual(window.activeSpace, d.view.space.id)
        let work = d.newSpace("Work")
        XCTAssertEqual(d.state.scriptSpaces(in: d.window).map(\.id), d.state.doc.spaceOrder)
        XCTAssertEqual(d.state.scriptSpaces(in: d.window).last?.title, "Work")
        XCTAssertNotNil(d.state.scriptTab(today, in: d.window))
        XCTAssertTrue(d.state.scriptTabs(inSpace: work, window: d.window).allSatisfy { $0.location != .pinned })

        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        XCTAssertEqual(d.state.scriptWindow(incognito)?.kind, .incognito)
        XCTAssertNil(d.state.scriptWindow(incognito)?.activeSpace)
        XCTAssertEqual(d.state.scriptSpaces(in: incognito), [])
        XCTAssertNil(d.state.scriptTab(today, in: incognito), "an incognito window cannot reach the profile's tabs")
        XCTAssertTrue(d.state.scriptTabs(in: incognito).allSatisfy { $0.location == .unpinned })
    }

    // MARK: Dock tile

    /// the Dock badge counts downloads in progress; the bar shows their bytes when every size is known; finished
    /// files are listed for the Downloads stack's bounce
    func testDockTileFollowsDownloads() {
        let d = Driver()
        let tab = d.todayIDs[0]
        XCTAssertEqual(d.snapshot.dockTile, DockTileSnapshot())
        d.download(tab, DownloadID("a"), .receiving(TransferProgress(received: 25, total: 100)))
        XCTAssertEqual(d.snapshot.dockTile.active, 1)
        XCTAssertEqual(d.snapshot.dockTile.progress ?? -1, 0.25, accuracy: 0.001)
        d.download(tab, DownloadID("b"), .receiving(TransferProgress(received: 50, total: 100)))
        XCTAssertEqual(d.snapshot.dockTile.active, 2)
        XCTAssertEqual(d.snapshot.dockTile.progress ?? -1, 0.375, accuracy: 0.001)
        d.download(tab, DownloadID("c"), .receiving(TransferProgress(received: 5, total: nil)))
        XCTAssertEqual(d.snapshot.dockTile.active, 3)
        XCTAssertNil(d.snapshot.dockTile.progress, "a download of unknown size: the badge only")
        d.download(tab, DownloadID("a"), .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/dock-a.zip"), bytes: 100))))
        XCTAssertEqual(d.snapshot.dockTile.active, 2)
        XCTAssertEqual(d.snapshot.dockTile.finished, [DownloadID("a"): "/tmp/dock-a.zip"])
    }
}
